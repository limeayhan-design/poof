import { decodeEnvelope, encodeEnvelope, decodeFrame } from './poof-protocol.js';

/**
 * Poof — PC side WebRTC engine.
 *
 * Symmetric to ios/WebRTCManager.swift:
 *   • `control` channel : unreliable (ordered:false, maxRetransmits:0),
 *     priority high  → clipboard / notif / hand-off / meta
 *   • `bulk` channel    : reliable ordered, priority low → binary file frames
 *
 * Signaling is intentionally external: hand SDP/ICE payloads to and from the
 * Node signaling server via `handleRemote*` / `onLocal*` callbacks.
 */
export class WebRTCManager extends EventTarget {
  constructor({ iceServers = [{ urls: 'stun:stun.l.google.com:19302' }] } = {}) {
    super();
    this.iceServers = iceServers;
    this.pc = null;
    this.control = null;
    this.bulk = null;
    this.state = 'idle';

    // Callbacks — the signaling client wires these to socket.io events.
    this.onLocalDescription = null;
    this.onLocalCandidate = null;
  }

  // ---------- lifecycle ----------

  async start({ initiator }) {
    this._setState('connecting');
    this.pc = new RTCPeerConnection({ iceServers: this.iceServers, bundlePolicy: 'max-bundle' });

    this.pc.onicecandidate = (e) => {
      if (e.candidate && this.onLocalCandidate) this.onLocalCandidate(e.candidate);
    };
    this.pc.oniceconnectionstatechange = () => {
      const s = this.pc.iceConnectionState;
      console.log('[webrtc] ICE state →', s);
      if (s === 'connected' || s === 'completed') this._setState('connected');
      if (s === 'failed') this._setState('closed', 'ice-failed');
      if (s === 'disconnected') this._setState('closed', 'ice-disconnected');
    };

    if (initiator) {
      // control: reliable + ordered. Small envelopes (clipboard, fileMeta, resume)
      // MUST arrive — dropping fileMeta silently breaks every following bulk frame.
      this.control = this._openChannel('control', { ordered: true, priority: 'high' });
      this.bulk = this._openChannel('bulk', { ordered: true, priority: 'low' });
      this.bulk.binaryType = 'arraybuffer';

      const offer = await this.pc.createOffer();
      await this.pc.setLocalDescription(offer);
      this.onLocalDescription?.(this.pc.localDescription);
    } else {
      this.pc.ondatachannel = (e) => this._attachIncoming(e.channel);
    }
  }

  close(reason = 'manual') {
    this.control?.close();
    this.bulk?.close();
    this.pc?.close();
    this.pc = this.control = this.bulk = null;
    this._setState('closed', reason);
  }

  // ---------- signaling handoff ----------

  async handleRemoteDescription(desc) {
    await this.pc.setRemoteDescription(desc);
    if (desc.type === 'offer') {
      const answer = await this.pc.createAnswer();
      await this.pc.setLocalDescription(answer);
      this.onLocalDescription?.(this.pc.localDescription);
    }
  }

  async addRemoteCandidate(candidate) {
    try { await this.pc.addIceCandidate(candidate); } catch { /* stale */ }
  }

  // ---------- sending ----------

  sendEnvelope(env) {
    if (!this.control || this.control.readyState !== 'open') return false;
    this.control.send(encodeEnvelope(env));
    return true;
  }

  sendBulk(buffer) {
    if (!this.bulk || this.bulk.readyState !== 'open') return false;
    this.bulk.send(buffer);
    return true;
  }

  get bulkBufferedAmount() { return this.bulk?.bufferedAmount ?? 0; }

  // ---------- internal ----------

  _openChannel(label, cfg) {
    const ch = this.pc.createDataChannel(label, cfg);
    this._attachIncoming(ch);
    return ch;
  }

  get isReady() {
    return this.control?.readyState === 'open' && this.bulk?.readyState === 'open';
  }

  _attachIncoming(ch) {
    ch.onopen = () => {
      console.log('[webrtc] channel OPEN →', ch.label, 'ordered=', ch.ordered, 'maxRetransmits=', ch.maxRetransmits);
      this.dispatchEvent(new CustomEvent('channel-open', { detail: ch.label }));
      if (this.isReady) this.dispatchEvent(new CustomEvent('ready'));
    };
    ch.onclose = () => {
      console.log('[webrtc] channel CLOSE →', ch.label);
      this.dispatchEvent(new CustomEvent('channel-close', { detail: ch.label }));
    };
    ch.onerror = (e) => console.warn('[webrtc] channel ERROR →', ch.label, e);

    if (ch.label === 'bulk') {
      ch.binaryType = 'arraybuffer';
      this.bulk = ch;
      ch.onmessage = (e) => {
        try {
          const frame = decodeFrame(e.data);
          this.dispatchEvent(new CustomEvent('bulk-frame', { detail: frame }));
        } catch (err) {
          console.warn('[webrtc] malformed bulk frame:', err);
          this.dispatchEvent(new CustomEvent('protocol-error', { detail: { channel: 'bulk', error: err } }));
        }
      };
    } else if (ch.label === 'control') {
      this.control = ch;
      ch.onmessage = (e) => {
        try {
          const env = decodeEnvelope(e.data);
          this.dispatchEvent(new CustomEvent('envelope', { detail: env }));
        } catch (err) {
          console.warn('[webrtc] malformed envelope:', err);
          this.dispatchEvent(new CustomEvent('protocol-error', { detail: { channel: 'control', error: err } }));
        }
      };
    }
  }

  _setState(state, reason) {
    this.state = state;
    this.dispatchEvent(new CustomEvent('state', { detail: { state, reason } }));
  }
}
