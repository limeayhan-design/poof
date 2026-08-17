import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { readFile, stat } from 'node:fs/promises';
import { readFileSync, existsSync, writeFileSync } from 'node:fs';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { networkInterfaces } from 'node:os';
import { Server } from 'socket.io';
import { Bonjour } from 'bonjour-service';
import apn from '@parse/node-apn';

const PORT = Number(process.env.PORT) || 3000;
const PAIR_CODE_TTL_MS = 5 * 60 * 1000;
const SESSION_TTL_MS = 5 * 60 * 1000;
const PAIR_CODE_LEN = 6;
const PAIR_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const MAX_PEERS = 2;

// Support chat — persistance JSON simple. threads = { deviceId: { name, messages: [{id, text, isAdmin, ts}] } }
const MESSAGES_FILE = process.env.MESSAGES_FILE || '/tmp/poof-messages.json';
const ADMIN_TOKEN = process.env.SUPPORT_ADMIN_TOKEN || 'poof-admin-change-me';
let supportThreads = {};
try { supportThreads = JSON.parse(readFileSync(MESSAGES_FILE, 'utf8')); } catch {}
function saveSupportThreads() {
  try { writeFileSync(MESSAGES_FILE, JSON.stringify(supportThreads)); } catch {}
}
function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', c => { data += c; if (data.length > 1e5) { reject(new Error('too-big')); req.destroy(); } });
    req.on('end', () => { try { resolve(JSON.parse(data)); } catch { resolve({}); } });
    req.on('error', reject);
  });
}

const STATIC_ROOT = resolve(fileURLToPath(new URL('./pc/', import.meta.url)));
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css':  'text/css; charset=utf-8',
  '.js':   'text/javascript; charset=utf-8',
  '.mjs':  'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg':  'image/svg+xml',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.ico':  'image/x-icon',
  '.webmanifest': 'application/manifest+json',
};

// Pick the best LAN IPv4 for this host: prefer Wi-Fi (en0/en1 on macOS,
// wlan* on Linux), fall back to any non-internal IPv4.
function pickLanIp() {
  const ifaces = networkInterfaces();
  const candidates = [];
  for (const [name, addrs] of Object.entries(ifaces)) {
    for (const a of addrs || []) {
      if (a.family !== 'IPv4' || a.internal) continue;
      const isWifi = /^en0$|^en1$|wlan|wifi/i.test(name);
      candidates.push({ name, address: a.address, isWifi });
    }
  }
  candidates.sort((a, b) => Number(b.isWifi) - Number(a.isWifi));
  return candidates[0]?.address || null;
}

async function serveStatic(req, res) {
  const urlPath = decodeURIComponent(req.url.split('?')[0]);
  const rel = urlPath === '/' ? '/index.html' : urlPath;
  const filePath = resolve(STATIC_ROOT, '.' + rel);
  if (!(filePath === STATIC_ROOT || filePath.startsWith(STATIC_ROOT + sep))) {
    res.writeHead(403); res.end(); return true;
  }
  try {
    const s = await stat(filePath);
    if (!s.isFile()) return false;
    const body = await readFile(filePath);
    res.writeHead(200, {
      'content-type': MIME[extname(filePath).toLowerCase()] || 'application/octet-stream',
      'cache-control': 'no-cache',
    });
    res.end(body);
    return true;
  } catch { return false; }
}

