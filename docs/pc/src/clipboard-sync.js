import { PoofMessageType, newId } from './poof-protocol.js';
import { NativeFeatures } from './native-features.js';

/**
 * PC-side clipboard bridge.
 * - Uses the async Clipboard API (requires user gesture / permission on the browser).
 * - Keeps a local history of the last 3 items.
 * - Poll-based local detection (Clipboard API has no change event on the web).
 * - Loop-back guard via fingerprint, identical to Swift side.
 */
export class ClipboardSync {
  constructor(manager, { pollIntervalMs = 800 } = {}) {
    this.manager = manager;
    this.history = [];
    this.lastLocalFp = null;
    this.lastRemoteFp = null;
    this.pollIntervalMs = pollIntervalMs;
    this._timer = null;
    // When false, silent clipboard changes are NOT auto-broadcast.
    // A user-triggered pushCurrent() still works either way.
    this.autoPushEnabled = false;

    manager.addEventListener('envelope', (e) => this._handle(e.detail));
  }

  start() {
    if (this._timer) return;
    this._timer = setInterval(() => this._pollLocal(), this.pollIntervalMs);
  }

  stop() { clearInterval(this._timer); this._timer = null; }

  /** Manual force-push regardless of fingerprint. */
  async pushCurrent() { await this._pollLocal(true); }

  onIncoming(callback) { this._onIncoming = callback; }
  onOutgoing(callback) { this._onOutgoing = callback; }

  // ------- local → remote -------

  async _pollLocal(force = false) {
    let text;
    // Prefer the Tauri native plugin (no user-gesture requirement) so a
    // silent poll can catch copies made from any app on the OS.
    if (NativeFeatures.isAvailable) {
      text = await NativeFeatures.readClipboardText();
    } else {
      try { text = await navigator.clipboard.readText(); }
      catch { return; }              // no permission / no gesture yet
    }
    if (!text) return;

    const fp = fingerprint(text);
    if (fp === this.lastRemoteFp) return;
    if (!force && fp === this.lastLocalFp) return;
    if (!force && !this.autoPushEnabled) return;
    this.lastLocalFp = fp;

    const item = { text, date: Date.now(), origin: 'local' };
    this._remember(item);

    this.manager.sendEnvelope({
      type: PoofMessageType.Clipboard,
      id: newId(),
      force,
      payload: { text, fp },
    });
    this._onOutgoing?.(item);
  }

  // ------- remote → local -------

  async _handle(env) {
    if (env.type !== PoofMessageType.Clipboard) return;
    const text = env.payload?.text;
    if (typeof text !== 'string') return;
    const fp = env.payload?.fp ?? fingerprint(text);
    this.lastRemoteFp = fp;
    if (NativeFeatures.isAvailable) {
      await NativeFeatures.writeClipboardText(text);
    } else {
      try { await navigator.clipboard.writeText(text); } catch { /* ignore */ }
    }
    const item = { text, date: Date.now(), origin: 'remote' };
    this._remember(item);
    this._onIncoming?.(item);
  }

  _remember(item) {
    this.history.unshift(item);
    if (this.history.length > 3) this.history.length = 3;
  }
}

function fingerprint(text) {
  // FNV-1a — same order-of-magnitude cheapness as Swift's hashValue trick.
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16);
}
