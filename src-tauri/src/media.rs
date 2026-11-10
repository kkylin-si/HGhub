//! 媒体层：封面解密 + HLS 代理。
//!
//! 站点封面是 AES-128-CBC 密文，m3u8 内部分片/key 又可能被 WebView 的 CORS 拦住，
//! 所以图片与视频统一走本地自定义协议（Windows/Android 为 `http://hg.localhost`，
//! macOS 为 `hg://localhost`，见 [`LOCAL_ORIGIN`]）。

use crate::net::fetch_bytes;
use aes::cipher::{BlockDecrypt, KeyInit};
use aes::Aes128;
use once_cell::sync::Lazy;
use percent_encoding::{percent_decode_str, utf8_percent_encode, NON_ALPHANUMERIC};
use std::collections::HashMap;
use std::sync::{Arc, Mutex, Weak};
use std::sync::atomic::{AtomicU64, Ordering};
use sha2::{Digest, Sha256};

static DOWNLOAD_LOCKS: Lazy<Mutex<HashMap<String, Weak<tokio::sync::Mutex<()>>>>> = Lazy::new(|| Mutex::new(HashMap::new()));

fn download_lock(url: &str) -> Arc<tokio::sync::Mutex<()>> {
    let mut locks = DOWNLOAD_LOCKS.lock().unwrap();
    locks.retain(|_, lock| lock.strong_count() > 0);
    if let Some(lock) = locks.get(url).and_then(Weak::upgrade) { return lock; }
    let lock = Arc::new(tokio::sync::Mutex::new(()));
    locks.insert(url.to_string(), Arc::downgrade(&lock));
    lock
}

#[derive(Clone, Copy, Debug, serde::Deserialize)]
pub struct ByteRange { pub start: u64, pub end: u64 }

static OBSERVED_PLAYLISTS: Lazy<Mutex<HashMap<String, std::time::Instant>>> = Lazy::new(|| Mutex::new(HashMap::new()));
fn playlist_id(url: &str) -> String { format!("{:x}", Sha256::digest(url.as_bytes())) }
fn observe_playlist(url: &str) {
    if let Ok(mut entries) = OBSERVED_PLAYLISTS.lock() {
        entries.retain(|_, at| at.elapsed() < std::time::Duration::from_secs(300));
        if entries.len() >= 256 { entries.clear(); }
        entries.insert(playlist_id(url), std::time::Instant::now());
    }
}
pub fn latest_playlist(urls: &[String]) -> Option<usize> {
    let entries = OBSERVED_PLAYLISTS.lock().ok()?;
    urls.iter().enumerate().filter_map(|(i, url)| entries.get(&playlist_id(url)).filter(|at| at.elapsed() < std::time::Duration::from_secs(300)).map(|at| (i, at)))
        .max_by_key(|(_, at)| **at).map(|(i, _)| i)
}

const DIRECT_BLOCK: u64 = 1024 * 1024;
#[derive(Clone)]
struct DirectInfo { total: u64, cursor: u64, etag: String, tag: String }
static DIRECT_MEDIA: Lazy<Mutex<HashMap<String, DirectInfo>>> = Lazy::new(|| Mutex::new(HashMap::new()));
static DIRECT_PROBE_FAILURES: Lazy<Mutex<HashMap<String, std::time::Instant>>> = Lazy::new(|| Mutex::new(HashMap::new()));

pub async fn probe_direct(url: &str) -> Result<(u64, String), String> {
    let referer = format!("{}/", crate::net::base());
    let mut response = crate::net::get_with_range(url, std::time::Duration::from_secs(20), None, Some(&referer), Some("bytes=0-0")).await?;
    if response.status() != reqwest::StatusCode::PARTIAL_CONTENT { return Err("服务器不支持范围请求".into()); }
    let (start, end, total) = response.headers().get(reqwest::header::CONTENT_RANGE).and_then(|v| v.to_str().ok())
        .and_then(parse_content_range).ok_or("无效的 Content-Range")?;
    if start != 0 || end != 0 || total > 9_007_199_254_740_991 { return Err("服务器返回的字节范围不匹配".into()); }
    let etag = response.headers().get(reqwest::header::ETAG).and_then(|v| v.to_str().ok())
        .filter(|tag| tag.starts_with('"') && tag.ends_with('"')).ok_or("服务器未提供强 ETag，无法安全复用文件块")?.to_string();
    let tag = format!("{:x}", Sha256::digest(etag.as_bytes()));
    let mut received = 0;
    while let Some(chunk) = response.chunk().await.map_err(|_| "范围探测失败")? {
        if chunk.len() > 1 - received { return Err("范围探测响应长度错误".into()); }
        received += chunk.len();
    }
    if received != 1 { return Err("范围探测响应长度错误".into()); }
    let mut direct = DIRECT_MEDIA.lock().map_err(|_| "范围状态锁失败")?;
    if direct.len() >= 128 { direct.clear(); }
    let cursor = direct.get(url).map_or(0, |entry| entry.cursor);
    direct.insert(url.to_string(), DirectInfo { total, cursor, etag, tag: tag.clone() });
    Ok((total, tag))
}
pub fn direct_cursor(url: &str) -> u64 {
    DIRECT_MEDIA.lock().ok().and_then(|map| map.get(url).map(|entry| entry.cursor)).unwrap_or(0)
}
fn direct_cache_key(target: &str, range: ByteRange, tag: &str) -> String {
    format!("{}\nvalidator={tag}", range_key(target, range))
}
fn direct_cache_read(target: &str, requested: ByteRange, total: u64, tag: &str) -> Option<(Option<String>, Vec<u8>)> {
    if requested.start >= total { return None; }
    let end = requested.end.min(total - 1);
    if end < requested.start { return None; }
    let end = end.min(requested.start.saturating_add(8 * 1024 * 1024 - 1));
    let mut offset = requested.start / DIRECT_BLOCK * DIRECT_BLOCK;
    let mut result = Vec::new(); let mut content_type = None;
    while offset <= end {
        let block_end = offset.saturating_add(DIRECT_BLOCK - 1).min(total - 1);
        let entry = crate::media_cache::get_entry(&direct_cache_key(target, ByteRange { start: offset, end: block_end }, tag));
        let Some((mime, saved_total, bytes)) = entry else { if result.is_empty() { return None; } break; };
        if saved_total != Some(total) || bytes.len() as u64 != block_end - offset + 1 { return None; }
        if content_type.is_none() { content_type = mime; }
        let first = requested.start.saturating_sub(offset) as usize;
        let last = (end.min(block_end) - offset + 1) as usize;
        result.extend_from_slice(bytes.get(first..last)?);
        offset = block_end + 1;
    }
    Some((content_type, result))
}

fn range_key(url: &str, range: ByteRange) -> String {
    format!("{url}\nrange={}-{}", range.start, range.end)
}

