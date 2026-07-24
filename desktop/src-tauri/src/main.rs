// Prevent an extra terminal window on Windows in release.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    poof_lib::run()
}
