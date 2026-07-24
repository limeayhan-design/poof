/**
 * Poof — PWA entry point (multi-device model).
 *
 * Flow:
 *   • On boot: register identity via `hello`; server returns which of my
 *     paired peers are already online.
 *   • The device list shows every peer in my local store, with a live
 *     online/offline dot from the server.
 *   • Tap a row → toggles selection. Sending fans out to every selected peer.
 *   • The `+`/settings buttons open the pairing modal (my code + type theirs).
 */

import { WebRTCManager }    from './src/webrtc-manager.js';
import { SignalingClient }  from './src/signaling-client.js';
import { ClipboardSync }    from './src/clipboard-sync.js';
import { NotificationSync } from './src/notification-sync.js';
import { PoofHandoff }     from './src/poof-handoff.js';
import { FileTransfer }     from './src/file-transfer.js';
import { DeviceIdentity }   from './src/device-identity.js';
import { PairedPeerStore }  from './src/paired-peer-store.js';
import { LanDiscovery }     from './src/lan-discovery.js';
import { NativeFeatures }   from './src/native-features.js';
import { RemoteFiles }      from './src/remote-files.js';
import { ScreenMirror }     from './src/screen-mirror.js';
import { currentTier, tierLimits, tierMeta, setTier, PoofTier, TierMeta } from './src/tier.js';
import { renderTierSection } from './src/tier-sections.js';
import { TransferTracker, formatBytes, formatSpeed, formatEta }
                            from './src/transfer-tracker.js';

// ------------------------------------------------------------------
// Bootstrap
// ------------------------------------------------------------------

const SIGNALING_URL = window.ATLAS_SIGNALING_URL || location.origin;

const manager     = new WebRTCManager();
const signaling   = new SignalingClient({ url: SIGNALING_URL });
signaling.attach(manager);

const clipboard    = new ClipboardSync(manager);
const notifications= new NotificationSync(manager);
const handoff      = new PoofHandoff(manager);
const transfer     = new FileTransfer(manager);
const tracker      = new TransferTracker(transfer);
const store        = new PairedPeerStore();
const lan          = new LanDiscovery();
const remoteFiles  = new RemoteFiles(manager, transfer);
const screenMirror = new ScreenMirror(manager);

// Read receipts state — mirrors iOS PoofSentFile.
const sentFiles = new Map();  // transferId -> { name, size, receipt, deliveredAt, seenAt }
transfer.addEventListener('outgoing-meta', (e) => {
  const { id, name, size } = e.detail;
  sentFiles.set(id, { name, size, receipt: 'sent', deliveredAt: null, seenAt: null });
  renderSentBadges();
});
transfer.addEventListener('delivered', (e) => {
  const s = sentFiles.get(e.detail.id);
  if (s && s.receipt === 'sent') { s.receipt = 'delivered'; s.deliveredAt = Date.now(); renderSentBadges(); }
});
transfer.addEventListener('seen', (e) => {
  const s = sentFiles.get(e.detail.id);
  if (s) { s.receipt = 'seen'; s.seenAt = Date.now(); renderSentBadges(); }
});

function renderSentBadges() {
  const el = document.querySelector('#sent-badges');
  if (!el) return;
  const rows = [...sentFiles.entries()].slice(-6).reverse();
  el.innerHTML = rows.map(([id, s]) => {
    const icon = s.receipt === 'seen' ? '👁' : s.receipt === 'delivered' ? '✓✓' : '✓';
    const color = s.receipt === 'seen' ? '#4ade80' : s.receipt === 'delivered' ? '#60a5fa' : '#94a3b8';
    return `<div class="sent-row" style="color:${color}">${icon} <span>${escapeHtml(s.name)}</span></div>`;
  }).join('');
}

// Auto-mark seen when the completed file is opened via openPath.
const _origOpenPath = NativeFeatures.openPath.bind(NativeFeatures);
NativeFeatures.openPath = async function (path) {
  const ok = await _origOpenPath(path);
  return ok;
};

// -------- Remote Files browser -------------------------------------
const rfModal = document.querySelector('#modal-remote-files');
const rfList = document.querySelector('#rf-list');
const rfEmpty = document.querySelector('#rf-empty');
const rfBreadcrumb = document.querySelector('#rf-breadcrumb');
const rfUpBtn = document.querySelector('#rf-up');
let rfCurrentPath = '';
let rfPendingReq = null;

function openRemoteFiles() {
  if (!manager.isReady) { toast('Not connected'); return; }
  rfCurrentPath = '';
  rfBrowse('');
  rfModal.showModal();
}

function rfRender(entries, path) {
  rfCurrentPath = path;
  rfBreadcrumb.textContent = '/' + (path || '');
  rfList.innerHTML = '';
  if (!entries.length) { rfEmpty.hidden = false; return; }
  rfEmpty.hidden = true;
  entries.forEach((e) => {
    const li = document.createElement('li');
    li.className = 'rf-row';
    li.innerHTML = `
      <span class="rf-icon">${e.isDir ? '📁' : '📄'}</span>
      <span class="rf-name">${escapeHtml(e.name)}</span>
      <span class="rf-size">${e.isDir ? '' : formatBytes(e.size)}</span>
    `;
    li.onclick = () => {
      const next = path ? `${path}/${e.name}` : e.name;
      if (e.isDir) rfBrowse(next);
      else { remoteFiles.requestGet(next); toast(`Pulling ${e.name}…`); }
    };
    rfList.appendChild(li);
  });
}

function rfBrowse(path) {
  rfPendingReq = remoteFiles.requestList(path);
  rfList.innerHTML = '<li class="rf-loading">Loading…</li>';
  rfEmpty.hidden = true;
  rfBreadcrumb.textContent = '/' + (path || '');
}

remoteFiles.addEventListener('list', (e) => {
  const { requestId, path, entries } = e.detail;
  if (requestId !== rfPendingReq && rfPendingReq !== null) return;
  rfRender(entries, path);
});

rfUpBtn?.addEventListener('click', () => {
  if (!rfCurrentPath) return;
  const parts = rfCurrentPath.split('/'); parts.pop();
  rfBrowse(parts.join('/'));
});


// -------- Screen Mirror --------------------------------------------
const smModal = document.querySelector('#modal-screen-mirror');
const smFrame = document.querySelector('#sm-frame');
const smEmpty = document.querySelector('#sm-empty');
const smStart = document.querySelector('#sm-start');
const smStop = document.querySelector('#sm-stop');
const smClose = document.querySelector('#sm-close');
function openScreenMirror() {
  if (!manager.isReady) { toast('Not connected'); return; }
  smModal.showModal();
}

