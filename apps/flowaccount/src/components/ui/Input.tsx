import { InputHTMLAttributes, forwardRef } from 'react';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  invalid?: boolean;
}

const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { className = '', invalid = false, id, ...props },
  ref,
) {
  return (
    <input
      ref={ref}
      id={id}
      className={[
        'w-full min-h-11 rounded-DEFAULT border bg-surface px-3 py-2.5 text-sm text-ink placeholder:text-muted transition-colors duration-200',
        invalid
          ? 'border-destructive focus:border-destructive'
          : 'border-border focus:border-accent',
        className,
      ].join(' ')}
      {...props}
    />
  );
});

export default Input;
