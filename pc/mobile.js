/**
 * Poof — PWA mobile entry point.
 *
 * Design principle : ne PAS utiliser WebRTC pour les fichiers (comme iOS
 * post-2026-08-18, voir project_poof_relay_https). Le server Render expose
 * un relay HTTPS complet — on upload en POST /relay/upload avec des headers
 * meta, le server push `relay-file-ready` via socket.io au destinataire,
 * qui download via GET /relay/{fileId}. Simple, fiable, marche partout.
 *
 * Signaling reste utilisé pour :
 *   - `hello` (registrer le device + récupérer les peers online)
 *   - `pair-advertise` / `pair-consume` (appairage via code 6 chars)
 *   - `peer-online` / `peer-offline` (live status)
 *   - `relay-file-ready` (notif d'un fichier prêt à télécharger)
 *   - `clipboard-inbound` (clipboard sync)
 *
 * URL du signaling FORCE Render (voir project_poof_signaling_url) — ne pas
 * autoriser d'override utilisateur.
 */
import { DeviceIdentity }  from './src/device-identity.js';
import { PairedPeerStore } from './src/paired-peer-store.js';

const SIGNALING_URL = 'https://poof-fgb8.onrender.com';

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------
const socket = io(SIGNALING_URL, {
  transports: ['websocket', 'polling'],
  upgrade: true,
  autoConnect: true,
});

const store = new PairedPeerStore();
const receivedFiles = [];      // { id, name, size, mime, blobUrl, receivedAt, senderName }
const onlinePeers = new Set(); // deviceIds actuellement online (via signaling events)
let selectedPeerId = null;     // peer destination du prochain send
let pendingFile = null;        // File / Blob en attente d'envoi
let pendingMode = null;        // 'photo' | 'doc' | 'clipboard'
let currentPairCode = null;    // code que j'annonce quand j'ouvre le modal pairing

// ---------------------------------------------------------------------------
// Hello + presence
// ---------------------------------------------------------------------------
socket.on('connect', async () => {
  toast('Connecté');
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
  } catch (err) {
    console.error('[Poof] hello failed', err);
  }
});

socket.on('disconnect', () => toast('Déconnecté'));
socket.on('peer-online',  ({ deviceId }) => { onlinePeers.add(deviceId);    renderDevices(); });
socket.on('peer-offline', ({ deviceId }) => { onlinePeers.delete(deviceId); renderDevices(); });
socket.on('peer-unpaired',({ deviceId }) => { store.remove(deviceId);       renderDevices(); });

// Auto-pair : quand un autre device consume mon code, le serveur me push
// pair-succeeded pour que j'ajoute le peer à ma liste sans devoir refresh.
socket.on('pair-succeeded', ({ peer }) => {
  if (!peer?.deviceId) return;
  store.upsert({ deviceId: peer.deviceId, name: peer.name, platform: peer.platform });
  onlinePeers.add(peer.deviceId);
  currentPairCode = null;
  hidePairingModal();
  renderDevices();
  toast(`Appairé avec ${peer.name}`);
});

// ---------------------------------------------------------------------------
// Réception : le serveur nous push un event dès qu'un fichier nous est destiné.
// On download direct + ajoute au received tab. Preview auto pour images.
// ---------------------------------------------------------------------------
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
    toast(`Fichier reçu de ${senderName}`);
    if (navigator.vibrate) navigator.vibrate([40, 30, 60]);
  } catch (err) {
    console.error('[Poof] relay download failed', err);
    toast('Réception échouée');
  }
});

// Clipboard entrant — l'iPhone envoie du texte via POST /relay/clipboard.
socket.on('clipboard-inbound', async ({ text, senderName }) => {
  if (!text) return;
  try {
    if (navigator.clipboard?.writeText) await navigator.clipboard.writeText(text);
    toast(`Presse-papiers de ${senderName || 'Device'}`);
  } catch {
    toast('Presse-papiers reçu (accès bloqué)');
  }
});

// ---------------------------------------------------------------------------
// Envoi via relay HTTPS
// ---------------------------------------------------------------------------
async function sendFile(file, targetDeviceId) {
  if (!file || !targetDeviceId) return false;
  toast(`Envoi de ${file.name}…`);
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
    toast(`Envoyé : ${file.name}`);
    if (navigator.vibrate) navigator.vibrate(30);
    return true;
  } catch (err) {
    console.error('[Poof] send failed', err);
    toast('Envoi échoué');
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
    toast('Presse-papiers envoyé');
    return true;
  } catch (err) {
    console.error('[Poof] clipboard send failed', err);
    toast('Envoi presse-papiers échoué');
    return false;
  }
}

// ---------------------------------------------------------------------------
// Pairing (via signaling ACKs)
// ---------------------------------------------------------------------------
async function startAdvertising() {
  try {
    const res = await emitAck('pair-advertise', {});
    if (!res?.ok) throw new Error(res?.error || 'advertise-failed');
    currentPairCode = res.code;
    renderPairingModal();
  } catch (err) {
    console.error('[Poof] advertise failed', err);
    toast('Impossible de générer un code');
  }
}

async function consumeCode(rawCode) {
  const code = String(rawCode || '').toUpperCase().trim();
  if (code.length < 4) { toast('Code invalide'); return; }
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
    toast(`Appairé avec ${peer.name}`);
  } catch (err) {
    console.error('[Poof] consume failed', err);
    toast('Code invalide ou expiré');
  }
}

function cancelAdvertising() {
  if (currentPairCode) socket.emit('pair-cancel');
  currentPairCode = null;
}

