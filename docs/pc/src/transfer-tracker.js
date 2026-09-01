/**
 * TransferTracker — unified view of every in-flight and recently-completed
 * transfer (both directions). Consumed by the global header pill.
 *
 * Speed is a rolling window over the last ~1.5s of samples so we don't jitter
 * when the browser schedules our progress events irregularly.
 */
export class TransferTracker extends EventTarget {
  constructor(transfer) {
    super();
    this.transfers = new Map(); // id -> state

    transfer.addEventListener('incoming-meta', (e) => this._register(e.detail, 'in'));
    transfer.addEventListener('outgoing-meta', (e) => this._register(e.detail, 'out'));
    transfer.addEventListener('progress',      (e) => this._onProgress(e.detail));
    transfer.addEventListener('completed',     (e) => this._markDone(e.detail.id));
    transfer.addEventListener('sent',          (e) => this._markDone(e.detail.id));
    transfer.addEventListener('cancelled',     (e) => this._markFailed(e.detail.id, e.detail.reason));
  }

  _register(meta, direction) {
    if (this.transfers.has(meta.id)) return;
    this.transfers.set(meta.id, {
      id: meta.id,
      name: meta.name,
      total: meta.size,
      mime: meta.mime,
      bytes: 0,
      direction,
      status: 'active',                  // 'active' | 'done' | 'failed'
      startedAt: Date.now(),
      completedAt: null,
      samples: [{ t: Date.now(), b: 0 }],
      speed: 0,                          // bytes/sec (rolling)
      eta: null,                         // seconds (null if unknown)
      error: null,
    });
    this._emit();
  }

  _onProgress({ id, bytes, total, direction }) {
    let t = this.transfers.get(id);
    if (!t) {
      this._register({ id, name: '…', size: total, mime: '' }, direction);
      t = this.transfers.get(id);
    }
    // Provisional receives (no fileMeta) grow `total` frame by frame — keep
    // t.total in sync so the pill percentage doesn't stay pinned at 0.
    if (total && total > (t.total || 0)) t.total = total;
    t.bytes = bytes;
    const now = Date.now();
    t.samples.push({ t: now, b: bytes });
    // Keep ~1.5s of samples for the speed rolling window.
    while (t.samples.length > 2 && now - t.samples[0].t > 1500) t.samples.shift();
    const first = t.samples[0];
    const dt = (now - first.t) / 1000;
    const db = bytes - first.b;
    t.speed = dt > 0.15 ? db / dt : 0;
    const remaining = Math.max(0, t.total - bytes);
    t.eta = t.speed > 0 ? Math.max(0, Math.round(remaining / t.speed)) : null;
    this._emit();
  }

  _markDone(id) {
    const t = this.transfers.get(id);
    if (!t) return;
    t.status = 'done';
    t.bytes = t.total;
    t.speed = 0;
    t.eta = 0;
    t.completedAt = Date.now();
    this._emit();
    // Auto-clear after a short victory lap so 100% flashes on screen.
    setTimeout(() => {
      if (this.transfers.get(id)?.status === 'done') {
        this.transfers.delete(id);
        this._emit();
      }
    }, 1400);
  }

  _markFailed(id, reason) {
    const t = this.transfers.get(id);
    if (!t) return;
    t.status = 'failed';
    t.error = reason || 'error';
    this._emit();
    setTimeout(() => {
      if (this.transfers.get(id)?.status === 'failed') {
        this.transfers.delete(id);
        this._emit();
      }
    }, 4500);
  }

  get all() { return [...this.transfers.values()]; }
  get active() { return this.all.filter((t) => t.status === 'active'); }

  /** The transfer to surface in the global pill (most recent active > failed > done). */
  get topmost() {
    const actives = this.active;
    if (actives.length) return actives[actives.length - 1];
    const failed = this.all.filter((t) => t.status === 'failed');
    if (failed.length) return failed[failed.length - 1];
    const done = this.all.filter((t) => t.status === 'done');
    return done.length ? done[done.length - 1] : null;
  }

  /**
   * Aggregated view when multiple transfers are in flight simultaneously.
   * Returns null if 0 or 1 active — caller falls back to `topmost` display.
   */
  get aggregate() {
    const actives = this.active;
    if (actives.length < 2) return null;
    const total = actives.reduce((s, t) => s + (t.total || 0), 0);
    const bytes = actives.reduce((s, t) => s + (t.bytes || 0), 0);
    const speed = actives.reduce((s, t) => s + (t.speed || 0), 0);
    const remaining = Math.max(0, total - bytes);
    const eta = speed > 0 ? Math.max(0, Math.round(remaining / speed)) : null;
    const directions = new Set(actives.map((t) => t.direction));
    return {
      count: actives.length,
      total,
      bytes,
      speed,
      eta,
      direction: directions.size === 1 ? [...directions][0] : 'mixed',
      percent: total > 0 ? Math.round((bytes / total) * 100) : 0,
    };
  }

  _emit() {
    this.dispatchEvent(new CustomEvent('update'));
  }
}

export function formatBytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1_048_576) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1_073_741_824) return `${(n / 1_048_576).toFixed(1)} MB`;
  return `${(n / 1_073_741_824).toFixed(2)} GB`;
}

export function formatSpeed(bytesPerSec) {
  if (!bytesPerSec || bytesPerSec < 1) return '';
  return `${formatBytes(bytesPerSec)}/s`;
}

export function formatEta(seconds) {
  if (seconds == null) return '';
  if (seconds <= 1) return '1s left';
  if (seconds < 60) return `${seconds}s left`;
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return s === 0 ? `${m}m left` : `${m}m ${s}s left`;
}
