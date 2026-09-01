/**
 * Poof — PWA mobile entry point.
 *
 * Architecture : PAS de WebRTC pour les fichiers (comme iOS post-relay
 * 2026-08-18). Tout passe par le relay HTTPS Render — POST /relay/upload
 * avec headers meta + push socket.io `relay-file-ready` côté destinataire,
 * qui télécharge via GET /relay/{fileId}. Simple, fiable, marche derrière
 * NAT/firewall. Signaling reste utilisé pour presence + pairing + notifs.
 *
 * URL du signaling FORCE Render (project_poof_signaling_url) — pas d'override.
 */
import { DeviceIdentity }  from './src/device-identity.js';
import { PairedPeerStore } from './src/paired-peer-store.js';

const SIGNALING_URL = 'https://poof-fgb8.onrender.com';

// ---------------------------------------------------------------------------
// Socket + state
// ---------------------------------------------------------------------------
const socket = io(SIGNALING_URL, {
  transports: ['websocket', 'polling'],
  upgrade: true,
  autoConnect: true,
});

const store = new PairedPeerStore();
const receivedFiles = [];      // { id, name, size, mime, blobUrl, receivedAt, senderName }
const onlinePeers = new Set(); // deviceIds actuellement online
let selectedPeerId = null;
let pendingFile = null;        // File OU { __clipboardText, name, size, type }
let currentPairCode = null;

// ---------------------------------------------------------------------------
// Signaling — presence + pairing
// ---------------------------------------------------------------------------
socket.on('connect', async () => {
  try {
    const res = await emitAck('hello', {
      deviceId: DeviceIdentity.deviceId,
      name: DeviceIdentity.name,
      platform: DeviceIdentity.platform,
      knownPeerIds: store.ids,
    });
    if (res?.ok && Array.isArray(res.onlinePeers)) {
      onlinePeers.clear();
      res.onlinePeers.forEach((p) => onlinePeers.add(p.deviceId || p));
    }
    renderDevices();
    renderHomeMetrics();
    toast('Connecté', 'success');
  } catch (err) {
    console.error('[Poof] hello failed', err);
    toast('Signaling injoignable', 'error');
  }
});

socket.on('disconnect', () => toast('Hors ligne', 'error'));
socket.on('peer-online',   ({ deviceId }) => { onlinePeers.add(deviceId);    renderDevices(); renderHomeMetrics(); });
socket.on('peer-offline',  ({ deviceId }) => { onlinePeers.delete(deviceId); renderDevices(); renderHomeMetrics(); });
socket.on('peer-unpaired', ({ deviceId }) => { store.remove(deviceId);       renderDevices(); renderHomeMetrics(); });

// Auto-pair côté qui a advertise
socket.on('pair-succeeded', ({ peer }) => {
  if (!peer?.deviceId) return;
  store.upsert({ deviceId: peer.deviceId, name: peer.name, platform: peer.platform });
  onlinePeers.add(peer.deviceId);
  currentPairCode = null;
  hidePairingModal();
  renderDevices();
  renderHomeMetrics();
  toast(`Appairé avec ${peer.name}`, 'success');
});

// Réception fichier
socket.on('relay-file-ready', async ({ fileId, meta }) => {
  try {
    const url = `${SIGNALING_URL}/relay/${encodeURIComponent(fileId)}`;
    const res = await fetch(url, { cache: 'no-store' });
    if (!res.ok) throw new Error(`relay GET ${res.status}`);
    const blob = await res.blob();
    const blobUrl = URL.createObjectURL(blob);
    const senderName = store.peers.find((p) => p.id === meta.senderDeviceId)?.name || 'Device';
    receivedFiles.unshift({
      id: fileId,
      name: meta.name || 'file',
      size: meta.size || blob.size,
      mime: meta.mime || blob.type || 'application/octet-stream',
      blobUrl,
      receivedAt: Date.now(),
      senderName,
    });
    renderReceived();
    renderHomeMetrics();
    toast(`Reçu de ${senderName}`, 'success');
    if (navigator.vibrate) navigator.vibrate([40, 30, 60]);
  } catch (err) {
    console.error('[Poof] relay download failed', err);
    toast('Réception échouée', 'error');
  }
});

