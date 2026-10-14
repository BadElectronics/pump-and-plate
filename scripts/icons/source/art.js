// Pump and Plate icon, redrawn as vectors, plus three variants.
// Everything is drawn on a 1024 x 1024 canvas.
const RED = '#e53935', INK = '#141414', RIM = '#6f6f6f', FACE = '#262626', SPOKE = '#3a3a3a', STEEL = '#a4a4a4', TXT = '#f3f3f3';
let uid = 0;

function plate(cx, cy, R, ls = 0.12, o = {}) {
  const id = 'arc' + (uid++);
  const tr = (o.tr || 0.655) * R;  // text radius
  const fs = 0.175 * R * (o.k || 1); // text size
  const lk = o.lk || o.k || 1;     // side-label size factor
  const mode = o.mode || 'full';
  const sw = Math.max(6, R * 0.035);
  const spokes = [45, 135, 225, 315].map(a =>
    `<rect x="${-0.05 * R}" y="${0.34 * R}" width="${0.1 * R}" height="${0.48 * R}" rx="${0.03 * R}" fill="${SPOKE}" stroke="${INK}" stroke-width="${sw * 0.5}" transform="rotate(${a})"/>`).join('');
  // A clockwise circle starting at the top; PUMP sits at the top, PLATE at the bottom (upside down, like a real plate).
  const circ = 2 * Math.PI * tr;
  return `<g transform="translate(${cx} ${cy})">
    <defs><path id="${id}" d="M 0 ${tr} A ${tr} ${tr} 0 1 1 0 ${-tr} A ${tr} ${tr} 0 1 1 0 ${tr}"/>
      <path id="${id}b" d="M 0 ${-tr} A ${tr} ${tr} 0 1 1 0 ${tr} A ${tr} ${tr} 0 1 1 0 ${-tr}"/></defs>
    <circle r="${R}" fill="${RIM}" stroke="${INK}" stroke-width="${sw * 1.3}"/>
    <path d="M ${-R * 0.93 * Math.cos(Math.PI * 0.2)} ${-R * 0.93 * Math.sin(Math.PI * 0.2) + 0.0} A ${R * 0.93} ${R * 0.93} 0 0 1 ${-R * 0.93 * Math.cos(Math.PI * 0.62)} ${-R * 0.93 * Math.sin(Math.PI * 0.62)}"
      fill="none" stroke="#a9a9a9" stroke-width="${R * 0.04}" stroke-linecap="round" opacity=".9"/>
    <circle r="${R * 0.875}" fill="${FACE}" stroke="${INK}" stroke-width="${sw}"/>
    ${spokes}
    <circle r="${R * 0.29}" fill="#3e3e3e" stroke="${INK}" stroke-width="${sw}"/>
    <circle r="${R * 0.215}" fill="#353535" stroke="#2b2b2b" stroke-width="${sw * 0.7}"/>
    <circle r="${R * 0.12}" fill="${RED}" stroke="${INK}" stroke-width="${sw}"/>
    ${mode === 'full' ? `<text font-family="Plate" font-size="${fs}" fill="${TXT}" letter-spacing="${fs * ls}">
      <textPath href="#${id}" startOffset="${circ * 0.5}" text-anchor="middle">PUMP</textPath>
    </text>
    <text font-family="Plate" font-size="${fs}" fill="${TXT}" letter-spacing="${fs * ls}">
      <textPath href="#${id}b" startOffset="${circ * 0.5}" text-anchor="middle">PLATE</textPath>
    </text>
    <g font-family="Plate" font-size="${0.175 * R * lk * 0.98}" fill="${TXT}" text-anchor="middle">
      <text x="${-(o.lx || 0.56) * R}" y="${-0.02 * R * lk}">45</text><text x="${-(o.lx || 0.56) * R}" y="${0.21 * R * lk}">LBS</text>
      <text x="${(o.lx || 0.56) * R}" y="${-0.02 * R * lk}">20.4</text><text x="${(o.lx || 0.56) * R}" y="${0.21 * R * lk}">KGS</text>
    </g>` : ''}
    ${mode === 'big45' ? `<text x="${(o.x45 || 0) * R}" y="${(o.y45 || -0.4) * R}" font-family="Plate" font-size="${(o.f45 || 0.42) * R}" fill="${TXT}" text-anchor="middle">45</text>` : ''}
  </g>`;
}

// Fork drawn 76 wide x 460 tall from its top-left corner, then scaled.
function fork(x, y, s, rot = 0, cx = 38, cy = 230) {
  const sw = 12 / 1;
  return `<g transform="translate(${x} ${y}) rotate(${rot} ${cx * s} ${cy * s}) scale(${s})">
    <path d="M30,170 L46,170 L50,300 Q56,385 54,440 Q53,460 38,460 Q23,460 22,440 Q20,385 26,300 Z" fill="${STEEL}" stroke="${INK}" stroke-width="${sw}" stroke-linejoin="round"/>
    <path d="M2,10 Q2,0 11,0 L65,0 Q74,0 74,10 L74,108 Q74,148 46,174 L30,174 Q2,148 2,108 Z" fill="${STEEL}" stroke="${INK}" stroke-width="${sw}" stroke-linejoin="round"/>
    <rect x="16" y="0" width="9" height="86" fill="${INK}"/><rect x="33.5" y="0" width="9" height="86" fill="${INK}"/><rect x="51" y="0" width="9" height="86" fill="${INK}"/>
  </g>`;
}

