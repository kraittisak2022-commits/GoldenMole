const LineChart = ({ data, color = "#10b981", height = 60 }: { data: number[], color?: string, height?: number }) => {
    if (data.length < 2) return <div className="h-full flex items-center justify-center text-slate-300 text-xs">No Data</div>;
    const width = 100; const max = Math.max(...data, 1);
    const points = data.map((d, i) => `${(i / (data.length - 1)) * width},${height - (d / max) * height}`).join(' ');
    return (
        <svg viewBox={`0 0 ${width} ${height}`} className="w-full h-full overflow-visible" preserveAspectRatio="none">
            <defs>
                <linearGradient id={`grad-${color}`} x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor={color} stopOpacity="0.2" />
                    <stop offset="100%" stopColor={color} stopOpacity="0" />
                </linearGradient>
            </defs>
            <path d={`M0,${height} L0,${height - (data[0] / max) * height} ${points.replace(/,/g, ' ')} L${width},${height} Z`} fill={`url(#grad-${color})`} stroke="none" />
            <polyline points={points} fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            {data.map((d, i) => <circle key={i} cx={(i / (data.length - 1)) * width} cy={height - (d / max) * height} r="2" fill="#fff" stroke={color} strokeWidth="1.5" />)}
        </svg>
    );
};

export default LineChart;
