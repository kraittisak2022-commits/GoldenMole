import { TextareaHTMLAttributes, forwardRef } from 'react';

const Textarea = forwardRef<HTMLTextAreaElement, TextareaHTMLAttributes<HTMLTextAreaElement>>(
  function Textarea({ className = '', rows = 3, ...props }, ref) {
    return (
      <textarea
        ref={ref}
        rows={rows}
        className={[
          'w-full rounded border border-border bg-surface px-3 py-2.5 text-base sm:text-sm text-ink placeholder:text-muted transition-colors duration-200 focus:border-primary',
          className,
        ].join(' ')}
        {...props}
      />
    );
  },
);

export default Textarea;
