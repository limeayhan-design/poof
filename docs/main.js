// ─────────── OS detection ───────────
function detectOS() {
  const ua = navigator.userAgent.toLowerCase();
  const platform = (navigator.platform || '').toLowerCase();
  if (/iphone|ipad|ipod/.test(ua)) return 'ios';
  if (platform.startsWith('mac') || ua.includes('mac')) return 'mac';
  if (platform.startsWith('win') || ua.includes('windows')) return 'windows';
  if (platform.startsWith('linux') || ua.includes('linux')) return 'linux';
  return 'mac';
}

const osLabels = {
  mac: 'Mac',
  windows: 'Windows',
  linux: 'Linux',
  ios: 'iOS',
};

const os = detectOS();
const heroOSEl = document.getElementById('hero-os');
if (heroOSEl) heroOSEl.textContent = osLabels[os] || 'your OS';

// ─────────── Pricing toggle ───────────
const periodUnits = {
  monthly: '/ month',
  annual: '/ year',
  lifetime: '· one-time',
};

document.querySelectorAll('.toggle-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    const period = btn.dataset.period;
    document.querySelectorAll('.toggle-btn').forEach(b => b.classList.toggle('active', b === btn));
    document.querySelectorAll('.tier-price').forEach(el => {
      const p = el.dataset[period];
      if (p === undefined) return;
      const price = el.querySelector('.price');
      const unit = el.querySelector('.unit');
      const numeric = Number(p);
      if (numeric === 0) {
        price.textContent = '€0';
        unit.textContent = '/ forever';
      } else {
        price.textContent = `€${p}`;
        unit.textContent = periodUnits[period];
      }
    });

    // Show/hide iOS note only on monthly
    const iosNote = document.querySelector('.tier-premium .ios-note');
    if (iosNote) iosNote.style.display = period === 'monthly' ? '' : 'none';
  });
});

// ─────────── Header scroll state ───────────
const header = document.querySelector('.site-header');
window.addEventListener('scroll', () => {
  if (header) header.classList.toggle('scrolled', window.scrollY > 20);
}, { passive: true });

// ─────────── Reveal on scroll ───────────
const io = new IntersectionObserver((entries) => {
  entries.forEach(e => {
    if (e.isIntersecting) {
      e.target.classList.add('visible');
      io.unobserve(e.target);
    }
  });
}, { threshold: 0.1, rootMargin: '0px 0px -80px 0px' });

document.querySelectorAll('.section, .hero-inner').forEach(el => {
  el.classList.add('reveal');
  io.observe(el);
});
