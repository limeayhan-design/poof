/**
 * Native bridge.
 *
 * When the PWA runs inside the Tauri desktop shell, Tauri injects
 * `window.__TAURI_INTERNALS__` with `invoke()` and event helpers.
 * Otherwise (Safari/Chrome/etc.) all methods no-op — the app keeps
 * working through the signaling server exactly as before.
 *
 * The Tauri v2 internals give us:
 *   __TAURI_INTERNALS__.invoke(cmd, args, opts?)
 *   __TAURI_INTERNALS__.transformCallback(cb, once?) → callback id
 *
 * We build `listen(event, handler)` on top of `invoke('plugin:event|listen')`
 * so we do NOT depend on the bundled `@tauri-apps/api/event` package (there is
 * no bundler in this project — bare specifier imports would 404 the webview).
 */

// Resolve internals *lazily* — Tauri v2 sometimes injects
// `__TAURI_INTERNALS__` after the first module scripts run, so evaluating
// it once at import time can wrongly report "no bridge" forever.
function getInternals() {
  return (typeof window !== 'undefined') ? window.__TAURI_INTERNALS__ : null;
}

function invokeRaw(cmd, args) {
  const internals = getInternals();
  if (!internals?.invoke) throw new Error('Tauri bridge unavailable');
  return internals.invoke(cmd, args ?? {});
}

async function listenRaw(event, handler) {
  const internals = getInternals();
  if (!internals?.invoke) return () => {};
  const callbackId = internals.transformCallback(
    (msg) => { try { handler(msg?.payload); } catch (e) { console.warn('[native-bridge] listener threw:', e); } },
    false,
  );
  const eventId = await invokeRaw('plugin:event|listen', {
    event,
    target: { kind: 'Any' },
    handler: callbackId,
  });
  return async () => {
    try {
      await invokeRaw('plugin:event|unlisten', { event, eventId });
    } catch (e) { /* noop */ }
  };
}

export const NativeBridge = {
  get isAvailable() { return !!getInternals()?.invoke; },
  async invoke(command, args) { return invokeRaw(command, args); },
  async listen(event, handler) { return listenRaw(event, handler); },
};
