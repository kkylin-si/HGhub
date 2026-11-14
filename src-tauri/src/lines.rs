//! 线路（数据源）：固定线路。唯一播放源固定为 huangguoai.com，不再解析镜像。

use serde_json::{json, Value};
use std::time::{Duration, Instant};

/// 固定线路：写死在客户端里，不依赖任何外部页面。
pub const FIXED: [(&str, &str); 1] = [
    ("固定线路 1", "https://huangguoai.com"),
];

/// 单条线路探测超时
const PROBE_TIMEOUT: Duration = Duration::from_secs(8);

pub fn fixed() -> Value {
    json!(FIXED
        .iter()
        .map(|(name, url)| json!({ "name": name, "url": url }))
        .collect::<Vec<_>>())
}

/// 镜像列表：唯一播放源已固定为 huangguoai.com，不再抓发布页、不探镜像。
/// 保留命令签名与返回结构，前端看到的始终是空列表。
pub async fn mirrors() -> Result<Value, String> {
    Ok(json!({
        "source": "",
        "items": [],
        "recommended": [],
    }))
}

/// 可达性探测（并发 6 条一组）。只报结果，不做自动切换。
pub async fn probe(urls: Vec<String>) -> Value {
    let mut out: Vec<Value> = Vec::new();
    for chunk in urls.chunks(6) {
        let mut handles = Vec::new();
        for u in chunk {
            let u = u.clone();
            handles.push(tokio::spawn(async move { probe_one(u).await }));
        }
        for h in handles {
            if let Ok(v) = h.await {
                out.push(v);
            }
        }
    }
    json!(out)
}

async fn probe_one(url: String) -> Value {
    let target = format!("{}/", url.trim_end_matches('/'));
    let started = Instant::now();
    let res = crate::net::get(
        &target,
        PROBE_TIMEOUT,
        Some("text/html,application/xhtml+xml"),
        None,
    )
    .await;
    let ms = started.elapsed().as_millis() as u64;
    match res {
        Ok(r) => {
            let status = r.status().as_u16();
            json!({ "url": url, "ok": status < 400, "status": status, "ms": ms })
        }
        Err(e) => json!({ "url": url, "ok": false, "ms": ms, "error": e }),
    }
}

/* ───────────────────────── 自动选线 ───────────────────────── */

/// 自动选线的主站候选（唯一线路）。
pub const AUTO_LINES: [(&str, &str); 1] = [("main", crate::net::DEFAULT_BASE)];
/// 判活就打这一个请求，成本等于 ping：能返回 200 就是这条线路能用。
const AUTO_PROBE_PATH: &str = "/api/videos?page=1&size=1";
/// 探测超时：只在启动/换网时用，等太久不如直接用另一条。
const AUTO_PROBE_TIMEOUT: Duration = Duration::from_secs(5);

/// 一条候选线路的探测结果。
#[derive(Clone)]
pub struct Hit {
    pub tier: &'static str,
    pub url: String,
    pub ok: bool,
    pub reachable: bool,
    pub ms: u64,
    pub status: Option<u16>,
}

impl Hit {
    fn json(&self) -> Value {
        json!({
            "tier": self.tier,
            "url": self.url,
            "ok": self.ok,
            "reachable": self.reachable,
            "ms": self.ms,
            "status": self.status,
        })
    }
}

async fn probe_hit(tier: &'static str, url: &str) -> Hit {
    let target = format!("{}{}", url.trim_end_matches('/'), AUTO_PROBE_PATH);
    let started = Instant::now();
    let res = crate::net::get(&target, AUTO_PROBE_TIMEOUT, Some("application/json"), None).await;
    let ms = started.elapsed().as_millis() as u64;
    match res {
        Ok(r) => {
            let status = r.status().as_u16();
            Hit {
                tier,
                url: url.to_string(),
                // 只看接口：首页 200 不代表能用（.ai 就是 200 + /api 全 404）
                ok: status == 200,
                reachable: status < 500,
                ms,
                status: Some(status),
            }
        }
        Err(_) => Hit {
            tier,
            url: url.to_string(),
            ok: false,
            reachable: false,
            ms,
            status: None,
        },
    }
}

/// 自动选线：唯一播放源固定为 huangguoai.com，不再探测、不再切镜像。
///
/// 保留返回结构与 `reason` 字段；`base` 恒为主站，前端据此只会停在 main。
pub async fn auto_pick() -> Value {
    let (main_tier, main_url) = AUTO_LINES[0];
    json!({
        "base": main_url,
        "tier": main_tier,
        "ms": 0,
        "reason": "main-fixed",
        "candidates": [{
            "tier": main_tier,
            "url": main_url,
            "ok": true,
            "reachable": true,
            "ms": 0,
            "status": null,
        }],
    })
}
/// 回切主站：主站就是唯一线路，恒返回主站可用，不发请求。
pub async fn try_main() -> Value {
    let (tier, url) = AUTO_LINES[0];
    json!({
        "ok": true,
        "base": url,
        "tier": tier,
        "ms": 0,
        "status": null,
    })
}
/// 判活「当前线路」：和 [`auto_pick`] 用同一个请求（`/api/videos?page=1&size=1`）。
///
/// 只看首页不行——`.ai` 首页 200、`/api` 全 404，首页判活会把体检结论骗成「通」，
/// 于是坏线路一直不被换掉。这里探的是真接口，通就是真能出内容。
pub async fn health() -> Value {
    let current = crate::net::base();
    let hit = probe_hit("current", &current).await;
    json!({
        "base": current,
        "ok": hit.ok,
        "ms": hit.ms,
        "status": hit.status,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 手动跑：`cargo test --lib -- --ignored lines::tests::mirrors_live -- --nocapture`
    #[tokio::test]
    #[ignore = "联网测试：请求上游镜像列表，手动用 --ignored 运行"]
    async fn mirrors_live() {
        match mirrors().await {
            Ok(v) => println!("{}", serde_json::to_string_pretty(&v).expect("json")),
            Err(e) => panic!("mirrors failed: {e}"),
        }
    }

    /// 手动跑：`cargo test --lib -- --ignored lines::tests::probe_live -- --nocapture`
    #[tokio::test]
    #[ignore = "联网测试：探测上游线路连通性，手动用 --ignored 运行"]
    async fn probe_live() {
        let urls = vec![
            "https://huangguoai.com".to_string(),
            "https://huangguoai.ai".to_string(),
            "https://thu.xxbgwypx.cc".to_string(),
        ];
        println!(
            "{}",
            serde_json::to_string_pretty(&probe(urls).await).expect("json")
        );
    }
}
