/// Text injection module for Windows
/// Injects text by:
/// 1. Copying text to clipboard
/// 2. Simulating Ctrl+V keypress using Windows SendInput API

#[cfg(target_os = "windows")]
use std::ptr;

#[cfg(target_os = "windows")]
use windows::Win32::Foundation::HWND;
#[cfg(target_os = "windows")]
use windows::Win32::System::DataExchange::{
    CloseClipboard, EmptyClipboard, GetClipboardData, OpenClipboard, SetClipboardData,
};
#[cfg(target_os = "windows")]
use windows::Win32::System::Memory::{GlobalAlloc, GlobalFree, GlobalLock, GlobalUnlock, GMEM_MOVEABLE, HGLOBAL};
#[cfg(target_os = "windows")]
use windows::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_KEYBOARD, KEYEVENTF_KEYUP, KEYBD_EVENT_FLAGS, VIRTUAL_KEY, VK_CONTROL,
};

/// CF_UNICODETEXT clipboard format
#[cfg(target_os = "windows")]
const CF_UNICODETEXT: u32 = 13;

/// Set clipboard text on Windows
#[cfg(target_os = "windows")]
fn set_clipboard_text(text: &str) -> Result<(), Box<dyn std::error::Error>> {
    unsafe {
        // Open clipboard
        OpenClipboard(HWND(ptr::null_mut()))?;

        // Empty clipboard
        if let Err(e) = EmptyClipboard() {
            let _ = CloseClipboard();
            return Err(format!("Failed to empty clipboard: {}", e).into());
        }

        // Allocate global memory for text
        let wide_text: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
        let size = wide_text.len() * std::mem::size_of::<u16>();

        let hglob = GlobalAlloc(GMEM_MOVEABLE, size)?;

        // Lock memory and copy text
        let locked = GlobalLock(hglob);
        if locked.is_null() {
            let _ = GlobalFree(hglob);
            let _ = CloseClipboard();
            return Err("Failed to lock global memory".into());
        }

        ptr::copy_nonoverlapping(wide_text.as_ptr(), locked as *mut u16, wide_text.len());
        let _ = GlobalUnlock(hglob);

        // Set clipboard data
        let result = SetClipboardData(CF_UNICODETEXT, windows::Win32::Foundation::HANDLE(hglob.0));
        if result.is_err() {
            let _ = GlobalFree(hglob);
            let _ = CloseClipboard();
            return Err("Failed to set clipboard data".into());
        }

        let _ = CloseClipboard();
        Ok(())
    }
}

/// Simulate Ctrl+V keypress using SendInput
#[cfg(target_os = "windows")]
fn simulate_ctrl_v() -> Result<(), Box<dyn std::error::Error>> {
    unsafe {
        let mut inputs: [INPUT; 4] = std::mem::zeroed();

        // Key down Ctrl
        inputs[0].r#type = INPUT_KEYBOARD;
        inputs[0].Anonymous.ki.wVk = VK_CONTROL;
        inputs[0].Anonymous.ki.dwFlags = KEYBD_EVENT_FLAGS(0);

        // Key down V
        inputs[1].r#type = INPUT_KEYBOARD;
        inputs[1].Anonymous.ki.wVk = VIRTUAL_KEY(0x56); // V key
        inputs[1].Anonymous.ki.dwFlags = KEYBD_EVENT_FLAGS(0);

        // Key up V
        inputs[2].r#type = INPUT_KEYBOARD;
        inputs[2].Anonymous.ki.wVk = VIRTUAL_KEY(0x56); // V key
        inputs[2].Anonymous.ki.dwFlags = KEYEVENTF_KEYUP;

        // Key up Ctrl
        inputs[3].r#type = INPUT_KEYBOARD;
        inputs[3].Anonymous.ki.wVk = VK_CONTROL;
        inputs[3].Anonymous.ki.dwFlags = KEYEVENTF_KEYUP;

        // Send all inputs
        let sent = SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);

        if sent != 4 {
            return Err(format!("Failed to send all inputs. Sent: {}", sent).into());
        }

        Ok(())
    }
}

/// Main injection function - copies text to clipboard and simulates Ctrl+V
#[cfg(target_os = "windows")]
pub fn inject_text(text: &str) -> Result<(), Box<dyn std::error::Error>> {
    // Small delay to ensure previous window is focused
    std::thread::sleep(std::time::Duration::from_millis(100));

    // Set clipboard
    set_clipboard_text(text)?;

    // Small delay before simulating keypress
    std::thread::sleep(std::time::Duration::from_millis(50));

    // Simulate Ctrl+V
    simulate_ctrl_v()?;

    Ok(())
}

/// Stub for non-Windows platforms
#[cfg(not(target_os = "windows"))]
pub fn inject_text(_text: &str) -> Result<(), Box<dyn std::error::Error>> {
    Err("Text injection is only supported on Windows".into())
}

/// Tauri command for text injection
#[tauri::command]
pub fn inject_text_command(text: String) -> Result<(), String> {
    inject_text(&text).map_err(|e| e.to_string())
}

/// Tauri command to get clipboard content (useful for debugging)
#[cfg(target_os = "windows")]
#[tauri::command]
pub fn get_clipboard_text() -> Result<String, String> {
    unsafe {
        OpenClipboard(HWND(ptr::null_mut())).map_err(|e| format!("Failed to open clipboard: {}", e))?;

        let hglob = match GetClipboardData(CF_UNICODETEXT) {
            Ok(h) => h,
            Err(_) => {
                let _ = CloseClipboard();
                return Err("No text in clipboard".to_string());
            }
        };

        let locked = GlobalLock(HGLOBAL(hglob.0));
        if locked.is_null() {
            let _ = CloseClipboard();
            return Err("Failed to lock clipboard data".to_string());
        }

        let wide_str = locked as *const u16;
        let mut len = 0;
        while *wide_str.offset(len) != 0 {
            len += 1;
        }

        let slice = std::slice::from_raw_parts(wide_str, len as usize);
        let result = String::from_utf16_lossy(slice);

        let _ = GlobalUnlock(HGLOBAL(hglob.0));
        let _ = CloseClipboard();

        Ok(result)
    }
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub fn get_clipboard_text() -> Result<String, String> {
    Err("Clipboard access is only supported on Windows".to_string())
}
