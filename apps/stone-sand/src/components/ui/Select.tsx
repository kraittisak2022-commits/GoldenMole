import { SelectHTMLAttributes, forwardRef } from 'react';

const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(
  function Select({ className = '', children, ...props }, ref) {
    return (
      <select
        ref={ref}
        className={[
          'w-full min-h-11 rounded border border-border bg-surface px-3 py-2.5 text-base sm:text-sm text-ink transition-colors duration-200 focus:border-primary',
          className,
        ].join(' ')}
        {...props}
      >
        {children}
      </select>
    );
  },
);

export default Select;
