// Poof downloads — highlight le bouton correspondant à l'OS du visiteur.
// Simple, sans dépendance. La détection est cosmétique : tous les boutons
// restent cliquables (l'user peut vouloir télécharger pour un autre device).

function detectOS() {
  const ua = (navigator.userAgent || '').toLowerCase();
  const platform = (navigator.platform || '').toLowerCase();
  if (/iphone|ipad|ipod/.test(ua)) return 'ios';
  if (/android/.test(ua)) return 'android';
  if (platform.startsWith('mac') || ua.includes('mac')) return 'mac';
  if (platform.startsWith('win') || ua.includes('windows')) return 'windows';
  if (platform.startsWith('linux') || ua.includes('linux')) return 'linux';
  return null;
}

const os = detectOS();
if (os) {
  const card = document.querySelector(`.dl-card[data-os="${os}"]`);
  if (card) {
    card.style.background = 'rgba(255, 255, 255, 0.18)';
    card.style.borderColor = 'rgba(255, 255, 255, 0.42)';
    card.style.boxShadow = '0 12px 28px rgba(0, 0, 0, 0.20), inset 0 1px 0 rgba(255, 255, 255, 0.20)';
    // Remet le highlight en tête de liste sans casser le DOM.
    card.parentElement.prepend(card);
  }
}
