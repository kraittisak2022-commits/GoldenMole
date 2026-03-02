import FormatNumber from '../ui/FormatNumber';

const DonutChartSimple = ({ data }: { data: { value: number, color: string, label: string }[] }) => {
    let cumulativePercent = 0;
    const total = data.reduce((acc, curr) => acc + curr.value, 0);

    if (total === 0) return <div className="w-full h-full flex items-center justify-center text-slate-300">No Data</div>;

    function getCoordinatesForPercent(percent: number) {
        const x = Math.cos(2 * Math.PI * percent);
        const y = Math.sin(2 * Math.PI * percent);
        return [x, y];
    }

    return (
        <div className="relative w-40 h-40 mx-auto">
            <svg viewBox="-1 -1 2 2" className="transform -rotate-90 w-full h-full">
                {data.map((slice, i) => {
                    const percent = slice.value / total;
                    const start = getCoordinatesForPercent(cumulativePercent);
                    cumulativePercent += percent;
                    const end = getCoordinatesForPercent(cumulativePercent);
                    const largeArcFlag = percent > 0.5 ? 1 : 0;
                    const pathData = [
                        `M ${start[0]} ${start[1]}`,
                        `A 1 1 0 ${largeArcFlag} 1 ${end[0]} ${end[1]}`,
                        `L 0 0`,
                    ].join(' ');
                    return <path key={i} d={pathData} fill={slice.color} stroke="white" strokeWidth="0.05" />;
                })}
                <circle cx="0" cy="0" r="0.6" fill="white" />
            </svg>
            <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                <span className="text-[10px] text-slate-400">Total</span>
                <span className="text-sm font-bold text-slate-800"><FormatNumber value={total} /></span>
            </div>
        </div>
    );
};

export default DonutChartSimple;
