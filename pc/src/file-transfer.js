import { PoofMessageType, CHUNK_SIZE, encodeFrame, newId } from './poof-protocol.js';

/**
 * File transfer over the reliable `bulk` channel.
 *
 * - Sender: chunk 64 KiB, ship binary frames, respect back-pressure < 1 MiB.
 * - Receiver: reassemble by transferId, hand a Blob to the host UI once
 *   the last frame is in.
 *
 * Resume: if the WebRTC channel drops mid-transfer, state is kept for
 * `stalledTTL` ms. On reconnect the sender emits FileResumeQuery; the
 * receiver replies FileResumeAck{ nextIndex } and the sender jumps ahead.
 */
export class FileTransfer extends EventTarget {
  constructor(manager) {
    super();
    this.manager = manager;
    this.backpressureLimit = 1_048_576;   // 1 MiB
    this.stalledTTL = 5 * 60 * 1000;      // 5 minutes
    this.resumeTimeout = 15_000;
    this.incoming = new Map();            // transferId -> receiver state
    this.outgoing = new Map();            // transferId -> sender state
    this._resumeWaiters = new Map();      // transferId -> {resolve, reject, timer}

    manager.addEventListener('envelope', (e) => this._handleEnvelope(e.detail));
    manager.addEventListener('bulk-frame', (e) => this._handleFrame(e.detail));
    manager.addEventListener('state', (e) => {
      if (e.detail?.state === 'closed') this._pauseAll('channel-closed');
    });
    manager.addEventListener('ready', () => this._resumeAll());

    this._gcTimer = setInterval(() => this._garbageCollect(), 30_000);
  }

  dispose() {
    clearInterval(this._gcTimer);
  }

  _pauseAll(reason) {
    for (const state of this.incoming.values()) state.paused = true;
    for (const state of this.outgoing.values()) state.paused = true;
    if (this.incoming.size || this.outgoing.size) {
      this.dispatchEvent(new CustomEvent('paused', { detail: { reason } }));
    }
  }

  _resumeAll() {
    for (const [id, state] of this.outgoing) {
      if (state.paused && !state.done) this._resumeOutgoing(id).catch(() => {});
    }
  }

  _garbageCollect() {
    const now = Date.now();
    for (const [id, state] of this.incoming) {
      if (now - state.lastActivity > this.stalledTTL) {
        this.incoming.delete(id);
        this.dispatchEvent(new CustomEvent('cancelled', { detail: { id, reason: 'stalled-ttl' } }));
      }
    }
    for (const [id, state] of this.outgoing) {
      if (state.done) { this.outgoing.delete(id); continue; }
      if (now - state.lastActivity > this.stalledTTL) {
        this.outgoing.delete(id);
        this.dispatchEvent(new CustomEvent('cancelled', { detail: { id, reason: 'stalled-ttl' } }));
      }
    }
  }

  /** Send a browser File / Blob to the peer. */
  async send(file) {
    const transferId = newId();
    const size = file.size;
    const chunks = Math.ceil(size / CHUNK_SIZE);
    const mime = file.type || 'application/octet-stream';

    const state = {
      file, size, chunks, mime, name: file.name,
      nextIndex: 0,
      lastActivity: Date.now(),
      paused: false,
      done: false,
      metaSent: false,
    };
    this.outgoing.set(transferId, state);

    this.dispatchEvent(new CustomEvent('outgoing-meta', {
      detail: { id: transferId, name: file.name, size, mime },
    }));

    try {
      await this._pumpOutgoing(transferId);
    } catch (err) {
      if (err?.message !== 'paused') {
        this.outgoing.delete(transferId);
        this.dispatchEvent(new CustomEvent('cancelled', {
          detail: { id: transferId, reason: err.message || 'send-failed' },
        }));
        throw err;
      }
    }

    return transferId;
  }

  async _pumpOutgoing(transferId) {
    const state = this.outgoing.get(transferId);
    if (!state) return;

    if (!state.metaSent) {
      if (!this.manager.sendEnvelope({
        type: PoofMessageType.FileMeta,
        id: transferId,
        payload: { name: state.name, size: state.size, mime: state.mime, chunks: state.chunks },
      })) throw new Error('paused');
      state.metaSent = true;
    }

    for (let index = state.nextIndex; index < state.chunks; index++) {
      if (!this.manager.isReady) { state.paused = true; throw new Error('paused'); }
      const start = index * CHUNK_SIZE;
      const end = Math.min(start + CHUNK_SIZE, state.size);
      const payload = await state.file.slice(start, end).arrayBuffer();
      const isLast = end === state.size;
      await this._awaitBackpressure();
      if (!this.manager.sendBulk(encodeFrame({ transferId, index, isLast, payload }))) {
        state.paused = true;
        throw new Error('paused');
      }
      state.nextIndex = index + 1;
      state.lastActivity = Date.now();
      this.dispatchEvent(new CustomEvent('progress', {
        detail: { id: transferId, bytes: end, total: state.size, direction: 'out' },
      }));
    }

    this.manager.sendEnvelope({
      type: PoofMessageType.FileComplete,
      id: transferId,
      payload: {},
    });
    state.done = true;
    this.outgoing.delete(transferId);
    this.dispatchEvent(new CustomEvent('sent', { detail: { id: transferId } }));
  }

