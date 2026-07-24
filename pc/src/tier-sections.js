// Tier-specific home sections — mirrors iOS TierSection{Premium,Family,Devium,Business}.
// Injected above the drop zone when a paid tier is active.
//
// Each renderer takes `(root, ctx)` where root is the container and ctx exposes:
//   - session state (peers, isRTCConnected, receivedFiles)
//   - callbacks: pushClipboard, openFolderPicker, openRemoteFiles, openScreenMirror,
//     openFeaturePreview({ icon, title, tagline, description, status })
//   - deviceName: this device's display name
//
// Layouts, icons, titles, subtitles and copy match iOS one-to-one.

import { TierMeta } from './tier.js';

const svg = {
  sparkles: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1"/></svg>',
  house: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 11l9-8 9 8v9a2 2 0 0 1-2 2h-4v-6H9v6H5a2 2 0 0 1-2-2z"/></svg>',
  terminal: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 17l6-6-6-6M12 19h8"/></svg>',
  building: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="8" height="16"/><rect x="13" y="9" width="8" height="12"/><path d="M6 9h2M6 13h2M6 17h2M16 13h2M16 17h2"/></svg>',
  clipboard: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="8" y="4" width="8" height="4" rx="1"/><path d="M8 6H5a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-3"/></svg>',
  folder: '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>',
  screen: '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="14" height="10" rx="2"/><rect x="8" y="10" width="14" height="10" rx="2"/></svg>',
  drive: '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="6" rx="2"/><rect x="3" y="14" width="18" height="6" rx="2"/><circle cx="7" cy="7" r="1"/><circle cx="7" cy="17" r="1"/></svg>',
  eye: '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8S1 12 1 12z"/><circle cx="12" cy="12" r="3"/></svg>',
  arrowUp: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 16V8M8 12l4-4 4 4"/></svg>',
  chevronRight: '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l6 6-6 6"/></svg>',
  personPlus: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M20 8v6M17 11h6"/></svg>',
  broadcast: '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="16" height="10" rx="2"/><path d="M8 20l4-4 4 4"/></svg>',
  lock: '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>',
  grid: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>',
  key: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="15" r="4"/><path d="M10.8 12.2L21 2M17 6l3 3M15 8l3 3"/></svg>',
  plane: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 16v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1L15 22v-1.5L13 19v-5.5z"/></svg>',
  copy: '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>',
  circlePlus: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/></svg>',
  magnify: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="12" height="14" rx="1"/><path d="M6 8h6M6 11h4M6 14h6"/><circle cx="17" cy="17" r="3"/><path d="M19.5 19.5L22 22"/></svg>',
  paint: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3a9 9 0 0 0 0 18c1.5 0 2-1 2-2 0-.5-.5-1-.5-1.5s.5-1.5 1.5-1.5H18a3 3 0 0 0 3-3 9 9 0 0 0-9-9z"/><circle cx="7.5" cy="10.5" r="1"/><circle cx="12" cy="7" r="1"/><circle cx="16.5" cy="10.5" r="1"/></svg>',
  people: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></svg>',
};

function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function initials(name) {
  const parts = String(name || '').trim().split(/\s+/).slice(0, 2);
  const letters = parts.map((p) => p[0] || '').join('');
  return (letters || String(name || '').slice(0, 2)).toUpperCase();
}

function relative(date) {
  const s = Math.max(0, Math.floor((Date.now() - new Date(date).getTime()) / 1000));
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}

function iconForFile(name) {
  const ext = String(name || '').split('.').pop().toLowerCase();
  if (['jpg', 'jpeg', 'png', 'heic', 'gif', 'webp'].includes(ext)) return '🖼';
  if (['mov', 'mp4', 'm4v'].includes(ext)) return '🎞';
  if (ext === 'pdf') return '📄';
  if (['zip', 'rar', '7z'].includes(ext)) return '🗜';
  if (['mp3', 'm4a', 'wav'].includes(ext)) return '🎵';
  return '📄';
}

function tile({ icon, title, subtitle, status = 'available', accent }) {
  const dot = status !== 'available'
    ? `<span class="ts-tile-dot" style="background:${status === 'coming-soon' ? '#8B95A7' : accent}"></span>`
    : '';
  return `
    <button class="ts-tile" data-tile="${esc(title)}" style="--tier-accent:${accent}">
      <span class="ts-tile-icon">${icon}</span>
      <span class="ts-tile-text">
        <span class="ts-tile-title">${esc(title)}${dot}</span>
        <span class="ts-tile-sub">${esc(subtitle)}</span>
      </span>
    </button>
  `;
}

