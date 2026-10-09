import type { ComponentProps } from 'react';
import Input from './Input';

type Props = Omit<ComponentProps<typeof Input>, 'type' | 'inputMode' | 'value' | 'onChange'> & {
  value: number;
  onValueChange: (value: number) => void;
};

/**
 * Whole-number field: opens the digit keypad, drops anything that is not a digit (some keypads
 * still offer - , .), and Enter closes the keyboard.
 */
export default function NumberInput({ value, onValueChange, onKeyDown, ...props }: Props) {
  return (
    <Input
      autoComplete="off"
      enterKeyHint="done"
      {...props}
      type="text"
      inputMode="numeric"
      pattern="[0-9]*"
      value={value ? String(value) : ''}
      onChange={(e) => onValueChange(Number(e.target.value.replace(/\D/g, '')) || 0)}
      onKeyDown={(e) => {
        onKeyDown?.(e);
        if (e.key === 'Enter') {
          e.preventDefault();
          e.currentTarget.blur();
        }
      }}
    />
  );
}