  async _resumeOutgoing(transferId) {
    const state = this.outgoing.get(transferId);
    if (!state || state.done) return;

    try {
      const nextIndex = await this._queryResume(transferId);
      if (nextIndex >= state.chunks) {
        state.done = true;
        this.outgoing.delete(transferId);
        this.manager.sendEnvelope({ type: PoofMessageType.FileComplete, id: transferId, payload: {} });
        this.dispatchEvent(new CustomEvent('sent', { detail: { id: transferId } }));
        return;
      }
      state.nextIndex = nextIndex;
      state.paused = false;
      state.metaSent = true;
      this.dispatchEvent(new CustomEvent('resumed', {
        detail: { id: transferId, from: nextIndex, total: state.chunks },
      }));
      await this._pumpOutgoing(transferId);
    } catch (err) {
      if (err?.message === 'paused') return;
      this.outgoing.delete(transferId);
      this.dispatchEvent(new CustomEvent('cancelled', {
        detail: { id: transferId, reason: err.message || 'resume-failed' },
      }));
    }
  }

  _queryResume(transferId) {
    return new Promise((resolve, reject) => {
      const prev = this._resumeWaiters.get(transferId);
      if (prev) { clearTimeout(prev.timer); prev.reject(new Error('superseded')); }

      const timer = setTimeout(() => {
        this._resumeWaiters.delete(transferId);
        reject(new Error('resume-timeout'));
      }, this.resumeTimeout);

      this._resumeWaiters.set(transferId, { resolve, reject, timer });

      if (!this.manager.sendEnvelope({
        type: PoofMessageType.FileResumeQuery,
        id: transferId,
        payload: {},
      })) {
        clearTimeout(timer);
        this._resumeWaiters.delete(transferId);
        reject(new Error('paused'));
      }
    });
  }

  cancel(transferId, reason = 'user') {
    this.manager.sendEnvelope({
      type: PoofMessageType.FileCancel,
      id: transferId,
      payload: { reason },
    });
    const hadIn = this.incoming.delete(transferId);
    const hadOut = this.outgoing.delete(transferId);
    const waiter = this._resumeWaiters.get(transferId);
    if (waiter) { clearTimeout(waiter.timer); waiter.reject(new Error('cancelled')); this._resumeWaiters.delete(transferId); }
    if (hadIn || hadOut) {
      this.dispatchEvent(new CustomEvent('cancelled', { detail: { id: transferId, reason } }));
    }
  }

  // ---- receiving ----

  _handleEnvelope(env) {
    if (env.type === PoofMessageType.FileMeta) {
      const { name, size, mime, chunks } = env.payload;
      const existing = this.incoming.get(env.id);
      if (existing && !existing.provisional) {
        console.log('[file-transfer] fileMeta duplicate (resume?)', env.id, name);
        existing.lastActivity = Date.now();
        existing.paused = false;
        return;
      }
      console.log('[file-transfer] fileMeta →', name, size, 'bytes,', chunks, 'chunks');
      if (existing && existing.provisional) {
        // Frames arrived before meta — merge without wiping received parts.
        existing.meta = { id: env.id, name, size, mime, chunks };
        existing.provisional = false;
        if (chunks > existing.parts.length) existing.parts.length = chunks;
        existing.lastActivity = Date.now();
      } else {
        this.incoming.set(env.id, {
          meta: { id: env.id, name, size, mime, chunks },
          parts: new Array(chunks),
          received: 0,
          expected: 0,
          lastActivity: Date.now(),
          paused: false,
          provisional: false,
        });
      }
      this.dispatchEvent(new CustomEvent('incoming-meta', {
        detail: { id: env.id, name, size, mime },
      }));
    } else if (env.type === PoofMessageType.FileCancel) {
      if (this.incoming.delete(env.id) || this.outgoing.delete(env.id)) {
        this.dispatchEvent(new CustomEvent('cancelled', {
          detail: { id: env.id, reason: env.payload?.reason || 'peer' },
        }));
      }
    } else if (env.type === PoofMessageType.FileResumeQuery) {
      const state = this.incoming.get(env.id);
      const nextIndex = state ? state.expected : 0;
      this.manager.sendEnvelope({
        type: PoofMessageType.FileResumeAck,
        id: env.id,
        payload: { nextIndex },
      });
      if (state) state.lastActivity = Date.now();
    } else if (env.type === PoofMessageType.FileResumeAck) {
      const waiter = this._resumeWaiters.get(env.id);
      if (waiter) {
        clearTimeout(waiter.timer);
        this._resumeWaiters.delete(env.id);
        waiter.resolve(Number(env.payload?.nextIndex ?? 0));
      }
    } else if (env.type === PoofMessageType.FileDelivered) {
      this.dispatchEvent(new CustomEvent('delivered', { detail: { id: env.id } }));
    } else if (env.type === PoofMessageType.FileSeen) {
      this.dispatchEvent(new CustomEvent('seen', { detail: { id: env.id } }));
    }
  }