screenMirror.addEventListener('receiving-start', () => {
  smEmpty.hidden = true;
  smFrame.hidden = false;
  if (!smModal.open) smModal.showModal();
  renderTierUI();
});
screenMirror.addEventListener('receiving-stop', () => {
  smFrame.hidden = true;
  smEmpty.hidden = false;
  renderTierUI();
});
screenMirror.addEventListener('frame', (e) => {
  smFrame.src = e.detail.dataUrl;
});
screenMirror.addEventListener('broadcasting-start', () => {
  smStart.hidden = true;
  smStop.hidden = false;
  renderTierUI();
});
screenMirror.addEventListener('broadcasting-stop', () => {
  smStart.hidden = false;
  smStop.hidden = true;
  renderTierUI();
});
smStart?.addEventListener('click', async () => {
  try { await screenMirror.startBroadcast(); }
  catch (err) { toast(`Broadcast failed: ${err.message || err}`); }
});
smStop?.addEventListener('click', () => screenMirror.stopBroadcast());
smClose?.addEventListener('click', () => {
  if (screenMirror.isBroadcasting) screenMirror.stopBroadcast();
  smModal.close();
});

// ------------------------------------------------------------------
// DOM refs
// ------------------------------------------------------------------

const $ = (sel) => document.querySelector(sel);
const dropZone   = $('#drop-zone');
const fileInput  = $('#file-input');
const devicesEl  = $('#devices');
const statusEl   = $('#status-text');
const wifiEl     = document.querySelector('.wifi');
const toastRoot  = $('#toast-region');

const pairModal      = $('#modal-pair');
const pairCodeEl     = $('#pair-code');
const pairQrEl       = $('#pair-qr');
const pairExpEl      = $('#pair-expiry');
const pairFallbackEl = $('#pair-fallback');
const pairFallbackUrlEl = $('#pair-fallback-url');
const btnNewCode     = $('#btn-new-code');
const joinForm       = $('#join-form');
const joinInput      = $('#join-code');

// Cache the server's LAN URL so we don't refetch on every QR render.
let cachedLocalUrl = null;
async function getLocalUrl() {
  if (cachedLocalUrl) return cachedLocalUrl;
  try {
    const r = await fetch('/local-url', { cache: 'no-cache' });
    const { url } = await r.json();
    cachedLocalUrl = url || null;
  } catch { cachedLocalUrl = null; }
  return cachedLocalUrl;
}

// ------------------------------------------------------------------
// Auto-pair from URL hash: when Safari opens `…/#pair=ABC123` after a
// QR scan, consume the code once signaling is ready and the device has
// completed onboarding. Both conditions can arrive in either order.
// ------------------------------------------------------------------

