import { createContext, ReactNode, useCallback, useContext, useEffect, useRef, useState } from 'react';
import Button from './ui/Button';
import Modal from './ui/Modal';

const ManualCopyContext = createContext<(text: string) => void>(() => undefined);

export const useManualCopy = () => useContext(ManualCopyContext);

/** Some in-app browsers (LINE, Facebook) block the clipboard; show the text selected so it can be copied by hand. */
export function ManualCopyProvider({ children }: { children: ReactNode }) {
  const [text, setText] = useState<string | null>(null);
  const areaRef = useRef<HTMLTextAreaElement>(null);
  const show = useCallback((value: string) => setText(value), []);

  useEffect(() => {
    if (text) requestAnimationFrame(() => areaRef.current?.select());
  }, [text]);

  return (
    <ManualCopyContext.Provider value={show}>
      {children}
      <Modal
        open={text !== null}
        title="คัดลอกข้อความ"
        onClose={() => setText(null)}
        footer={<Button onClick={() => setText(null)}>เสร็จ</Button>}
      >
        <p className="text-sm text-muted">เบราว์เซอร์นี้ไม่อนุญาตให้คัดลอกอัตโนมัติ กดค้างที่ข้อความแล้วเลือก "คัดลอก"</p>
        <textarea
          ref={areaRef}
          readOnly
          value={text ?? ''}
          rows={3}
          onFocus={(e) => e.currentTarget.select()}
          className="mt-3 w-full resize-none rounded-xl border border-border bg-surface px-4 py-3 text-sm text-ink focus:outline-none focus:ring-2 focus:ring-ring"
        />
      </Modal>
    </ManualCopyContext.Provider>
  );
}
