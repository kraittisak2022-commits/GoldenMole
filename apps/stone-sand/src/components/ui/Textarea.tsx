import { TextareaHTMLAttributes, forwardRef } from 'react';

interface Props extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  /** The keyboard's Enter key becomes "done" and closes the keyboard; long text still wraps. */
  doneOnEnter?: boolean;
}

const Textarea = forwardRef<HTMLTextAreaElement, Props>(
  function Textarea({ className = '', rows = 3, doneOnEnter = false, onKeyDown, ...props }, ref) {
    return (
      <textarea
        ref={ref}
        rows={rows}
        className={[
          'w-full rounded border border-border bg-surface px-4 py-3 text-base text-ink placeholder:text-muted/70 transition-colors duration-200 focus:border-primary',
          className,
        ].join(' ')}
        enterKeyHint={doneOnEnter ? 'done' : undefined}
        {...props}
        onKeyDown={(e) => {
          onKeyDown?.(e);
          if (doneOnEnter && e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
            e.preventDefault();
            e.currentTarget.blur();
          }
        }}
      />
    );
  },
);

export default Textarea;
