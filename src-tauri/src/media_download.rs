//! Shared media transfers. Foreground consumers promote an existing background transfer.
use once_cell::sync::Lazy;
use std::{collections::{HashMap, HashSet}, future::Future, sync::{Arc, Mutex, Weak, atomic::{AtomicUsize, Ordering}}};
use tokio::sync::watch;

#[derive(Clone)]
pub struct Object {
    pub mime: Option<String>,
    pub total: Option<u64>,
    pub etag: Option<String>,
    pub range: Option<crate::media::ByteRange>,
    pub bytes: Arc<Vec<u8>>,
}
type Result = std::result::Result<Object, String>;

#[derive(Default)]
struct Scheduler { foreground: usize, buffering: HashSet<String> }
static SCHEDULER: Lazy<watch::Sender<Scheduler>> = Lazy::new(|| watch::channel(Scheduler::default()).0);
static TRANSFERS: Lazy<Mutex<HashMap<String, Weak<Transfer>>>> = Lazy::new(|| Mutex::new(HashMap::new()));

pub struct Foreground;
pub fn foreground() -> Foreground {
    SCHEDULER.send_modify(|state| state.foreground += 1);
    Foreground
}
impl Drop for Foreground {
    fn drop(&mut self) { SCHEDULER.send_modify(|state| state.foreground -= 1); }
}
pub fn buffer_ready(session: &str, ready: bool) {
    SCHEDULER.send_modify(|state| {
        if ready { state.buffering.remove(session); } else { state.buffering.insert(session.into()); }
    });
}

pub struct Transfer {
    urgent: AtomicUsize,
    result: watch::Sender<Option<Result>>,
}
impl Transfer {
    // Keep the future alive while background work is paused, preserving received bytes.
    pub async fn run<T>(&self, future: impl Future<Output = T>) -> T {
        tokio::pin!(future);
        let mut scheduler = SCHEDULER.subscribe();
        loop {
            let allowed = {
                let state = scheduler.borrow_and_update();
                self.urgent.load(Ordering::SeqCst) > 0 || (state.foreground == 0 && state.buffering.is_empty())
            };
            if allowed {
                tokio::select! {
                    biased;
                    _ = scheduler.changed() => {},
                    result = &mut future => return result,
                }
            } else { let _ = scheduler.changed().await; }
        }
    }
    pub fn is_urgent(&self) -> bool { self.urgent.load(Ordering::SeqCst) > 0 }
    async fn unused(&self) {
        loop {
            self.result.closed().await;
            // A seek can cancel the cache session immediately before the player asks for the same object.
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
            if self.result.receiver_count() == 0 { return; }
        }
    }
}

struct Consumer { transfer: Arc<Transfer>, urgent: bool }
impl Drop for Consumer {
    fn drop(&mut self) {
        if self.urgent {
            self.transfer.urgent.fetch_sub(1, Ordering::SeqCst);
            SCHEDULER.send_modify(|_| {});
        }
    }
}

pub async fn shared<F, Fut>(key: String, urgent: bool, start: F) -> Result
where F: FnOnce(Arc<Transfer>) -> Fut + Send + 'static,
      Fut: Future<Output = Result> + Send + 'static {
    let (transfer, mut result, created) = {
        let mut transfers = TRANSFERS.lock().map_err(|_| "下载任务锁失败")?;
        transfers.retain(|_, transfer| transfer.strong_count() > 0);
        if let Some(transfer) = transfers.get(&key).and_then(Weak::upgrade) {
            let result = transfer.result.subscribe();
            (transfer, result, false)
        } else {
            let (sender, result) = watch::channel(None);
            let transfer = Arc::new(Transfer { urgent: AtomicUsize::new(0), result: sender });
            transfers.insert(key.clone(), Arc::downgrade(&transfer));
            (transfer, result, true)
        }
    };
    if urgent {
        transfer.urgent.fetch_add(1, Ordering::SeqCst);
        SCHEDULER.send_modify(|_| {});
    }
    let _consumer = Consumer { transfer: transfer.clone(), urgent };
    if created {
        let transfer = transfer.clone();
        tokio::spawn(async move {
            let outcome = tokio::select! {
                result = start(transfer.clone()) => result,
                _ = transfer.unused() => Err("下载任务已取消".into()),
            };
            // A later caller can need a different portion of the same transfer page.
            // Validated bytes are already stored before the result is published.
            if let Ok(mut transfers) = TRANSFERS.lock() {
                if transfers.get(&key).is_some_and(|entry| entry.ptr_eq(&Arc::downgrade(&transfer))) { transfers.remove(&key); }
            }
            transfer.result.send_replace(Some(outcome));
        });
    }
    loop {
        if let Some(result) = result.borrow_and_update().clone() { return result; }
        result.changed().await.map_err(|_| "下载任务已结束")?;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn object() -> Object { Object { mime: None, total: None, etag: None, range: None, bytes: Arc::new(b"shared".to_vec()) } }

    #[tokio::test]
    async fn low_buffer_and_foreground_pause_background_work() {
        let _lock = crate::media_cache::TEST_LOCK.lock().unwrap();
        buffer_ready("scheduler-test", false);
        let foreground = foreground();
        let (started, mut received) = tokio::sync::oneshot::channel();
        let background = tokio::spawn(shared("scheduler-test".into(), false, move |transfer| async move {
            transfer.run(async { let _ = started.send(()); }).await;
            Ok(object())
        }));
        tokio::task::yield_now().await;
        assert!(received.try_recv().is_err());
        buffer_ready("scheduler-test", true);
        tokio::task::yield_now().await;
        assert!(received.try_recv().is_err());
        drop(foreground);
        tokio::time::timeout(std::time::Duration::from_secs(1), received).await.unwrap().unwrap();
        background.await.unwrap().unwrap();
    }

    #[tokio::test]
    async fn foreground_promotes_transfer_and_keeps_it_after_background_cancellation() {
        let _lock = crate::media_cache::TEST_LOCK.lock().unwrap();
        let (started, received) = tokio::sync::oneshot::channel();
        let (release, released) = tokio::sync::oneshot::channel();
        let background = tokio::spawn(shared("promoted-test".into(), false, move |transfer| async move {
            transfer.run(async { let _ = started.send(()); }).await;
            transfer.run(released).await.map_err(|_| "fixture closed")?;
            Ok(object())
        }));
        received.await.unwrap();
        let _foreground = foreground();
        let player = tokio::spawn(shared("promoted-test".into(), true, |_| async { panic!("duplicate download") }));
        tokio::task::yield_now().await;
        background.abort();
        let _ = background.await;
        release.send(()).unwrap();
        let result = tokio::time::timeout(std::time::Duration::from_secs(1), player).await.unwrap().unwrap().unwrap();
        assert_eq!(result.bytes.as_slice(), b"shared");
    }
}
