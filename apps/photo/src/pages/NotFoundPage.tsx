import { Link } from 'react-router-dom';
import { ImageOff } from 'lucide-react';
import { EmptyState } from '../components/ui/States';

export default function NotFoundPage() {
  return (
    <main className="flex min-h-[100dvh] items-center justify-center">
      <EmptyState
        icon={<ImageOff size={40} strokeWidth={1.5} aria-hidden />}
        title="ไม่พบหน้านี้"
        body="ลิงก์อาจพิมพ์ผิด หรือถูกเปลี่ยนแล้ว"
        action={
          <Link to="/" className="inline-flex min-h-11 items-center rounded-full px-5 text-sm font-medium text-primary hover:bg-primary/[0.08]">
            ไปหน้าแรก
          </Link>
        }
      />
    </main>
  );
}