let pendingPairCode = (() => {
  const m = /(?:^|[#&])pair=([A-Z0-9]{4,10})/i.exec(location.hash || '');
  if (!m) return null;
  history.replaceState(null, '', location.pathname + location.search);
  return m[1].toUpperCase();
})();
let signalingReady = false;
let onboardingReady = false;
async function tryAutoPair() {
  if (!pendingPairCode || !signalingReady || !onboardingReady) return;
  const code = pendingPairCode;
  pendingPairCode = null;
  try {
    const peer = await signaling.pairConsume(code);
    store.upsert(peer);
    signaling.subscribe([peer.deviceId]);
    state.online.add(peer.deviceId);
    toast(`Paired with ${peer.name}`);
    renderDevices();
  } catch (err) {
    toast(`Auto-pair failed: ${err.message}`);
  }
}

const onboardingModal = $('#modal-onboarding');
const onboardingForm  = $('#onboarding-form');
const onboardingInput = $('#onboarding-name');
const renameForm      = $('#rename-form');
const renameInput     = $('#rename-input');

const photoInput  = $('#photo-input');
const clipCardEl    = $('#clipboard-card');
const clipIconEl    = $('#clipboard-icon');
const clipLabelEl   = $('#clipboard-label');
const clipPreviewEl = $('#clipboard-preview');

const transferPillEl    = $('#transfer-pill');
const transferIconEl    = $('#transfer-pill-icon');
const transferNameEl    = $('#transfer-pill-name');
const transferStatsEl   = $('#transfer-pill-stats');
const transferFillEl    = $('#transfer-pill-fill');
const transferCancelEl  = $('#transfer-pill-cancel');

const historyModal = $('#modal-history');
const historyClip  = $('#history-clipboard');
const historyXfer  = $('#history-transfers');

const settingsBtn  = $('#btn-settings');
function setHistoryUnread(hasUnread) {
  settingsBtn?.classList.toggle('has-unread', hasUnread);
}

// ------------------------------------------------------------------
// State
// ------------------------------------------------------------------

const state = {
  online: new Set(),            // deviceIds currently online (per server)
  selected: new Set(),          // deviceIds picked by the user
  connectedPeerId: null,        // deviceId we currently have a WebRTC link with
  transfers: new Map(),         // id -> { name, bytes, total, direction, done }
  pendingSend: { files: [], targets: [] },
};

// ------------------------------------------------------------------
// Rendering
// ------------------------------------------------------------------

function renderDevices() {
  const peers = store.peers;
  devicesEl.innerHTML = '';

  if (peers.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'devices-empty';
    empty.innerHTML = `
      <p>No paired device yet.</p>
      <button class="poof-btn" id="btn-add-first">Add a device</button>
    `;
    devicesEl.appendChild(empty);
    empty.querySelector('#btn-add-first').addEventListener('click', openPairing);
    return;
  }

  const frag = document.createDocumentFragment();
  for (const p of peers) {
    const isOnline = state.online.has(p.id);
    const isSelected = state.selected.has(p.id);
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.dataset.peerId = p.id;
    btn.className = `device-row glass ${isOnline ? 'on' : 'off'}${isSelected ? ' selected' : ''}`;
    btn.innerHTML = `
      <span class="dot"></span>
      <span class="name">${escapeHtml(p.name)}</span>
      <span class="platform">${escapeHtml(p.platform)}</span>
      <span class="chip" hidden>Selected</span>
      <button class="unpair" title="Unpair" aria-label="Unpair ${escapeHtml(p.name)}">✕</button>
    `;
    const chipEl = btn.querySelector('.chip');
    if (isSelected) chipEl.hidden = false;
    btn.querySelector('.unpair').addEventListener('click', (e) => {
      e.stopPropagation();
      if (!confirm(`Remove ${p.name} from your paired devices?`)) return;
      signaling.broadcastUnpair(p.id);
      store.remove(p.id);
      state.selected.delete(p.id);
      state.online.delete(p.id);
    });
    btn.addEventListener('click', () => {
      const willSelect = !state.selected.has(p.id);
      if (willSelect) state.selected.add(p.id);
      else state.selected.delete(p.id);
      btn.classList.toggle('selected', willSelect);
      chipEl.hidden = !willSelect;
    });
    frag.appendChild(btn);
  }
  devicesEl.appendChild(frag);
  renderPeersGrid();
}

function renderHistory() {
  historyClip.innerHTML = clipboard.history
    .map((it) => `<li>${escapeHtml(it.text.slice(0, 200))}
      <small style="opacity:.5"> — ${it.origin}</small></li>`)
    .join('') || '<li style="opacity:.5">Empty</li>';

  historyXfer.innerHTML = [...state.transfers.values()]
    .map((t) => {
      const pct = t.total ? Math.round((t.bytes / t.total) * 100) : 0;
      return `<li>${escapeHtml(t.name)} — ${t.direction} — ${pct}%${t.done ? ' ✓' : ''}</li>`;
    })
    .join('') || '<li style="opacity:.5">No transfers yet</li>';
}

// ------------------------------------------------------------------
// Main-area panels: peers grid, live clipboard, activity feed
// ------------------------------------------------------------------

const peersGridEl = document.getElementById('peers-grid');
const clipLiveStatus  = document.getElementById('clip-live-status');
const clipLiveLocalEl = document.getElementById('clip-live-local');
const clipLiveLocalTime = document.getElementById('clip-live-local-time');
const clipLiveRemoteEl = document.getElementById('clip-live-remote');
const clipLiveRemoteTime = document.getElementById('clip-live-remote-time');
const activityListEl = document.getElementById('activity-list');
const activityClearBtn = document.getElementById('activity-clear');

function iconForPlatform(p = '') {
  const k = p.toLowerCase();
  if (k.includes('ios') || k.includes('iphone')) return '📱';
  if (k.includes('mac') || k.includes('darwin')) return '💻';
  if (k.includes('win')) return '🖥️';
  if (k.includes('linux')) return '🐧';
  if (k.includes('android')) return '🤖';
  return '🔗';
}

function renderPeersGrid() {
  if (!peersGridEl) return;
  const peers = store.peers;
  if (peers.length === 0) {
    peersGridEl.innerHTML = `
      <button class="peer-empty" id="peer-empty" type="button">
        <span class="peer-empty-icon">+</span>
        <span>Pair your first device</span>
      </button>
    `;
    peersGridEl.querySelector('#peer-empty')?.addEventListener('click', openPairing);
    return;
  }
  peersGridEl.innerHTML = peers.map((p) => {
    const on = state.online.has(p.id);
    const sel = state.selected.has(p.id);
    return `
      <button class="peer-tile ${on ? 'on' : 'off'}${sel ? ' selected' : ''}" data-peer-id="${p.id}">
        <div class="peer-avatar">${iconForPlatform(p.platform)}</div>
        <div class="peer-info">
          <div class="peer-name">${escapeHtml(p.name)}</div>
          <div class="peer-meta"><span class="peer-dot"></span>${on ? 'Online' : 'Offline'} · ${escapeHtml(p.platform)}</div>
        </div>
      </button>
    `;
  }).join('');
  peersGridEl.querySelectorAll('.peer-tile').forEach((tile) => {
    tile.addEventListener('click', () => {
      const id = tile.dataset.peerId;
      const willSelect = !state.selected.has(id);
      if (willSelect) state.selected.add(id);
      else state.selected.delete(id);
      renderDevices(); // triggers peers-grid via chain below
    });
  });
}

function relTime(ts) {
  const diff = Math.max(0, Date.now() - ts);
  if (diff < 30_000) return 'just now';
  if (diff < 60_000) return `${Math.floor(diff / 1000)}s ago`;
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h ago`;
  return `${Math.floor(diff / 86_400_000)}d ago`;
}

function renderClipLive() {
  const latestLocal  = clipboard.history.find((it) => it.origin === 'local');
  const latestRemote = clipboard.history.find((it) => it.origin === 'remote');
  const on = clipboard.autoPushEnabled;
  clipLiveStatus.textContent = on ? 'On' : 'Off';
  clipLiveStatus.classList.toggle('on', on);
  clipLiveLocalEl.textContent  = latestLocal?.text?.slice(0, 140) || '—';
  clipLiveLocalTime.textContent = latestLocal ? relTime(latestLocal.date) : '';
  clipLiveRemoteEl.textContent = latestRemote?.text?.slice(0, 140) || '—';
  clipLiveRemoteTime.textContent = latestRemote ? relTime(latestRemote.date) : '';
}

function iconForFile(name = '') {
  const ext = (name.split('.').pop() || '').toLowerCase();
  if (['png','jpg','jpeg','gif','webp','heic'].includes(ext)) return '🖼️';
  if (['mp4','mov','webm','m4v'].includes(ext)) return '🎬';
  if (ext === 'pdf') return '📕';
  if (['zip','tar','gz','7z','rar'].includes(ext)) return '🗜️';
  if (['txt','md','rtf'].includes(ext)) return '📝';
  if (['mp3','wav','m4a','aac','flac'].includes(ext)) return '🎵';
  return '📄';
}

function renderActivity() {
  const items = [...state.transfers.values()]
    .sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))
    .slice(0, 8);
  if (activityClearBtn) activityClearBtn.hidden = items.length === 0;
  if (items.length === 0) {
    activityListEl.innerHTML = `<li class="activity-empty">Send or receive a file and it'll show up here.</li>`;
    return;
  }
  activityListEl.innerHTML = items.map((t) => {
    const pct = t.total ? Math.round((t.bytes / t.total) * 100) : 0;
    const isSent = t.direction === 'sent' || t.direction === 'out';
    const done = t.done ? 'done' : 'in-flight';
    const size = t.total ? formatBytes(t.total) : '';
    return `
      <li class="activity-item ${done}">
        <div class="activity-icon">${iconForFile(t.name)}</div>
        <div class="activity-body">
          <div class="activity-row">
            <span class="activity-name">${escapeHtml(t.name || 'Unnamed')}</span>
            <span class="activity-time">${relTime(t.updatedAt || Date.now())}</span>
          </div>
          <div class="activity-sub">
            <span class="activity-dir">${isSent ? '↑ Sent' : '↓ Received'}</span>
            ${size ? `<span class="activity-sep">·</span><span>${size}</span>` : ''}
            ${!t.done ? `<span class="activity-sep">·</span><span class="activity-pct">${pct}%</span>` : ''}
          </div>
        </div>
      </li>
    `;
  }).join('');
}

activityClearBtn?.addEventListener('click', () => {
  state.transfers.clear();
  renderActivity();
});

// Refresh times every 30s so "just now" ticks
setInterval(() => {
  renderClipLive();
  renderActivity();
}, 30_000);

function setStatus(text, online = false) {
  statusEl.textContent = text;
  if (wifiEl) wifiEl.setAttribute('stroke', online ? '#34C759' : '#FF7300');
  const badge = document.getElementById('status');
  if (badge) badge.classList.toggle('on', !!online);
}

function toast(msg, ms = 3200) {
  const el = document.createElement('div');
  el.className = 'toast';
  el.textContent = msg;
  toastRoot.appendChild(el);
  setTimeout(() => el.remove(), ms);
}

function escapeHtml(s = '') {
  return s.replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

// ------------------------------------------------------------------
// Signaling lifecycle
// ------------------------------------------------------------------

signaling.addEventListener('connected', async () => {
  setStatus('Online', true);
  try {
    const online = await signaling.hello({
      deviceId:      DeviceIdentity.deviceId,
      name:          DeviceIdentity.name,
      platform:      DeviceIdentity.platform,
      knownPeerIds:  store.ids,
    });
    state.online = new Set(online);
    renderDevices();
    signalingReady = true;
    tryAutoPair();
  } catch (e) {
    toast(`Hello failed: ${e.message}`);
  }
});

// ------------------------------------------------------------------
// LAN discovery (Tauri only — no-op in a plain browser)
// ------------------------------------------------------------------

lan.addEventListener('peer-found', ({ detail }) => {
  // A LAN peer is auto-known: no code exchange, no server round-trip.
  store.upsert({
    deviceId: detail.deviceId,
    name:     detail.name,
    platform: detail.platform,
  });
  state.online.add(detail.deviceId);
  // Piggyback on the signaling server for the actual WebRTC handshake, but the
  // discovery step is free thanks to mDNS.
  signaling.subscribe?.([detail.deviceId]);
  renderDevices();
});

lan.addEventListener('peer-lost', () => {
  // Presence stays authoritative through signaling — we only rebuild the row.
  renderDevices();
});

if (lan.isAvailable) {
  lan.start({
    deviceId: DeviceIdentity.deviceId,
    name:     DeviceIdentity.name,
  }).catch((e) => console.warn('[lan] start failed:', e));
}

// ------------------------------------------------------------------
// Native "killer UX" — tray, global shortcuts, screenshot watcher
// (all no-ops on plain browsers)
// ------------------------------------------------------------------

if (NativeFeatures.isAvailable) {
  NativeFeatures.startScreenshotWatcher();

  NativeFeatures.onScreenshotCaptured(async ({ path, name }) => {
    const blob = await NativeFeatures.readFileAsBlob(path, 'image/png');
    if (!blob) return;
    const file = new File([blob], name || 'screenshot.png', { type: 'image/png' });
    const targets = [...state.selected].filter((id) => state.online.has(id));
    if (!targets.length) {
      showRetryToast(`Screenshot ready — pick a device first`, () => {});
      return;
    }
    toast(`Sending screenshot → ${targets.map(nameFor).join(', ')}`);
    await sendFilesToSelected([file]);
  });

  NativeFeatures.onPushClipboardShortcut(async () => {
    await clipboard.pushCurrent();
    toast('Clipboard pushed');
  });

  NativeFeatures.onTraySendFile(async () => {
    const path = await NativeFeatures.pickFile();
    if (!path) return;
    const name = path.split(/[/\\]/).pop() || 'file';
    const ext = (name.split('.').pop() || '').toLowerCase();
    const mime = ext === 'png' ? 'image/png'
               : ext === 'jpg' || ext === 'jpeg' ? 'image/jpeg'
               : ext === 'pdf' ? 'application/pdf'
               : 'application/octet-stream';
    const blob = await NativeFeatures.readFileAsBlob(path, mime);
    if (!blob) return;
    const file = new File([blob], name, { type: mime });
    await sendFilesToSelected([file]);
  });

  // Auto-update check on launch. 1.5s delay so the app has time to paint.
  // Detect → toast "downloading" → install → toast "restart".
  setTimeout(() => {
    NativeFeatures.checkForUpdates((version) => {
      toast(`Poof ${version} available — downloading…`);
    }).then((version) => {
      if (!version) return;
      showRetryToast(`Poof ${version} ready — restart to apply`, () => {
        NativeFeatures.restart();
      }, 'Restart');
    });
  }, 1500);
}

signaling.addEventListener('disconnected', () => {
  setStatus('Offline', false);
  state.online.clear();
  renderDevices();
});

signaling.addEventListener('peer-online',  ({ detail }) => {
  state.online.add(detail.deviceId);
  store.touch(detail.deviceId);
  renderDevices();
});
signaling.addEventListener('peer-offline', ({ detail }) => {
  state.online.delete(detail.deviceId);
  renderDevices();
});
signaling.addEventListener('peer-unpaired', ({ detail }) => {
  const id = detail.deviceId;
  if (!id) return;
  const peer = store.peers.find((p) => p.id === id);
  store.remove(id);
  state.online.delete(id);
  state.selected.delete(id);
  if (state.connectedPeerId === id) state.connectedPeerId = null;
  toast(`${peer?.name || 'A paired device'} removed you`);
  renderDevices();
});

signaling.addEventListener('pair-succeeded', ({ detail }) => {
  const { peer } = detail;
  const limits = tierLimits();
  if (!store.has(peer.deviceId) && store.peers.length >= limits.maxDevices) {
    toast(`Free tier limited to ${limits.maxDevices} devices — upgrade for unlimited.`);
    return;
  }
  store.upsert(peer);
  signaling.subscribe([peer.deviceId]);
  state.online.add(peer.deviceId);
  pairCodeEl.textContent = '— — — — — —';
  toast(`Paired with ${peer.name}`);
  renderDevices();
});
signaling.addEventListener('pair-expired', () => {
  pairCodeEl.textContent = '— — — — — —';
  pairQrEl.innerHTML = '';
  pairExpEl.textContent = 'Code expired — generate a new one';
  pairExpEl.classList.add('expired');
  clearInterval(expiryTimer);
});

signaling.addEventListener('session-opened', ({ detail }) => {
  if (detail.from) state.connectedPeerId = detail.from.deviceId;
});
signaling.addEventListener('session-closed', () => {
  state.connectedPeerId = null;
});
signaling.addEventListener('peer-left',   () => {
  state.connectedPeerId = null;
});

manager.addEventListener('state', ({ detail }) => {
  const { state: s } = detail;
  if (s === 'closed') clipboard.stop?.();
});
manager.addEventListener('ready', () => {
  clipboard.start();
  notifications.ensurePermission?.();
  if (typeof renderTierUI === 'function') renderTierUI();
});

// ------------------------------------------------------------------
// Store change → re-render
// ------------------------------------------------------------------

store.addEventListener('change', () => { renderDevices(); renderPeersGrid(); });

// ------------------------------------------------------------------
// Drag & drop / file picker
// ------------------------------------------------------------------

let dragDepth = 0;
window.addEventListener('dragenter', (e) => {
  e.preventDefault();
  if (!hasFiles(e.dataTransfer)) return;
  dragDepth++;
  document.body.classList.add('is-dropping');
});
window.addEventListener('dragover', (e) => { if (hasFiles(e.dataTransfer)) e.preventDefault(); });
window.addEventListener('dragleave', () => {
  if (--dragDepth <= 0) { dragDepth = 0; document.body.classList.remove('is-dropping'); }
});
window.addEventListener('drop', async (e) => {
  e.preventDefault();
  dragDepth = 0;
  document.body.classList.remove('is-dropping');
  const files = [...(e.dataTransfer?.files || [])];
  await sendFilesToSelected(files);
});

['dragenter', 'dragover'].forEach((ev) => {
  dropZone.addEventListener(ev, (e) => { e.preventDefault(); dropZone.classList.add('is-hover'); });
});
['dragleave', 'drop'].forEach((ev) => {
  dropZone.addEventListener(ev, () => dropZone.classList.remove('is-hover'));
});

dropZone.addEventListener('click', () => fileInput.click());
dropZone.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); fileInput.click(); }
});
fileInput.addEventListener('change', async () => {
  await sendFilesToSelected([...fileInput.files]);
  fileInput.value = '';
});