function pill(status, accent) {
  if (status === 'available') return '';
  const label = status === 'coming-soon' ? 'Soon' : 'Preview';
  return `<span class="ts-pill" style="color:${accent};border-color:${accent}55;background:${accent}22">${label}</span>`;
}

// ── Premium ────────────────────────────────────────────────────────────

function renderPremium(root, ctx) {
  const accent = TierMeta.premium.accent;
  const clipReady = ctx.isRTCConnected;
  const mirrorLive = ctx.isBroadcasting;
  root.innerHTML = `
    <div class="ts-header">
      <span class="ts-header-icon" style="color:${accent}">${svg.sparkles}</span>
      <span class="ts-header-title">Power tools</span>
      <span class="ts-header-badge" style="color:${accent}">Premium</span>
    </div>

    <button class="ts-row" data-action="clipboard" style="--tier-accent:${accent}">
      <span class="ts-row-icon" style="color:${accent};background:${accent}28">${svg.clipboard}</span>
      <span class="ts-row-body">
        <span class="ts-row-title-line">
          <span class="ts-row-title">Universal Clipboard</span>
          <span class="ts-row-dot" style="background:${clipReady ? '#3FBF7F' : '#8B95A7'}"></span>
          <span class="ts-row-status">${clipReady ? 'Ready · click to push' : 'Waiting'}</span>
        </span>
        <span class="ts-row-sub">Text, images, and files across every device</span>
      </span>
      <span class="ts-row-arrow" style="color:${clipReady ? accent : '#8B95A7'}">${svg.arrowUp}</span>
    </button>

    <div class="ts-grid-2">
      ${tile({ icon: svg.folder, title: 'Folder Drop', subtitle: 'Any size', accent })}
      ${tile({ icon: svg.screen, title: 'Screen Mirror', subtitle: mirrorLive ? 'Live · tap to stop' : '1-tap to any device', accent })}
    </div>
    <div class="ts-grid-2">
      ${tile({ icon: svg.drive, title: 'Remote Files', subtitle: 'Browse peer', accent })}
      ${tile({ icon: svg.eye,   title: 'Read receipts', subtitle: 'Sent · Delivered · Seen', accent })}
    </div>
  `;

  root.querySelector('[data-action="clipboard"]')?.addEventListener('click', () => {
    if (ctx.isRTCConnected) ctx.pushClipboard();
    else ctx.openFeaturePreview({
      icon: '📋', title: 'Universal Clipboard', tagline: 'Copy anywhere, paste everywhere',
      status: 'available', accent,
      description: 'Copy text or an image, then click this tile — Poof pushes it to your paired device instantly. Connect a device from the gear icon to enable it.',
    });
  });
  root.querySelector('[data-tile="Folder Drop"]')?.addEventListener('click', () => {
    if (ctx.openFolderPicker) ctx.openFolderPicker();
    else ctx.openFeaturePreview({
      icon: '📁', title: 'Folder Drop', tagline: 'Send an entire folder in one drop',
      status: 'available', accent,
      description: 'Pick a folder. Poof enumerates every file inside and sends them one after the other, keeping the structure intact.',
    });
  });
  root.querySelector('[data-tile="Screen Mirror"]')?.addEventListener('click', () => {
    if (ctx.isRTCConnected) ctx.openScreenMirror();
    else ctx.openFeaturePreview({
      icon: '🖥', title: 'Screen Mirror', tagline: 'Cast your screen anywhere',
      status: 'available', accent,
      description: 'Push this screen to a paired device at ~10 FPS. Fully P2P — the frames flow through the encrypted WebRTC link, never a server. Connect a device first, then reopen this tile.',
    });
  });
  root.querySelector('[data-tile="Remote Files"]')?.addEventListener('click', () => ctx.openRemoteFiles());
  root.querySelector('[data-tile="Read receipts"]')?.addEventListener('click', () => ctx.openFeaturePreview({
    icon: '👁', title: 'Read receipts', tagline: 'Know when your file lands',
    status: 'available', accent,
    description: 'Every file you send now shows a receipt: Sent when it left this device, Delivered when the peer wrote it to disk, Seen when the peer opened the preview.',
  }));
}

