// Tier model — mirrors iOS PoofTier.
// Persisted in localStorage. Users can change tier via PricingSheet (later)
// or via `?tier=premium` URL param for testing.

const KEY = 'poof.tier';

export const PoofTier = Object.freeze({
  Standard: 'standard',       // Free — 2 devices, 2 GB per transfer
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