async function sendFilesToSelected(files) {
  if (!files.length) return;
  const targets = [...state.selected].filter((id) => state.online.has(id));
  if (!targets.length) { toast('No online device selected'); return; }
  state.pendingSend.files.push(...files);
  state.pendingSend.targets = targets;
  drainPendingSend();
}

async function drainPendingSend() {
  const { files, targets } = state.pendingSend;
  if (!files.length || !targets.length) return;

  for (const targetId of targets) {
    for (const f of files) {
      try {
        const id = await sendWithRetry(f, targetId, 3);
        state.transfers.set(id, { name: f.name, bytes: 0, total: f.size, direction: 'out', done: false, updatedAt: Date.now() });
        toast(`Sending ${f.name} → ${nameFor(targetId)}`);
        renderActivity();
      } catch (e) {
        showRetryToast(`${f.name} → ${nameFor(targetId)} failed: ${e.message}`, async () => {
          state.pendingSend.files = [f];
          state.pendingSend.targets = [targetId];
          drainPendingSend();
        });
      }
    }
  }
  state.pendingSend.files = [];
}

async function sendWithRetry(file, targetId, maxAttempts) {
  const limits = tierLimits();
  if (file.size > limits.maxTransferBytes) {
    toast(`${file.name} is ${formatBytes(file.size)} — Free tier caps at 2 GB. Upgrade to Premium.`);
    throw new Error('tier-limit-exceeded');
  }
  let lastErr;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await ensureConnected(targetId);
      return await transfer.send(file);
    } catch (err) {
      lastErr = err;
      if (attempt < maxAttempts) {
        const wait = 500 * Math.pow(2, attempt - 1);
        toast(`Retry ${attempt}/${maxAttempts - 1} for ${file.name} in ${wait}ms…`);
        await new Promise((r) => setTimeout(r, wait));
      }
    }
  }
  throw lastErr || new Error('send-failed');
}

