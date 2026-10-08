import { useId } from 'react';

const MICRO = 'PIRASIT CONSTRUCTION MATERIALS • พีรสิทธิ์ วัสดุก่อสร้าง • ';

/**
 * Anti-copy layers drawn over the A4 sheet: a tiled diagonal watermark with the document number
 * and a microtext frame that turns into a plain line when photocopied or re-typed.
 */
export default function BillSecurity({ docNo, label }: { docNo: string; label: string }) {
  const uid = useId().replace(/[^a-zA-Z0-9]/g, '');
  const pattern = `wm-${uid}`;
  const frame = `mf-${uid}`;

  return (
    <svg
      className="pointer-events-none absolute inset-0 h-full w-full"
      viewBox="0 0 210 297"
      preserveAspectRatio="none"
      aria-hidden
    >
      <defs>
        <pattern id={pattern} width="70" height="38" patternUnits="userSpaceOnUse" patternTransform="rotate(-32)">
          <text x="0" y="12" fontSize="4.2" fontFamily="'Noto Sans Thai', sans-serif" fontWeight={700} fill="#1e3a5f" fillOpacity="0.07">
            พีรสิทธิ์ วัสดุก่อสร้าง
          </text>
          <text x="35" y="31" fontSize="3.2" fontFamily="monospace" fill="#1e3a5f" fillOpacity="0.07">
            {docNo}
          </text>
        </pattern>
        <path id={frame} d="M 5,5 H 205 V 292 H 5 Z" />
      </defs>
      <rect width="210" height="297" fill={`url(#${pattern})`} />
      <text
        x="105"
        y="160"
        textAnchor="middle"
        fontSize="30"
        fontFamily="'Noto Sans Thai', sans-serif"
        fontWeight={800}
        fill="#1e3a5f"
        fillOpacity="0.035"
        transform="rotate(-32 105 160)"
      >
        {label}
      </text>
      <text fontSize="1.35" fontFamily="'Noto Sans Thai', sans-serif" fill="#1e3a5f" fillOpacity="0.55" letterSpacing="0.05">
        <textPath href={`#${frame}`}>{MICRO.repeat(26)}</textPath>
      </text>
    </svg>
  );
}