// Knife drawn 48 wide x 460 tall.
function knife(x, y, s, rot = 0, cx = 24, cy = 230) {
  const sw = 12;
  return `<g transform="translate(${x} ${y}) rotate(${rot} ${cx * s} ${cy * s}) scale(${s})">
    <rect x="7" y="210" width="34" height="250" rx="17" fill="${STEEL}" stroke="${INK}" stroke-width="${sw}"/>
    <path d="M44,0 L44,214 L4,214 L4,112 Q4,28 44,0 Z" fill="${STEEL}" stroke="${INK}" stroke-width="${sw}" stroke-linejoin="round"/>
    <path d="M30,22 Q14,48 13,112" fill="none" stroke="#c9c9c9" stroke-width="7" stroke-linecap="round"/>
  </g>`;
}

// A 45 lb dumbbell seen from the side, centred on cx, cy, about 560 wide.
function dumbbell(cx, cy, s, rot = 0) {
  const sw = 12;
  const plateR = (x, w, h, label) => `<rect x="${x}" y="${-h / 2}" width="${w}" height="${h}" rx="18" fill="#2a2a2a" stroke="${INK}" stroke-width="${sw}"/>` +
    `<rect x="${x + 10}" y="${-h / 2 + 14}" width="8" height="${h - 28}" rx="4" fill="#4a4a4a"/>` +
    (label ? `<text transform="translate(${x + w / 2 + 2} 0) rotate(${-rot})" font-family="Plate" font-size="54" fill="${TXT}" text-anchor="middle" dominant-baseline="central">${label}</text>` : '');
  const knurl = Array.from({ length: 9 }, (_, i) => `<line x1="${-72 + i * 18}" y1="-16" x2="${-82 + i * 18}" y2="16" stroke="#7d7d7d" stroke-width="5"/>`).join('');
  return `<g transform="translate(${cx} ${cy}) rotate(${rot}) scale(${s})">
    <rect x="-280" y="-26" width="560" height="52" rx="14" fill="${STEEL}" stroke="${INK}" stroke-width="${sw}"/>
    ${plateR(-262, 54, 230, '')}
    ${plateR(-212, 92, 330, '45')}
    <rect x="-122" y="-46" width="30" height="92" rx="8" fill="#8a8a8a" stroke="${INK}" stroke-width="${sw}"/>
    ${plateR(120, 92, 330, '45')}
    ${plateR(208, 54, 230, '')}
    <rect x="92" y="-46" width="30" height="92" rx="8" fill="#8a8a8a" stroke="${INK}" stroke-width="${sw}"/>
    <rect x="-90" y="-22" width="180" height="44" rx="10" fill="#8f8f8f" stroke="${INK}" stroke-width="8"/>
    ${knurl}
  </g>`;
}

const bg = `<rect width="1024" height="1024" fill="${RED}"/>`;

// Each design: the full-bleed square (iPhone) and the content scale for Android's circle.
const DESIGNS = {
  current: { label: 'Current', art: () => bg + plate(512, 512, 340) + fork(74, 285, 1.0) + knife(876, 285, 1.0), android: 0.8 },
  a: { label: 'A: bigger fork and knife', art: () => bg + plate(512, 512, 340) + fork(56, 150, 1.52) + knife(868, 150, 1.52), android: 0.76 },
  b: { label: 'B1: same as now', art: () => bg + plate(512, 512, 410, 0.03) + knife(512 - 24 * 2.16, 512 - 230 * 2.16, 2.16, 45) + fork(512 - 38 * 2.16, 512 - 230 * 2.16, 2.16, -45), android: 0.88 },
  b2: { label: 'B2: big 45 only', art: () => bg + plate(512, 512, 410, 0.03, { mode: 'big45', f45: 0.37, y45: 0.665, x45: 0 }) + knife(512 - 24 * 2.16, 512 - 230 * 2.16, 2.16, 45) + fork(512 - 38 * 2.16, 512 - 230 * 2.16, 2.16, -45), android: 0.88 },
  b3: { label: 'B3: same text, bigger', art: () => bg + plate(512, 512, 410, 0.0, { k: 1.18, tr: 0.655, lk: 1.16, lx: 0.585 }) + knife(512 - 24 * 2.16, 512 - 230 * 2.16, 2.16, 45) + fork(512 - 38 * 2.16, 512 - 230 * 2.16, 2.16, -45), android: 0.88 },
  c: { label: 'C: vertical 45 lb dumbbell', art: () => bg + dumbbell(512, 512, 1.12, 90) + fork(52, 150, 1.52) + knife(872, 150, 1.52), android: 0.76 },
};

function svg(key, size = 1024) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 1024 1024">${DESIGNS[key].art()}</svg>`;
}
// Android: red circle, design scaled into the visible circle.
function svgAndroid(key, size = 1024) {
  const s = DESIGNS[key].android;
  const o = 512 - 512 * s;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 1024 1024">
    <defs><clipPath id="c${key}${uid++}"><circle cx="512" cy="512" r="512"/></clipPath></defs>
    <g clip-path="url(#c${key}${uid - 1})"><rect width="1024" height="1024" fill="${RED}"/><g transform="translate(${o} ${o}) scale(${s})">${DESIGNS[key].art()}</g></g></svg>`;
}
