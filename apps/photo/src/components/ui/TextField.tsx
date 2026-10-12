import { forwardRef, InputHTMLAttributes, ReactNode, useId } from 'react';

interface TextFieldProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string;
  hint?: string;
  error?: string | null;
  trailing?: ReactNode;
}

const TextField = forwardRef<HTMLInputElement, TextFieldProps>(function TextField(
  { label, hint, error, trailing, className = '', id, ...props },
  ref,
) {
  const autoId = useId();
  const inputId = id ?? autoId;
  const hintId = `${inputId}-hint`;
  return (
    <div className={className}>
      <label htmlFor={inputId} className="mb-1.5 block text-sm font-medium text-ink">
        {label}
      </label>
      <div
        className={[
          'flex min-h-12 items-center rounded border bg-surface transition focus-within:border-2',
          error ? 'border-destructive focus-within:border-destructive' : 'border-border focus-within:border-primary',
        ].join(' ')}
      >
        <input
          ref={ref}
          id={inputId}
          aria-invalid={error ? true : undefined}
          aria-describedby={hint || error ? hintId : undefined}
          className="min-w-0 flex-1 bg-transparent px-4 py-3 text-base text-ink outline-none placeholder:text-muted/70"
          {...props}
        />
        {trailing}
      </div>
      {error ? (
        <p id={hintId} role="alert" className="mt-1.5 text-sm text-destructive">
          {error}
        </p>
      ) : hint ? (
        <p id={hintId} className="mt-1.5 text-sm text-muted">
          {hint}
        </p>
      ) : null}
    </div>
  );
});

export default TextField;
