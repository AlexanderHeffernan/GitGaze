//! Preferences and the offline activity cache, stored as private JSON files.
//! On macOS the cache keeps the original GitBar location and format, and preferences are read
//! once from the previous app's user defaults, so upgrading keeps history, layout and favourites.

use serde_json::{json, Value};
use std::path::PathBuf;
use tauri::Manager;

fn directory(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let base = app.path().data_dir().map_err(|error| error.to_string())?;
    Ok(base.join(if cfg!(target_os = "macos") { "GitBar" } else { "GitGaze" }))
}

fn read_json(path: PathBuf) -> Value {
    std::fs::read(path).ok().and_then(|data| serde_json::from_slice(&data).ok()).unwrap_or(Value::Null)
}

/// Writes through a temporary file so a crash never leaves a half-written cache.
fn write_private(path: PathBuf, contents: &[u8]) -> Result<(), String> {
    let parent = path.parent().ok_or("Invalid storage path")?;
    std::fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let temporary = path.with_extension("tmp");
    std::fs::write(&temporary, contents).map_err(|error| error.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700));
        let _ = std::fs::set_permissions(&temporary, std::fs::Permissions::from_mode(0o600));
    }
    std::fs::rename(&temporary, &path).map_err(|error| error.to_string())
}

#[cfg(target_os = "macos")]
fn legacy_preferences() -> Value {
    let Some(home) = std::env::var_os("HOME") else { return Value::Null };
    let path = PathBuf::from(home).join("Library/Preferences/app.gitbar.mac.plist");
    plist::Value::from_file(path).ok().and_then(|value| serde_json::to_value(value).ok()).unwrap_or(Value::Null)
}

#[cfg(not(target_os = "macos"))]
fn legacy_preferences() -> Value {
    Value::Null
}

#[tauri::command]
pub fn load_state(app: tauri::AppHandle) -> Result<Value, String> {
    let directory = directory(&app)?;
    let mut preferences = read_json(directory.join("preferences.json"));
    let migrated = preferences.is_null();
    if migrated {
        preferences = legacy_preferences();
    }
    Ok(json!({ "preferences": preferences, "migrated": migrated, "cache": read_json(directory.join("dashboard.json")) }))
}

#[tauri::command]
pub fn save_preferences(app: tauri::AppHandle, preferences: Value) -> Result<(), String> {
    let data = serde_json::to_vec_pretty(&preferences).map_err(|error| error.to_string())?;
    write_private(directory(&app)?.join("preferences.json"), &data)
}

#[tauri::command]
pub fn save_cache(app: tauri::AppHandle, cache: String) -> Result<(), String> {
    serde_json::from_str::<Value>(&cache).map_err(|error| error.to_string())?;
    write_private(directory(&app)?.join("dashboard.json"), cache.as_bytes())
}
