import { SelectHTMLAttributes, forwardRef } from 'react';

interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  invalid?: boolean;
}

const Select = forwardRef<HTMLSelectElement, SelectProps>(function Select(
  { className = '', invalid = false, children, ...props },
  ref,
) {
  return (
    <select
      ref={ref}
      className={[
        'w-full min-h-11 rounded-DEFAULT border bg-surface px-3 py-2.5 text-sm text-ink transition-colors duration-200',
        invalid ? 'border-destructive' : 'border-border focus:border-accent',
        className,
      ].join(' ')}
      {...props}
    >
      {children}
    </select>
  );
});

export default Select;