function showRetryToast(msg, onRetry, buttonLabel = 'Retry') {
  const el = document.createElement('div');
  el.className = 'toast toast-error';
  el.innerHTML = `<span>${escapeHtml(msg)}</span><button class="toast-btn">${escapeHtml(buttonLabel)}</button>`;
  el.querySelector('.toast-btn').addEventListener('click', () => {
    el.remove();
    onRetry();
  });
  toastRoot.appendChild(el);
  setTimeout(() => el.remove(), 8000);
}

async function ensureConnected(targetDeviceId) {
  if (state.connectedPeerId === targetDeviceId && manager.isReady) return;
  if (manager.state !== 'idle' && manager.state !== 'closed') { manager.close?.(); }
  state.connectedPeerId = targetDeviceId;
  try { await signaling.openSession(targetDeviceId); }
  catch (e) {
    state.connectedPeerId = null;
    toast(`Cannot reach peer: ${e.message}`);
    throw e;
  }
  const start = Date.now();
  while (!manager.isReady && Date.now() - start < 10000) {
    if (manager.state === 'closed') {
      state.connectedPeerId = null;
      throw new Error('channel-closed-during-connect');
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  if (!manager.isReady) {
    state.connectedPeerId = null;
    throw new Error('data-channel-timeout');
  }
}

function nameFor(id) {
  return store.peers.find((p) => p.id === id)?.name || id.slice(0, 6);
}

function hasFiles(dt) {
  return dt && [...(dt.types || [])].includes('Files');
}

// ------------------------------------------------------------------
// Transfer callbacks
// ------------------------------------------------------------------

transfer.addEventListener('progress', ({ detail }) => {
  const t = state.transfers.get(detail.id) ?? { name: '…', direction: detail.direction, done: false };
  t.bytes = detail.bytes; t.total = detail.total; t.updatedAt = Date.now();
  state.transfers.set(detail.id, t);
  renderActivity();
});
transfer.addEventListener('incoming-meta', ({ detail }) => {
  state.transfers.set(detail.id, { name: detail.name, bytes: 0, total: detail.size, direction: 'in', done: false, updatedAt: Date.now() });
  toast(`Receiving ${detail.name}`);
  setHistoryUnread(true);
  renderActivity();
});
transfer.addEventListener('completed', ({ detail }) => {
  const t = state.transfers.get(detail.id); if (t) { t.done = true; t.bytes = t.total; t.updatedAt = Date.now(); }
  renderActivity();
  // Inside Tauri: skip the in-webview preview (it decodes the whole blob and
  // freezes the event loop long enough to kill the socket). Write to disk and
  // let macOS open it with the default app.
  if (NativeFeatures.isAvailable) {
    NativeFeatures.saveBlob(detail.blob, detail.meta.name).then((path) => {
      if (path) {
        toast(`Received ${detail.meta.name}`);
        NativeFeatures.openPath(path);
      } else {
        toast(`Save failed for ${detail.meta.name}`);
      }
    });
    return;
  }
  if (isPreviewable(detail.meta, detail.blob)) {
    showMediaPreview(detail.meta, detail.blob);
  } else {
    offerDownload(detail.meta, detail.blob);
  }
  toast(`Received ${detail.meta.name}`);
});
transfer.addEventListener('cancelled', ({ detail }) => {
  const t = state.transfers.get(detail.id); if (t) { t.done = true; t.updatedAt = Date.now(); }
  toast(`Transfer cancelled: ${detail.reason}`);
  renderActivity();
});

function offerDownload(meta, blob) {
  // Inside Tauri, WKWebView silently drops <a download="…">. Write the file
  // ourselves through the fs plugin instead.
  if (NativeFeatures.isAvailable) {
    NativeFeatures.saveBlob(blob, meta.name).then((path) => {
      if (path) toast(`Saved to Downloads: ${meta.name}`);
      else      toast(`Save failed for ${meta.name}`);
    });
    return;
  }
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = meta.name;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
}

function previewKind(meta, blob) {
  const mime = (meta?.mime || blob?.type || '').toLowerCase();
  const name = (meta?.name || '').toLowerCase();
  if (mime.startsWith('image/') || /\.(png|jpe?g|gif|webp|heic|heif|bmp|avif)$/.test(name)) return 'image';
  if (mime.startsWith('video/') || /\.(mp4|mov|m4v|webm|ogv)$/.test(name)) return 'video';
  if (mime === 'application/pdf' || /\.pdf$/.test(name)) return 'pdf';
  return null;
}
function isPreviewable(meta, blob) { return previewKind(meta, blob) !== null; }

const previewModal = document.getElementById('modal-preview');
const previewImg   = document.getElementById('preview-img');
const previewVideo = document.getElementById('preview-video');
const previewEmbed = document.getElementById('preview-embed');
const previewName  = document.getElementById('preview-name');
const previewSize  = document.getElementById('preview-size');
const previewSave  = document.getElementById('preview-save');
const previewClose = document.getElementById('preview-close');
let previewUrl = null;
let previewMeta = null;
let previewBlob = null;

function showMediaPreview(meta, blob) {
  if (previewUrl) { URL.revokeObjectURL(previewUrl); previewUrl = null; }
  previewMeta = meta;
  previewBlob = blob;
  previewUrl  = URL.createObjectURL(blob);

  previewImg.hidden = true;   previewImg.removeAttribute('src');
  previewVideo.hidden = true; previewVideo.removeAttribute('src'); previewVideo.pause?.();
  previewEmbed.hidden = true; previewEmbed.removeAttribute('src');

  const kind = previewKind(meta, blob);
  if (kind === 'video') {
    previewVideo.src = previewUrl;
    previewVideo.hidden = false;
  } else if (kind === 'pdf') {
    previewEmbed.setAttribute('type', 'application/pdf');
    previewEmbed.src = previewUrl;
    previewEmbed.hidden = false;
  } else {
    previewImg.src = previewUrl;
    previewImg.alt = meta.name || 'Image';
    previewImg.hidden = false;
  }

  previewName.textContent = meta.name || 'File';
  previewSize.textContent = formatBytes(meta.size ?? blob.size);
  if (typeof previewModal.showModal === 'function') previewModal.showModal();
  else previewModal.setAttribute('open', '');
}

function closePreview() {
  if (previewModal.open) previewModal.close();
  previewImg.removeAttribute('src');   previewImg.hidden = true;
  previewVideo.pause?.();              previewVideo.removeAttribute('src'); previewVideo.hidden = true;
  previewEmbed.removeAttribute('src'); previewEmbed.hidden = true;
  if (previewUrl) { URL.revokeObjectURL(previewUrl); previewUrl = null; }
  previewMeta = null; previewBlob = null;
}

previewClose?.addEventListener('click', closePreview);
previewModal?.addEventListener('cancel', (e) => { e.preventDefault(); closePreview(); });
previewModal?.addEventListener('click', (e) => {
  // Click on the backdrop area (the dialog itself, not inner content) closes.
  if (e.target === previewModal) closePreview();
});
previewSave?.addEventListener('click', () => {
  if (previewMeta && previewBlob) offerDownload(previewMeta, previewBlob);
});

clipboard.onIncoming?.((item) => {
  renderClipboardCard('in', item.text);
  toast(`Clipboard: ${item.text.slice(0, 80)}`);
  setHistoryUnread(true);
  renderClipLive();
});
clipboard.onOutgoing?.((item) => {
  renderClipboardCard('out', item.text);
  renderClipLive();
});

// ─── Universal Clipboard toggle ───────────────────────────────
const UC_KEY = 'poof.universalClipboard';
const ucToggle = document.getElementById('toggle-uc');
if (ucToggle) {
  const saved = localStorage.getItem(UC_KEY) === '1';
  ucToggle.checked = saved;
  clipboard.autoPushEnabled = saved;
  ucToggle.addEventListener('change', () => {
    const on = ucToggle.checked;
    clipboard.autoPushEnabled = on;
    localStorage.setItem(UC_KEY, on ? '1' : '0');
    toast(on ? 'Universal Clipboard on' : 'Universal Clipboard off');
    renderClipLive();
  });
}
renderClipLive();
handoff.onIncoming?.(({ url }) => { toast(`Hand-off: opening ${url}`); window.open(url, '_blank', 'noopener'); });
notifications.onIncoming?.((n) => { if (!n.activated) toast(`${n.title || 'Notification'}: ${n.body || ''}`); });

// ------------------------------------------------------------------
// Global transfer pill (header)
// ------------------------------------------------------------------

const ICON_IN  = `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v13"/><path d="m6 11 6 6 6-6"/></svg>`;
const ICON_OUT = `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20V7"/><path d="m6 13 6-6 6 6"/></svg>`;
const ICON_OK  = `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5L20 7"/></svg>`;
const ICON_ERR = `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 8v5"/><circle cx="12" cy="16.5" r="1" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="9"/></svg>`;

let renderPillPending = false;
function schedulePillRender() {
  if (renderPillPending) return;
  renderPillPending = true;
  requestAnimationFrame(() => {
    renderPillPending = false;
    renderTransferPill();
  });
}

function renderTransferPill() {
  const agg = tracker.aggregate;
  const t = tracker.topmost;
  if (!t && !agg) {
    transferPillEl.classList.remove('is-visible');
    setTimeout(() => {
      if (!tracker.topmost && !tracker.aggregate) transferPillEl.hidden = true;
    }, 240);
    return;
  }
  transferPillEl.hidden = false;
  requestAnimationFrame(() => transferPillEl.classList.add('is-visible'));

  if (agg) {
    transferPillEl.classList.remove('is-done', 'is-fail');
    transferPillEl.classList.toggle('is-in',  agg.direction === 'in');
    transferPillEl.classList.toggle('is-out', agg.direction !== 'in');
    transferIconEl.innerHTML = agg.direction === 'in' ? ICON_IN : ICON_OUT;
    transferNameEl.textContent = `${agg.count} files`;
    const pct = agg.total > 0 ? Math.min(100, (agg.bytes / agg.total) * 100) : 0;
    transferFillEl.style.width = `${pct.toFixed(1)}%`;
    const parts = [`${formatBytes(agg.bytes)} / ${formatBytes(agg.total)}`];
    const speed = formatSpeed(agg.speed);
    if (speed) parts.push(speed);
    const eta = formatEta(agg.eta);
    if (eta) parts.push(eta);
    transferStatsEl.textContent = parts.join(' · ');
    return;
  }

  transferPillEl.classList.toggle('is-in',   t.direction === 'in' && t.status === 'active');
  transferPillEl.classList.toggle('is-out',  t.direction === 'out' && t.status === 'active');
  transferPillEl.classList.toggle('is-done', t.status === 'done');
  transferPillEl.classList.toggle('is-fail', t.status === 'failed');

  transferIconEl.innerHTML = t.status === 'failed' ? ICON_ERR
                          : t.status === 'done'   ? ICON_OK
                          : t.direction === 'in'  ? ICON_IN
                          :                         ICON_OUT;

  transferNameEl.textContent = t.name;

  const pct = t.total > 0 ? Math.min(100, (t.bytes / t.total) * 100) : 0;
  transferFillEl.style.width = `${pct.toFixed(1)}%`;

  if (t.status === 'failed') {
    transferStatsEl.textContent = `Failed · ${t.error || 'error'}`;
  } else if (t.status === 'done') {
    transferStatsEl.textContent = `Done · ${formatBytes(t.total)}`;
  } else {
    const parts = [`${formatBytes(t.bytes)} / ${formatBytes(t.total)}`];
    const speed = formatSpeed(t.speed);
    if (speed) parts.push(speed);
    const eta = formatEta(t.eta);
    if (eta) parts.push(eta);
    transferStatsEl.textContent = parts.join(' · ');
  }
}

tracker.addEventListener('update', schedulePillRender);
transferCancelEl.addEventListener('click', () => {
  const actives = tracker.active;
  if (actives.length > 1) {
    for (const t of actives) transfer.cancel(t.id, 'user');
    return;
  }
  const t = tracker.topmost;
  if (t && t.status === 'active') transfer.cancel(t.id, 'user');
});

// Auto-hide clipboard card timer
let clipboardCardTimer = null;

function renderClipboardCard(direction, text) {
  if (!clipCardEl) return;
  const isIn = direction === 'in';
  clipCardEl.classList.remove('is-in', 'is-out', 'is-visible');
  // Force reflow so re-adding the visible class re-triggers the animation
  void clipCardEl.offsetWidth;
  clipCardEl.classList.add(isIn ? 'is-in' : 'is-out');

  clipIconEl.innerHTML = isIn
    ? `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v13"/><path d="m6 11 6 6 6-6"/></svg>`
    : `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20V7"/><path d="m6 13 6-6 6 6"/></svg>`;
  clipLabelEl.textContent = isIn ? 'Received clipboard' : 'Sent clipboard';
  clipPreviewEl.textContent = text;

  clipCardEl.hidden = false;
  requestAnimationFrame(() => clipCardEl.classList.add('is-visible'));

  clearTimeout(clipboardCardTimer);
  clipboardCardTimer = setTimeout(() => {
    clipCardEl.classList.remove('is-visible');
    setTimeout(() => { clipCardEl.hidden = true; }, 260);
  }, 6000);
}

// ------------------------------------------------------------------
// UI buttons
// ------------------------------------------------------------------

$('#btn-settings').addEventListener('click', openPairing);
$('#btn-add-device')?.addEventListener('click', openPairing);
$('#btn-open-history').addEventListener('click', () => {
  pairModal.close();
  renderHistory();
  historyModal.showModal();
  setHistoryUnread(false);
});

// ─── Send Text ───────────────────────────────────────────────
const sendTextModal = $('#modal-send-text');
const sendTextArea  = $('#send-text-area');
$('#btn-send-text').addEventListener('click', () => {
  sendTextArea.value = '';
  sendTextModal.showModal();
  setTimeout(() => sendTextArea.focus(), 50);
});
$('#btn-send-text-confirm').addEventListener('click', async () => {
  const text = sendTextArea.value.trim();
  if (!text) { toast('Type something first'); return; }
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const file = new File([text], `note-${stamp}.txt`, { type: 'text/plain' });
  sendTextModal.close();
  await sendFilesToSelected([file]);
});

// ─── Screenshot ──────────────────────────────────────────────
$('#btn-screenshot').addEventListener('click', async () => {
  if (!navigator.mediaDevices?.getDisplayMedia) {
    toast('Screenshot not supported on this browser');
    return;
  }
  let stream;
  try {
    stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false });
  } catch {
    return; // user cancelled
  }
  try {
    const video = document.createElement('video');
    video.srcObject = stream;
    video.muted = true;
    await video.play();
    await new Promise((r) => (video.readyState >= 2 ? r() : video.onloadedmetadata = r));
    const canvas = document.createElement('canvas');
    canvas.width  = video.videoWidth;
    canvas.height = video.videoHeight;
    canvas.getContext('2d').drawImage(video, 0, 0);
    const blob = await new Promise((r) => canvas.toBlob(r, 'image/png'));
    const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const file = new File([blob], `screenshot-${stamp}.png`, { type: 'image/png' });
    await sendFilesToSelected([file]);
  } catch (e) {
    toast(`Screenshot failed: ${e.message}`);
  } finally {
    stream.getTracks().forEach((t) => t.stop());
  }
});

