//! Optional push detection through Git's built-in Trace2 events. Git writes events to a
//! user-private socket (macOS) or named pipe (Windows). No hooks, repository access, or raw
//! trace logs: only push session identifiers are kept, in memory.

use serde_json::Value;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

pub type OnPush = Arc<dyn Fn() + Send + Sync>;

/// Reports a push only when Git confirms that a `git push` process exited successfully.
#[derive(Default)]
pub struct PushEvents {
    pushes: HashMap<String, Instant>,
}

impl PushEvents {
    pub fn receive(&mut self, data: &[u8]) -> bool {
        let Ok(event) = serde_json::from_slice::<Value>(data) else { return false };
        let (Some(kind), Some(sid)) = (event["event"].as_str(), event["sid"].as_str()) else { return false };
        let now = Instant::now();
        self.pushes.retain(|_, started| now.duration_since(*started) < Duration::from_secs(3600));
        if kind == "cmd_name" && event["name"].as_str() == Some("push") {
            if self.pushes.len() >= 256 {
                if let Some(oldest) = self.pushes.iter().min_by_key(|(_, started)| **started).map(|(sid, _)| sid.clone()) {
                    self.pushes.remove(&oldest);
                }
            }
            self.pushes.insert(sid.to_string(), now);
        }
        if kind == "signal" {
            self.pushes.remove(sid);
        }
        kind == "exit" && self.pushes.remove(sid).is_some() && event["code"].as_i64() == Some(0)
    }
}

#[derive(Default)]
pub struct Monitor(Mutex<Option<platform::Listener>>);

impl Monitor {
    pub fn start(&self, on_push: OnPush) -> Result<(), String> {
        let mut listener = self.0.lock().unwrap();
        if listener.is_none() {
            *listener = Some(platform::Listener::start(on_push)?);
        }
        Ok(())
    }

    pub fn stop(&self) {
        if let Some(listener) = self.0.lock().unwrap().take() {
            listener.stop();
        }
    }
}

fn git_config(arguments: &[&str], allow_missing: bool) -> Result<String, String> {
    let git = if cfg!(target_os = "macos") { "/usr/bin/git" } else { "git" };
    let output = crate::github::command(git)
        .args(["config", "--global"])
        .args(arguments)
        .output()
        .map_err(|_| "Git isn't installed, so pushes can't be detected.".to_string())?;
    if !output.status.success() && !(allow_missing && output.status.code() == Some(1)) {
        return Err("Couldn't update Git's user configuration. Check your global Git config permissions.".into());
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Changes only Stoke's exact value; an existing tracing setup is never overwritten.
pub fn configure(monitor: &Monitor, enabled: bool, on_push: OnPush) -> Result<(), String> {
    let target = platform::target();
    let existing: Vec<String> =
        git_config(&["--get-all", "trace2.eventTarget"], true)?.lines().map(str::to_string).collect();
    if enabled {
        if !(existing.is_empty() || existing == [target.clone()]) {
            return Err("Git already has a Trace2 event target. Stoke left it unchanged.".into());
        }
        monitor.start(on_push)?;
        if existing.is_empty() {
            if let Err(error) = git_config(&["--add", "trace2.eventTarget", &target], false) {
                monitor.stop();
                return Err(error);
            }
        }
    } else {
        if existing.contains(&target) {
            git_config(&["--fixed-value", "--unset-all", "trace2.eventTarget", &target], false)?;
        }
        monitor.stop();
    }
    Ok(())
}

/// Starts only the listener and exits successfully after Git reports one successful push.
/// Used by CI to prove real Git events arrive, without touching any configuration.
pub fn smoke_test() {
    let (sender, receiver) = std::sync::mpsc::channel();
    let sender = Mutex::new(sender);
    let monitor = Monitor::default();
    if let Err(error) = monitor.start(Arc::new(move || {
        let _ = sender.lock().unwrap().send(());
    })) {
        eprintln!("{error}");
        std::process::exit(1);
    }
    println!("{}", platform::target());
    use std::io::Write;
    let _ = std::io::stdout().flush();
    match receiver.recv_timeout(Duration::from_secs(120)) {
        Ok(()) => println!("push detected"),
        Err(_) => {
            eprintln!("no push detected");
            std::process::exit(1)
        }
    }
}

#[cfg(unix)]
mod platform {
    use super::{OnPush, PushEvents};
    use std::fs::File;
    use std::os::unix::fs::PermissionsExt;
    use std::os::unix::net::UnixDatagram;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    use std::time::Duration;

    // Stable path: existing opt-in Trace2 configurations must survive app updates.
    fn directory() -> PathBuf {
        let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        if cfg!(target_os = "macos") { home.join("Library/Caches/GitBar") } else { home.join(".cache/gitgaze") }
    }

    fn socket() -> PathBuf {
        directory().join("push.sock")
    }

    pub fn target() -> String {
        format!("af_unix:dgram:{}", socket().display())
    }

    pub struct Listener {
        stop: Arc<AtomicBool>,
        _lock: File,
    }

    impl Listener {
        pub fn start(on_push: OnPush) -> Result<Self, String> {
            let directory = directory();
            std::fs::create_dir_all(&directory).map_err(|error| error.to_string())?;
            let _ = std::fs::set_permissions(&directory, std::fs::Permissions::from_mode(0o700));
            let lock = File::options()
                .create(true)
                .truncate(false)
                .write(true)
                .open(directory.join("listener.lock"))
                .map_err(|error| error.to_string())?;
            lock.try_lock().map_err(|_| "Another Stoke push listener is already running.".to_string())?;
            let path = socket();
            let _ = std::fs::remove_file(&path);
            let socket = UnixDatagram::bind(&path).map_err(|_| "Couldn't bind the Git event socket.".to_string())?;
            let _ = std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600));
            socket.set_read_timeout(Some(Duration::from_millis(500))).map_err(|error| error.to_string())?;
            let stop = Arc::new(AtomicBool::new(false));
            let stopped = stop.clone();
            std::thread::spawn(move || {
                let mut events = PushEvents::default();
                let mut buffer = vec![0u8; 65_536];
                while !stopped.load(Ordering::Relaxed) {
                    if let Ok(length) = socket.recv(&mut buffer) {
                        if events.receive(&buffer[..length]) {
                            on_push();
                        }
                    }
                }
                let _ = std::fs::remove_file(path);
            });
            Ok(Self { stop, _lock: lock })
        }

        pub fn stop(self) {
            self.stop.store(true, Ordering::Relaxed);
        }
    }
}

