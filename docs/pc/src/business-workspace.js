// Business tier: on-device workspace store (mirror of ios BusinessWorkspace).
// Name, logo, accent color, per-peer role. All persisted in localStorage.

const KEY_NAME  = 'poof.workspace.name';
const KEY_LOGO  = 'poof.workspace.logo';
const KEY_COLOR = 'poof.workspace.color';
const KEY_ROLES = 'poof.workspace.roles';

export const COLOR_PRESETS = ['#5B8BFF', '#8B7EFF', '#3FBF7F', '#FF7A9C', '#FFBF3C', '#FF5C52'];
export const DEFAULT_COLOR = '#5B8BFF';
export const DEFAULT_LOGO  = 'P';
export const ROLES = ['Admin', 'Member', 'Guest'];

export function getName()  { return localStorage.getItem(KEY_NAME) || ''; }
export function getLogo()  { return localStorage.getItem(KEY_LOGO) || DEFAULT_LOGO; }
export function getColor() { return localStorage.getItem(KEY_COLOR) || DEFAULT_COLOR; }

export function setName(v) {
  const t = String(v || '').trim();
  if (t) localStorage.setItem(KEY_NAME, t);
  else localStorage.removeItem(KEY_NAME);
}
export function setLogo(v) {
  const t = String(v || '').trim().slice(0, 2);
  localStorage.setItem(KEY_LOGO, t || DEFAULT_LOGO);
}
export function setColor(v) {
  localStorage.setItem(KEY_COLOR, v || DEFAULT_COLOR);
}

export function getRoles() {
  try { return JSON.parse(localStorage.getItem(KEY_ROLES) || '{}'); }
  catch { return {}; }
}
export function getRole(peerId) { return getRoles()[peerId] || 'Member'; }
export function setRole(peerId, role) {
  const r = getRoles();
  r[peerId] = role;
  localStorage.setItem(KEY_ROLES, JSON.stringify(r));
}

export function workspaceState() {
  return { name: getName(), logo: getLogo(), color: getColor(), roles: getRoles() };
}