fn parse_content_range(raw: &str) -> Option<(u64, u64, u64)> {
    let (range, total) = raw.strip_prefix("bytes ")?.split_once('/')?;
    let (start, end) = range.split_once('-')?;
    let (start, end, total) = (start.parse().ok()?, end.parse().ok()?, total.parse().ok()?);
    if start > end || end >= total { return None; }
    Some((start, end, total))
}

fn valid_range_header(raw: &str) -> bool {
    if raw.len() > 100 { return false; }
    let Some(ranges) = raw.strip_prefix("bytes=") else { return false };
    ranges.split(',').all(|range| {
        let Some((start, end)) = range.split_once('-') else { return false };
        if start.is_empty() { return end.parse::<u64>().is_ok_and(|n| n > 0); }
        let Ok(start) = start.parse::<u64>() else { return false };
        end.is_empty() || end.parse::<u64>().is_ok_and(|end| start <= end)
    })
}

fn parse_bounded_range(raw: &str) -> Option<ByteRange> {
    let (start, end) = raw.strip_prefix("bytes=")?.split_once('-')?;
    let (start, end) = (start.parse().ok()?, end.parse().ok()?);
    if start > end { return None; }
    Some(ByteRange { start, end })
}

fn media_mime(url: &str, upstream: Option<String>) -> String {
    if let Some(mime) = upstream.filter(|mime| !mime.eq_ignore_ascii_case("application/octet-stream")) { return mime; }
    let path = url.split(['?', '#']).next().unwrap_or(url).to_ascii_lowercase();
    let mime = if path.ends_with(".vtt") { "text/vtt" }
        else if path.ends_with(".aac") { "audio/aac" }
        else if path.ends_with(".m4a") { "audio/mp4" }
        else if path.ends_with(".mp3") { "audio/mpeg" }
        else if path.ends_with(".ts") { "video/mp2t" }
        else if path.ends_with(".m4s") || path.ends_with(".mp4") { "video/mp4" }
        else { "application/octet-stream" };
    mime.to_string()
}

async fn prefetch_body(mut response: reqwest::Response) -> Result<Vec<u8>, String> {
    const MAX: usize = 16 * 1024 * 1024;
    if response.content_length().is_some_and(|length| length > MAX as u64) { return Err("缓存块超过 16 MiB".into()); }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| "分片下载失败")? {
        if chunk.len() > MAX - bytes.len() { return Err("缓存块超过 16 MiB".into()); }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

pub async fn prefetch_segment(url: &str, range: Option<ByteRange>, validator: Option<&str>, protected_urls: &[String]) -> Result<bool, String> {
    crate::network_policy::parse_target(url)?;
    let Some(generation) = crate::media_cache::generation() else { return Ok(false) };
    let direct = if let Some(validator) = validator {
        let info = DIRECT_MEDIA.lock().ok().and_then(|map| map.get(url).cloned()).ok_or("媒体文件需要重新探测")?;
        if info.tag != validator { return Err("媒体文件已改变，请重新加载".into()); }
        Some(info)
    } else { None };
    let cache_key = range.map(|range| match &direct { Some(info) => direct_cache_key(url, range, &info.tag), None => range_key(url, range) }).unwrap_or_else(|| url.to_string());
    let lock = download_lock(&cache_key);
    let _guard = lock.lock().await;
    if crate::media_cache::contains(&cache_key) { return Ok(true); }
    if let Some(range) = range {
        if range.start > range.end || range.end.saturating_sub(range.start) >= 16 * 1024 * 1024 { return Err("无效的缓存范围".into()); }
        let header = format!("bytes={}-{}", range.start, range.end);
        let referer = format!("{}/", crate::net::base());
        let response = crate::net::get_with_range(url, std::time::Duration::from_secs(20), None, Some(&referer), Some(&header)).await?;
        if response.status() != reqwest::StatusCode::PARTIAL_CONTENT { return Err("服务器不支持字节范围".into()); }
        let (start, end, total) = response.headers().get(reqwest::header::CONTENT_RANGE).and_then(|v| v.to_str().ok())
            .and_then(parse_content_range).ok_or("无效的 Content-Range")?;
        if let Some(info) = &direct {
            if total != info.total || response.headers().get(reqwest::header::ETAG).and_then(|v| v.to_str().ok()) != Some(info.etag.as_str()) { return Err("媒体文件已改变，请重新加载".into()); }
        }
        if start != range.start || end != range.end { return Err("服务器返回的字节范围不匹配".into()); }
        let mime = Some(media_mime(url, response.headers().get(reqwest::header::CONTENT_TYPE).and_then(|v| v.to_str().ok()).map(str::to_string)));
        let bytes = prefetch_body(response).await?;
        if bytes.len() as u64 != end - start + 1 { return Err("字节范围响应长度不匹配".into()); }
        return Ok(crate::media_cache::put_entry(&cache_key, mime, Some(total), &bytes, generation, protected_urls));
    }
    // A foreground request may have completed while prefetch waited for the same object.
    let memory = KEY_CACHE.lock().ok().and_then(|cache| cache.get(url).cloned())
        .or_else(|| SEG_CACHE.lock().ok().and_then(|cache| cache.get(url).cloned()));
    if let Some((mime, bytes)) = memory { return Ok(crate::media_cache::put(&cache_key, Some(mime), &bytes, generation, protected_urls)); }
    let referer = format!("{}/", crate::net::base());
    let response = crate::net::get(url, std::time::Duration::from_secs(20), None, Some(&referer)).await?;
    if !response.status().is_success() { return Err(format!("HTTP {}", response.status())); }
    let mime = Some(media_mime(url, response.headers().get(reqwest::header::CONTENT_TYPE).and_then(|value| value.to_str().ok()).map(str::to_string)));
    let bytes = prefetch_body(response).await?;
    Ok(crate::media_cache::put(&cache_key, mime, &bytes, generation, protected_urls))
}

use tauri::http::{Response, StatusCode};

/// 本平台自定义协议的完整基址。
///
/// Tauri 的自定义协议地址随平台不同：Windows / Android 是 `http://<scheme>.localhost`，
/// macOS / iOS / Linux 是 `<scheme>://localhost`。m3u8 里的分片与 key 地址按它改写。
/// 前端 `src/api.ts` 的 `LOCAL` 必须与此一致，否则封面与视频全部加载失败。
#[cfg(any(target_os = "windows", target_os = "android"))]
pub const LOCAL_ORIGIN: &str = "http://hg.localhost";
#[cfg(not(any(target_os = "windows", target_os = "android")))]
pub const LOCAL_ORIGIN: &str = "hg://localhost";

const IMG_KEY: &[u8] = b"f5d965df75336270";
const IMG_IV: &[u8] = b"97b60394abc2fbe1";

static MEMORY_REVISION: AtomicU64 = AtomicU64::new(0);
static IMG_CACHE: Lazy<Mutex<HashMap<String, Arc<Vec<u8>>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static PL_CACHE: Lazy<Mutex<HashMap<String, (std::time::Instant, Arc<String>)>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static KEY_CACHE: Lazy<Mutex<HashMap<String, (String, Arc<Vec<u8>>)>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static SEG_CACHE: Lazy<Mutex<HashMap<String, (String, Arc<Vec<u8>>)>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

const IMG_CACHE_MAX: usize = 240;
const PL_CACHE_MAX: usize = 60;
const KEY_CACHE_MAX: usize = 120;
const SEG_CACHE_MAX: usize = 36;
const SEG_CACHE_MAX_BYTES: usize = 4 * 1024 * 1024;

fn cache_put<V: Clone>(map: &Mutex<HashMap<String, V>>, key: String, val: V, max: usize) {
    let mut m = map.lock().unwrap();
    if m.len() >= max {
        if let Some(k) = m.keys().next().cloned() {
            m.remove(&k);
        }
    }
    m.insert(key, val);
}

/* ───────────────────────── AES ───────────────────────── */

fn aes_cbc_decrypt(data: &[u8]) -> Option<Vec<u8>> {
    if data.is_empty() || data.len() % 16 != 0 {
        return None;
    }
    let cipher = Aes128::new_from_slice(IMG_KEY).ok()?;
    let mut prev = [0u8; 16];
    prev.copy_from_slice(IMG_IV);
    let mut out = Vec::with_capacity(data.len());
    for chunk in data.chunks(16) {
        let mut ct = [0u8; 16];
        ct.copy_from_slice(chunk);
        let mut block = ct;
        cipher.decrypt_block((&mut block).into());
        for i in 0..16 {
            out.push(block[i] ^ prev[i]);
        }
        prev = ct;
    }
    Some(out)
}

fn strip_padding(mut buf: Vec<u8>) -> Vec<u8> {
    let pad = *buf.last().unwrap_or(&0) as usize;
    if pad > 0 && pad <= 16 && buf.len() >= pad {
        if buf[buf.len() - pad..].iter().all(|b| *b as usize == pad) {
            buf.truncate(buf.len() - pad);
        }
    }
    buf
}

fn image_kind(buf: &[u8]) -> Option<&'static str> {
    if buf.len() < 12 {
        return None;
    }
    if buf[0] == 0xFF && buf[1] == 0xD8 {
        return Some("image/jpeg");
    }
    if buf.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
        return Some("image/png");
    }
    if buf.starts_with(b"GIF8") {
        return Some("image/gif");
    }
    if buf.starts_with(b"RIFF") && &buf[8..12] == b"WEBP" {
        return Some("image/webp");
    }
    None
}

