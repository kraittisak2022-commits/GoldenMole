interface ExcavatorIconProps {
    size?: number;
    className?: string;
}

/** Stroke excavator silhouette — uses currentColor like lucide icons. */
const ExcavatorIcon = ({ size = 24, className }: ExcavatorIconProps) => (
    <svg
        viewBox="0 0 64 64"
        width={size}
        height={size}
        fill="none"
        stroke="currentColor"
        strokeWidth={3}
        strokeLinecap="round"
        strokeLinejoin="round"
        className={className}
        aria-hidden="true"
    >
        {/* Tracks */}
        <rect x="14" y="44" width="44" height="12" rx="6" />
        <circle cx="21" cy="50" r="2" />
        <circle cx="51" cy="50" r="2" />
        {/* Body + cab */}
        <path d="M34 44V32a3 3 0 0 1 3-3h17a3 3 0 0 1 3 3v12" />
        <path d="M38 29v-6a2 2 0 0 1 2-2h6l3 8" />
        {/* Boom + arm */}
        <path d="M36 33 22 17" />
        <path d="M22 17 13 26" />
        {/* Bucket */}
        <path d="M13 26 7 31l4 5 7-6z" />
    </svg>
);

export default ExcavatorIcon;
