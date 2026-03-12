import { ReactNode, ButtonHTMLAttributes } from 'react';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
    children: ReactNode;
    variant?: 'primary' | 'secondary' | 'outline' | 'ghost' | 'danger';
}

const Button = ({ children, onClick, variant = 'primary', className = '', disabled = false, ...props }: ButtonProps) => {
    const baseStyle = "px-4 py-2.5 rounded-xl font-medium transition-all duration-200 flex items-center justify-center gap-2 text-sm active:scale-95";
    const variants = {
        primary: "bg-slate-800 dark:bg-amber-500/90 text-white hover:bg-slate-900 dark:hover:bg-amber-500 shadow-md hover:shadow-lg",
        secondary: "bg-emerald-50 dark:bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 hover:bg-emerald-100 dark:hover:bg-emerald-500/20 border border-emerald-200 dark:border-emerald-500/30",
        outline: "border border-slate-200 dark:border-white/20 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/10",
        ghost: "text-slate-500 dark:text-slate-400 hover:bg-slate-50 dark:hover:bg-white/10",
        danger: "bg-red-50 dark:bg-red-500/10 text-red-600 dark:text-red-400 hover:bg-red-100 dark:hover:bg-red-500/20 border border-red-100 dark:border-red-500/20"
    };
    return <button onClick={onClick} disabled={disabled} className={`${baseStyle} ${variants[variant]} ${className} ${disabled ? 'opacity-50 cursor-not-allowed' : ''}`} {...props}>{children}</button>;
};

export default Button;