const httpServer = createServer(async (req, res) => {
  // Support chat — POST routes (avant le guard GET-only).
  if (req.method === 'POST' && req.url === '/messages') {
    try {
      const { deviceId, name, text } = await readJsonBody(req);
      if (!deviceId || !text) { res.writeHead(400); res.end(); return; }
      if (!supportThreads[deviceId]) supportThreads[deviceId] = { name: name || '', messages: [] };
      if (name) supportThreads[deviceId].name = name;
      supportThreads[deviceId].messages.push({
        id: randomBytes(8).toString('hex'),
        text: String(text).slice(0, 2000),
        isAdmin: false,
        ts: Date.now() / 1000
      });
      saveSupportThreads();
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true }));
    } catch { res.writeHead(500); res.end(); }
    return;
  }
  if (req.method === 'POST' && req.url?.startsWith('/admin/reply')) {
    const u = new URL(req.url, 'http://x');
    if (u.searchParams.get('token') !== ADMIN_TOKEN) { res.writeHead(401); res.end(); return; }
    try {
      const { deviceId, text } = await readJsonBody(req);
      if (!deviceId || !text) { res.writeHead(400); res.end(); return; }
      if (!supportThreads[deviceId]) supportThreads[deviceId] = { name: '', messages: [] };
      supportThreads[deviceId].messages.push({
        id: randomBytes(8).toString('hex'),
        text: String(text).slice(0, 2000),
        isAdmin: true,
        ts: Date.now() / 1000
      });
      saveSupportThreads();
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true }));
    } catch { res.writeHead(500); res.end(); }
    return;
  }

  if (req.method !== 'GET') { res.writeHead(405); res.end(); return; }

  // Support chat — GET routes.
  if (req.url?.startsWith('/messages')) {
    const u = new URL(req.url, 'http://x');
    const deviceId = u.searchParams.get('deviceId') || '';
    const thread = supportThreads[deviceId] || { name: '', messages: [] };
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(thread));
    return;
  }
  if (req.url?.startsWith('/admin/threads')) {
    const u = new URL(req.url, 'http://x');
    if (u.searchParams.get('token') !== ADMIN_TOKEN) { res.writeHead(401); res.end(); return; }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(supportThreads));
    return;
  }

  if (req.url === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      ok: true,
      devices: devices.size,
      sessions: sessions.size,
      pairingCodes: pairingCodes.size,
    }));
    return;
  }
  if (req.url === '/local-url') {
    const ip = pickLanIp();
    const url = ip ? `http://${ip}:${PORT}` : null;
    res.writeHead(200, {
      'content-type': 'application/json',
      'cache-control': 'no-cache',
    });
    res.end(JSON.stringify({ url }));
    return;
  }
  // GET /debug/apns-test?token=<hex>&title=<t>&body=<b>
  // Envoie un push APNS direct au token fourni, sans passer par socket.io.
  // Permet de valider le pipeline APNS bout en bout avec un simple curl.
  if (req.url?.startsWith('/debug/apns-test')) {
    const u = new URL(req.url, 'http://x');
    const token = u.searchParams.get('token');
    const title = u.searchParams.get('title') || 'Poof test';
    const body = u.searchParams.get('body') || 'Hello from server';
    if (!token) {
      res.writeHead(400, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: 'missing token param' }));
      return;
    }
    if (!apnProvider) {
      res.writeHead(500, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: 'APNS provider not initialized' }));
      return;
    }
    console.log(`[Poof] /debug/apns-test → token=${token.slice(0, 12)}… title="${title}"`);
    const notif = new apn.Notification();
    notif.alert = { title, body };
    notif.sound = 'default';
    notif.topic = APNS_TOPIC;
    notif.pushType = 'alert';
    try {
      const result = await apnProvider.send(notif, token);
      const payload = {
        ok: result.sent.length > 0,
        sent: result.sent.length,
        failed: result.failed.length,
        failures: result.failed.map((f) => ({ status: f.status, response: f.response })),
        topic: APNS_TOPIC,
        production: APNS_PRODUCTION,
      };
      console.log(`[Poof] /debug/apns-test result:`, JSON.stringify(payload));
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify(payload, null, 2));
    } catch (err) {
      console.error(`[Poof] /debug/apns-test error:`, err);
      res.writeHead(500, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: err.message }));
    }
    return;
  }
  if (await serveStatic(req, res)) return;
  res.writeHead(404); res.end();
});

const io = new Server(httpServer, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
  maxHttpBufferSize: 4096,
  pingInterval: 25000,
  pingTimeout: 20000,
  transports: ['websocket', 'polling'],
  allowUpgrades: true,
});

// -------------------------------------------------------------
// State
// -------------------------------------------------------------

/**
 * deviceId → { socketId, name, platform, knownPeerIds: Set<string> }
 * A device is present in this map iff its socket is currently connected AND
 * it has completed the `hello` handshake.
 */
const devices = new Map();

/** socketId → deviceId (reverse lookup) */
const socketToDevice = new Map();

/**
 * deviceId → { token: string, platform: string }
 * APNS device tokens registered by devices. Survive socket disconnects — le
 * whole point est de pouvoir push un device dont l'app est fermée.
 * Persistant en mémoire seulement (perdu au restart du server, mais l'app
 * re-register au prochain launch).
 */
