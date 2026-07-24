import { PoofMessageType, newId } from './poof-protocol.js';

/**
 * Screen Mirror — matches iOS PoofScreenBroadcast.
 *
 * Two directions:
 *  - Receive: peer sends `screenMirrorStart` → we open the viewer canvas.
 *    Each `screenMirrorFrame` envelope carries base64 JPEG → drawn to canvas.
 *  - Send: user picks a source via `getDisplayMedia`. We paint a frame every
 *    100 ms into an offscreen canvas → toBlob(quality=0.4) → base64 →
 *    `screenMirrorFrame` envelope on the control channel.
 *
 * Uses control channel (`maxRetransmits=0`, unordered) — drop stale frames
 * rather than stall on a slow link.
 */
export class ScreenMirror extends EventTarget {
  constructor(manager) {
    super();
    this.manager = manager;
    this.isReceiving = false;
    this.isBroadcasting = false;
    this._stream = null;
    this._loop = null;
    this._offscreen = null;
    this._videoEl = null;
    manager.addEventListener('envelope', (e) => this._handle(e.detail));
  }

  _handle(env) {
    if (env.type === PoofMessageType.ScreenMirrorStart) {
      this.isReceiving = true;
      this.dispatchEvent(new CustomEvent('receiving-start'));
    } else if (env.type === PoofMessageType.ScreenMirrorStop) {
      this.isReceiving = false;
      this.dispatchEvent(new CustomEvent('receiving-stop'));
    } else if (env.type === PoofMessageType.ScreenMirrorFrame) {
      const b64 = env.payload?.jpeg;
      if (typeof b64 !== 'string') return;
      if (!this.isReceiving) {
        this.isReceiving = true;
        this.dispatchEvent(new CustomEvent('receiving-start'));
      }
      this.dispatchEvent(new CustomEvent('frame', {
        detail: { dataUrl: `data:image/jpeg;base64,${b64}` },
      }));
    }
  }

  async startBroadcast({ fps = 10, maxDim = 1280, quality = 0.4 } = {}) {
    if (this.isBroadcasting) return true;
    if (!navigator.mediaDevices?.getDisplayMedia) {
      throw new Error('getDisplayMedia unsupported');
    }
    this._stream = await navigator.mediaDevices.getDisplayMedia({
      video: { frameRate: fps },
      audio: false,
    });
    this._stream.getVideoTracks()[0].addEventListener('ended', () => this.stopBroadcast());

    this._videoEl = document.createElement('video');
    this._videoEl.autoplay = true;
    this._videoEl.playsInline = true;
    this._videoEl.muted = true;
    this._videoEl.srcObject = this._stream;
    await this._videoEl.play().catch(() => {});

    this._offscreen = document.createElement('canvas');
    this.isBroadcasting = true;

    this.manager.sendEnvelope({
      type: PoofMessageType.ScreenMirrorStart,
      id: newId(),
      payload: {},
    });
    this.dispatchEvent(new CustomEvent('broadcasting-start'));

    const interval = 1000 / fps;
    this._loop = setInterval(() => this._captureFrame(maxDim, quality), interval);
    return true;
  }

  stopBroadcast() {
    if (!this.isBroadcasting) return;
    this.isBroadcasting = false;
    if (this._loop) { clearInterval(this._loop); this._loop = null; }
    if (this._stream) { this._stream.getTracks().forEach((t) => t.stop()); this._stream = null; }
    this._videoEl = null;
    this._offscreen = null;
    this.manager.sendEnvelope({
      type: PoofMessageType.ScreenMirrorStop,
      id: newId(),
      payload: {},
    });
    this.dispatchEvent(new CustomEvent('broadcasting-stop'));
  }

  async _captureFrame(maxDim, quality) {
    if (!this._videoEl || !this._offscreen) return;
    const w0 = this._videoEl.videoWidth;
    const h0 = this._videoEl.videoHeight;
    if (!w0 || !h0) return;
    const longest = Math.max(w0, h0);
    const scale = longest > maxDim ? maxDim / longest : 1;
    const w = Math.round(w0 * scale);
    const h = Math.round(h0 * scale);
    if (this._offscreen.width !== w) this._offscreen.width = w;
    if (this._offscreen.height !== h) this._offscreen.height = h;
    const ctx = this._offscreen.getContext('2d');
    ctx.drawImage(this._videoEl, 0, 0, w, h);
    const blob = await new Promise((r) => this._offscreen.toBlob(r, 'image/jpeg', quality));
    if (!blob) return;
    const buf = await blob.arrayBuffer();
    const b64 = arrayBufferToBase64(buf);
    this.manager.sendEnvelope({
      type: PoofMessageType.ScreenMirrorFrame,
      id: newId(),
      payload: { jpeg: b64 },
    });
  }
}

function arrayBufferToBase64(buf) {
  let s = '';
  const bytes = new Uint8Array(buf);
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    s += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(s);
}
