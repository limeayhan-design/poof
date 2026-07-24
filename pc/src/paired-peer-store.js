/**
 * Persistent list of paired peers, mirrored to localStorage.
 * Each peer:  { id, name, platform, addedAt, lastSeenAt }
 *
 * Emits a 'change' CustomEvent every time the list is mutated so the UI can
 * re-render.
 */
const KEY = 'poof.pairedPeers';

export class PairedPeerStore extends EventTarget {
  constructor() {
    super();
    this._peers = new Map();
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) {
        for (const p of JSON.parse(raw)) this._peers.set(p.id, p);
      }
    } catch { /* corrupted — start empty */ }
  }

  get peers() { return [...this._peers.values()]; }
  get ids()   { return [...this._peers.keys()];   }

  has(id) { return this._peers.has(id); }

  upsert({ deviceId, name, platform }) {
    const existing = this._peers.get(deviceId) || { addedAt: Date.now() };
    this._peers.set(deviceId, {
      id: deviceId,
      name: name || existing.name || 'Unknown',
      platform: platform || existing.platform || 'unknown',
      addedAt: existing.addedAt,
      lastSeenAt: Date.now(),
    });
    this._save();
  }

  remove(id) {
    if (!this._peers.delete(id)) return;
    this._save();
  }

  touch(id) {
    const p = this._peers.get(id);
    if (!p) return;
    p.lastSeenAt = Date.now();
    this._save();
  }

  _save() {
    localStorage.setItem(KEY, JSON.stringify(this.peers));
    this.dispatchEvent(new CustomEvent('change'));
  }
}
