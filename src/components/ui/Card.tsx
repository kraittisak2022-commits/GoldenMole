import { ReactNode } from 'react';

const Card = ({ children, className = '' }: { children: ReactNode; className?: string }) => (
    <div className={`bg-white rounded-2xl shadow-sm border border-slate-100 ${className} dashboard-card`}>{children}</div>
);

export default Card;