// ---------------------------------------------------------------------------
// UI rendering (docs/pc/mobile.html)
// ---------------------------------------------------------------------------
function renderDevices() {
  const slots = document.querySelectorAll('.device-slot');
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
      bubble.innerHTML = `<svg viewBox="0 0 24 24" width="26" height="26" fill="#fff"><path d="M7 2h10a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2zm0 3v14h10V5H7zm3 15h4v1h-4v-1z"/></svg>`;
      bubble.classList.toggle('online', online);
      label.textContent = peer.name + (online ? '' : ' · off');
    } else {
      delete slot.dataset.peerId;
      bubble.innerHTML = `<span class="plus">+</span>`;
      bubble.classList.remove('online');
      label.textContent = 'Empty';
    }
  });
  updateSendButtonState();
}

function renderReceived() {
  const list = document.querySelector('#received-list');
  if (!list) return;
  if (receivedFiles.length === 0) {
    list.innerHTML = `<div class="received-empty">Rien pour l'instant. Les fichiers envoyés vers ce device apparaîtront ici.</div>`;
    return;
  }
  list.innerHTML = receivedFiles.map((f) => {
    const isImage = f.mime.startsWith('image/');
    const isVideo = f.mime.startsWith('video/');
    const preview = isImage
      ? `<img src="${f.blobUrl}" alt="" class="received-thumb"/>`
      : isVideo
        ? `<video src="${f.blobUrl}" class="received-thumb" muted></video>`
        : `<div class="received-thumb received-thumb-icon"><svg viewBox="0 0 24 24" width="24" height="24" fill="#fff"><path d="M6 2h9l5 5v13a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2zm8 1v5h5"/></svg></div>`;
    return `
      <div class="received-row" data-id="${f.id}">
        ${preview}
        <div class="received-meta">
          <div class="received-name">${escapeHtml(f.name)}</div>
          <div class="received-sub">${escapeHtml(f.senderName)} · ${formatBytes(f.size)}</div>
        </div>
        <a class="received-dl" href="${f.blobUrl}" download="${escapeHtml(f.name)}" aria-label="Télécharger">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12m0 0l-4-4m4 4l4-4M4 21h16"/></svg>
        </a>
      </div>`;
  }).join('');
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
        width: 168, height: 168,
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
  const sendBtn = document.querySelector('#send-fab');
  if (!sendBtn) return;
  const ready = !!(pendingFile && selectedPeerId);
  sendBtn.disabled = !ready;
  sendBtn.classList.toggle('ready', ready);
}

// ---------------------------------------------------------------------------
// Wiring UI events
// ---------------------------------------------------------------------------
function wireUI() {
  // Chip photo
  document.querySelector('.chip[aria-label="Photo"]')?.addEventListener('click', () => {
    pendingMode = 'photo';
    document.querySelector('#file-input-photo').click();
  });
  // Chip doc
  document.querySelector('.chip[aria-label="Fichier"]')?.addEventListener('click', () => {
    pendingMode = 'doc';
    document.querySelector('#file-input-doc').click();
  });
  // Chip clipboard
  document.querySelector('.chip[aria-label="Clipboard"]')?.addEventListener('click', async () => {
    pendingMode = 'clipboard';
    try {
      const text = await navigator.clipboard?.readText();
      if (!text) { toast('Presse-papiers vide'); return; }
      pendingFile = { __clipboardText: text, name: 'clipboard.txt', size: text.length, type: 'text/plain' };
      toast(`Prêt à envoyer : ${text.slice(0, 30)}…`);
      updateSendButtonState();
    } catch {
      toast('Accès presse-papiers refusé');
    }
  });

  document.querySelector('#file-input-photo')?.addEventListener('change', onFilePicked);
  document.querySelector('#file-input-doc')?.addEventListener('change', onFilePicked);

  // Tap sur un slot device — vide → pairing modal, plein → select
  document.querySelectorAll('.device-slot').forEach((slot) => {
    slot.addEventListener('click', () => {
      const peerId = slot.dataset.peerId;
      if (!peerId) { startAdvertising(); return; }
      selectedPeerId = (selectedPeerId === peerId) ? null : peerId;
      renderDevices();
    });
  });

  // Send FAB
  document.querySelector('#send-fab')?.addEventListener('click', async () => {
    if (!pendingFile || !selectedPeerId) return;
    if (pendingFile.__clipboardText) {
      await sendClipboardText(pendingFile.__clipboardText, selectedPeerId);
    } else {
      await sendFile(pendingFile, selectedPeerId);
    }
    pendingFile = null; pendingMode = null;
    updateSendButtonState();
  });

  // Tab bar navigation
  document.querySelectorAll('.tab-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab-btn').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      const view = btn.dataset.view || 'send';
      document.body.dataset.view = view;
    });
  });

  // Pairing modal — bouton Consume, bouton Close
  document.querySelector('#pairing-submit')?.addEventListener('click', () => {
    const val = document.querySelector('#pairing-input')?.value;
    consumeCode(val);
  });
  document.querySelector('#pairing-input')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') consumeCode(e.target.value);
  });
  document.querySelector('#pairing-close')?.addEventListener('click', () => {
    cancelAdvertising();
    hidePairingModal();
  });
}

function onFilePicked(e) {
  const file = e.target.files?.[0];
  if (!file) return;
  pendingFile = file;
  toast(`Prêt à envoyer : ${file.name}`);
  updateSendButtonState();
  e.target.value = '';
}

// ---------------------------------------------------------------------------
// Toast helper
// ---------------------------------------------------------------------------
let toastTimer = null;
function toast(msg) {
  let el = document.querySelector('#toast');
  if (!el) {
    el = document.createElement('div');
    el.id = 'toast';
    document.body.appendChild(el);
  }
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 2400);
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
// Init
// ---------------------------------------------------------------------------
document.addEventListener('DOMContentLoaded', () => {
  wireUI();
  renderDevices();
  renderReceived();
});
