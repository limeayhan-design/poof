import { NativeBridge } from './native-bridge.js';

/**
 * Wire the Tauri-only "killer UX" events into a set of callbacks the app
 * can hook without caring whether we're running natively.
 *
 *   startScreenshotWatcher()      → auto-toast "Send this screenshot?"
 *   onPushClipboardShortcut(fn)   → ⌘⇧V pressed globally
 *   onTraySendFile(fn)            → user picked "Send file…" from the tray
 *   onScreenshotCaptured(fn)      → { path, name }
 *
 * All methods are no-ops in a plain browser.
 *
 * File I/O uses our own Rust commands (`save_to_downloads`, `open_file`) so
 * we don't depend on the fs/opener/dialog npm packages — the frontend is
 * served as plain <script> tags, no bundler.
 */
export const NativeFeatures = {
  isAvailable: NativeBridge.isAvailable,

  async startScreenshotWatcher() {
    if (!NativeBridge.isAvailable) return;
    try { await NativeBridge.invoke('screenshots_start'); }
    catch (e) { console.warn('[screenshots] start failed:', e); }
  },

  async stopScreenshotWatcher() {
    if (!NativeBridge.isAvailable) return;
    try { await NativeBridge.invoke('screenshots_stop'); } catch { /* noop */ }
  },

  onScreenshotCaptured(handler) {
    if (!NativeBridge.isAvailable) return () => {};
    return NativeBridge.listen('screenshot-captured', handler);
  },

  onPushClipboardShortcut(handler) {
    if (!NativeBridge.isAvailable) return () => {};
    return NativeBridge.listen('shortcut-push-clipboard', handler);
  },

  onTraySendFile(handler) {
    if (!NativeBridge.isAvailable) return () => {};
    return NativeBridge.listen('tray-send-file', handler);
  },

  /**
   * Write a Blob to ~/Downloads via our custom Rust command.
   * Returns the absolute path on success, null otherwise.
   */
  async saveBlob(blob, filename) {
    if (!NativeBridge.isAvailable) return null;
    try {
      const bytes = new Uint8Array(await blob.arrayBuffer());
      const path = await NativeBridge.invoke('save_to_downloads', {
        filename: String(filename || `poof-${Date.now()}.bin`),
        bytes: Array.from(bytes),
      });
      return path;
    } catch (e) {
      console.warn('[fs] saveBlob failed:', e);
      return null;
    }
  },

  /** Open a file with the OS default application (Preview, QuickTime, …). */
  async openPath(path) {
    if (!NativeBridge.isAvailable || !path) return false;
    try {
      await NativeBridge.invoke('open_file', { path });
      return true;
    } catch (e) { console.warn('[open_file] failed:', e); return false; }
  },

  /**
   * Read the OS clipboard as text via the Tauri clipboard-manager plugin.
   * Bypasses the browser `navigator.clipboard.readText()` user-gesture
   * requirement, so a background poll can detect copies from any app.
   */
  async readClipboardText() {
    if (!NativeBridge.isAvailable) return null;
    try { return await NativeBridge.invoke('plugin:clipboard-manager|read_text'); }
    catch { return null; }
  },

  /** Write text to the OS clipboard via the plugin. */
  async writeClipboardText(text) {
    if (!NativeBridge.isAvailable || typeof text !== 'string') return false;
    try {
      await NativeBridge.invoke('plugin:clipboard-manager|write_text', { label: null, text });
      return true;
    } catch (e) { console.warn('[clipboard] write failed:', e); return false; }
  },

  /**
   * Check for an available update and, if one exists, download + install it.
   * Silent on failure (no update endpoint, offline, etc.). Returns the new
   * version string if an update was installed, null otherwise. Caller must
   * ask the user to restart — the new binary only takes effect on next launch.
   */
  async checkForUpdates() {
    if (!NativeBridge.isAvailable) return null;
    try {
      const info = await NativeBridge.invoke('plugin:updater|check');
      if (!info || !info.available) return null;
      await NativeBridge.invoke('plugin:updater|download_and_install');
      return info.version || 'new version';
    } catch (e) {
      console.warn('[updater] check failed:', e);
      return null;
    }
  },

  /** Restart the current app. */
  async restart() {
    if (!NativeBridge.isAvailable) return;
    try { await NativeBridge.invoke('plugin:process|restart'); }
    catch (e) { console.warn('[process] restart failed:', e); }
  },
};