// Clipboard entrant
socket.on('clipboard-inbound', async ({ text, senderName }) => {
  if (!text) return;
  try {
    if (navigator.clipboard?.writeText) await navigator.clipboard.writeText(text);
    toast(`Presse-papiers de ${senderName || 'Device'}`, 'success');
  } catch {
    toast('Presse-papiers reçu (accès bloqué)', 'info');
  }
});

// ---------------------------------------------------------------------------
// Envoi
// ---------------------------------------------------------------------------
async function sendFile(file, targetDeviceId) {
  if (!file || !targetDeviceId) return false;
  toast(`Envoi de ${file.name}…`, 'info');
  try {
    const transferId = crypto.randomUUID();
    const res = await fetch(`${SIGNALING_URL}/relay/upload`, {
      method: 'POST',
      headers: {
        'Content-Type': file.type || 'application/octet-stream',
        'X-Target-Device-Id': targetDeviceId,
        'X-Sender-Device-Id': DeviceIdentity.deviceId,
        'X-File-Name': encodeURIComponent(file.name || 'file'),
        'X-Mime-Type': file.type || 'application/octet-stream',
        'X-Transfer-Id': transferId,
      },
      body: file,
    });
    if (!res.ok) throw new Error(`upload ${res.status}`);
    toast(`Envoyé : ${file.name}`, 'success');
    if (navigator.vibrate) navigator.vibrate(30);
    return true;
  } catch (err) {
    console.error('[Poof] send failed', err);
    toast('Envoi échoué', 'error');
    return false;
  }
}

async function sendClipboardText(text, targetDeviceId) {
  if (!text || !targetDeviceId) return false;
  try {
    const res = await fetch(`${SIGNALING_URL}/relay/clipboard`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        targetDeviceId,
        senderDeviceId: DeviceIdentity.deviceId,
        senderName: DeviceIdentity.name,
        text,
      }),
    });
    if (!res.ok) throw new Error(`clipboard ${res.status}`);
    toast('Presse-papiers envoyé', 'success');
    return true;
  } catch (err) {
    console.error('[Poof] clipboard send failed', err);
    toast('Envoi échoué', 'error');
    return false;
  }
}

// ---------------------------------------------------------------------------
// Pairing
// ---------------------------------------------------------------------------
async function startAdvertising() {
  try {
    const res = await emitAck('pair-advertise', {});
    if (!res?.ok) throw new Error(res?.error || 'advertise-failed');
    currentPairCode = res.code;
    renderPairingModal();
  } catch (err) {
    console.error('[Poof] advertise failed', err);
    toast('Impossible de générer un code', 'error');
  }
}

async function consumeCode(rawCode) {
  const code = String(rawCode || '').toUpperCase().trim();
  if (code.length < 4) { toast('Code invalide', 'error'); return; }
  try {
    const res = await emitAck('pair-consume', { code });
    if (!res?.ok) throw new Error(res?.error || 'consume-failed');
    const peer = res.peer;
    if (!peer?.deviceId) throw new Error('no-peer');
    store.upsert({ deviceId: peer.deviceId, name: peer.name, platform: peer.platform });
    onlinePeers.add(peer.deviceId);
    currentPairCode = null;
    hidePairingModal();
    renderDevices();
    renderHomeMetrics();
    toast(`Appairé avec ${peer.name}`, 'success');
  } catch (err) {
    console.error('[Poof] consume failed', err);
    toast('Code invalide ou expiré', 'error');
  }
}

function cancelAdvertising() {
  if (currentPairCode) socket.emit('pair-cancel');
  currentPairCode = null;
}

