import React from 'react';

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
    label?: string;
}

const Input = ({ label, className = '', ...props }: InputProps) => (
    <div className="flex flex-col gap-1.5 w-full">
        {label && <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">{label}</label>}
        <input className={`w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500 transition-all bg-white text-slate-800 disabled:bg-slate-50 ${className}`} {...props} />
    </div>
);

export default Input;
