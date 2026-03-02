import React from 'react';
import { ChevronDown } from 'lucide-react';

interface SelectProps extends React.SelectHTMLAttributes<HTMLSelectElement> {
    label?: string;
}

const Select = ({ label, children, className = '', ...props }: SelectProps) => (
    <div className="flex flex-col gap-1.5 w-full">
        {label && <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">{label}</label>}
        <div className="relative">
            <select className={`w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500 transition-all bg-white appearance-none text-slate-800 ${className}`} {...props}>{children}</select>
            <ChevronDown className="absolute right-3 top-3 w-4 h-4 text-slate-400 pointer-events-none" />
        </div>
    </div>
);

export default Select;
