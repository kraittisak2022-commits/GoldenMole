import { Download } from 'lucide-react';
import { isIos, isStandalone, useInstallPrompt } from '../lib/installPrompt';

export default function InstallApp({ className }: { className: string }) {
  const install = useInstallPrompt();
  if (isStandalone()) return null;
  if (install) {
    return (
      <button type="button" onClick={() => void install()} className={className}>
        <Download size={18} className="text-muted" aria-hidden />
        ติดตั้งเป็นแอปบนเครื่อง
      </button>
    );
  }
  if (isIos()) {
    return <p className="px-3 py-2 text-sm text-muted">ติดตั้งเป็นแอป: กดปุ่มแชร์ แล้วเลือก “เพิ่มไปยังหน้าจอโฮม”</p>;
  }
  return null;
}
