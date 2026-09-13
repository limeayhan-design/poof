/**
 * Persistent local identity for this PWA install.
 * Stored in localStorage — cleared if the user wipes site data.
 */
const ID_KEY   = 'poof.deviceId';
const NAME_KEY = 'poof.deviceName';

function generateUuid() {
  if (globalThis.crypto?.randomUUID) return crypto.randomUUID();
  // Fallback for very old browsers.
  const b = new Uint8Array(16);
  crypto.getRandomValues(b);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const hex = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

// iPad/iPhone Safari récent renvoie une UA "Mac" en mode Desktop.
// Détection fiable : UA Mac + maxTouchPoints > 1 (Mac desktop = 0 touch points).
function isIOSDevice() {
  const ua = navigator.userAgent || '';
  if (/iPhone|iPad|iPod/i.test(ua)) return true;
  if (/Mac/i.test(ua) && (navigator.maxTouchPoints > 1 || 'ontouchstart' in window)) return true;
  return false;
}

function guessDefaultName() {
  const ua = navigator.userAgent || '';
  const isTouch = matchMedia?.('(hover: none)').matches ?? false;
  if (isIOSDevice()) {
    // Distingue iPhone vs iPad via viewport (iPad ≥ 768px min-side)
    return (Math.min(screen.width, screen.height) >= 768) ? 'iPad' : 'iPhone';
  }
  if (/Mac/i.test(ua))     return isTouch ? 'Mac' : 'MacBook';
  if (/Windows/i.test(ua)) return isTouch ? 'Windows Tablet' : 'Windows PC';
  if (/CrOS/i.test(ua))    return 'Chromebook';
  if (/Linux/i.test(ua))   return isTouch ? 'Linux Tablet' : 'Linux PC';
  if (/Android/i.test(ua)) return /Tablet|SM-T/i.test(ua) ? 'Android Tablet' : 'Android Phone';
  return 'Browser';
}

function guessPlatform() {
  const ua = navigator.userAgent || '';
  if (isIOSDevice())       return 'ios';
  if (/Mac/i.test(ua))     return 'macos';
  if (/Windows/i.test(ua)) return 'windows';
  if (/CrOS/i.test(ua))    return 'chromeos';
  if (/Linux/i.test(ua))   return 'linux';
  if (/Android/i.test(ua)) return 'android';
  return 'web';
}

export const DeviceIdentity = {
  get deviceId() {
    let id = localStorage.getItem(ID_KEY);
    if (!id) {
      id = generateUuid();
      localStorage.setItem(ID_KEY, id);
    }
    return id;
  },

  get name() {
    return localStorage.getItem(NAME_KEY) || guessDefaultName();
  },
  set name(v) {
    const trimmed = String(v || '').trim();
    if (!trimmed) localStorage.removeItem(NAME_KEY);
    else localStorage.setItem(NAME_KEY, trimmed);
  },

  get hasCustomName() { return !!localStorage.getItem(NAME_KEY); },
  get suggestedName() { return guessDefaultName(); },

  platform: guessPlatform(),
};