// ── Family ─────────────────────────────────────────────────────────────

function renderFamily(root, ctx) {
  const accent = TierMeta.family.accent;
  const glow = TierMeta.family.glow;
  const peers = ctx.peers || [];
  const colors = ['#FF7A9C', '#5B8BFF', '#8B7EFF', '#3FBF7F', '#FFBF3C'];
  const onlineCount = peers.filter((p) => ctx.isPeerOnline?.(p.id)).length;

  const membersHTML = peers.length === 0
    ? `
      <button class="ts-row" data-action="invite-family" style="--tier-accent:${accent}">
        <span class="ts-row-icon" style="color:${accent};background:${accent}24">${svg.personPlus}</span>
        <span class="ts-row-body">
          <span class="ts-row-title">Invite your family</span>
          <span class="ts-row-sub">Pair the first device to get started</span>
        </span>
        <span class="ts-row-arrow" style="color:#8B95A7">${svg.chevronRight}</span>
      </button>
    `
    : `
      <div class="ts-members">
        ${peers.map((p, i) => `
          <div class="ts-member">
            <div class="ts-member-avatar" style="background:${colors[i % colors.length]}">
              ${esc(initials(p.name))}
              <span class="ts-member-online" style="background:${ctx.isPeerOnline?.(p.id) ? '#3FBF7F' : '#8B95A7'}"></span>
            </div>
            <div class="ts-member-name">${esc(p.name)}</div>
          </div>
        `).join('')}
      </div>
    `;

  const recentHTML = (ctx.receivedFiles || []).slice(0, 2).map((f) => `
    <div class="ts-recent">
      <span class="ts-recent-icon" style="color:${accent};background:${accent}22">${iconForFile(f.name)}</span>
      <span class="ts-recent-body">
        <span class="ts-recent-name">${esc(f.name)}</span>
        <span class="ts-recent-time">${relative(f.date || Date.now())}</span>
      </span>
    </div>
  `).join('');

  root.innerHTML = `
    <div class="ts-header">
      <span class="ts-header-icon" style="color:${accent}">${svg.house}</span>
      <span class="ts-header-title">Family Room</span>
      <span class="ts-header-badge" style="color:${peers.length ? accent : '#8B95A7'}">
        ${peers.length === 0 ? 'Empty' : `${onlineCount} online`}
      </span>
    </div>

    ${membersHTML}
    ${recentHTML ? `<div class="ts-recent-list">${recentHTML}</div>` : ''}

    <button class="ts-row" data-action="family-drop" style="--tier-accent:${accent};border:1px solid ${accent}5A">
      <span class="ts-row-icon" style="background:linear-gradient(135deg,${accent},${glow});color:#fff">${svg.broadcast}</span>
      <span class="ts-row-body">
        <span class="ts-row-title-line">
          <span class="ts-row-title">Drop for family</span>
          ${pill('preview', accent)}
        </span>
        <span class="ts-row-sub">Everyone receives instantly</span>
      </span>
      <span class="ts-row-arrow" style="color:#8B95A7">${svg.chevronRight}</span>
    </button>

    <button class="ts-slim" data-action="kid-controls" style="--tier-accent:${accent}">
      <span class="ts-slim-icon">${svg.lock}</span>
      <span class="ts-slim-title">Kid controls</span>
      <span class="ts-slim-status">Coming soon</span>
      <span class="ts-slim-arrow">${svg.chevronRight}</span>
    </button>
  `;

  root.querySelector('[data-action="invite-family"]')?.addEventListener('click', () => ctx.openFeaturePreview({
    icon: '👨‍👩‍👧', title: 'Invite your family', tagline: 'Pair phones, tablets, and laptops',
    status: 'available', accent,
    description: 'Click the gear icon at the top right and pair a device. Your family appears here with live online status and instant broadcast.',
  }));
  root.querySelector('[data-action="family-drop"]')?.addEventListener('click', () => ctx.openFeaturePreview({
    icon: '📣', title: 'Drop for family', tagline: 'Broadcast to everyone at once',
    status: 'preview', accent,
    description: peers.length > 0
      ? 'Send a photo, video, or file and every paired family member gets it instantly. One tap, everywhere. Rolling out next update.'
      : 'Pair at least one family device first, then this becomes a one-tap broadcast to everyone.',
  }));
  root.querySelector('[data-action="kid-controls"]')?.addEventListener('click', () => ctx.openFeaturePreview({
    icon: '🛡', title: 'Kid controls', tagline: 'Safe sharing for younger family',
    status: 'coming-soon', accent,
    description: "Approve or block incoming files before they land on your kid's device. Schedule quiet hours, review activity, and lock sensitive folders.",
  }));
}

