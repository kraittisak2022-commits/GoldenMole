import { ReactNode } from 'react';

interface FieldProps {
  id: string;
  label: string;
  error?: string;
  children: ReactNode;
}

export default function Field({ id, label, error, children }: FieldProps) {
  const errorId = `${id}-error`;
  return (
    <div className="flex w-full flex-col gap-1.5">
      <label htmlFor={id} className="text-sm font-medium text-ink">
        {label}
      </label>
      {children}
      {error ? (
        <p id={errorId} role="alert" className="text-sm text-destructive">
          {error}
        </p>
      ) : null}
    </div>
  );
}