#[cfg(windows)]
mod platform {
    use super::{OnPush, PushEvents};
    use std::sync::{Arc, Mutex};
    use tokio::io::{AsyncBufReadExt, BufReader};
    use tokio::net::windows::named_pipe::ServerOptions;

    pub fn target() -> String {
        let user: String = std::env::var("USERNAME")
            .unwrap_or_default()
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
            .collect();
        format!(r"\\.\pipe\gitgaze-push-{user}")
    }

    /// Pipe instances kept waiting for Git. Every Git process opens its own connection (a push
    /// runs several), and Git checks the path before opening it, which briefly takes one too.
    const WAITING: usize = 4;

    pub struct Listener(Vec<tauri::async_runtime::JoinHandle<()>>);

    impl Listener {
        pub fn start(on_push: OnPush) -> Result<Self, String> {
            let name = target();
            // The first instance fails if another Stoke already listens, like the macOS lock.
            let first = tauri::async_runtime::block_on(async {
                ServerOptions::new().first_pipe_instance(true).create(&name)
            })
            .map_err(|_| "Another Stoke push listener is already running.".to_string())?;
            let events = Arc::new(Mutex::new(PushEvents::default()));
            let mut first = Some(first);
            let tasks = (0..WAITING)
                .map(|_| {
                    let (name, events, on_push, mut waiting) = (name.clone(), events.clone(), on_push.clone(), first.take());
                    tauri::async_runtime::spawn(async move {
                        loop {
                            let server = match waiting.take() {
                                Some(server) => server,
                                None => match ServerOptions::new().create(&name) {
                                    Ok(server) => server,
                                    Err(_) => return,
                                },
                            };
                            // A client that left before the connection completed leaves the
                            // instance unusable, so it is dropped and replaced.
                            if server.connect().await.is_err() {
                                continue;
                            }
                            let (events, on_push) = (events.clone(), on_push.clone());
                            tauri::async_runtime::spawn(async move {
                                // Each Git process writes one JSON event per line, then disconnects.
                                let mut lines = BufReader::new(server).lines();
                                while let Ok(Some(line)) = lines.next_line().await {
                                    if events.lock().unwrap().receive(line.as_bytes()) {
                                        on_push();
                                    }
                                }
                            });
                        }
                    })
                })
                .collect();
            Ok(Self(tasks))
        }

        pub fn stop(self) {
            for task in self.0 {
                task.abort();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::PushEvents;

    #[test]
    fn reports_only_successful_pushes() {
        let mut events = PushEvents::default();
        assert!(!events.receive(br#"{"event":"cmd_name","sid":"a","name":"push"}"#));
        assert!(!events.receive(br#"{"event":"cmd_name","sid":"b","name":"fetch"}"#));
        assert!(!events.receive(br#"{"event":"exit","sid":"b","code":0}"#));
        assert!(events.receive(br#"{"event":"exit","sid":"a","code":0}"#));
        assert!(!events.receive(br#"{"event":"exit","sid":"a","code":0}"#), "one exit per push");
        events.receive(br#"{"event":"cmd_name","sid":"c","name":"push"}"#);
        assert!(!events.receive(br#"{"event":"exit","sid":"c","code":1}"#), "failed push");
        events.receive(br#"{"event":"cmd_name","sid":"d","name":"push"}"#);
        events.receive(br#"{"event":"signal","sid":"d"}"#);
        assert!(!events.receive(br#"{"event":"exit","sid":"d","code":0}"#), "interrupted push");
    }
}
