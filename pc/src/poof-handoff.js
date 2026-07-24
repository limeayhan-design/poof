import { PoofMessageType, newId } from './poof-protocol.js';

/**
 * Hand-off receiver / emitter for the PC.
 * Payload is deliberately untyped JSON — the receiving app decides how to act.
 */
export class PoofHandoff {
  constructor(manager) {
    this.manager = manager;
    manager.addEventListener('envelope', (e) => this._handle(e.detail));
  }

  /** Ship the current tab/state to iOS. */
  push({ url, title = '', state = {} }) {
    this.manager.sendEnvelope({
      type: PoofMessageType.Handoff,
      id: newId(),
      force: true,
      payload: { url, title, state },
    });
  }

  onIncoming(callback) { this._onIncoming = callback; }

  _handle(env) {
    if (env.type !== PoofMessageType.Handoff) return;
    const { url, title, state } = env.payload || {};
    if (!url) return;
    this._onIncoming?.({ url, title, state });

    this.manager.sendEnvelope({
      type: PoofMessageType.HandoffAck,
      id: env.id,
      payload: {},
    });
  }
}
