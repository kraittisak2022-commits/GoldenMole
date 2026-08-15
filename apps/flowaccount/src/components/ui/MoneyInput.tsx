import { InputHTMLAttributes, forwardRef } from 'react';

interface MoneyInputProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'type' | 'onChange' | 'value'> {
  value: number | '';
  onValueChange: (n: number | '') => void;
  invalid?: boolean;
}

const MoneyInput = forwardRef<HTMLInputElement, MoneyInputProps>(function MoneyInput(
  { value, onValueChange, className = '', invalid = false, ...props },
  ref,
) {
  return (
    <input
      ref={ref}
      type="number"
      inputMode="decimal"
      min={0}
      step="0.01"
      value={value}
      onChange={(e) => {
        const v = e.target.value;
        if (v === '') onValueChange('');
        else onValueChange(Number(v));
      }}
      className={[
        'w-full min-h-11 rounded-DEFAULT border bg-surface px-3 py-2.5 text-sm text-ink tabular-nums transition-colors duration-200',
        invalid ? 'border-destructive' : 'border-border focus:border-accent',
        className,
      ].join(' ')}
      {...props}
    />
  );
});

export default MoneyInput;