// ─── Send File ───────────────────────────────────────────────
$('#btn-send-file').addEventListener('click', () => {
  fileInput.value = '';
  fileInput.click();
});

// History modal legacy button (kept if user opens history from settings)
$('#btn-force-clipboard').addEventListener('click', async () => {
  await clipboard.pushCurrent();
  toast('Clipboard pushed');
  renderHistory();
});
btnNewCode.addEventListener('click', requestPairingCode);

async function openPairing() {
  renameInput.value = DeviceIdentity.name;
  pairCodeEl.textContent = '— — — — — —';
  pairQrEl.innerHTML = '<div class="pair-qr-placeholder">Generating…</div>';
  pairExpEl.textContent = '';
  pairExpEl.classList.remove('expired');
  pairModal.showModal();
  await requestPairingCode();
}

let expiryTimer = null;
function startExpiryTimer(seconds) {
  clearInterval(expiryTimer);
  let remaining = seconds;
  const tick = () => {
    if (remaining <= 0) {
      pairExpEl.textContent = 'Code expired — generate a new one';
      pairExpEl.classList.add('expired');
      clearInterval(expiryTimer);
      return;
    }
    const m = Math.floor(remaining / 60);
    const s = remaining % 60;
    pairExpEl.textContent = `Expires in ${m}:${String(s).padStart(2, '0')}`;
    pairExpEl.classList.toggle('expired', remaining < 30);
    remaining--;
  };
  tick();
  expiryTimer = setInterval(tick, 1000);
}

