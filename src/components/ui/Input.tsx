import React from 'react';

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
    label?: string;
}

const Input = ({ label, className = '', ...props }: InputProps) => (
    <div className="flex flex-col gap-1.5 w-full">
        {label && <label className="text-xs font-bold text-slate-500 dark:text-slate-400 uppercase tracking-wider">{label}</label>}
        <input className={`w-full px-4 py-2.5 rounded-xl border border-slate-200 dark:border-white/20 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 dark:focus:ring-amber-500/30 focus:border-emerald-500 dark:focus:border-amber-500/50 transition-all bg-white dark:bg-white/5 text-slate-800 dark:text-slate-100 placeholder:text-slate-400 dark:placeholder:text-slate-500 disabled:bg-slate-50 dark:disabled:bg-white/[0.03] ${className}`} {...props} />
    </div>
);

export default Input;