// ---------------------------------------------------------------------------
// Icônes SF-like par platform (deviceBubble contenu)
// ---------------------------------------------------------------------------
function platformIconSvg(platform) {
  switch ((platform || '').toLowerCase()) {
    case 'ios':
      return `<svg viewBox="0 0 24 24" width="24" height="24"><path d="M7 2h10a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2zm0 3v14h10V5H7zm3 15h4v1h-4v-1z"/></svg>`;
    case 'ipados':
      return `<svg viewBox="0 0 24 24" width="24" height="24"><path d="M4 3h16a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zm0 3v12h16V6H4z"/></svg>`;
    case 'macos':
      return `<svg viewBox="0 0 24 24" width="24" height="24"><path d="M3 4h18a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1h-8v2h4v2H7v-2h4v-2H3a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z"/></svg>`;
    case 'windows':
      return `<svg viewBox="0 0 24 24" width="24" height="24"><path d="M3 5.5L11 4v8H3V5.5zm0 7.5h8v8l-8-1.5V13zm9-9l9-1.5V12h-9V4zm0 9h9v8.5L12 20v-7z"/></svg>`;
    case 'android':
      return `<svg viewBox="0 0 24 24" width="24" height="24"><path d="M7 2h10a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2zm0 3v14h10V5H7zm3 15h4v1h-4v-1z"/></svg>`;
    default:
      return `<svg viewBox="0 0 24 24" width="24" height="24"><circle cx="12" cy="9" r="5"/><path d="M4 21c0-4 4-6 8-6s8 2 8 6"/></svg>`;
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------
function renderDevices() {
  const slots = document.querySelectorAll('.send-view .device-slot');
  const peers = store.peers.slice(0, 3);
  slots.forEach((slot, i) => {
    const bubble = slot.querySelector('.device-bubble');
    const label  = slot.querySelector('.device-label');
    const peer   = peers[i];
    slot.dataset.slot = String(i);
    slot.classList.toggle('selected', peer && peer.id === selectedPeerId);
    if (peer) {
      const online = onlinePeers.has(peer.id);
      slot.dataset.peerId = peer.id;
      bubble.innerHTML = platformIconSvg(peer.platform);
      bubble.classList.toggle('online', online);
      label.textContent = peer.name + (online ? '' : ' · off');
    } else {
      delete slot.dataset.peerId;
      bubble.innerHTML = `<span class="plus">+</span>`;
      bubble.classList.remove('online');
      label.textContent = 'Vide';
    }
  });
  updateSendButtonState();
}

function renderReceived() {
  const list = document.querySelector('#received-list');
  if (!list) return;
  if (receivedFiles.length === 0) {
    list.innerHTML = `
      <div class="received-empty">
        <div class="received-empty-icon">
          <svg viewBox="0 0 24 24" width="30" height="30"><path d="M5 3h14a2 2 0 0 1 2 2v10h-6l-2 3h-4l-2-3H3V5a2 2 0 0 1 2-2zm-2 14h6l2 3h4l2-3h6v2a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-2z"/></svg>
        </div>
        Rien pour l'instant.<br>Les fichiers envoyés vers ce device apparaîtront ici.
      </div>`;
    return;
  }
  list.innerHTML = receivedFiles.map((f) => {
    const isImage = f.mime.startsWith('image/');
    const isVideo = f.mime.startsWith('video/');
    const preview = isImage
      ? `<img src="${f.blobUrl}" alt="" class="received-thumb"/>`
      : isVideo
        ? `<video src="${f.blobUrl}" class="received-thumb" muted playsinline></video>`
        : `<div class="received-thumb received-thumb-icon"><svg viewBox="0 0 24 24" width="26" height="26"><path d="M6 2h9l5 5v13a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2zm8 1v5h5"/></svg></div>`;
    return `
      <div class="received-row" data-id="${f.id}">
        ${preview}
        <div class="received-meta">
          <div class="received-name">${escapeHtml(f.name)}</div>
          <div class="received-sub">
            <span class="sender-pill">${escapeHtml(f.senderName)}</span>
            <span>${formatBytes(f.size)}</span>
          </div>
        </div>
        <a class="received-dl" href="${f.blobUrl}" download="${escapeHtml(f.name)}" aria-label="Télécharger">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12m0 0l-4-4m4 4l4-4M4 21h16"/></svg>
        </a>
      </div>`;
  }).join('');
}

function renderHomeMetrics() {
  const dEl = document.querySelector('#home-metric-devices');
  const rEl = document.querySelector('#home-metric-received');
  if (dEl) {
    const onlineCount = store.peers.filter((p) => onlinePeers.has(p.id)).length;
    dEl.innerHTML = `${onlineCount}<span class="unit">/ ${store.peers.length} en ligne</span>`;
  }
  if (rEl) {
    rEl.innerHTML = `${receivedFiles.length}<span class="unit">cette session</span>`;
  }
}

function renderPairingModal() {
  const modal = document.querySelector('#pairing-modal');
  if (!modal) return;
  modal.hidden = false;
  const codeBox = modal.querySelector('#pairing-code');
  const qrBox   = modal.querySelector('#pairing-qr');
  codeBox.textContent = currentPairCode || '—';
  qrBox.innerHTML = '';
  if (currentPairCode && typeof QRCode !== 'undefined') {
    try {
      new QRCode(qrBox, {
        text: currentPairCode,
        width: 160, height: 160,
        colorDark: '#000', colorLight: '#fff',
        correctLevel: QRCode.CorrectLevel.M,
      });
    } catch (err) { console.warn('[Poof] QR render failed', err); }
  }
}

function hidePairingModal() {
  const modal = document.querySelector('#pairing-modal');
  if (modal) modal.hidden = true;
  const input = document.querySelector('#pairing-input');
  if (input) input.value = '';
}

function updateSendButtonState() {
  const fab = document.querySelector('#send-fab');
  if (!fab) return;
  const ready = !!(pendingFile && selectedPeerId);
  fab.disabled = !ready;
  fab.classList.toggle('ready', ready);
  updatePendingPreview();
}

function updatePendingPreview() {
  const preview = document.querySelector('#pending-file');
  const nameEl  = document.querySelector('#pending-file-name');
  const subEl   = document.querySelector('#pending-file-sub');
  if (!preview) return;
  document.querySelectorAll('.chip').forEach((c) => c.classList.remove('armed'));
  if (!pendingFile) {
    preview.classList.remove('visible');
    return;
  }
  const label = pendingFile.__clipboardText
    ? 'Presse-papiers'
    : (pendingFile.name || 'Fichier');
  const sub = selectedPeerId
    ? 'Prêt · tape « Envoyer »'
    : 'Choisis un destinataire';
  nameEl.textContent = label;
  subEl.textContent  = sub;
  preview.classList.add('visible');
  // Highlight the armed chip
  const mode = pendingFile.__clipboardText ? 'Clipboard'
             : (pendingFile.type || '').startsWith('image/') || (pendingFile.type || '').startsWith('video/') ? 'Photo'
             : 'Fichier';
  const armed = document.querySelector(`.chip[aria-label="${mode}"]`);
  if (armed) armed.classList.add('armed');
}

// ---------------------------------------------------------------------------
// UI wiring
// ---------------------------------------------------------------------------
function wireUI() {
  document.querySelector('.chip[aria-label="Photo"]')?.addEventListener('click', () => {
    document.querySelector('#file-input-photo').click();
  });
  document.querySelector('.chip[aria-label="Fichier"]')?.addEventListener('click', () => {
    document.querySelector('#file-input-doc').click();
  });
  document.querySelector('.chip[aria-label="Clipboard"]')?.addEventListener('click', async () => {
    try {
      const text = await navigator.clipboard?.readText();
      if (!text) { toast('Presse-papiers vide', 'info'); return; }
      pendingFile = { __clipboardText: text, name: 'clipboard.txt', size: text.length, type: 'text/plain' };
      updateSendButtonState();
    } catch {
      toast('Accès presse-papiers refusé', 'error');
    }
  });

  document.querySelector('#file-input-photo')?.addEventListener('change', onFilePicked);
  document.querySelector('#file-input-doc')?.addEventListener('change', onFilePicked);

  document.querySelector('#pending-file-clear')?.addEventListener('click', () => {
    pendingFile = null;
    updateSendButtonState();
  });

  // Delegate clicks sur toute la .send-view pour les slots devices (avec re-render)
  document.querySelector('.send-view')?.addEventListener('click', (e) => {
    const slot = e.target.closest('.device-slot');
    if (!slot) return;
    const peerId = slot.dataset.peerId;
    if (!peerId) { startAdvertising(); return; }
    selectedPeerId = (selectedPeerId === peerId) ? null : peerId;
    renderDevices();
  });

  document.querySelector('#send-fab')?.addEventListener('click', async () => {
    if (!pendingFile || !selectedPeerId) return;
    const isClipboard = !!pendingFile.__clipboardText;
    const ok = isClipboard
      ? await sendClipboardText(pendingFile.__clipboardText, selectedPeerId)
      : await sendFile(pendingFile, selectedPeerId);
    if (ok) {
      pendingFile = null;
      updateSendButtonState();
    }
  });

  document.querySelectorAll('.tab-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab-btn').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      const view = btn.dataset.view || 'send';
      document.body.dataset.view = view;
      if (view === 'home') renderHomeMetrics();
    });
  });

  document.querySelector('#pairing-submit')?.addEventListener('click', () => {
    consumeCode(document.querySelector('#pairing-input')?.value);
  });
  document.querySelector('#pairing-input')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') consumeCode(e.target.value);
  });
  document.querySelector('#pairing-close')?.addEventListener('click', () => {
    cancelAdvertising();
    hidePairingModal();
  });
  document.querySelector('#pairing-copy')?.addEventListener('click', async () => {
    if (!currentPairCode) return;
    try {
      await navigator.clipboard.writeText(currentPairCode);
      toast('Code copié', 'success');
    } catch {
      toast('Copie refusée', 'error');
    }
  });
  // Fermer le modal au tap sur l'overlay
  document.querySelector('#pairing-modal')?.addEventListener('click', (e) => {
    if (e.target.id === 'pairing-modal') {
      cancelAdvertising();
      hidePairingModal();
    }
  });
}