  markSeen(transferId) {
    this.manager.sendEnvelope({
      type: PoofMessageType.FileSeen,
      id: transferId,
      payload: {},
    });
  }

  _handleFrame(frame) {
    let state = this.incoming.get(frame.transferId);
    if (!state) {
      // fileMeta hasn't arrived (unreliable control on old iOS, or races).
      // Create a provisional state and start accepting frames — meta may
      // arrive later and update name/size/mime, or we synthesize at the end.
      console.warn('[file-transfer] provisional state (no fileMeta yet) for', frame.transferId);
      state = {
        meta: { id: frame.transferId, name: '', size: 0, mime: 'application/octet-stream', chunks: 0 },
        parts: [],
        received: 0,
        expected: 0,
        lastActivity: Date.now(),
        paused: false,
        provisional: true,
      };
      this.incoming.set(frame.transferId, state);
      this.dispatchEvent(new CustomEvent('incoming-meta', {
        detail: { id: frame.transferId, name: 'Fichier reçu', size: 0, mime: state.meta.mime },
      }));
    }
    if (frame.index < state.expected) return;         // duplicate after resume
    if (frame.index !== state.expected) {             // gap → protocol violation
      console.warn('[file-transfer] out-of-order frame', frame.index,
                   'expected', state.expected);
      this.cancel(frame.transferId, 'out-of-order');
      return;
    }
    state.parts[frame.index] = frame.payload;
    state.expected++;
    state.received += frame.payload.byteLength;
    state.lastActivity = Date.now();
    // If we're still provisional, use received bytes as a lower-bound total
    // so the pill at least shows progress instead of ∞.
    const total = state.provisional ? state.received : state.meta.size;
    this.dispatchEvent(new CustomEvent('progress', {
      detail: { id: frame.transferId, bytes: state.received, total, direction: 'in' },
    }));

    if (frame.isLast) {
      // Fill in meta if we never got the envelope.
      if (state.provisional) {
        state.meta.size = state.received;
        state.meta.chunks = state.expected;
        const sniff = sniffMime(state.parts[0]);
        if (sniff) state.meta.mime = sniff.mime;
        if (!state.meta.name) {
          const ext = sniff?.ext || 'bin';
          state.meta.name = `poof-${new Date().toISOString().replace(/[:.]/g, '-')}.${ext}`;
        }
      }
      const blob = new Blob(state.parts, { type: state.meta.mime });
      this.incoming.delete(frame.transferId);
      this.manager.sendEnvelope({
        type: PoofMessageType.FileDelivered,
        id: frame.transferId,
        payload: {},
      });
      this.dispatchEvent(new CustomEvent('completed', {
        detail: { id: frame.transferId, meta: state.meta, blob },
      }));
    }
  }

  async _awaitBackpressure() {
    while (this.manager.bulkBufferedAmount > this.backpressureLimit) {
      await new Promise((r) => setTimeout(r, 5));
    }
  }
}

// Guess file type from the first bytes of the payload. Used only when the
// fileMeta envelope never arrived (unreliable control channel).
function sniffMime(firstChunk) {
  if (!firstChunk) return null;
  const b = new Uint8Array(firstChunk);
  if (b.length < 4) return null;
  // PNG
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4E && b[3] === 0x47)
    return { mime: 'image/png', ext: 'png' };
  // JPG
  if (b[0] === 0xFF && b[1] === 0xD8 && b[2] === 0xFF)
    return { mime: 'image/jpeg', ext: 'jpg' };
  // GIF
  if (b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x38)
    return { mime: 'image/gif', ext: 'gif' };
  // PDF
  if (b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46)
    return { mime: 'application/pdf', ext: 'pdf' };
  // ZIP / DOCX / XLSX / IPA / APK
  if (b[0] === 0x50 && b[1] === 0x4B && (b[2] === 0x03 || b[2] === 0x05 || b[2] === 0x07))
    return { mime: 'application/zip', ext: 'zip' };
  // ISO Base Media (MP4 / MOV / HEIC / M4A) — "ftyp" at offset 4
  if (b.length >= 12 && b[4] === 0x66 && b[5] === 0x74 && b[6] === 0x79 && b[7] === 0x70) {
    const brand = String.fromCharCode(b[8], b[9], b[10], b[11]).toLowerCase();
    if (brand.startsWith('heic') || brand.startsWith('heix') || brand === 'mif1' || brand === 'msf1')
      return { mime: 'image/heic', ext: 'heic' };
    if (brand.startsWith('qt  ')) return { mime: 'video/quicktime', ext: 'mov' };
    if (brand.startsWith('m4a')) return { mime: 'audio/mp4', ext: 'm4a' };
    return { mime: 'video/mp4', ext: 'mp4' };
  }
  // WebP: "RIFF????WEBP"
  if (b.length >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46
      && b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50)
    return { mime: 'image/webp', ext: 'webp' };
  // MP3
  if ((b[0] === 0x49 && b[1] === 0x44 && b[2] === 0x33) ||
      (b[0] === 0xFF && (b[1] & 0xE0) === 0xE0))
    return { mime: 'audio/mpeg', ext: 'mp3' };
  return null;
}
