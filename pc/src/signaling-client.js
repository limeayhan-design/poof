/**
 * Socket.IO bridge between the multi-device signaling server (server.js) and a
 * WebRTCManager instance.
 *
 * Wiring:
 *   const sig = new SignalingClient({ url });
 *   sig.attach(manager);
 *   await sig.hello({ deviceId, name, platform, knownPeerIds: [...] });
 *   // Advertise or consume:
 *   const code = await sig.pairAdvertise();
 *   // ... or ...
 *   const peer = await sig.pairConsume(code);
 *   // Then to actually talk:
 *   await sig.openSession(peer.deviceId);   // becomes offerer
 */
export class SignalingClient extends EventTarget {
  constructor({ url } = {}) {
    super();
    if (typeof io === 'undefined') throw new Error('socket.io client not loaded');
    this.socket = io(url || location.origin, {
      transports: ['websocket'],
      autoConnect: true,
    });
    this.sessionId = null;
    this.manager = null;
    this.knownPeerIds = new Set();

    this.socket.on('connect', () => this._emit('connected'));
    this.socket.on('disconnect', (reason) => this._emit('disconnected', { reason }));

    this.socket.on('peer-online',  ({ deviceId }) => this._emit('peer-online',  { deviceId }));
    this.socket.on('peer-offline', ({ deviceId }) => this._emit('peer-offline', { deviceId }));
    this.socket.on('peer-unpaired',({ deviceId }) => this._emit('peer-unpaired',{ deviceId }));

    this.socket.on('pair-succeeded', ({ peer }) => this._emit('pair-succeeded', { peer }));
    this.socket.on('pair-expired',  ({ code })  => this._emit('pair-expired',  { code }));

    this.socket.on('session-opened', ({ sessionId, initiator, from }) => {
      this.sessionId = sessionId;
      this.manager?.start({ initiator: !!initiator });
      this._emit('session-opened', { sessionId, initiator, from });
    });
    this.socket.on('session-closed', ({ sessionId, reason }) => {
      this.sessionId = null;
      this._emit('session-closed', { sessionId, reason });
    });
    this.socket.on('peer-left', ({ sessionId, reason }) => {
      this._emit('peer-left', { sessionId, reason });
    });

    this.socket.on('sdp-offer',    ({ sdp })       => this.manager?.handleRemoteDescription(sdp));
    this.socket.on('sdp-answer',   ({ sdp })       => this.manager?.handleRemoteDescription(sdp));
    this.socket.on('ice-candidate',({ candidate }) => this.manager?.addRemoteCandidate(candidate));
  }

  attach(manager) {
    this.manager = manager;
    manager.onLocalDescription = (desc) => {
      const event = desc.type === 'offer' ? 'sdp-offer' : 'sdp-answer';
      this.socket.emit(event, { sdp: desc });
    };
    manager.onLocalCandidate = (candidate) => {
      this.socket.emit('ice-candidate', { candidate });
    };
  }

  // -------------------------------------------------------------------------
  // Identity + presence
  // -------------------------------------------------------------------------

  hello({ deviceId, name, platform, knownPeerIds = [] }) {
    this.knownPeerIds = new Set(knownPeerIds);
    return new Promise((resolve, reject) => {
      this.socket.emit('hello', {
        deviceId, name, platform, knownPeerIds: [...this.knownPeerIds],
      }, (res) => {
        if (!res?.ok) return reject(new Error(res?.error || 'hello-failed'));
        resolve(res.onlinePeers || []);
      });
    });
  }

  subscribe(deviceIds) {
    for (const id of deviceIds) this.knownPeerIds.add(id);
    this.socket.emit('subscribe', { deviceIds });
  }

  unsubscribe(deviceIds) {
    for (const id of deviceIds) this.knownPeerIds.delete(id);
    this.socket.emit('unsubscribe', { deviceIds });
  }

  broadcastUnpair(deviceId) {
    this.knownPeerIds.delete(deviceId);
    this.socket.emit('unpair', { deviceId });
  }

  // -------------------------------------------------------------------------
  // Pairing
  // -------------------------------------------------------------------------

  pairAdvertise() {
    return new Promise((resolve, reject) => {
      this.socket.emit('pair-advertise', {}, (res) => {
        if (!res?.ok) return reject(new Error(res?.error || 'advertise-failed'));
        resolve(res.code);
      });
    });
  }

  pairCancel() { this.socket.emit('pair-cancel'); }

  pairConsume(code) {
    return new Promise((resolve, reject) => {
      this.socket.emit('pair-consume', { code: String(code || '').toUpperCase() }, (res) => {
        if (!res?.ok) return reject(new Error(res?.error || 'consume-failed'));
        resolve(res.peer);
      });
    });
  }

  // -------------------------------------------------------------------------
  // Direct session with a known online peer (caller becomes the offerer)
  // -------------------------------------------------------------------------

  openSession(targetDeviceId) {
    return new Promise((resolve, reject) => {
      this.socket.emit('session-open', { targetDeviceId }, (res) => {
        if (!res?.ok) return reject(new Error(res?.error || 'session-open-failed'));
        this.sessionId = res.sessionId;
        this.manager?.start({ initiator: true });
        resolve(res.sessionId);
      });
    });
  }

  leaveSession() {
    this.socket.emit('session-leave');
    this.sessionId = null;
  }

  _emit(name, detail = {}) {
    this.dispatchEvent(new CustomEvent(name, { detail }));
  }
}