/// 取封面：命中缓存直接返回，否则下载并按需解密。
pub async fn load_image(url: &str) -> Result<(String, Arc<Vec<u8>>), String> {
    let revision = MEMORY_REVISION.load(Ordering::SeqCst);
    if let Some(hit) = IMG_CACHE.lock().unwrap().get(url).cloned() {
        let kind = image_kind(&hit).unwrap_or("image/jpeg");
        return Ok((kind.to_string(), hit));
    }
    let (_, bytes) = fetch_bytes(url).await?;
    let plain = if image_kind(&bytes).is_some() {
        bytes
    } else {
        let dec = aes_cbc_decrypt(&bytes).ok_or_else(|| "封面解密失败".to_string())?;
        strip_padding(dec)
    };
    let kind = image_kind(&plain).unwrap_or("image/jpeg").to_string();
    let arc = Arc::new(plain);
    if MEMORY_REVISION.load(Ordering::SeqCst) == revision { cache_put(&IMG_CACHE, url.to_string(), arc.clone(), IMG_CACHE_MAX); }
    Ok((kind, arc))
}

/* ───────────────────────── HLS ───────────────────────── */

fn enc(s: &str) -> String {
    utf8_percent_encode(s, NON_ALPHANUMERIC).to_string()
}

fn dec(s: &str) -> String {
    percent_decode_str(s).decode_utf8_lossy().to_string()
}

fn absolutize(base: &str, target: &str) -> String {
    if target.starts_with("http://") || target.starts_with("https://") {
        return target.to_string();
    }
    if let Ok(b) = url::Url::parse(base) {
        if let Ok(j) = b.join(target) {
            return j.to_string();
        }
    }
    target.to_string()
}

/// 属性列表中的引号内可含逗号，不能直接 split(',')。
fn hls_attributes(line: &str) -> Option<(&str, Vec<&str>)> {
    let (tag, rest) = line.split_once(':')?;
    let mut attributes = Vec::new();
    let mut quoted = false;
    let mut start = 0;
    for (i, ch) in rest.char_indices() {
        if ch == '"' {
            quoted = !quoted;
        }
        if ch == ',' && !quoted {
            attributes.push(&rest[start..i]);
            start = i + 1;
        }
    }
    attributes.push(&rest[start..]);
    Some((tag, attributes))
}

fn map_uri_attributes(line: &str, mut rewrite: impl FnMut(&str) -> String) -> String {
    let Some((tag, attributes)) = hls_attributes(line) else {
        return line.to_string();
    };
    let mapped: Vec<String> = attributes
        .into_iter()
        .map(|attribute| {
            if let Some((key, value)) = attribute.split_once('=') {
                if key.trim() == "URI" {
                    if let Some(uri) = value
                        .trim()
                        .strip_prefix('"')
                        .and_then(|v| v.strip_suffix('"'))
                    {
                        return format!("{key}=\"{}\"", rewrite(uri));
                    }
                }
            }
            attribute.to_string()
        })
        .collect();
    format!("{tag}:{}", mapped.join(","))
}

fn rewrite_uri_attr(line: &str, prefix: &str) -> String {
    map_uri_attributes(line, |uri| format!("{prefix}/seg?u={}", enc(uri)))
}

/// 取 m3u8 并把 key / 子列表 / 分片地址改写到本地协议。
pub async fn load_playlist(url: &str, prefix: &str) -> Result<Arc<String>, String> {
    let cache_key = format!("{prefix}|{url}");
    let revision = MEMORY_REVISION.load(Ordering::SeqCst);
    if let Some((expires, hit)) = PL_CACHE.lock().unwrap().get(&cache_key).cloned() {
        if std::time::Instant::now() < expires { return Ok(hit); }
    }
    let (_, bytes) = fetch_bytes(url).await?;
    let text = std::str::from_utf8(&bytes).map_err(|_| "播放列表不是 UTF-8 文本")?;
    if !text.trim_start_matches('\u{feff}').starts_with("#EXTM3U") {
        return Err("响应不是 HLS 播放列表".into());
    }
    let arc = Arc::new(rewrite_playlist(url, text, prefix));
    let ttl = if text.lines().any(|line| line.trim() == "#EXT-X-ENDLIST") { 300 } else { 2 };
    if MEMORY_REVISION.load(Ordering::SeqCst) == revision {
        cache_put(&PL_CACHE, cache_key, (std::time::Instant::now() + std::time::Duration::from_secs(ttl), arc.clone()), PL_CACHE_MAX);
    }
    Ok(arc)
}