async function renderPairQr(code) {
  pairQrEl.innerHTML = '';
  pairFallbackEl.hidden = true;
  if (!code || typeof qrcode !== 'function') return;

  // Encode a full URL when we know the server's LAN address, so scanning
  // from the iPhone Camera app opens Safari directly and auto-pairs via
  // the `#pair=` hash. Fall back to the bare code otherwise.
  const localUrl = await getLocalUrl();
  const payload  = localUrl ? `${localUrl}/#pair=${code}` : code;

  const q = qrcode(0, 'M');
  q.addData(payload);
  q.make();
  pairQrEl.innerHTML = q.createSvgTag({ cellSize: 6, margin: 2, scalable: true });

  if (localUrl) {
    pairFallbackUrlEl.textContent = localUrl;
    pairFallbackEl.hidden = false;
  }
}

async function requestPairingCode() {
  pairExpEl.textContent = 'Generating…';
  pairQrEl.innerHTML = '<div class="pair-qr-placeholder">Generating…</div>';
  try {
    signaling.pairCancel();
    const code = await signaling.pairAdvertise();
    pairCodeEl.textContent = code;
    renderPairQr(code);
    startExpiryTimer(300);
  } catch (e) {
    pairCodeEl.textContent = 'error';
    pairQrEl.innerHTML = '';
    pairExpEl.textContent = 'Failed to generate code';
    pairExpEl.classList.add('expired');
    clearInterval(expiryTimer);
    toast(`Pair code: ${e.message}`);
  }
}

async function saveDeviceName(newName) {
  const trimmed = String(newName || '').trim();
  if (!trimmed) return;
  DeviceIdentity.name = trimmed;
  try {
    await signaling.hello({
      deviceId:     DeviceIdentity.deviceId,
      name:         DeviceIdentity.name,
      platform:     DeviceIdentity.platform,
      knownPeerIds: store.ids,
    });
  } catch { /* the change is persisted locally either way */ }
  lan.updateName(trimmed).catch(() => {});
}

function maybeShowOnboarding() {
  if (DeviceIdentity.hasCustomName) {
    onboardingReady = true;
    tryAutoPair();
    return;
  }
  onboardingInput.value = DeviceIdentity.suggestedName;
  onboardingInput.placeholder = DeviceIdentity.suggestedName;
  onboardingModal.showModal();
  requestAnimationFrame(() => onboardingInput.select?.());
}

onboardingForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const v = onboardingInput.value.trim() || DeviceIdentity.suggestedName;
  await saveDeviceName(v);
  onboardingModal.close();
  onboardingReady = true;
  tryAutoPair();
});

renameForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const v = renameInput.value.trim();
  if (!v) return;
  await saveDeviceName(v);
  toast(`Renamed to "${v}"`);
});

joinForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const code = (joinInput.value || '').trim().toUpperCase();
  if (code.length < 4) { toast('Enter a valid code'); return; }
  try {
    const peer = await signaling.pairConsume(code);
    store.upsert(peer);
    signaling.subscribe([peer.deviceId]);
    state.online.add(peer.deviceId);
    joinInput.value = '';
    pairModal.close();
    toast(`Paired with ${peer.name}`);
    renderDevices();
  } catch (err) {
    toast(`Pair failed: ${err.message}`);
  }
});

