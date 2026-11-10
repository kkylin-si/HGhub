//! Bounded disk cache. Only complete objects are visible to readers.
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{collections::HashMap, path::{Path, PathBuf}, sync::Mutex, time::{Instant, SystemTime, UNIX_EPOCH}};

#[derive(Clone, Serialize, Deserialize)]
struct Entry { size: u64, accessed: u64, mime: Option<String>, #[serde(default)] total: Option<u64> }
#[derive(Default, Serialize, Deserialize)]
struct Index { max_mib: u32, entries: HashMap<String, Entry> }
struct Store { root: PathBuf, index: Index, generation: u64, last_access: u64, dirty: bool, flushed: Instant }
#[cfg(test)]
pub(crate) static TEST_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));
static STORE: Lazy<Mutex<Option<Store>>> = Lazy::new(|| Mutex::new(None));
static SESSIONS: Lazy<Mutex<HashMap<String, tokio::sync::watch::Sender<bool>>>> = Lazy::new(|| Mutex::new(HashMap::new()));
pub static PREFETCH_SLOT: Lazy<tokio::sync::Semaphore> = Lazy::new(|| tokio::sync::Semaphore::new(1));
pub fn start_session(id: String) -> Result<(), String> {
    if id.is_empty() || id.len() > 128 { return Err("无效的预缓存任务".into()); }
    let mut sessions = SESSIONS.lock().map_err(|_| "缓存任务锁失败")?;
    if sessions.contains_key(&id) || sessions.len() >= 64 { return Err("预缓存任务过多或已存在".into()); }
    sessions.insert(id, tokio::sync::watch::channel(false).0);
    Ok(())
}
pub fn cancel_session(id: &str) {
    if let Ok(mut sessions) = SESSIONS.lock() {
        if let Some(sender) = sessions.remove(id) { let _ = sender.send(true); }
    }
}
fn cancel_all() {
    if let Ok(mut sessions) = SESSIONS.lock() { for (_, sender) in sessions.drain() { let _ = sender.send(true); } }
}
pub fn session(id: &str) -> Option<tokio::sync::watch::Receiver<bool>> {
    SESSIONS.lock().ok()?.get(id).map(|sender| sender.subscribe())
}
fn now() -> u64 { SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as u64 }
fn key(url: &str) -> String { format!("{:x}", Sha256::digest(url.as_bytes())) }
fn valid_key(id: &str) -> bool { id.len() == 64 && id.bytes().all(|b| b.is_ascii_hexdigit()) }
fn save(store: &mut Store) -> Result<(), String> {
    let data = serde_json::to_vec(&store.index).map_err(|e| e.to_string())?;
    let tmp = store.root.join("index.tmp");
    std::fs::write(&tmp, data).and_then(|_| std::fs::rename(tmp, store.root.join("index.json"))).map_err(|e| e.to_string())?;
    store.dirty = false; store.flushed = Instant::now(); Ok(())
}
fn remove(store: &mut Store, id: &str) -> Result<(), String> {
    match std::fs::remove_file(store.root.join(id)) { Ok(()) => {}, Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}, Err(e) => return Err(e.to_string()) }
    store.index.entries.remove(id); store.dirty = true; Ok(())
}
fn trim(store: &mut Store) -> Result<(), String> {
    let limit = u64::from(store.index.max_mib) * 1024 * 1024;
    let mut size: u64 = store.index.entries.values().map(|e| e.size).sum();
    let mut oldest: Vec<_> = store.index.entries.iter().map(|(id, entry)| (id.clone(), entry.clone())).collect();
    oldest.sort_by_key(|(_, entry)| entry.accessed);
    for (id, entry) in oldest { if size <= limit { break; } remove(store, &id)?; size = size.saturating_sub(entry.size); }
    Ok(())
}
pub fn bind(dir: &Path) {
    let root = dir.join("playback-cache");
    if std::fs::create_dir_all(&root).is_err() { return; }
    let mut index: Index = std::fs::read(root.join("index.json")).ok().and_then(|v| serde_json::from_slice(&v).ok()).unwrap_or_default();
    if index.max_mib != 0 && !(128..=4096).contains(&index.max_mib) { index.max_mib = 0; }
    index.entries.retain(|id, e| valid_key(id) && e.size <= 4096 * 1024 * 1024 && std::fs::metadata(root.join(id)).is_ok_and(|m| m.is_file() && m.len() == e.size));
    let last_access = index.entries.values().map(|e| e.accessed).max().unwrap_or(0);
    let mut store = Store { root, index, generation: 0, last_access, dirty: false, flushed: Instant::now() };
    if let Ok(files) = std::fs::read_dir(&store.root) { for file in files.flatten() {
        let name = file.file_name().to_string_lossy().to_string();
        if name != "index.json" && !store.index.entries.contains_key(&name) { let _ = std::fs::remove_file(file.path()); }
    }}
    let _ = trim(&mut store); let _ = save(&mut store);
    if let Ok(mut guard) = STORE.lock() { *guard = Some(store); }
}
pub fn status() -> (u32, u64) {
    STORE.lock().ok().and_then(|mut s| s.as_mut().map(|s| {
        if s.dirty && s.flushed.elapsed().as_secs() >= 5 { let _ = save(s); }
        (s.index.max_mib, s.index.entries.values().map(|e| e.size).sum())
    })).unwrap_or_default()
}
pub fn revision() -> u64 { STORE.lock().ok().and_then(|s| s.as_ref().map(|s| s.generation)).unwrap_or(0) }
pub fn set_limit(mib: u32) -> Result<(), String> {
    if mib != 0 && !(128..=4096).contains(&mib) { return Err("缓存容量须为 0 或 128–4096 MiB 的整数".into()); }
    let mut guard = STORE.lock().map_err(|_| "缓存锁失败")?;
    let store = guard.as_mut().ok_or("缓存尚未初始化")?;
    let previous = store.index.max_mib; store.index.max_mib = mib;
    if let Err(error) = save(store) { store.index.max_mib = previous; return Err(error); }
    store.generation += 1; cancel_all();
    let result = trim(store); let saved = save(store); result.and(saved)
}
pub fn clear() -> Result<(), String> {
    let mut guard = STORE.lock().map_err(|_| "缓存锁失败")?;
    let store = guard.as_mut().ok_or("缓存尚未初始化")?;
    store.generation += 1; cancel_all();
    let ids: Vec<_> = store.index.entries.keys().cloned().collect();
    for id in ids { if let Err(error) = remove(store, &id) { let _ = save(store); return Err(error); } }
    save(store)
}
pub fn generation() -> Option<u64> { STORE.lock().ok().and_then(|s| s.as_ref().filter(|s| s.index.max_mib != 0).map(|s| s.generation)) }
pub fn contains(url: &str) -> bool {
    let Ok(mut guard) = STORE.lock() else { return false }; let Some(s) = guard.as_mut() else { return false };
    if s.index.max_mib == 0 { return false; }
    let id = key(url); let Some(entry) = s.index.entries.get(&id) else { return false };
    if std::fs::metadata(s.root.join(&id)).is_ok_and(|m| m.is_file() && m.len() == entry.size) { return true; }
    let _ = remove(s, &id); false
}
pub fn get(url: &str) -> Option<(Option<String>, Vec<u8>)> { get_entry(url).map(|(mime, _, bytes)| (mime, bytes)) }
pub fn get_entry(url: &str) -> Option<(Option<String>, Option<u64>, Vec<u8>)> {
    let mut guard = STORE.lock().ok()?; let s = guard.as_mut()?;
    if s.index.max_mib == 0 { return None; }
    let id = key(url); let entry = s.index.entries.get(&id)?.clone();
    let bytes = std::fs::read(s.root.join(&id)).ok();
    let Some(bytes) = bytes.filter(|bytes| bytes.len() as u64 == entry.size) else { let _ = remove(s, &id); return None };
    s.last_access = now().max(s.last_access.saturating_add(1));
    s.index.entries.get_mut(&id)?.accessed = s.last_access; s.dirty = true;
    if s.flushed.elapsed().as_secs() >= 5 { let _ = save(s); }
    Some((entry.mime, entry.total, bytes))
}
pub fn put(url: &str, mime: Option<String>, bytes: &[u8], generation: u64, protected_urls: &[String]) -> bool { put_entry(url, mime, None, bytes, generation, protected_urls) }
pub fn put_entry(url: &str, mime: Option<String>, total: Option<u64>, bytes: &[u8], generation: u64, protected_urls: &[String]) -> bool {
    let Ok(mut guard) = STORE.lock() else { return false }; let Some(s) = guard.as_mut() else { return false };
    if s.generation != generation || s.index.max_mib == 0 { return false; }
    let limit = u64::from(s.index.max_mib) * 1024 * 1024;
    let id = key(url); let mut used: u64 = s.index.entries.values().map(|e| e.size).sum();
    let old = s.index.entries.get(&id).map_or(0, |e| e.size);
    if bytes.len() as u64 > limit { return false; }
    let protected: std::collections::HashSet<String> = protected_urls.iter().map(|url| key(url)).collect();
    let mut candidates: Vec<_> = s.index.entries.iter().filter(|(candidate, _)| !protected.contains(*candidate) && *candidate != &id).map(|(id, e)| (id.clone(), e.clone())).collect();
    candidates.sort_by_key(|(_, e)| e.accessed); let mut victims = Vec::new();
    for (victim, entry) in candidates {
        if used.saturating_sub(old) + bytes.len() as u64 <= limit { break; }
        used = used.saturating_sub(entry.size); victims.push(victim);
    }
    if used.saturating_sub(old) + bytes.len() as u64 > limit { return false; }
    let temp = s.root.join(format!("{id}.tmp"));
    if std::fs::write(&temp, bytes).is_err() { let _ = std::fs::remove_file(temp); return false; }
    for victim in victims { if remove(s, &victim).is_err() { let _ = std::fs::remove_file(&temp); let _ = save(s); return false; } }
    if std::fs::rename(&temp, s.root.join(&id)).is_err() { let _ = std::fs::remove_file(temp); let _ = save(s); return false; }
    s.last_access = now().max(s.last_access.saturating_add(1));
    s.index.entries.insert(id.clone(), Entry { size: bytes.len() as u64, accessed: s.last_access, mime, total });
    if save(s).is_err() { let _ = remove(s, &id); return false; }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn default_disabled_persistence_and_clear_invalidate_inflight() {
        let _test_guard = TEST_LOCK.lock().unwrap();
        let dir = std::env::temp_dir().join(format!("hghub-disk-cache-{}-{}", std::process::id(), now()));
        std::fs::create_dir_all(&dir).unwrap();
        bind(&dir);
        assert_eq!(status(), (0, 0));
        assert!(generation().is_none());
        assert!(set_limit(127).is_err());
        set_limit(128).unwrap();
        let gen = generation().unwrap();
        assert!(put("https://example.test/segment?secret=1", Some("video/mp2t".into()), b"segment", gen, &[]));
        assert_eq!(get("https://example.test/segment?secret=1").unwrap().1, b"segment");
        let index = std::fs::read_to_string(dir.join("playback-cache/index.json")).unwrap();
        assert!(!index.contains("secret"));
        {
            let mut guard = STORE.lock().unwrap();
            let store = guard.as_mut().unwrap();
            let first = key("https://example.test/old");
            let second = key("https://example.test/upcoming");
            for (id, accessed) in [(first, 1), (second, 2)] {
                let file = std::fs::File::create(store.root.join(&id)).unwrap();
                file.set_len(64 * 1024 * 1024).unwrap();
                store.index.entries.insert(id, Entry { size: 64 * 1024 * 1024, accessed, mime: None, total: None });
            }
        }
        assert!(put("https://example.test/new", None, b"12345678", gen, &["https://example.test/upcoming".into()]));
        assert!(!contains("https://example.test/old"));
        assert!(contains("https://example.test/upcoming"));
        assert!(contains("https://example.test/new"));
        // Missing files cannot keep the prefetch queue or progress indicator stuck on a false hit.
        let missing = dir.join("playback-cache").join(key("https://example.test/new"));
        std::fs::remove_file(missing).unwrap();
        assert!(!contains("https://example.test/new"));
        // A failed settings write must preserve the confirmed effective limit.
        std::fs::create_dir(dir.join("playback-cache/index.tmp")).unwrap();
        assert!(set_limit(256).is_err());
        assert_eq!(status().0, 128);
        std::fs::remove_dir(dir.join("playback-cache/index.tmp")).unwrap();
        start_session("cache-clear-test".into()).unwrap();
        let cancelled = session("cache-clear-test").unwrap();
        clear().unwrap();
        assert!(*cancelled.borrow());
        assert!(session("cache-clear-test").is_none());
        let gen = generation().unwrap();
        assert!(put("https://example.test/segment?secret=1", None, b"segment", gen, &[]));
        bind(&dir);
        assert_eq!(status(), (128, 7));
        assert!(contains("https://example.test/segment?secret=1"));
        let gen = generation().unwrap();
        clear().unwrap();
        assert!(!put("https://example.test/late", None, b"late", gen, &[]));
        set_limit(0).unwrap();
        assert_eq!(status(), (0, 0));
        *STORE.lock().unwrap() = None;
        std::fs::remove_dir_all(dir).unwrap();
    }
}
