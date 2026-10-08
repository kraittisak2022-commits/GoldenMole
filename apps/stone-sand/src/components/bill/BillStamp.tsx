import { useId } from 'react';

interface Props {
  /** Middle line, e.g. "ชำระเงินแล้ว" */
  label?: string;
  sublabel?: string;
  size?: number;
  rotate?: number;
}

/** Round rubber-stamp style company seal (SVG, prints in color). */
export default function BillStamp({ label = 'พีรสิทธิ์', sublabel = 'วัสดุก่อสร้าง', size = 128, rotate = -12 }: Props) {
  const uid = useId().replace(/[^a-zA-Z0-9]/g, '');
  const top = `st-top-${uid}`;
  const bottom = `st-bot-${uid}`;
  const rough = `st-rough-${uid}`;
  const color = 'var(--color-stamp)';

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 200 200"
      style={{ transform: `rotate(${rotate}deg)`, opacity: 0.88, mixBlendMode: 'multiply' }}
      aria-label="ตราประทับบริษัท"
      role="img"
    >
      <defs>
        <path id={top} d="M 30,100 A 70,70 0 0 1 170,100" />
        <path id={bottom} d="M 24,100 A 76,76 0 0 0 176,100" />
        <filter id={rough} x="-5%" y="-5%" width="110%" height="110%">
          <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="7" result="noise" />
          <feDisplacementMap in="SourceGraphic" in2="noise" scale="2.2" />
        </filter>
      </defs>
      <g filter={`url(#${rough})`} fill="none" stroke={color}>
        <circle cx="100" cy="100" r="95" strokeWidth="5" />
        <circle cx="100" cy="100" r="86" strokeWidth="1.5" />
        <circle cx="100" cy="100" r="52" strokeWidth="1.5" />
        <g fill={color} stroke="none" fontFamily="'Noto Sans Thai', sans-serif" fontWeight={700}>
          <text fontSize="15.5" letterSpacing="0.5">
            <textPath href={`#${top}`} startOffset="50%" textAnchor="middle">
              ห้างหุ้นส่วนจำกัด พีรสิทธิ์ วัสดุก่อสร้าง
            </textPath>
          </text>
          <text fontSize="10.5" letterSpacing="1.4">
            <textPath href={`#${bottom}`} startOffset="50%" textAnchor="middle" dominantBaseline="hanging">
              PIRASIT CONSTRUCTION MATERIALS
            </textPath>
          </text>
          <text x="22" y="104" fontSize="12">★</text>
          <text x="166" y="104" fontSize="12">★</text>
          <text x="100" y="97" fontSize={label.length > 9 ? 15 : 19} textAnchor="middle">
            {label}
          </text>
          <text x="100" y="118" fontSize="12" textAnchor="middle" fontWeight={600}>
            {sublabel}
          </text>
        </g>
      </g>
    </svg>
  );
}
