const BarChart = ({ data, labels, color = "#64748b" }: { data: number[], labels?: string[], color?: string }) => {
    const max = Math.max(...data, 1);
    return (
        <div className="h-full w-full flex items-end justify-between gap-2 pt-6 px-2">
            {data.map((val, i) => (
                <div key={i} className="w-full flex flex-col items-center gap-2 group h-full justify-end relative">
                    <div className="absolute -top-6 text-[10px] font-bold text-slate-500 opacity-0 group-hover:opacity-100 transition-opacity">฿{val.toLocaleString()}</div>
                    <div className="relative w-full bg-slate-100 rounded-md h-full flex items-end overflow-hidden group-hover:bg-slate-200 transition-colors">
                        <div className="w-full transition-all duration-700 ease-out rounded-t-md" style={{ height: `${(val / max) * 100}%`, backgroundColor: color }} />
                    </div>
                    {labels && <span className="text-[10px] text-slate-400 font-medium truncate w-full text-center">{labels[i]}</span>}
                </div>
            ))}
        </div>
    );
};

export default BarChart;