function onFilePicked(e) {
  const file = e.target.files?.[0];
  if (!file) return;
  pendingFile = file;
  updateSendButtonState();
  e.target.value = '';
}

// ---------------------------------------------------------------------------
// Toast (typed)
// ---------------------------------------------------------------------------
let toastTimer = null;
const TOAST_ICONS = {
  success: `<svg viewBox="0 0 24 24" width="14" height="14"><path d="M5 12l5 5L20 7" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  error:   `<svg viewBox="0 0 24 24" width="14" height="14"><path d="M6 6l12 12M6 18L18 6" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"/></svg>`,
  info:    `<svg viewBox="0 0 24 24" width="14" height="14"><path d="M12 8v.01M12 12v5" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/></svg>`,
};
function toast(msg, type = 'info') {
  let el = document.querySelector('#toast');
  if (!el) {
    el = document.createElement('div');
    el.id = 'toast';
    document.body.appendChild(el);
  }
  const icon = TOAST_ICONS[type] || TOAST_ICONS.info;
  el.className = `type-${type}`;
  el.innerHTML = `<span class="toast-icon">${icon}</span><span>${escapeHtml(msg)}</span>`;
  requestAnimationFrame(() => el.classList.add('show'));
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 2600);
}

// ---------------------------------------------------------------------------
// Utils
// ---------------------------------------------------------------------------
function emitAck(event, payload, timeoutMs = 8000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('ack-timeout')), timeoutMs);
    socket.emit(event, payload, (res) => { clearTimeout(timer); resolve(res); });
  });
}

function formatBytes(n) {
  if (!n && n !== 0) return '';
  const u = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return `${n.toFixed(i === 0 ? 0 : 1)} ${u[i]}`;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------
document.addEventListener('DOMContentLoaded', () => {
  wireUI();
  renderDevices();
  renderReceived();
  renderHomeMetrics();
});
