import { ReactNode, useEffect, useId } from 'react';
import { X } from 'lucide-react';
import { useScrollLock } from '../../lib/useScrollLock';
import IconButton from './IconButton';

interface ModalProps {
  open: boolean;
  title: string;
  onClose: () => void;
  children: ReactNode;
  footer?: ReactNode;
}

export default function Modal({ open, title, onClose, children, footer }: ModalProps) {
  const titleId = useId();
  useScrollLock(open);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[65] flex items-end justify-center sm:items-center sm:p-4" role="dialog" aria-modal="true" aria-labelledby={titleId}>
      <button type="button" aria-label="ปิด" className="fade-in absolute inset-0 cursor-pointer bg-black/50" onClick={onClose} />
      <div className="sheet-up relative z-10 flex max-h-[92dvh] w-full flex-col rounded-t-2xl bg-surface shadow-e3 sm:max-w-md sm:rounded-2xl">
        <div className="flex items-center justify-between gap-2 px-6 pb-2 pt-5">
          <h2 id={titleId} className="text-xl font-medium text-ink">
            {title}
          </h2>
          <IconButton label="ปิด" onClick={onClose} className="-mr-3">
            <X size={20} aria-hidden />
          </IconButton>
        </div>
        <div className={`overflow-y-auto overscroll-contain px-6 ${footer ? 'pb-4' : 'pb-[max(1rem,env(safe-area-inset-bottom))]'}`}>{children}</div>
        {footer ? (
          <div className="flex flex-wrap justify-end gap-2 px-6 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-2">{footer}</div>
        ) : null}
      </div>
    </div>
  );
}
