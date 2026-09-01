import { NativeBridge } from './native-bridge.js';

/**
 * LAN discovery — thin wrapper around the Rust mDNS service exposed by the
 * Tauri shell. On plain browsers this class is a no-op; callers can still
 * bind listeners and `isAvailable` will simply stay `false`.
 *
 * Events:
 *   - "peer-found"  → { deviceId, name, platform, host, port }
 *   - "peer-lost"   → { fullname }
 */
export class LanDiscovery extends EventTarget {
  constructor() {
    super();
    this.isAvailable = NativeBridge.isAvailable;
    this.started = false;
    this._unlistenFound = null;
    this._unlistenLost = null;
    this._selfDeviceId = null;
  }

  /**
   * Start advertising this device on the LAN and subscribe to peer events.
   * Silently returns on browsers without Tauri.
   */
  async start({ deviceId, name }) {
    if (this.started) return;
    this._selfDeviceId = deviceId;

    // Wait up to 3s for the Tauri bridge — v2 sometimes injects it after
    // the first module scripts finish, and evaluating too early silently
    // no-ops the whole LAN layer.
    let waited = 0;
    while (!NativeBridge.isAvailable && waited < 3000) {
      await new Promise((r) => setTimeout(r, 100));
      waited += 100;
    }
    if (!NativeBridge.isAvailable) {
      console.warn('[lan] bridge never became available — LAN discovery disabled');
      return;
    }
    this.isAvailable = true;

    this._unlistenFound = await NativeBridge.listen('lan-peer-found', (peer) => {
      // Never surface ourselves as a peer.
      if (peer?.deviceId && peer.deviceId !== this._selfDeviceId) {
        this.dispatchEvent(new CustomEvent('peer-found', { detail: peer }));
      }
    });
    this._unlistenLost = await NativeBridge.listen('lan-peer-lost', (fullname) => {
      this.dispatchEvent(new CustomEvent('peer-lost', { detail: { fullname } }));
    });

    console.log('[lan] invoking lan_start (waited', waited, 'ms) →', deviceId, name);
    await NativeBridge.invoke('lan_start', { deviceId, name });
    this.started = true;
    console.log('[lan] ✅ advertising on LAN as', deviceId);
  }

  async updateName(name) {
    if (!this.isAvailable || !this.started || !this._selfDeviceId) return;
    await NativeBridge.invoke('lan_update_name', {
      deviceId: this._selfDeviceId,
      name,
    });
  }

  async stop() {
    if (!this.isAvailable) return;
    try { this._unlistenFound?.(); } catch { /* noop */ }
    try { this._unlistenLost?.(); } catch { /* noop */ }
    this._unlistenFound = null;
    this._unlistenLost = null;
    if (this.started) {
      await NativeBridge.invoke('lan_stop').catch(() => {});
    }
    this.started = false;
  }
}