// ── Devium ─────────────────────────────────────────────────────────────

function renderDevium(root, ctx) {
  const accent = TierMeta.devium.accent;
  const peers = ctx.peers || [];
  const firstSlug = peers[0]?.name?.toLowerCase().replace(/\s+/g, '-') || '<peer>';
  const cliCmd = `poof send report.zip ${firstSlug}`;

  const multiDrop = peers.length === 0
    ? `
      <div class="ts-multidrop-empty" style="background:${accent}14">
        <span style="color:${accent}">${svg.circlePlus}</span>
        <span>Pair a device to fill this grid</span>
      </div>
    `
    : `
      <div class="ts-multidrop-grid">
        ${peers.map((p) => {
          const online = ctx.isPeerOnline?.(p.id);
          return `
            <div class="ts-multidrop-cell" style="background:${accent}${online ? '24' : '12'}">
              <span style="color:${online ? accent : '#8B95A7'}">${online ? '☑' : '☐'}</span>
              <span class="ts-multidrop-name">${esc(p.name)}</span>
            </div>
          `;
        }).join('')}
      </div>
    `;

  root.innerHTML = `
    <div class="ts-header">
      <span class="ts-header-icon" style="color:${accent}">${svg.terminal}</span>
      <span class="ts-header-title">Dev cockpit</span>
      <span class="ts-header-badge" style="color:${accent}">Devium</span>
    </div>

    <button class="ts-card" data-action="multi-drop" style="--tier-accent:${accent}">
      <div class="ts-card-head">
        <span class="ts-card-title-line">
          <span class="ts-card-title">Multi-Drop</span>
          ${pill('preview', accent)}
        </span>
        <span class="ts-card-sub">${peers.length === 0 ? 'No devices paired' : `Broadcast to ${peers.length} device${peers.length === 1 ? '' : 's'}`}</span>
      </div>
      ${multiDrop}
    </button>

    <div class="ts-cli" data-action="cli">
      <div class="ts-cli-head">
        <span class="ts-cli-dot" style="background:#FF5C52"></span>
        <span class="ts-cli-dot" style="background:#FFBF3C"></span>
        <span class="ts-cli-dot" style="background:#3FD067"></span>
        <span class="ts-cli-tag">CLI · Preview</span>
      </div>
      <div class="ts-cli-line">
        <span class="ts-cli-prompt" style="color:${accent}">$</span>
        <span class="ts-cli-cmd">${esc(cliCmd)}</span>
        <button class="ts-cli-copy" data-copy="${esc(cliCmd)}" title="Copy">${svg.copy}</button>
      </div>
    </div>

    <button class="ts-row" data-action="api-key" style="--tier-accent:${accent}">
      <span class="ts-row-icon" style="color:${accent};background:${accent}28">${svg.key}</span>
      <span class="ts-row-body">
        <span class="ts-row-title-line">
          <span class="ts-row-title">API key</span>
          ${pill('preview', accent)}
        </span>
        <span class="ts-row-sub"><code>pk_live_••••••4d92</code></span>
      </span>
      <span class="ts-row-arrow" style="color:#8B95A7">${svg.chevronRight}</span>
    </button>

    <button class="ts-row" data-action="airgap" style="--tier-accent:${accent}">
      <span class="ts-row-icon" style="color:${accent};background:${accent}20">${svg.plane}</span>
      <span class="ts-row-body">
        <span class="ts-row-title-line">
          <span class="ts-row-title">Air-gapped mode</span>
          ${pill('preview', accent)}
        </span>
        <span class="ts-row-sub">Internet enabled</span>
      </span>
      <span class="ts-row-toggle"><span class="ts-toggle-off"></span></span>
    </button>
  `;

  root.querySelector('[data-action="multi-drop"]')?.addEventListener('click', () => ctx.openFeaturePreview({
    icon: '🔲', title: 'Multi-Drop', tagline: 'Broadcast a file to N devices at once',
    status: peers.length ? 'preview' : 'available', accent,
    description: peers.length
      ? `You have ${peers.length} paired device${peers.length === 1 ? '' : 's'} ready. Multi-Drop broadcasts your next transfer to all of them in parallel. Rolling out.`
      : 'Pair a few devices from the gear menu, then send one file to all of them in a single click. WebRTC peer-to-peer, no cloud relay.',
  }));
  root.querySelector('[data-action="cli"]')?.addEventListener('click', () => ctx.openFeaturePreview({
    icon: '⌨', title: 'Poof CLI', tagline: 'Scriptable transfers from your terminal',
    status: 'coming-soon', accent,
    description: '`poof send`, `poof pair`, `poof receive`. Ship files from CI jobs, cron tasks, or your build pipeline. Same E2E encryption, zero cloud.',
  }));
  root.querySelector('[data-copy]')?.addEventListener('click', (e) => {
    e.stopPropagation();
    navigator.clipboard.writeText(cliCmd);
    ctx.toast?.('Command copied');
  });
  root.querySelector('[data-action="api-key"]')?.addEventListener('click', () => ctx.openFeaturePreview({
    icon: '🔑', title: 'API key', tagline: 'Programmatic access to Poof transfers',
    status: 'coming-soon', accent,
    description: 'Generate keys for scripts, servers, and integrations. Rate-limited, revocable, scoped. Everything stays peer-to-peer — the key just authenticates you.',
  }));
  root.querySelector('[data-action="airgap"]')?.addEventListener('click', () => ctx.openFeaturePreview({
    icon: '✈', title: 'Air-gapped mode', tagline: 'LAN-only transfers, zero internet',
    status: 'coming-soon', accent,
    description: 'Force every transfer through your local network — no signaling server, no STUN, no cloud metadata. Perfect for sensitive environments.',
  }));
}

