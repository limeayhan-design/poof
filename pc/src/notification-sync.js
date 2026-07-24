import { PoofMessageType, newId } from './poof-protocol.js';

/**
 * PC-side notification bridge.
 *
 * - Displays incoming iOS notifications using either Electron's `Notification`
 *   or the Web `Notification` API (auto-detected).
 * - When the user clicks a native action button (e.g. Reply), sends an
 *   `notificationReply` envelope back to the iOS device.
 * - `sendActionResponse()` is the manual force entry-point for the app UI.
 */
export class NotificationSync {
  constructor(manager) {
    this.manager = manager;
    this._nativeNotif = globalThis.Notification;
    manager.addEventListener('envelope', (e) => this._handle(e.detail));
  }

  async ensurePermission() {
    if (!this._nativeNotif) return 'unsupported';
    if (this._nativeNotif.permission === 'granted') return 'granted';
    return await this._nativeNotif.requestPermission();
  }

  /** Called by the UI when the user typed a reply. */
  sendReply(notificationId, text) {
    this.sendActionResponse(notificationId, 'reply', text);
  }

  sendActionResponse(notificationId, action, text = null) {
    this.manager.sendEnvelope({
      type: PoofMessageType.NotificationReply,
      id: notificationId,
      force: true,       // user-initiated
      payload: { action, text },
    });
  }

  onIncoming(callback) { this._onIncoming = callback; }

  // ---- inbound iOS → PC ----

  _handle(env) {
    if (env.type !== PoofMessageType.Notification) return;
    const { title, body, actions = [], sourceApp } = env.payload || {};
    const payload = { id: env.id, title, body, actions, sourceApp };
    this._onIncoming?.(payload);
    this._display(payload);
  }

  _display({ id, title, body, actions }) {
    if (!this._nativeNotif || this._nativeNotif.permission !== 'granted') return;
    // Web `Notification` API only supports actions via ServiceWorker.
    // For a first pass we open the app UI on click; the reply itself is
    // captured by the host application's compose view.
    const n = new this._nativeNotif(title || 'Poof', { body, tag: id });
    n.onclick = () => {
      window.focus?.();
      this._onIncoming?.({ id, title, body, actions, activated: true });
    };
  }
}
