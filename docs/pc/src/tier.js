// Tier model — mirrors iOS PoofTier.
// Persisted in localStorage. Users can change tier via PricingSheet
// or via `?tier=premium` URL param for testing.

const KEY = 'poof.tier';

export const PoofTier = Object.freeze({
  Standard: 'standard',
  Premium: 'premium',
  Family: 'family',
  Devium: 'devium',
  Business: 'business',
});

export const TierLimits = Object.freeze({
  standard: { maxDevices: 2, maxTransferBytes: 2 * 1024 * 1024 * 1024 },
  premium:  { maxDevices: Infinity, maxTransferBytes: Infinity },
  family:   { maxDevices: Infinity, maxTransferBytes: Infinity },
  devium:   { maxDevices: Infinity, maxTransferBytes: Infinity },
  business: { maxDevices: Infinity, maxTransferBytes: Infinity },
});

// Mirrors PoofTier.swift (displayName / priceLabel / tagline / accent / glow).
export const TierMeta = Object.freeze({
  standard: {
    displayName: 'Standard',
    priceLabel: 'Free forever',
    tagline: 'AirDrop for everyone.',
    accent: '#3FBF7F',
    glow:   '#73DDAB',
  },
  premium: {
    displayName: 'Premium',
    priceLabel: '€4.99 / month',
    tagline: 'Your files. All devices. Everywhere.',
    accent: '#5B8BFF',
    glow:   '#7CA5FF',
  },
  family: {
    displayName: 'Family',
    priceLabel: '€6.99 / month',
    tagline: 'Share with the people you love.',
    accent: '#FF7A9C',
    glow:   '#FFA5BF',
  },
  devium: {
    displayName: 'Devium',
    priceLabel: '€9.99 / month',
    tagline: 'For developers who ship.',
    accent: '#8B7EFF',
    glow:   '#A594FF',
  },
  business: {
    displayName: 'Business',
    priceLabel: '€19.99 / user',
    tagline: 'Poof for teams.',
    accent: '#8FA3B5',
    glow:   '#ADBDCD',
  },
});

export function currentTier() {
  const url = new URL(location.href);
  const q = url.searchParams.get('tier');
  if (q && Object.values(PoofTier).includes(q)) {
    localStorage.setItem(KEY, q);
    return q;
  }
  const stored = localStorage.getItem(KEY);
  return stored && Object.values(PoofTier).includes(stored) ? stored : PoofTier.Standard;
}

export function setTier(tier) {
  if (!Object.values(PoofTier).includes(tier)) return;
  localStorage.setItem(KEY, tier);
  window.dispatchEvent(new CustomEvent('poof-tier-changed', { detail: { tier } }));
}

export function tierLimits(tier = currentTier()) {
  return TierLimits[tier] || TierLimits.standard;
}

export function tierMeta(tier = currentTier()) {
  return TierMeta[tier] || TierMeta.standard;
}