const pushTokens = new Map();

// -------------------------------------------------------------
// APNS provider (lazy init, activé seulement si env vars présentes)
// -------------------------------------------------------------

const APNS_TOPIC = process.env.APNS_TOPIC || 'com.Poof.App.Poof';
const APNS_PRODUCTION = process.env.APNS_PRODUCTION === 'true';

/**
 * Charge la clé .p8 depuis, dans l'ordre :
 *   1) env var `APNS_KEY_P8_B64` (base64 — le plus safe, une seule ligne)
 *   2) Secret File `/etc/secrets/AuthKey.p8`
 *   3) env var `APNS_KEY_P8` (raw, avec \\n littéraux décodés)
 */
function loadApnsKey() {
  const b64 = process.env.APNS_KEY_P8_B64;
  if (b64) {
    const decoded = Buffer.from(b64, 'base64').toString('utf-8');
    console.log(`[Poof] APNS key loaded from env var (base64, ${decoded.length} chars)`);
    console.log(`[Poof] APNS key preview: ${JSON.stringify(decoded.slice(0, 60))}`);
    return decoded;
  }
  try {
    const secretPath = '/etc/secrets/AuthKey.p8';
    if (existsSync(secretPath)) {
      const content = readFileSync(secretPath, 'utf-8');
      console.log(`[Poof] APNS key loaded from secret file (${content.length} chars)`);
      console.log(`[Poof] APNS key preview: ${JSON.stringify(content.slice(0, 60))}`);
      return content;
    }
  } catch (err) {
    console.error('[Poof] APNS key secret file read error:', err.message);
  }
  const envKey = process.env.APNS_KEY_P8;
  if (envKey) {
    const decoded = envKey.replace(/\\n/g, '\n');
    console.log(`[Poof] APNS key loaded from env var (raw, ${decoded.length} chars)`);
    console.log(`[Poof] APNS key preview: ${JSON.stringify(decoded.slice(0, 60))}`);
    return decoded;
  }
  return null;
}

let apnProvider = null;
const apnsKey = loadApnsKey();
if (apnsKey && process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID) {
  try {
    apnProvider = new apn.Provider({
      token: {
        key: apnsKey,
        keyId: process.env.APNS_KEY_ID,
        teamId: process.env.APNS_TEAM_ID,
      },
      production: APNS_PRODUCTION,
    });
    console.log(`[Poof] APNS provider ready (production=${APNS_PRODUCTION}, topic=${APNS_TOPIC})`);
  } catch (err) {
    console.error('[Poof] APNS provider init failed:', err.message);
    console.error('[Poof] Full error:', err);
  }
} else {
  console.warn(`[Poof] APNS disabled — hasKey=${!!apnsKey} hasKeyID=${!!process.env.APNS_KEY_ID} hasTeamID=${!!process.env.APNS_TEAM_ID}`);
}

async function sendApnsPush(toDeviceId, title, body) {
  if (!apnProvider) {
    console.warn(`[Poof] sendApnsPush ABORT — no APNS provider`);
    return;
  }
  const entry = pushTokens.get(toDeviceId);
  if (!entry) {
    console.log(`[Poof] push-alert: no token for ${toDeviceId} — known tokens: [${Array.from(pushTokens.keys()).join(', ') || 'NONE'}]`);
    return;
  }
  const notif = new apn.Notification();
  notif.alert = { title, body };
  notif.sound = 'default';
  notif.topic = APNS_TOPIC;
  notif.pushType = 'alert';
  console.log(`[Poof] APNS → sending to ${toDeviceId} token=${entry.token.slice(0, 12)}… topic=${APNS_TOPIC} title="${title}"`);
  try {
    const result = await apnProvider.send(notif, entry.token);
    console.log(`[Poof] APNS sent to ${toDeviceId} → sent=${result.sent.length} failed=${result.failed.length}`);
    if (result.failed.length > 0) {
      for (const f of result.failed) {
        console.error(`[Poof] APNS failure: ${f.status} ${JSON.stringify(f.response)}`);
        // Token invalide → on le retire pour ne pas re-tenter.
        if (f.status === '410' || f.response?.reason === 'Unregistered') {
          pushTokens.delete(toDeviceId);
        }
      }
    }
  } catch (err) {
    console.error('[Poof] APNS send error:', err);
  }
}

