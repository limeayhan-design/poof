// Shared wire protocol — mirror of ios/PoofProtocol.swift.
// Any change here must be replicated on the Swift side.

export const PoofMessageType = Object.freeze({
  Clipboard: 'clipboard',
  ClipboardAck: 'clipboardAck',
  Notification: 'notification',
  NotificationReply: 'notificationReply',
  NotificationAction: 'notificationAction',
  Handoff: 'handoff',
  HandoffAck: 'handoffAck',
  FileMeta: 'fileMeta',
  FileComplete: 'fileComplete',
  FileCancel: 'fileCancel',
  FileResumeQuery: 'fileResumeQuery',
  FileResumeAck:   'fileResumeAck',
  Ping: 'ping',
  Pong: 'pong',
});

export function encodeEnvelope({ type, id, ts = Date.now() / 1000, force = false, payload = {} }) {
  return JSON.stringify({ type, id, ts, force, payload });
}

export function decodeEnvelope(raw) {
  const obj = typeof raw === 'string' ? JSON.parse(raw) : JSON.parse(new TextDecoder().decode(raw));
  if (!obj || typeof obj.type !== 'string' || typeof obj.id !== 'string') {
    throw new Error('malformed-envelope');
  }
  return {
    type: obj.type,
    id: obj.id,
    ts: obj.ts ?? Date.now() / 1000,
    force: !!obj.force,
    payload: obj.payload ?? {},
  };
}

// Binary framing — must match PoofFrame in Swift.
export const CHUNK_SIZE = 64 * 1024;
export const HEADER_SIZE = 21;

function uuidToBytes(uuid) {
  const hex = uuid.replace(/-/g, '');
  const out = new Uint8Array(16);
  for (let i = 0; i < 16; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}

function bytesToUuid(bytes) {
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function encodeFrame({ transferId, index, isLast, payload }) {
  const out = new Uint8Array(HEADER_SIZE + payload.byteLength);
  out.set(uuidToBytes(transferId), 0);
  new DataView(out.buffer).setUint32(16, index, false); // big-endian
  out[20] = isLast ? 0x01 : 0x00;
  out.set(new Uint8Array(payload), HEADER_SIZE);
  return out.buffer;
}

export function decodeFrame(buffer) {
  const view = new Uint8Array(buffer);
  if (view.byteLength < HEADER_SIZE) throw new Error('malformed-frame');
  return {
    transferId: bytesToUuid(view.subarray(0, 16)),
    index: new DataView(view.buffer, view.byteOffset, view.byteLength).getUint32(16, false),
    isLast: (view[20] & 0x01) !== 0,
    payload: view.subarray(HEADER_SIZE).slice().buffer,
  };
}

export function newId() {
  // RFC 4122 v4 via crypto if available.
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}
