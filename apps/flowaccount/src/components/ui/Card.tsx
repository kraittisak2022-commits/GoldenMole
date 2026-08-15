import { HTMLAttributes, ReactNode } from 'react';

interface CardProps extends HTMLAttributes<HTMLDivElement> {
  children: ReactNode;
}

export default function Card({ children, className = '', ...props }: CardProps) {
  return (
    <div
      className={[
        'rounded-DEFAULT border border-border bg-surface',
        className,
      ].join(' ')}
      {...props}
    >
      {children}
    </div>
  );
}
