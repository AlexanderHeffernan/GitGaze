//! Launch at login: the macOS login item service (the same registration earlier versions used),
//! or the per-user Run entry on Windows.

#[cfg(target_os = "macos")]
mod platform {
    use objc2_service_management::{SMAppService, SMAppServiceStatus};

    pub fn enabled(_: &tauri::AppHandle) -> bool {
        unsafe { SMAppService::mainAppService().status() == SMAppServiceStatus::Enabled }
    }

    pub fn set(app: &tauri::AppHandle, enabled: bool) -> Result<bool, String> {
        let service = unsafe { SMAppService::mainAppService() };
        let result = unsafe { if enabled { service.registerAndReturnError() } else { service.unregisterAndReturnError() } };
        result.map_err(|error| format!("Couldn't change launch at login. {}", error.localizedDescription()))?;
        let now = self::enabled(app);
        if enabled && !now {
            unsafe { SMAppService::openSystemSettingsLoginItems() };
        }
        Ok(now)
    }
}

#[cfg(windows)]
mod platform {
    use tauri_plugin_autostart::ManagerExt;

    pub fn enabled(app: &tauri::AppHandle) -> bool {
        app.autolaunch().is_enabled().unwrap_or(false)
    }

    pub fn set(app: &tauri::AppHandle, enabled: bool) -> Result<bool, String> {
        let launcher = app.autolaunch();
        if enabled { launcher.enable() } else { launcher.disable() }
            .map_err(|error| format!("Couldn't change launch at login. {error}"))?;
        Ok(self::enabled(app))
    }
}

#[cfg(not(any(target_os = "macos", windows)))]
mod platform {
    pub fn enabled(_: &tauri::AppHandle) -> bool {
        false
    }
    pub fn set(_: &tauri::AppHandle, _: bool) -> Result<bool, String> {
        Err("Launch at login isn't supported on this platform.".into())
    }
}

#[tauri::command]
pub fn launch_at_login(app: tauri::AppHandle) -> bool {
    platform::enabled(&app)
}

#[tauri::command]
pub fn set_launch_at_login(app: tauri::AppHandle, enabled: bool) -> Result<bool, String> {
    platform::set(&app, enabled)
}