/**
 * code → { socketId, deviceInfo, timer }
 * Short-lived pairing codes (5 min TTL). Consumed once.
 */
const pairingCodes = new Map();

/**
 * sessionId → { peers: Set<socketId>, timer }
 * A WebRTC signalling session between exactly 2 sockets. Auto-destroyed on
 * the last peer leaving or after TTL.
 */
const sessions = new Map();

/** socketId → sessionId (reverse lookup, one session per socket at a time) */
const socketToSession = new Map();

// -------------------------------------------------------------
// Helpers
// -------------------------------------------------------------

function randomCode(len, alphabet, taken) {
  let out;
  do {
    const bytes = randomBytes(len);
    out = '';
    for (let i = 0; i < len; i++) out += alphabet[bytes[i] % alphabet.length];
  } while (taken.has(out));
  return out;
}

function publicDeviceInfo(deviceId) {
  const d = devices.get(deviceId);
  if (!d) return null;
  return { deviceId, name: d.name, platform: d.platform };
}

function isOnline(deviceId) {
  return devices.has(deviceId);
}

function broadcastPresence(deviceId, online) {
  // Notify every currently-connected socket that has `deviceId` in its
  // knownPeerIds set — those are the peers who care.
  for (const [, d] of devices) {
    if (d.knownPeerIds.has(deviceId)) {
      io.to(d.socketId).emit(online ? 'peer-online' : 'peer-offline', { deviceId });
    }
  }
}

function scheduleSessionExpiry(sessionId) {
  const s = sessions.get(sessionId);
  if (!s) return;
  clearTimeout(s.timer);
  s.timer = setTimeout(() => destroySession(sessionId, 'expired'), SESSION_TTL_MS);
}

function destroySession(sessionId, reason) {
  const s = sessions.get(sessionId);
  if (!s) return;
  clearTimeout(s.timer);
  for (const sid of s.peers) {
    socketToSession.delete(sid);
    io.to(sid).emit('session-closed', { sessionId, reason });
  }
  sessions.delete(sessionId);
}

function leaveSession(socket, reason) {
  const sessionId = socketToSession.get(socket.id);
  if (!sessionId) return;
  socketToSession.delete(socket.id);
  const s = sessions.get(sessionId);
  if (!s) return;
  s.peers.delete(socket.id);
  socket.to(sessionId).emit('peer-left', { sessionId, reason });
  if (s.peers.size === 0) destroySession(sessionId, 'empty');
}

function cancelPairingCode(socket) {
  for (const [code, entry] of pairingCodes) {
    if (entry.socketId === socket.id) {
      clearTimeout(entry.timer);
      pairingCodes.delete(code);
    }
  }
}

// -------------------------------------------------------------
// Wire events
// -------------------------------------------------------------

