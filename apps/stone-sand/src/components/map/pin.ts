/** Site pin, 32×42 with the tip at (16, 40). */
export const PIN_SVG = `<svg width="32" height="42" viewBox="0 0 32 42" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <path d="M16 1C8 1 2 7 2 15c0 10.5 14 26 14 26s14-15.5 14-26C30 7 24 1 16 1z" fill="#1e3a5f" stroke="#fff" stroke-width="2"/>
    <circle cx="16" cy="15" r="5.5" fill="#fff"/></svg>`;

export const ROUTE_COLOR = '#2563eb';
export const ROAD_START_COLOR = '#d97706';

/** Pill with the route distance, drawn at the middle of the route line. */
export function distanceLabelSvg(text: string): { svg: string; width: number; height: number } {
  const width = Math.ceil(text.length * 7.4) + 18;
  const height = 24;
  const safe = text.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
    <rect x="1" y="1" width="${width - 2}" height="${height - 2}" rx="11" fill="${ROUTE_COLOR}" stroke="#fff" stroke-width="2"/>
    <text x="${width / 2}" y="16.5" text-anchor="middle" font-family="'Noto Sans Thai', system-ui, sans-serif" font-size="12.5" font-weight="700" fill="#fff">${safe}</text></svg>`;
  return { svg, width, height };
}