fn rewrite_playlist(url: &str, text: &str, prefix: &str) -> String {
    let mut out = String::with_capacity(text.len() + 512);
    for raw in text.trim_start_matches('\u{feff}').lines() {
        let line = raw.trim_end();
        if line.is_empty() {
            out.push('\n');
            continue;
        }
        if line.starts_with('#') {
            // 禁用可派生 URL 的内容引导；DATERANGE 保留时间线/SCTE-35 元数据。
            if line.starts_with("#EXT-X-CONTENT-STEERING:") {
                continue;
            }
            if line.starts_with("#EXT-X-DATERANGE:") {
                if let Some((tag, attributes)) = hls_attributes(line) {
                    let safe: Vec<&str> = attributes
                        .into_iter()
                        .filter(|attribute| {
                            let key = attribute
                                .split('=')
                                .next()
                                .unwrap_or("")
                                .trim()
                                .to_ascii_uppercase();
                            !key.contains("URI") && key != "X-ASSET-LIST"
                        })
                        .collect();
                    out.push_str(&format!("{tag}:{}\n", safe.join(",")));
                }
                continue;
            }
            if line.contains("URI=\"") {
                // KEY/MAP/MEDIA/SESSION-KEY/PART/PRELOAD-HINT 等 URI 都必须经过目标检查。
                let absolute = absolutize_uri_in_attr(url, line);
                out.push_str(&rewrite_uri_attr(&absolute, prefix));
            } else {
                out.push_str(line);
            }
        } else {
            let absolute = absolutize(url, line);
            out.push_str(&format!("{prefix}/seg?u={}", enc(&absolute)));
        }
        out.push('\n');
    }

    out
}

fn absolutize_uri_in_attr(base: &str, line: &str) -> String {
    map_uri_attributes(line, |uri| absolutize(base, uri))
}

/// 加载分片或 AES Key（带内存缓存，避免拖动进度条时重复拉取同一 Key 或分片导致卡顿）。
pub async fn load_segment(url: &str) -> Result<(Option<String>, Arc<Vec<u8>>), String> {
    let revision = MEMORY_REVISION.load(Ordering::SeqCst);
    crate::network_policy::parse_target(url)?;
    let lock = download_lock(url);
    let _guard = lock.lock().await;
    if let Some((mime, bytes)) = crate::media_cache::get(url) { return Ok((mime, Arc::new(bytes))); }
    if let Some((ctype, hit)) = KEY_CACHE.lock().unwrap().get(url).cloned() {
        return Ok((Some(ctype), hit));
    }
    if let Some((ctype, hit)) = SEG_CACHE.lock().unwrap().get(url).cloned() {
        return Ok((Some(ctype), hit));
    }
    let (ctype, bytes) = fetch_bytes(url).await?;
    let mime = media_mime(url, ctype.clone());
    let len = bytes.len();
    let arc = Arc::new(bytes);
    let playlist = mime.to_ascii_lowercase().contains("mpegurl") || arc.starts_with(b"#EXTM3U") || arc.starts_with(b"\xef\xbb\xbf#EXTM3U");
    if !playlist && MEMORY_REVISION.load(Ordering::SeqCst) == revision && len <= 65536 {
        cache_put(&KEY_CACHE, url.to_string(), (mime.clone(), arc.clone()), KEY_CACHE_MAX);
    } else if !playlist && MEMORY_REVISION.load(Ordering::SeqCst) == revision && len <= SEG_CACHE_MAX_BYTES {
        cache_put(&SEG_CACHE, url.to_string(), (mime.clone(), arc.clone()), SEG_CACHE_MAX);
    }
    Ok((Some(mime), arc))
}

/// 清空封面 / 播放列表 / 分片内存缓存
pub fn clear_caches() {
    MEMORY_REVISION.fetch_add(1, Ordering::SeqCst);
    if let Ok(mut g) = IMG_CACHE.lock() { g.clear(); }
    if let Ok(mut g) = PL_CACHE.lock() { g.clear(); }
    if let Ok(mut g) = KEY_CACHE.lock() { g.clear(); }
    if let Ok(mut g) = SEG_CACHE.lock() { g.clear(); }
}

/* ───────────────────────── 协议响应 ───────────────────────── */

fn respond(status: u16, ctype: &str, body: Vec<u8>, cache: &str) -> Response<Vec<u8>> {
    let len = body.len().to_string();
    Response::builder()
        .status(StatusCode::from_u16(status).unwrap_or(StatusCode::OK))
        .header("Content-Type", ctype)
        .header("Content-Length", len)
        .header("Accept-Ranges", "bytes")
        .header("X-Content-Type-Options", "nosniff")
        .header("Access-Control-Expose-Headers", "Content-Length, Content-Type, Accept-Ranges")
        .header("Cache-Control", cache)
        .body(body)
        .unwrap_or_else(|_| Response::new(Vec::new()))
}

/// 主清单的子清单也经 /seg 返回：必须继续改写，不能把内层 URL 原样交给播放器。
fn segment_response(
    target: &str,
    ctype: Option<&str>,
    bytes: Vec<u8>,
    origin: &str,
) -> Response<Vec<u8>> {
    let playlist = ctype.is_some_and(|t| t.to_ascii_lowercase().contains("mpegurl"))
        || bytes.starts_with(b"#EXTM3U")
        || bytes.starts_with(b"\xef\xbb\xbf#EXTM3U");
    if playlist {
        observe_playlist(target);
        return match std::str::from_utf8(&bytes) {
            Ok(text) => respond(
                200,
                "application/vnd.apple.mpegurl",
                rewrite_playlist(target, text, origin).into_bytes(),
                // Media playlists can change even when their URL stays the same.
                "no-store",
            ),
            Err(_) => respond(
                502,
                "text/plain",
                b"invalid playlist encoding".to_vec(),
                "no-store",
            ),
        };
    }
    respond(
        200,
        ctype.unwrap_or("application/octet-stream"),
        bytes,
        if crate::media_cache::generation().is_some() { "no-store" } else { "public, max-age=3600" },
    )
}

