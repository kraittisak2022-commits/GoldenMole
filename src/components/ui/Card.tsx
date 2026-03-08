import { ReactNode } from 'react';

const Card = ({ children, className = '' }: { children: ReactNode; className?: string }) => (
    <div className={`rounded-2xl shadow-sm border ${className} 
        bg-white border-slate-100 
        dark:bg-white/[0.02] dark:border-white/[0.05] dark:shadow-2xl dark:backdrop-blur-sm
        dashboard-card relative overflow-hidden transition-all duration-300`}>
        {/* Subtle top highlight for glassmorphism in dark mode */}
        <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-white/[0.1] to-transparent hidden dark:block" />
        <div className="relative z-10">{children}</div>
    </div>
);

export default Card;
