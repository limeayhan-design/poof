import { PoofMessageType, newId } from './poof-protocol.js';
import { NativeBridge } from './native-bridge.js';

/**
 * Remote Files — matches iOS PoofRemoteFiles.
 *
 * Two sides:
 *  - Requester: `requestList(path)` returns a request id. The peer replies with
 *    `remoteListResponse` → we emit `list` event with { requestId, path, entries }.
 *    `requestGet(path)` asks the peer to push a file back via the normal file transfer.
 *  - Responder: on `remoteListRequest` we call the local Tauri command
 *    `remote_list_dir` and echo `remoteListResponse`. On `remoteGetRequest` we
 *    read the file via `remote_read_file` and hand it to `fileTransfer.sendBlob`.
 *
 * Scope: `~/Documents/Poof` (see lib.rs remote_root). Users can drop anything
 * in there to make it visible to a paired device.
 */
export class RemoteFiles extends EventTarget {
  constructor(manager, fileTransfer) {
    super();
    this.manager = manager;
    this.fileTransfer = fileTransfer;
    manager.addEventListener('envelope', (e) => this._handle(e.detail));
  }

  requestList(path = '') {
    const requestId = newId();
    this.manager.sendEnvelope({
      type: PoofMessageType.RemoteListRequest,
      id: requestId,
      payload: { path },
    });
    return requestId;
  }

  requestGet(path) {
    const requestId = newId();
    this.manager.sendEnvelope({
      type: PoofMessageType.RemoteGetRequest,
      id: requestId,
      payload: { path },
    });
    return requestId;
  }

  async _handle(env) {
    if (env.type === PoofMessageType.RemoteListRequest) {
      const path = String(env.payload?.path ?? '');
      const entries = await this._localList(path);
      this.manager.sendEnvelope({
        type: PoofMessageType.RemoteListResponse,
        id: env.id,
        payload: { path, entries },
      });
    } else if (env.type === PoofMessageType.RemoteListResponse) {
      this.dispatchEvent(new CustomEvent('list', {
        detail: {
          requestId: env.id,
          path: String(env.payload?.path ?? ''),
          entries: Array.isArray(env.payload?.entries) ? env.payload.entries : [],
        },
      }));
    } else if (env.type === PoofMessageType.RemoteGetRequest) {
      const path = String(env.payload?.path ?? '');
      await this._localGet(path);
    }
  }

  async _localList(path) {
    if (!NativeBridge.isAvailable) return [];
    try {
      const rows = await NativeBridge.invoke('remote_list_dir', { rel: path });
      return Array.isArray(rows) ? rows : [];
    } catch (e) {
      console.warn('[remote-files] list failed:', e);
      return [];
    }
  }

  async _localGet(path) {
    if (!NativeBridge.isAvailable || !this.fileTransfer) return;
    try {
      const [name, bytes] = await NativeBridge.invoke('remote_read_file', { rel: path });
      const blob = new Blob([new Uint8Array(bytes)], { type: 'application/octet-stream' });
      const file = new File([blob], name || path.split('/').pop() || 'file.bin');
      await this.fileTransfer.send(file);
    } catch (e) {
      console.warn('[remote-files] get failed:', e);
    }
  }
}