// ── Business ───────────────────────────────────────────────────────────

function renderBusiness(root, ctx) {
  const accent = TierMeta.business.accent;
  const glow = TierMeta.business.glow;
  const peers = ctx.peers || [];
  const memberCount = peers.length + 1;
  const colors = ['#8FA3B5', '#5B8BFF', '#8B7EFF', '#3FBF7F', '#FF7A9C'];
  const workspaceName = `${ctx.deviceName || 'Your'}'s workspace`;

  const auditHTML = (ctx.receivedFiles || []).length === 0
    ? `
      <div class="ts-audit-empty">
        <span>⏲</span>
        <span>No activity yet — your transfers appear here in real time</span>
      </div>
    `
    : `
      <ul class="ts-audit-list">
        ${(ctx.receivedFiles || []).slice(0, 3).map((f) => `
          <li>
            <span class="ts-audit-dot" style="background:${accent}"></span>
            <span class="ts-audit-name">Received ${esc(f.name)}</span>
            <span class="ts-audit-time">${relative(f.date || Date.now())}</span>
          </li>
        `).join('')}
      </ul>
    `;

  const teamBubbles = `
    <div class="ts-team-bubbles">
      <div class="ts-bubble">
        <div class="ts-bubble-avatar" style="background:${colors[0]}">${esc(initials(ctx.deviceName || 'Me'))}
          <span class="ts-bubble-online" style="background:#3FBF7F"></span>
        </div>
        <div class="ts-bubble-role">You · Admin</div>
      </div>
      ${peers.map((p, i) => {
        const online = ctx.isPeerOnline?.(p.id);
        const role = i === 0 ? 'Member' : (i === peers.length - 1 && peers.length > 1 ? 'Guest' : 'Member');
        return `
          <div class="ts-bubble">
            <div class="ts-bubble-avatar" style="background:${colors[(i + 1) % colors.length]}">${esc(initials(p.name))}
              <span class="ts-bubble-online" style="background:${online ? '#3FBF7F' : '#8B95A7'}"></span>
            </div>
            <div class="ts-bubble-role">${role}</div>
          </div>
        `;
      }).join('')}
    </div>
  `;

  root.innerHTML = `
    <div class="ts-header">
      <span class="ts-header-icon" style="color:${accent}">${svg.building}</span>
      <span class="ts-header-title">Team command</span>
      <span class="ts-header-badge" style="color:${ctx.isSignalingConnected ? '#3FBF7F' : '#8B95A7'}">
        ${ctx.isSignalingConnected ? '● Online' : '● Offline'}
      </span>
    </div>

    <button class="ts-row" data-action="workspace" style="--tier-accent:${accent}">
      <span class="ts-workspace-logo" style="background:linear-gradient(135deg,${accent},${glow})">P</span>
      <span class="ts-row-body">
        <span class="ts-row-title-line">
          <span class="ts-row-title">${esc(workspaceName)}</span>
          ${pill('preview', accent)}
        </span>
        <span class="ts-row-sub">${memberCount} member${memberCount === 1 ? '' : 's'} · Enterprise plan</span>
      </span>
      <span class="ts-row-arrow" style="color:#8B95A7">${svg.chevronRight}</span>
    </button>

    <button class="ts-card" data-action="live-audit" style="--tier-accent:${accent}">
      <div class="ts-card-head">
        <span class="ts-card-title-line">
          <span style="color:${accent}">${svg.magnify}</span>
          <span class="ts-card-title">Live audit</span>
        </span>
        <span class="ts-card-dot" style="background:${ctx.isSignalingConnected ? '#3FBF7F' : '#8B95A7'}"></span>
      </div>
      ${auditHTML}
    </button>

    <div class="ts-card">
      <div class="ts-card-head">
        <span class="ts-card-title">Team</span>
        <button class="ts-card-cta" data-action="manage-team" style="color:${accent}">Manage</button>
      </div>
      ${peers.length === 0
        ? `<div class="ts-team-empty" style="background:${accent}14"><span style="color:${accent}">${svg.personPlus}</span>Invite your first teammate</div>`
        : teamBubbles}
    </div>

    <button class="ts-row" data-action="branding" style="--tier-accent:${accent}">
      <span class="ts-row-icon" style="color:${accent};background:${accent}22">${svg.paint}</span>
      <span class="ts-row-body">
        <span class="ts-row-title-line">
          <span class="ts-row-title">Custom branding</span>
          ${pill('preview', accent)}
        </span>
        <span class="ts-row-sub">Your logo · your colors · your domain</span>
      </span>
      <span class="ts-row-arrow" style="color:#8B95A7">${svg.chevronRight}</span>
    </button>
  `;

  root.querySelector('[data-action="workspace"]')?.addEventListener('click', () => ctx.openFeaturePreview({
    icon: '🏢', title: 'Workspace', tagline: 'Rename, invite, and manage',
    status: 'coming-soon', accent,
    description: 'Create a shared organization name, invite teammates by email or link, and assign roles. All transfers stay peer-to-peer — the workspace is just identity.',
  }));
  root.querySelector('[data-action="live-audit"]')?.addEventListener('click', () => ctx.openFeaturePreview({
    icon: '🔍', title: 'Live audit', tagline: 'Every transfer, every device, real time',
    status: 'available', accent,
    description: 'Track file sends, receives, and device pairings across your team as they happen. Export to CSV for compliance. On-device — nothing shared with us.',
  }));
  root.querySelector('[data-action="manage-team"]')?.addEventListener('click', (e) => {
    e.stopPropagation();
    ctx.openFeaturePreview({
      icon: '👥', title: 'Team management', tagline: 'Invite, revoke, assign roles',
      status: 'coming-soon', accent,
      description: 'Bulk invite by email, set per-user roles (Admin/Member/Guest), revoke access instantly. All identity flows through your workspace.',
    });
  });
  root.querySelector('[data-action="branding"]')?.addEventListener('click', () => ctx.openFeaturePreview({
    icon: '🎨', title: 'Custom branding', tagline: 'Your logo, your colors, your domain',
    status: 'coming-soon', accent,
    description: 'White-label the send/receive UI with your company logo and colors. Route transfers through your own custom domain. Enterprise-only.',
  }));
}

// ── Dispatcher ─────────────────────────────────────────────────────────

export function renderTierSection(tier, root, ctx) {
  root.innerHTML = '';
  root.hidden = false;
  root.dataset.tier = tier;
  switch (tier) {
    case 'standard': root.hidden = true; break;
    case 'premium':  renderPremium(root, ctx); break;
    case 'family':   renderFamily(root, ctx); break;
    case 'devium':   renderDevium(root, ctx); break;
    case 'business': renderBusiness(root, ctx); break;
    default:         root.hidden = true;
  }
}
