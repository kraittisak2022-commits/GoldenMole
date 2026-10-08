import { InputHTMLAttributes, forwardRef } from 'react';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  invalid?: boolean;
}

const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { className = '', invalid = false, ...props },
  ref,
) {
  return (
    <input
      ref={ref}
      aria-invalid={invalid || undefined}
      className={[
        'w-full min-h-12 rounded border bg-surface px-4 py-2.5 text-base text-ink placeholder:text-muted/70 transition-colors duration-200',
        invalid ? 'border-destructive focus:border-destructive' : 'border-border focus:border-primary',
        className,
      ].join(' ')}
      {...props}
    />
  );
});

export default Input;
