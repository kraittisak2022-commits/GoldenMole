import { useId } from 'react';

interface SwitchProps {
  checked: boolean;
  onChange: (checked: boolean) => void;
  label: string;
  description?: string;
  disabled?: boolean;
}

export default function Switch({ checked, onChange, label, description, disabled }: SwitchProps) {
  const id = useId();
  return (
    <div className="flex items-center justify-between gap-4 py-2">
      <label htmlFor={id} className="min-w-0 cursor-pointer">
        <span className="block text-base text-ink">{label}</span>
        {description ? <span className="mt-0.5 block text-sm text-muted">{description}</span> : null}
      </label>
      <button
        id={id}
        type="button"
        role="switch"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={[
          'relative inline-flex h-8 w-[52px] shrink-0 cursor-pointer items-center rounded-full border-2 transition duration-200 disabled:cursor-not-allowed disabled:opacity-40',
          checked ? 'border-primary bg-primary' : 'border-muted bg-container-high',
        ].join(' ')}
      >
        <span
          aria-hidden
          className={[
            'absolute rounded-full transition-all duration-200',
            checked ? 'left-[22px] h-6 w-6 bg-primary-foreground' : 'left-1.5 h-4 w-4 bg-muted',
          ].join(' ')}
        />
      </button>
    </div>
  );
}
