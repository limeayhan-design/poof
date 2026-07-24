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
    if (!this.isAvailable) return;
    if (this.started) return;
    this._selfDeviceId = deviceId;

    this._unlistenFound = await NativeBridge.listen('lan-peer-found', (peer) => {
      // Never surface ourselves as a peer.
      if (peer?.deviceId && peer.deviceId !== this._selfDeviceId) {
        this.dispatchEvent(new CustomEvent('peer-found', { detail: peer }));
      }
    });
    this._unlistenLost = await NativeBridge.listen('lan-peer-lost', (fullname) => {
      this.dispatchEvent(new CustomEvent('peer-lost', { detail: { fullname } }));
    });

    await NativeBridge.invoke('lan_start', { deviceId, name });
    this.started = true;
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
