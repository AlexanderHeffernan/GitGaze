//! Reads the GitHub CLI's active github.com session into memory and runs GraphQL queries with it.
//! The token never reaches the web view, disk, or logs. Stoke never signs in or out of the CLI.

use serde_json::{json, Value};
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Mutex, OnceLock};

/// The CLI token, and the OAuth scopes GitHub last reported for it (absent for fine-grained tokens).
#[derive(Default)]
pub struct Session(Mutex<Option<String>>, Mutex<Option<String>>);

pub fn command(program: impl AsRef<std::ffi::OsStr>) -> Command {
    #[allow(unused_mut)]
    let mut command = Command::new(program);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x0800_0000); // CREATE_NO_WINDOW: no console flash.
    }
    command
}

/// GUI apps don't inherit a shell PATH on macOS, so check the usual install locations too.
pub fn cli_path() -> Option<PathBuf> {
    let name = if cfg!(windows) { "gh.exe" } else { "gh" };
    let mut candidates: Vec<PathBuf> = std::env::var_os("PATH")
        .map(|path| std::env::split_paths(&path).map(|dir| dir.join(name)).collect())
        .unwrap_or_default();
    if cfg!(target_os = "macos") {
        candidates.splice(0..0, ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].map(PathBuf::from));
    }
    if cfg!(windows) {
        for base in ["ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA"] {
            if let Some(dir) = std::env::var_os(base) {
                candidates.push(PathBuf::from(&dir).join("GitHub CLI").join(name));
                candidates.push(PathBuf::from(dir).join("Programs").join("GitHub CLI").join(name));
            }
        }
    }
    candidates.into_iter().find(|path| path.is_file())
}

fn cli_token() -> Option<String> {
    let output = command(cli_path()?).args(["auth", "token", "--hostname", "github.com"]).output().ok()?;
    let token = String::from_utf8(output.stdout).ok()?.trim().to_string();
    (output.status.success() && !token.is_empty()).then_some(token)
}

#[tauri::command]
pub fn gh_installed() -> bool {
    cli_path().is_some()
}

#[tauri::command]
pub async fn github_connect(session: tauri::State<'_, Session>) -> Result<(), String> {
    let token = tauri::async_runtime::spawn_blocking(cli_token).await.ok().flatten().ok_or_else(|| {
        "No GitHub CLI session found. Run gh auth login in a terminal, then try again.".to_string()
    })?;
    *session.0.lock().unwrap() = Some(token);
    Ok(())
}

fn client() -> &'static reqwest::Client {
    static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            .user_agent("Stoke/1.1")
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .expect("HTTP client")
    })
}

#[tauri::command]
pub async fn github_query(session: tauri::State<'_, Session>, query: String, variables: Value) -> Result<Value, String> {
    let token = session.0.lock().unwrap().clone().ok_or("Connect GitHub CLI first.")?;
    let response = client()
        .post("https://api.github.com/graphql")
        .bearer_auth(token)
        .json(&json!({ "query": query, "variables": variables }))
        .send()
        .await
        .map_err(|_| "GitHub did not respond. Check your connection.".to_string())?;
    if let Some(scopes) = response.headers().get("x-oauth-scopes").and_then(|value| value.to_str().ok()) {
        *session.1.lock().unwrap() = Some(scopes.to_string());
    }
    match response.status().as_u16() {
        200 => {}
        401 => return Err("Your GitHub CLI session expired. Run gh auth login, then relaunch Stoke.".into()),
        403 | 429 => {
            return Err("GitHub is limiting requests. Your saved contributions are still here; try again later.".into())
        }
        status => return Err(format!("GitHub returned HTTP {status}. Try again shortly.")),
    }
    let body: Value = response.json().await.map_err(|_| "GitHub sent an unreadable response.".to_string())?;
    if let Some(message) = body["errors"][0]["message"].as_str() {
        return Err(message.to_string());
    }
    Ok(body["data"].clone())
}

/// Private-repository contributions are only counted for tokens with read:user (or user).
#[tauri::command]
pub fn github_scopes(session: tauri::State<'_, Session>) -> Option<String> {
    session.1.lock().unwrap().clone()
}