io.on('connection', (socket) => {
  console.log(`[Poof] socket connected ${socket.id} (transport=${socket.conn.transport.name})`);
  socket.on('disconnect', (reason) => {
    const me = socketToDevice.get(socket.id);
    console.log(`[Poof] socket disconnected ${socket.id} device=${me || '?'} reason=${reason}`);
  });

  // ---- 1. Identity + subscription -----------------------------------------
  socket.on('hello', (payload = {}, ack) => {
    const { deviceId, name, platform, knownPeerIds = [] } = payload;
    console.log(`[Poof] hello from socket=${socket.id} deviceId=${deviceId} name=${name} platform=${platform}`);
    if (typeof deviceId !== 'string' || !deviceId) {
      return ack?.({ ok: false, error: 'invalid-deviceId' });
    }
    // If a previous socket owned this deviceId, force it out (multiple tabs, reconnect).
    const existing = devices.get(deviceId);
    if (existing && existing.socketId !== socket.id) {
      const oldSocket = io.sockets.sockets.get(existing.socketId);
      oldSocket?.disconnect(true);
      devices.delete(deviceId);
      socketToDevice.delete(existing.socketId);
    }

    devices.set(deviceId, {
      socketId: socket.id,
      name: String(name || 'Unknown'),
      platform: String(platform || 'unknown'),
      knownPeerIds: new Set(knownPeerIds),
    });
    socketToDevice.set(socket.id, deviceId);

    const online = knownPeerIds.filter(isOnline);
    ack?.({ ok: true, onlinePeers: online });
    broadcastPresence(deviceId, true);
  });

  socket.on('subscribe', ({ deviceIds = [] } = {}) => {
    const me = socketToDevice.get(socket.id);
    const d = me && devices.get(me);
    if (!d) return;
    for (const id of deviceIds) d.knownPeerIds.add(String(id));
  });

  socket.on('unsubscribe', ({ deviceIds = [] } = {}) => {
    const me = socketToDevice.get(socket.id);
    const d = me && devices.get(me);
    if (!d) return;
    for (const id of deviceIds) d.knownPeerIds.delete(String(id));
  });

  // ---- 2. Pairing (short-lived code exchange) -----------------------------
  socket.on('pair-advertise', (_, ack) => {
    const me = socketToDevice.get(socket.id);
    if (!me) return ack?.({ ok: false, error: 'not-hello' });
    cancelPairingCode(socket);
    const code = randomCode(PAIR_CODE_LEN, PAIR_ALPHABET, pairingCodes);
    const info = publicDeviceInfo(me);
    const timer = setTimeout(() => {
      pairingCodes.delete(code);
      socket.emit('pair-expired', { code });
    }, PAIR_CODE_TTL_MS);
    pairingCodes.set(code, { socketId: socket.id, deviceInfo: info, timer });
    ack?.({ ok: true, code });
  });

  socket.on('pair-cancel', () => cancelPairingCode(socket));

  socket.on('pair-consume', ({ code } = {}, ack) => {
    if (typeof code !== 'string') return ack?.({ ok: false, error: 'invalid-code' });
    const entry = pairingCodes.get(code.toUpperCase());
    if (!entry) return ack?.({ ok: false, error: 'not-found' });

    const me = socketToDevice.get(socket.id);
    const myInfo = me && publicDeviceInfo(me);
    if (!myInfo) return ack?.({ ok: false, error: 'not-hello' });
    if (entry.socketId === socket.id) return ack?.({ ok: false, error: 'self-pair' });

    clearTimeout(entry.timer);
    pairingCodes.delete(code.toUpperCase());

    // Tell both sides who the other is.
    io.to(entry.socketId).emit('pair-succeeded', { peer: myInfo });
    ack?.({ ok: true, peer: entry.deviceInfo });

    // Mutual subscribe so presence broadcasts flow.
    const consumer = devices.get(me);
    const host = devices.get(entry.deviceInfo.deviceId);
    if (consumer && entry.deviceInfo?.deviceId) consumer.knownPeerIds.add(entry.deviceInfo.deviceId);
    if (host) host.knownPeerIds.add(me);
  });

  // ---- 3. Direct connection to a known peer -------------------------------
  socket.on('session-open', ({ targetDeviceId } = {}, ack) => {
    if (typeof targetDeviceId !== 'string') return ack?.({ ok: false, error: 'invalid-target' });
    const target = devices.get(targetDeviceId);
    if (!target) return ack?.({ ok: false, error: 'offline' });
    const me = socketToDevice.get(socket.id);
    if (!me) return ack?.({ ok: false, error: 'not-hello' });

    // Reuse an existing session if the two sockets already share one.
    let sessionId = socketToSession.get(socket.id);
    if (sessionId) {
      const s = sessions.get(sessionId);
      if (s && s.peers.has(target.socketId)) {
        return ack?.({ ok: true, sessionId, initiator: true });
      }
      leaveSession(socket, 'switch');
    }
    if (socketToSession.has(target.socketId)) {
      // Target is busy in another session — evict it so we can talk.
      const targetSocket = io.sockets.sockets.get(target.socketId);
      if (targetSocket) leaveSession(targetSocket, 'preempted');
    }

    sessionId = randomCode(8, PAIR_ALPHABET, sessions);
    const s = { peers: new Set([socket.id, target.socketId]), timer: null };
    sessions.set(sessionId, s);
    socketToSession.set(socket.id, sessionId);
    socketToSession.set(target.socketId, sessionId);
    socket.join(sessionId);
    io.sockets.sockets.get(target.socketId)?.join(sessionId);
    scheduleSessionExpiry(sessionId);

    io.to(target.socketId).emit('session-opened', {
      sessionId,
      initiator: false,
      from: publicDeviceInfo(me),
    });
    ack?.({ ok: true, sessionId, initiator: true });
  });

  socket.on('session-leave', () => leaveSession(socket, 'left'));

  // -------------------------------------------------------------
  // Push notifications (APNS relay)
  // -------------------------------------------------------------
  //
  // Le token APNS est envoyé par l'app au launch. On le mappe au deviceId
  // courant. Persisté au-delà de la déconnexion socket pour pouvoir push
  // un device dont l'app est fermée (c'est tout l'intérêt).
  socket.on('register-push-token', ({ token, platform } = {}) => {
    const me = socketToDevice.get(socket.id);
    console.log(`[Poof] register-push-token received — socket=${socket.id} me=${me || 'NO-HELLO'} tokenLen=${token?.length || 0} platform=${platform}`);
    if (!me) {
      console.warn(`[Poof] register-push-token DROPPED — no hello for socket ${socket.id}`);
      return;
    }
    if (typeof token !== 'string' || !token) {
      console.warn(`[Poof] register-push-token DROPPED — invalid token for ${me}`);
      return;
    }
    pushTokens.set(me, { token, platform: String(platform || 'ios') });
    console.log(`[Poof] push-token registered for ${me} (${platform}) — total tokens=${pushTokens.size}`);
  });

  // Émis par le receiver quand il ouvre un fichier Track — le sender peut
  // être app-fermée, donc WebRTC event ne suffit pas. On relaie via APNS.
  socket.on('push-alert', ({ toDeviceId, title, body } = {}) => {
    console.log(`[Poof] push-alert received — from=${socketToDevice.get(socket.id)} to=${toDeviceId} title="${title}"`);
    if (typeof toDeviceId !== 'string' || !toDeviceId) {
      console.warn(`[Poof] push-alert DROPPED — invalid toDeviceId`);
      return;
    }
    const safeTitle = String(title || 'File opened').slice(0, 100);
    const safeBody = String(body || '').slice(0, 200);
    sendApnsPush(toDeviceId, safeTitle, safeBody);
  });

  // Notify a paired peer that this device removed it from its paired list.
  // Also drops mutual presence subscription so ghost "online" events stop.
  socket.on('unpair', ({ deviceId } = {}) => {
    if (typeof deviceId !== 'string' || !deviceId) return;
    const me = socketToDevice.get(socket.id);
    const meEntry = me && devices.get(me);
    if (meEntry) meEntry.knownPeerIds.delete(deviceId);
    const target = devices.get(deviceId);
    if (target) {
      const targetEntry = devices.get(deviceId);
      if (targetEntry && me) targetEntry.knownPeerIds.delete(me);
      io.to(target.socketId).emit('peer-unpaired', { deviceId: me });
    }
  });

  // ---- 4. WebRTC relay ----------------------------------------------------
  const relay = (event) => (payload) => {
    const sessionId = socketToSession.get(socket.id);
    if (!sessionId) return;
    socket.to(sessionId).emit(event, { from: socket.id, ...payload });
  };
  socket.on('sdp-offer', relay('sdp-offer'));
  socket.on('sdp-answer', relay('sdp-answer'));
  socket.on('ice-candidate', relay('ice-candidate'));

  // ---- 5. Cleanup ---------------------------------------------------------
  socket.on('disconnect', () => {
    cancelPairingCode(socket);
    leaveSession(socket, 'disconnected');
    const me = socketToDevice.get(socket.id);
    socketToDevice.delete(socket.id);
    if (me) {
      const entry = devices.get(me);
      if (entry && entry.socketId === socket.id) devices.delete(me);
      broadcastPresence(me, false);
    }
  });
});

// Zero-config LAN discovery. iOS/macOS/Windows peers can find this gateway
// automatically via mDNS without typing an IP.
const bonjour = new Bonjour();
let mdnsService = null;

httpServer.listen(PORT, () => {
  console.log(`[poof] signaling gateway listening on :${PORT}`);
  const ip = pickLanIp();
  mdnsService = bonjour.publish({
    name: `Poof Gateway${ip ? ' — ' + ip : ''}`,
    type: 'poof',
    protocol: 'tcp',
    port: PORT,
    txt: { v: '1', ip: ip || '' },
  });
  console.log(`[poof] mDNS advertised as _poof._tcp.local. on :${PORT}`);
});

const shutdown = () => {
  try { mdnsService?.stop(() => {}); } catch {}
  try { bonjour.destroy(); } catch {}
  io.close(() => httpServer.close(() => process.exit(0)));
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
