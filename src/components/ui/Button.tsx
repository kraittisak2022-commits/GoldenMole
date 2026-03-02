import { ReactNode, ButtonHTMLAttributes } from 'react';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
    children: ReactNode;
    variant?: 'primary' | 'secondary' | 'outline' | 'ghost' | 'danger';
}

const Button = ({ children, onClick, variant = 'primary', className = '', disabled = false, ...props }: ButtonProps) => {
    const baseStyle = "px-4 py-2.5 rounded-xl font-medium transition-all duration-200 flex items-center justify-center gap-2 text-sm active:scale-95";
    const variants = {
        primary: "bg-slate-800 text-white hover:bg-slate-900 shadow-md hover:shadow-lg",
        secondary: "bg-emerald-50 text-emerald-600 hover:bg-emerald-100 border border-emerald-200",
        outline: "border border-slate-200 text-slate-600 hover:bg-slate-50",
        ghost: "text-slate-500 hover:bg-slate-50",
        danger: "bg-red-50 text-red-600 hover:bg-red-100 border border-red-100"
    };
    return <button onClick={onClick} disabled={disabled} className={`${baseStyle} ${variants[variant]} ${className} ${disabled ? 'opacity-50 cursor-not-allowed' : ''}`} {...props}>{children}</button>;
};

export default Button;
