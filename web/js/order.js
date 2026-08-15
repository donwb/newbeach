/**
 * Per-city board order. The county feed is alphabetical; the board reads
 * north-of-the-inlet ramps in the order a driver meets them. Ramps not
 * listed here sort after the listed ones, alphabetically.
 *
 * (The TRMNL template uses a different, north-to-south order — deliberate,
 * per REQUIREMENTS §12.2. Do not unify.)
 */

const CITY_ORDER = {
  'NEW SMYRNA BEACH': ['BEACHWAY AV', 'CRAWFORD RD', 'FLAGLER AV', '3RD AV', '27TH AV'],
};

export function sortRampsForCity(ramps, city) {
  const order = CITY_ORDER[(city || '').toUpperCase()] || [];
  const rank = (ramp) => {
    const i = order.indexOf((ramp.ramp_name || '').toUpperCase());
    return i === -1 ? order.length : i;
  };
  return [...ramps].sort((a, b) => {
    const d = rank(a) - rank(b);
    if (d !== 0) return d;
    return (a.ramp_name || '').localeCompare(b.ramp_name || '');
  });
}