document.querySelectorAll('[data-close]').forEach((btn) => {
  btn.addEventListener('click', (e) => {
    signaling.pairCancel();
    e.target.closest('dialog').close();
  });
});

// ------------------------------------------------------------------
// Tier UI — pill, upgrade button, dynamic tier section, pricing sheet
// ------------------------------------------------------------------

const tierSectionEl = document.getElementById('tier-section');
const tierPillEl    = document.getElementById('tier-pill');
const btnUpgrade    = document.getElementById('btn-upgrade');
const pricingModal  = document.getElementById('modal-pricing');
const pricingListEl = document.getElementById('pricing-list');
const featureModal  = document.getElementById('modal-feature');

let signalingConnected = false;
signaling.addEventListener('connected',    () => { signalingConnected = true; renderTierUI(); });
signaling.addEventListener('disconnected', () => { signalingConnected = false; renderTierUI(); });

function isPeerOnline(id) { return state.online.has(id); }
function thisDeviceName() { return DeviceIdentity.name || 'This device'; }

function openFeaturePreview(preview) {
  document.getElementById('feature-icon').textContent = preview.icon || '✨';
  document.getElementById('feature-title').textContent = preview.title;
  document.getElementById('feature-tagline').textContent = preview.tagline || '';
  const statusEl = document.getElementById('feature-status');
  statusEl.textContent = preview.status === 'coming-soon' ? 'Coming soon' : preview.status === 'preview' ? 'Preview' : 'Available';
  statusEl.style.color = preview.accent || '#5B8BFF';
  statusEl.style.borderColor = (preview.accent || '#5B8BFF') + '55';
  statusEl.style.background = (preview.accent || '#5B8BFF') + '22';
  document.getElementById('feature-description').textContent = preview.description || '';
  featureModal.showModal();
}

const SPARKLES_SVG = `
  <svg viewBox="0 0 24 24" width="18" height="18" fill="#fff" aria-hidden="true">
    <path d="M11 4 L12.5 9.5 L18 11 L12.5 12.5 L11 18 L9.5 12.5 L4 11 L9.5 9.5 Z"/>
    <path d="M19 3 L19.5 4.5 L21 5 L19.5 5.5 L19 7 L18.5 5.5 L17 5 L18.5 4.5 Z"/>
    <path d="M5 17 L5.5 18.5 L7 19 L5.5 19.5 L5 21 L4.5 19.5 L3 19 L4.5 18.5 Z"/>
  </svg>`;

const CROWN_SVG = `
  <svg viewBox="0 0 24 24" width="18" height="18" fill="#fff" aria-hidden="true">
    <path d="M4 12 L6 6 L9 12 L12 4 L15 12 L18 6 L20 12 L20 18 L4 18 Z"/>
    <circle cx="12" cy="15" r="0.9" fill="rgba(0,0,0,0.35)"/>
  </svg>`;

function renderTierUI() {
  const tier = currentTier();
  const meta = tierMeta(tier);
  document.body.dataset.tier = tier;
  document.documentElement.style.setProperty('--tier-accent', meta.accent);
  document.documentElement.style.setProperty('--tier-glow', meta.glow);

  if (btnUpgrade) {
    const isTop = tier === PoofTier.Devium || tier === PoofTier.Business;
    btnUpgrade.innerHTML = isTop ? CROWN_SVG : SPARKLES_SVG;
    btnUpgrade.setAttribute('aria-label', isTop ? 'Manage plan' : 'Upgrade');
  }

  if (tier === PoofTier.Standard) {
    tierPillEl.hidden = true;
  } else {
    tierPillEl.hidden = false;
    tierPillEl.textContent = meta.displayName;
    tierPillEl.style.color = meta.accent;
    tierPillEl.style.borderColor = meta.accent + '5A';
    tierPillEl.style.background = meta.accent + '28';
  }

  renderTierSection(tier, tierSectionEl, {
    peers: store.peers,
    receivedFiles: transfer.receivedFiles || [],
    isRTCConnected: manager.isReady,
    isBroadcasting: screenMirror.isBroadcasting,
    isSignalingConnected: signalingConnected,
    deviceName: thisDeviceName(),
    isPeerOnline,
    pushClipboard: () => { clipboard.pushCurrent?.(); toast('Clipboard sent'); },
    openFolderPicker: () => { fileInput.setAttribute('webkitdirectory', ''); fileInput.click(); setTimeout(() => fileInput.removeAttribute('webkitdirectory'), 500); },
    openRemoteFiles,
    openScreenMirror,
    openFeaturePreview,
    toast,
  });
}

function renderPricingSheet() {
  const active = currentTier();
  const order = [PoofTier.Standard, PoofTier.Premium, PoofTier.Family, PoofTier.Devium, PoofTier.Business];
  pricingListEl.innerHTML = order.map((t) => {
    const meta = TierMeta[t];
    const isActive = t === active;
    return `
      <button class="pricing-row" data-tier="${t}" style="--tier-accent:${meta.accent};${isActive ? 'border-color:' + meta.accent + ';' : ''}">
        <span class="pricing-row-head">
          <span class="pricing-row-name" style="color:${meta.accent}">${meta.displayName}</span>
          <span class="pricing-row-price">${meta.priceLabel}</span>
        </span>
        <span class="pricing-row-tagline">${meta.tagline}</span>
        <span class="pricing-row-cta" style="background:${isActive ? '#ffffff10' : meta.accent};color:${isActive ? '#8B95A7' : '#fff'}">${isActive ? 'Current plan' : 'Choose ' + meta.displayName}</span>
      </button>
    `;
  }).join('');
  pricingListEl.querySelectorAll('[data-tier]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const t = btn.dataset.tier;
      if (t === currentTier()) { pricingModal.close(); return; }
      setTier(t);
      pricingModal.close();
      toast(`Switched to ${TierMeta[t].displayName}`);
    });
  });
}

btnUpgrade?.addEventListener('click', () => {
  renderPricingSheet();
  pricingModal.showModal();
});

window.addEventListener('poof-tier-changed', renderTierUI);
store.addEventListener('change', renderTierUI);
transfer.addEventListener('outgoing-meta', renderTierUI);

// Initial paint (no online info yet — that arrives after hello)
renderDevices();
renderPeersGrid();
renderActivity();
renderTierUI();
maybeShowOnboarding();

// ------------------------------------------------------------------
// Service worker
// ------------------------------------------------------------------

// Skip the service worker when running inside Tauri — it aggressively caches
// the app shell (index.html, app.js) and hides fixes behind stale copies.
const isTauriShell = location.port !== '3000';
if ('serviceWorker' in navigator && !isTauriShell) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./service-worker.js').catch(() => {});
  });
} else if ('serviceWorker' in navigator && isTauriShell) {
  // Nuke any SW already registered from a previous run so the Tauri webview
  // stops serving cached HTML/JS.
  navigator.serviceWorker.getRegistrations().then((regs) => {
    regs.forEach((r) => r.unregister());
  }).catch(() => {});
  if (window.caches) {
    caches.keys().then((keys) => keys.forEach((k) => caches.delete(k))).catch(() => {});
  }
}
