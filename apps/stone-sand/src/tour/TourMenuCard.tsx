import { useState } from 'react';
import { GraduationCap, Play, Trash2 } from 'lucide-react';
import Button from '../components/ui/Button';
import { useTour } from './tourContext';
import { TOUR_STEPS } from './tourSteps';

export default function TourMenuCard() {
  const { state, starting, error, start, resume, end } = useTour();
  const [ending, setEnding] = useState(false);

  const finish = async () => {
    if (!window.confirm('ลบข้อมูลสาธิตทั้งหมดและเลิกสอนใช้งาน?')) return;
    setEnding(true);
    await end();
    setEnding(false);
  };

  return (
    <section
      id="tour"
      className="mb-6 flex flex-col gap-4 rounded-2xl border border-violet-200 bg-gradient-to-br from-violet-50 to-surface p-5 sm:flex-row sm:items-center"
    >
      <div className="flex min-w-0 flex-1 items-start gap-4">
        <span className="inline-flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-violet-600 text-white">
          <GraduationCap size={26} aria-hidden />
        </span>
        <div className="min-w-0">
          <h2 className="text-lg font-semibold">สอนใช้งาน</h2>
          {state ? (
            <p className="text-sm text-muted">
              {state.paused ? 'พักไว้ที่' : 'กำลังสอนอยู่ ·'} ขั้น {state.step + 1}/{TOUR_STEPS.length} — ข้อมูลที่มีป้าย "สาธิต" จะถูกลบเมื่อจบ
            </p>
          ) : (
            <p className="text-sm text-muted">
              พาทำจริงทีละขั้น ตั้งแต่สร้างออเดอร์ ออกบิล รับเงิน จนวางบิลและเคลียร์บิล ใช้เวลาประมาณ 10 นาที
              ข้อมูลที่สร้างเป็นข้อมูลสาธิต คนอื่นไม่เห็น และถูกลบเมื่อจบ
            </p>
          )}
          {error ? <p className="mt-2 text-sm text-destructive">{error}</p> : null}
        </div>
      </div>
      <div className="flex shrink-0 flex-wrap gap-2">
        {state ? (
          <>
            {state.paused ? (
              <Button size="lg" className="flex-1 !bg-violet-600 hover:!bg-violet-700" onClick={resume}>
                <Play size={18} aria-hidden /> สอนต่อ
              </Button>
            ) : null}
            <Button variant="secondary" size="lg" className="flex-1" disabled={ending} onClick={finish}>
              <Trash2 size={18} aria-hidden /> {ending ? 'กำลังลบ…' : 'เลิกสอน'}
            </Button>
          </>
        ) : (
          <Button size="lg" className="w-full !bg-violet-600 hover:!bg-violet-700 sm:w-auto" disabled={starting} onClick={() => void start()}>
            <Play size={18} aria-hidden /> {starting ? 'กำลังเตรียม…' : 'เริ่มสอนใช้งาน'}
          </Button>
        )}
      </div>
    </section>
  );
}