async fn range_response(target: &str, raw_range: &str, is_direct: bool) -> Response<Vec<u8>> {
    let cache_generation = crate::media_cache::generation();
    if !valid_range_header(raw_range) {
        return respond(400, "text/plain", b"invalid range".to_vec(), "no-store");
    }
    if let Err(e) = crate::network_policy::parse_target(target) { return respond(403, "text/plain", e.into_bytes(), "no-store"); }
    let bounded = parse_bounded_range(raw_range);
    let probe_allowed = DIRECT_PROBE_FAILURES.lock().ok().is_none_or(|failures| failures.get(&playlist_id(target)).is_none_or(|at| at.elapsed() >= std::time::Duration::from_secs(30)));
    if is_direct && probe_allowed && crate::media_cache::generation().is_some() && DIRECT_MEDIA.lock().ok().is_some_and(|map| !map.contains_key(target)) {
        // Probe before starting a large open-ended request; unsupported origins retain the original path.
        if probe_direct(target).await.is_err() {
            if let Ok(mut failures) = DIRECT_PROBE_FAILURES.lock() {
                failures.retain(|_, at| at.elapsed() < std::time::Duration::from_secs(30));
                if failures.len() >= 128 { failures.clear(); }
                failures.insert(playlist_id(target), std::time::Instant::now());
            }
        }
    }
    let start = if raw_range.contains(',') { None } else { raw_range.strip_prefix("bytes=").and_then(|value| value.split_once('-')).and_then(|(start, _)| start.parse::<u64>().ok()) };
    let direct = if is_direct && crate::media_cache::generation().is_some() {
        if let Ok(mut map) = DIRECT_MEDIA.lock() {
            map.get_mut(target).map(|entry| { if let Some(start) = start { entry.cursor = start; } entry.clone() })
        } else { None }
    } else { None };
    if let (Some(info), Some(start)) = (&direct, start) {
        let requested = ByteRange { start, end: bounded.map_or(info.total.saturating_sub(1), |r| r.end) };
        if let Some((mime, bytes)) = direct_cache_read(target, requested, info.total, &info.tag) {
            let end = start + bytes.len() as u64 - 1;
            return byte_response(206, mime.as_deref(), Some(&format!("bytes {start}-{end}/{}", info.total)), bytes);
        }
    }
    let cache_key = bounded.map(|r| range_key(target, r));
    let direct_key = match (&direct, start) {
        (Some(info), Some(start)) if start < info.total => {
            let first = start / DIRECT_BLOCK * DIRECT_BLOCK;
            Some(direct_cache_key(target, ByteRange { start: first, end: first.saturating_add(DIRECT_BLOCK - 1).min(info.total - 1) }, &info.tag))
        }
        _ => None,
    };
    let lock = download_lock(direct_key.as_deref().or(cache_key.as_deref()).unwrap_or(target));
    let _guard = lock.lock().await;
    if let (Some(info), Some(start)) = (&direct, start) {
        let requested = ByteRange { start, end: bounded.map_or(info.total.saturating_sub(1), |r| r.end) };
        if let Some((mime, bytes)) = direct_cache_read(target, requested, info.total, &info.tag) {
            let end = start + bytes.len() as u64 - 1;
            return byte_response(206, mime.as_deref(), Some(&format!("bytes {start}-{end}/{}", info.total)), bytes);
        }
    }
    if !is_direct {
        if let (Some(range), Some(key)) = (bounded, cache_key.as_deref()) {
            if let Some((mime, Some(total), bytes)) = crate::media_cache::get_entry(key) {
                if range.end < total && bytes.len() as u64 == range.end - range.start + 1 {
                    return byte_response(206, mime.as_deref(), Some(&format!("bytes {}-{}/{total}", range.start, range.end)), bytes);
                }
            }
        }
    }
    let referer = format!("{}/", crate::net::base());
    let capped = match (&direct, start) {
        (Some(info), Some(start)) if start < info.total => {
            let end = bounded.map_or(info.total - 1, |range| range.end.min(info.total - 1)).min(start.saturating_add(8 * 1024 * 1024 - 1));
            Some(format!("bytes={start}-{end}"))
        }
        _ => None,
    };
    match crate::net::get_with_range(target, std::time::Duration::from_secs(20), None, Some(&referer), Some(capped.as_deref().unwrap_or(raw_range))).await {
        Ok(response) => {
            let status = response.status().as_u16();
            let content_range = response.headers().get(reqwest::header::CONTENT_RANGE).and_then(|v| v.to_str().ok()).map(str::to_string);
            let same_direct = direct.as_ref().is_some_and(|info| response.headers().get(reqwest::header::ETAG).and_then(|v| v.to_str().ok()) == Some(info.etag.as_str()));
            if direct.is_some() && status == 206 && !same_direct {
                if let Ok(mut map) = DIRECT_MEDIA.lock() { map.remove(target); }
            }
            let mime = response.headers().get(reqwest::header::CONTENT_TYPE).and_then(|v| v.to_str().ok()).map(str::to_string);
            match response.bytes().await {
                Ok(bytes) => {
                    if status == 206 {
                        let valid = if raw_range.contains(',') {
                            mime.as_deref().is_some_and(|value| value.to_ascii_lowercase().starts_with("multipart/byteranges"))
                        } else {
                            let expected = capped.as_deref().and_then(parse_bounded_range).or(bounded);
                            content_range.as_deref().and_then(parse_content_range).is_some_and(|(actual_start, end, _)| {
                                bytes.len() as u64 == end - actual_start + 1
                                    && start.is_none_or(|requested| actual_start == requested)
                                    && expected.is_none_or(|requested| actual_start == requested.start && end <= requested.end)
                            })
                        };
                        if !valid { return respond(502, "text/plain", b"invalid upstream range".to_vec(), "no-store"); }
                    }
                    if status == 206 {
                        if let (Some(generation), Some((first, last, total))) = (cache_generation, content_range.as_deref().and_then(parse_content_range)) {
                            if let Some(info) = direct.as_ref().filter(|info| same_direct && info.total == total) {
                                // Save complete aligned blocks already fetched for playback, avoiding a second download.
                                let mut offset = first.div_ceil(DIRECT_BLOCK) * DIRECT_BLOCK;
                                let mut blocks = Vec::new();
                                while offset <= last {
                                    let end = offset.saturating_add(DIRECT_BLOCK - 1).min(total - 1);
                                    if end > last { break; }
                                    blocks.push((direct_cache_key(target, ByteRange { start: offset, end }, &info.tag), offset, end));
                                    offset = end + 1;
                                }
                                let protected: Vec<_> = blocks.iter().map(|(key, _, _)| key.clone()).collect();
                                for (key, offset, end) in blocks {
                                    let data = &bytes[(offset - first) as usize..=(end - first) as usize];
                                    crate::media_cache::put_entry(&key, mime.clone(), Some(total), data, generation, &protected);
                                }
                            } else if !is_direct && bounded.is_some_and(|range| range.start == first && range.end == last) && bytes.len() <= 16 * 1024 * 1024 {
                                crate::media_cache::put_entry(&range_key(target, ByteRange { start: first, end: last }), mime.clone(), Some(total), &bytes, generation, &[]);
                            }
                        }
                    }
                    byte_response(status, mime.as_deref(), content_range.as_deref(), bytes.to_vec())
                }
                Err(_) => respond(502, "text/plain", b"range download failed".to_vec(), "no-store"),
            }
        }
        Err(e) => respond(502, "text/plain", e.into_bytes(), "no-store"),
    }
}

fn byte_response(status: u16, mime: Option<&str>, range: Option<&str>, bytes: Vec<u8>) -> Response<Vec<u8>> {
    let mut response = respond(status, mime.unwrap_or("application/octet-stream"), bytes, "no-store");
    if let Some(range) = range.and_then(|r| tauri::http::HeaderValue::from_str(r).ok()) {
        response.headers_mut().insert("Content-Range", range);
    }
    response.headers_mut().insert("Access-Control-Expose-Headers", tauri::http::HeaderValue::from_static("Content-Length, Content-Type, Accept-Ranges, Content-Range"));
    response
}

/// 统一入口：`<LOCAL_ORIGIN>/img?u=` / `hls?u=` / `seg?u=`
///
/// `origin` 是本平台自定义协议的完整基址，见 [`LOCAL_ORIGIN`]；用于改写 m3u8 里的
/// 分片与 key 地址。正常情况下调用方直接传 [`LOCAL_ORIGIN`]。
pub async fn handle(path: &str, query: &str, origin: &str, range: Option<&str>) -> Response<Vec<u8>> {
    let target = query
        .split('&')
        .find_map(|kv| kv.strip_prefix("u="))
        .map(dec)
        .unwrap_or_default();

    if target.is_empty() {
        return respond(400, "text/plain", b"missing u".to_vec(), "no-store");
    }

    let started = std::time::Instant::now();
    let route = match path {
        "/img" => "image",
        "/hls" => "playlist",
        "/seg" => "segment_or_key",
        _ => "unknown",
    };
    crate::playback_log::record(
        "proxy.begin",
        serde_json::json!({"route": route, "resource": crate::playback_log::resource_id(&target)}),
    );
    let response = match path {
        "/img" => match load_image(&target).await {
            Ok((kind, bytes)) => {
                respond(200, &kind, bytes.as_ref().clone(), "public, max-age=86400")
            }
            Err(e) => respond(502, "text/plain", e.into_bytes(), "no-store"),
        },
        "/hls" => match load_playlist(&target, origin).await {
            Ok(text) => respond(
                200,
                "application/vnd.apple.mpegurl",
                text.as_bytes().to_vec(),
                "no-store",
            ),
            Err(e) => respond(502, "text/plain", e.into_bytes(), "no-store"),
        },
        "/seg" if range.is_some() => range_response(&target, range.unwrap(), query.split('&').any(|part| part == "direct=1")).await,
        "/seg" => match load_segment(&target).await {
            Ok((ctype, bytes)) => {
                segment_response(&target, ctype.as_deref(), bytes.as_ref().clone(), origin)
            }
            Err(e) => respond(502, "text/plain", e.into_bytes(), "no-store"),
        },
        _ => respond(404, "text/plain", b"not found".to_vec(), "no-store"),
    };
    crate::playback_log::record(
        "proxy.end",
        serde_json::json!({"route": route, "resource": crate::playback_log::resource_id(&target), "status": response.status().as_u16(), "bytes": response.body().len(), "elapsed_ms": started.elapsed().as_millis() as u64}),
    );
    response
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore = "local HTTP integration test; run individually with loopback access"]
    async fn range_cache_local_server() {
        use std::io::{Read, Write};
        let _test_guard = crate::media_cache::TEST_LOCK.lock().unwrap();
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            for (sequence, incoming) in listener.incoming().take(8).enumerate() {
                let mut stream = incoming.unwrap();
                stream.set_read_timeout(Some(std::time::Duration::from_secs(5))).unwrap();
                let mut request = Vec::new(); let mut chunk = [0; 2048];
                while !request.ends_with(b"\r\n\r\n") {
                    let size = stream.read(&mut chunk).unwrap();
                    if size == 0 { break; }
                    request.extend_from_slice(&chunk[..size]);
                }
                let request = String::from_utf8(request).unwrap();
                if request.lines().next().unwrap().contains(".aac") || request.lines().next().unwrap().contains(".vtt") {
                    let text = request.lines().next().unwrap().contains(".vtt");
                    let payload: &[u8] = if text { b"WEBVTT\n\n00:00.000 --> 00:04.000\nCached subtitle\n" } else { b"audio fixture" };
                    // Exercise type inference for generic upstream content types.
                    write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", payload.len()).unwrap();
                    stream.write_all(payload).unwrap();
                    continue;
                }
                if request.lines().next().unwrap().contains(".m3u8") {
                    let payload = format!("#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\nseg{sequence}.ts\n#EXT-X-ENDLIST\n");
                    write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", payload.len(), payload).unwrap();
                    continue;
                }
                let header = request.lines().find_map(|line| line.split_once(':').filter(|(name, _)| name.eq_ignore_ascii_case("range")).map(|(_, value)| value.trim())).unwrap();
                let range = parse_bounded_range(header).unwrap();
                let bytes = b"01234567";
                let payload = &bytes[range.start as usize..=range.end as usize];
                write!(stream, "HTTP/1.1 206 Partial Content\r\nContent-Type: video/mp4\r\nETag: \"v1\"\r\nContent-Range: bytes {}-{}/8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", range.start, range.end, payload.len()).unwrap();
                stream.write_all(payload).unwrap();
            }
        });
        let unique = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
        let dir = std::env::temp_dir().join(format!("hghub-range-net-{}-{unique}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        crate::network_policy::bind_security(&dir);
        crate::network_policy::set_strict_security(false).unwrap();
        crate::media_cache::bind(&dir);
        crate::media_cache::set_limit(128).unwrap();
        let url = format!("http://{address}/video.mp4");
        let (total, tag) = probe_direct(&url).await.unwrap();
        assert_eq!(total, 8);
        assert!(prefetch_segment(&url, Some(ByteRange { start: 0, end: 7 }), Some(&tag), &[]).await.unwrap());
        let changing = format!("http://{address}/changing.m3u8");
        let (_, first) = load_segment(&changing).await.unwrap();
        let (_, second) = load_segment(&changing).await.unwrap();
        assert_ne!(first, second, "media playlists must not be frozen in the small-object cache");
        let root = format!("http://{address}/root.m3u8");
        let first = load_playlist(&root, LOCAL_ORIGIN).await.unwrap();
        let key = format!("{LOCAL_ORIGIN}|{root}");
        PL_CACHE.lock().unwrap().get_mut(&key).unwrap().0 = std::time::Instant::now();
        let second = load_playlist(&root, LOCAL_ORIGIN).await.unwrap();
        assert_ne!(first, second, "an expired root playlist must be refetched");
        let audio = format!("http://{address}/selected.aac");
        let subtitles = format!("http://{address}/selected.vtt");
        assert!(prefetch_segment(&audio, None, None, &[]).await.unwrap());
        assert!(prefetch_segment(&subtitles, None, None, &[]).await.unwrap());
        server.join().unwrap();
        let (mime, bytes) = load_segment(&audio).await.unwrap();
        assert_eq!(mime.as_deref(), Some("audio/aac")); assert_eq!(bytes.as_slice(), b"audio fixture");
        let (mime, bytes) = load_segment(&subtitles).await.unwrap();
        assert_eq!(mime.as_deref(), Some("text/vtt")); assert!(bytes.starts_with(b"WEBVTT"));
        let response = range_response(&url, "bytes=2-4", true).await;
        assert_eq!(response.status(), 206);
        assert_eq!(response.headers()["Content-Range"], "bytes 2-4/8");
        assert_eq!(response.body(), b"234");
        crate::media_cache::clear().unwrap();
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[tokio::test]
    async fn direct_ranges_read_exact_bytes_from_cached_blocks() {
        let _test_guard = crate::media_cache::TEST_LOCK.lock().unwrap();
        let unique = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
        let dir = std::env::temp_dir().join(format!("hghub-range-{}-{unique}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        crate::media_cache::bind(&dir);
        crate::media_cache::set_limit(128).unwrap();
        let url = "https://example.test/movie.mp4";
        let info = DirectInfo { total: 8, cursor: 0, etag: "\"v1\"".into(), tag: "test-v1".into() };
        DIRECT_MEDIA.lock().unwrap().insert(url.into(), info.clone());
        let key = direct_cache_key(url, ByteRange { start: 0, end: 7 }, &info.tag);
        assert!(crate::media_cache::put_entry(&key, Some("video/mp4".into()), Some(8), b"01234567", crate::media_cache::generation().unwrap(), &[]));
        let response = range_response(url, "bytes=2-4", true).await;
        assert_eq!(response.status(), 206);
        assert_eq!(response.headers()["Content-Range"], "bytes 2-4/8");
        assert_eq!(response.body(), b"234");
        let response = range_response(url, "bytes=5-", true).await;
        assert_eq!(response.status(), 206);
        assert_eq!(response.headers()["Content-Range"], "bytes 5-7/8");
        assert_eq!(response.body(), b"567");
        assert_eq!(direct_cursor(url), 5);
        let total = DIRECT_BLOCK + 5;
        DIRECT_MEDIA.lock().unwrap().insert(url.into(), DirectInfo { total, ..info.clone() });
        let generation = crate::media_cache::generation().unwrap();
        let first = direct_cache_key(url, ByteRange { start: 0, end: DIRECT_BLOCK - 1 }, &info.tag);
        let second = direct_cache_key(url, ByteRange { start: DIRECT_BLOCK, end: total - 1 }, &info.tag);
        assert!(crate::media_cache::put_entry(&first, Some("video/mp4".into()), Some(total), &vec![b'A'; DIRECT_BLOCK as usize], generation, &[]));
        assert!(crate::media_cache::put_entry(&second, Some("video/mp4".into()), Some(total), b"BCDEF", generation, &[]));
        let response = range_response(url, "bytes=1048574-1048578", true).await;
        assert_eq!(response.status(), 206);
        assert_eq!(response.body(), b"AABCD");
        assert_eq!(response.headers()["Content-Range"], "bytes 1048574-1048578/1048581");
        assert_eq!(range_response(url, "bytes=4-1", true).await.status(), 400);
        DIRECT_MEDIA.lock().unwrap().remove(url);
        crate::media_cache::clear().unwrap();
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn byte_ranges_have_distinct_keys_and_strict_content_ranges() {
        let a = ByteRange { start: 0, end: 99 };
        let b = ByteRange { start: 100, end: 199 };
        assert_ne!(range_key("https://example.test/video", a), range_key("https://example.test/video", b));
        assert_eq!(parse_content_range("bytes 0-99/200"), Some((0, 99, 200)));
        assert!(parse_content_range("bytes 0-200/200").is_none());
        assert!(parse_content_range("bytes 0-99/*").is_none());
        assert!(parse_bounded_range("bytes=0-99").is_some());
        assert!(parse_bounded_range("bytes=0-").is_none());
        assert!(parse_bounded_range("bytes=99-0").is_none());
        for value in ["bytes=0-", "bytes=-500", "bytes=0-9,20-29"] { assert!(valid_range_header(value)); }
        for value in ["bytes=9-0", "bytes=-0", "bytes=--", "bytes=0-1,"] { assert!(!valid_range_header(value)); }
    }

    #[test]
    fn dateranges_keep_timing_and_scte_metadata_but_drop_external_resources() {
        let line = "#EXTM3U\n#EXT-X-DATERANGE:ID=\"event\",START-DATE=\"2026-11-07T00:00:00Z\",DURATION=4,SCTE35-OUT=0xFC,X-TEXT=\"a,b\",X-ASSET-URI=\"https://evil.example/ad\",X-ASSET-LIST=\"https://evil.example/list.json\"\n";
        let out = rewrite_playlist("https://cdn.example/master.m3u8", line, LOCAL_ORIGIN);
        assert!(out.contains("DURATION=4,SCTE35-OUT=0xFC,X-TEXT=\"a,b\""));
        assert!(out.contains("START-DATE="));
        assert!(!out.contains("evil.example") && !out.contains("X-ASSET"));
    }

    #[test]
    fn every_uri_attribute_is_rewritten_without_splitting_quoted_commas() {
        let line = "#EXT-X-MEDIA:NAME=\"audio,main\",URI=\"first.m3u8\",URI=\"second.m3u8\"";
        let absolute = absolutize_uri_in_attr("https://cdn.example/master.m3u8", line);
        let rewritten = rewrite_uri_attr(&absolute, LOCAL_ORIGIN);
        assert_eq!(
            rewritten.matches(&format!("{LOCAL_ORIGIN}/seg?u=")).count(),
            2
        );
        assert!(rewritten.contains("NAME=\"audio,main\""));
        assert!(!rewritten.contains("URI=\"https://"));
    }

    #[test]
    fn nested_playlists_and_alternate_uris_stay_behind_proxy() {
        let text = "#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,URI=\"audio/list.m3u8\"\n#EXT-X-SESSION-KEY:METHOD=AES-128,URI=\"http://127.0.0.1/key\"\n#EXT-X-PART:DURATION=1,URI=\"part.ts\"\nvariant/list.m3u8\n";
        let response = segment_response(
            "https://cdn.example/master.m3u8",
            Some("application/octet-stream"),
            text.as_bytes().to_vec(),
            LOCAL_ORIGIN,
        );
        let body = std::str::from_utf8(response.body()).unwrap();
        assert_eq!(body.matches(&format!("{LOCAL_ORIGIN}/seg?u=")).count(), 4);
        assert!(!body.contains("URI=\"http://127.0.0.1"));
        assert!(body.contains("https%3A%2F%2Fcdn%2Eexample%2Faudio%2Flist%2Em3u8"));
        assert_eq!(
            response.headers()["Content-Type"],
            "application/vnd.apple.mpegurl"
        );
        assert_eq!(response.headers()["X-Content-Type-Options"], "nosniff");
        assert!(!response
            .headers()
            .contains_key("Access-Control-Allow-Origin"));
        let optional = rewrite_playlist("https://cdn.example/list.m3u8",
            "#EXTM3U\n#EXT-X-CONTENT-STEERING:SERVER-URI=\"https://other.example/list.json\"\n#EXT-X-DATERANGE:ID=\"ad\",X-ASSET-LIST=\"http://127.0.0.1/assets\"\nsegment.ts\n", LOCAL_ORIGIN);
        assert!(!optional.contains("CONTENT-STEERING") && !optional.contains("X-ASSET-LIST"));
        assert!(optional.contains("#EXT-X-DATERANGE:ID=\"ad\""));
        let bom = segment_response(
            "https://cdn.example/list.m3u8",
            None,
            b"\xef\xbb\xbf#EXTM3U\nsegment.ts\n".to_vec(),
            LOCAL_ORIGIN,
        );
        assert!(bom.body().starts_with(b"#EXTM3U\n"));
    }

    /// 联网测试：默认跳过，手动跑 `cargo test --lib -- --ignored`。
    /// 依赖上游 `/api/videos/117/play` 返回的实时播放地址。
    #[tokio::test]
    #[ignore = "联网测试：依赖上游实时播放地址，手动用 --ignored 运行"]
    async fn live_play_chain() {
        use crate::net::edge;
        let play = edge(
            &crate::net::base(),
            "GET",
            "/api/videos/117/play?ep=3&page_texts=0",
            None,
            None,
        )
        .await
        .expect("play api");
        let url = play["video_url"].as_str().expect("video_url").to_string();
        println!("play url: {}", &url[..url.len().min(90)]);
        let (_, bytes) = fetch_bytes(&url).await.expect("fetch playlist");
        let text = String::from_utf8_lossy(&bytes);
        println!(
            "raw playlist len={} head={}",
            text.len(),
            &text[..text.len().min(160)]
        );
        let q = format!("u={}", enc(&url));
        let resp = handle("/hls", &q, LOCAL_ORIGIN, None).await;
        let body = String::from_utf8_lossy(resp.body()).to_string();
        println!("proxied status={} len={}", resp.status(), body.len());
        assert!(body.contains("#EXTM3U"));
        // 取一个分片验证
        let seg_line = body
            .lines()
            .find(|l| !l.starts_with('#') && l.contains("/seg?u="))
            .expect("seg line")
            .to_string();
        println!("seg line: {}", &seg_line[..seg_line.len().min(120)]);
        let seg_q = seg_line.split("?u=").nth(1).unwrap();
        let seg = handle("/seg", &format!("u={seg_q}"), LOCAL_ORIGIN, None).await;
        println!("segment status={} len={}", seg.status(), seg.body().len());
        assert_eq!(seg.status(), 200);
        assert!(seg.body().len() > 1000);
    }

    /// 离线回归：不再依赖带 auth_key 时效的真实上游地址（旧地址已过期，会 403）。
    /// 与真实播放列表同构：带签名的分片地址 + 加密 KEY + 相对路径分片。
    #[test]
    fn playlist_rewrite_works() {
        let base = "https://cdn.example/videos5/abc/abc.m3u8?auth_key=9999999999-0-0-deadbeef&v=3&via=hgdj";
        let text = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin?auth_key=9999999999-0-0-deadbeef\"\n#EXTINF:4,\nseg-1.ts?auth_key=9999999999-0-0-deadbeef\n";
        let body = rewrite_playlist(base, text, LOCAL_ORIGIN);

        assert!(body.contains("#EXTM3U"), "not a playlist: {body}");
        assert!(
            body.contains(&format!("{LOCAL_ORIGIN}/seg?u=")),
            "segments not rewritten: {body}"
        );
        // 分片必须绝对化到源站，并保留签名查询串。
        assert!(
            body.contains("https%3A%2F%2Fcdn%2Eexample%2Fvideos5%2Fabc%2Fseg%2D1%2Ets%3Fauth%5Fkey%3D"),
            "segment not absolutized with query: {body}"
        );
        // 加密 KEY 也要走本地代理，否则 hls.js 会直接打源站被 CORS 拦住。
        assert!(
            body.contains("URI=\"") && body.contains("%2Fkey%2Ebin%3Fauth%5Fkey%3D"),
            "key uri not rewritten: {body}"
        );
        assert!(!body.contains("URI=\"key.bin"), "key uri left relative");
    }

    /// 离线回归：用已知明文 + 项目内置 key/IV 构造密文，验证解密、去填充与类型识别。
    /// 真实封面抓取那条仍保留为 `#[ignore]` 联网测试。
    #[test]
    fn cover_decrypt_roundtrip() {
        use aes::cipher::BlockEncrypt;

        let plain = b"\xFF\xD8\xFF\xE0cover-payload-for-test".to_vec();
        let mut buf = plain.clone();
        let pad = 16 - plain.len() % 16;
        buf.extend(std::iter::repeat_n(pad as u8, pad));

        let cipher = Aes128::new_from_slice(IMG_KEY).expect("key");
        let mut prev = [0u8; 16];
        prev.copy_from_slice(IMG_IV);
        let mut encrypted = Vec::with_capacity(buf.len());
        for chunk in buf.chunks(16) {
            let mut block = [0u8; 16];
            block.copy_from_slice(chunk);
            for i in 0..16 {
                block[i] ^= prev[i];
            }
            let mut out_block = block;
            cipher.encrypt_block((&mut out_block).into());
            encrypted.extend_from_slice(&out_block);
            prev = out_block;
        }

        let decrypted = aes_cbc_decrypt(&encrypted).expect("decrypt");
        let stripped = strip_padding(decrypted);
        assert_eq!(stripped, plain);
        assert_eq!(image_kind(&stripped), Some("image/jpeg"));
    }

    /// 联网测试：默认跳过。封面地址带时效签名，不能硬编码进仓库，
    /// 需要用当次上游返回的地址显式传入：
    /// `HGHUB_TEST_COVER_URL='https://…?auth_key=…' cargo test --lib -- --ignored`
    #[tokio::test]
    #[ignore = "联网测试：需要 HGHUB_TEST_COVER_URL，手动用 --ignored 运行"]
    async fn cover_decrypt_works() {
        let url = std::env::var("HGHUB_TEST_COVER_URL")
            .expect("需要设置 HGHUB_TEST_COVER_URL 为当前有效的封面地址");
        match load_image(&url).await {
            Ok((kind, bytes)) => {
                println!("kind={kind} len={}", bytes.len());
                assert!(kind.starts_with("image/"));
            }
            Err(e) => panic!("image failed: {e}"),
        }
    }
}
