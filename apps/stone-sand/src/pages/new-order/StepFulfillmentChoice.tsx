import type { ReactNode } from 'react';
import { MapPin, Store, Truck } from 'lucide-react';
import type { Fulfillment } from '../../types';
import StepTitle from './StepTitle';

interface Props {
  fulfillment: Fulfillment | null;
  onSelect: (f: Fulfillment) => void;
}

export default function StepFulfillmentChoice({ fulfillment, onSelect }: Props) {
  return (
    <div className="step-enter flex flex-col gap-5">
      <StepTitle title="การรับสินค้า" subtitle="ลูกค้ามารับเองที่ท่าทราย หรือให้รถไปส่ง ราคาสินค้าจะคิดตามที่เลือก" />

      <div className="grid grid-cols-2 gap-3" role="radiogroup" aria-label="การรับสินค้า">
        <ChoiceCard
          active={fulfillment === 'pickup'}
          onClick={() => onSelect('pickup')}
          icon={<Store size={26} aria-hidden />}
          title="มารับเอง"
          hint="ราคามารับเอง ไม่มีค่าส่ง"
        />
        <ChoiceCard
          active={fulfillment === 'delivery'}
          onClick={() => onSelect('delivery')}
          icon={<Truck size={26} aria-hidden />}
          title="จัดส่ง"
          hint="ในเขต อ.วังเหนือ"
        />
      </div>

      {fulfillment === 'pickup' ? (
        <div className="flex items-start gap-3 rounded border border-border bg-surface p-4 text-sm text-muted">
          <MapPin size={18} className="mt-0.5 shrink-0 text-primary" aria-hidden />
          ลูกค้ามารับที่ท่าทราย ไม่มีค่าส่ง ระบบจะบันทึกสถานะการส่งเป็น "มารับเอง"
        </div>
      ) : null}
      {fulfillment === 'delivery' ? (
        <div className="flex items-start gap-3 rounded border border-border bg-surface p-4 text-sm text-muted">
          <Truck size={18} className="mt-0.5 shrink-0 text-primary" aria-hidden />
          เลือกสินค้าและลูกค้าก่อน แล้วค่อยปักหมุด เลือกตำบล รถ และคนขับ ในขั้น "จัดส่ง"
        </div>
      ) : null}
    </div>
  );
}

function ChoiceCard({
  active,
  onClick,
  icon,
  title,
  hint,
}: {
  active: boolean;
  onClick: () => void;
  icon: ReactNode;
  title: string;
  hint: string;
}) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={active}
      onClick={onClick}
      className={[
        'flex min-h-28 flex-col items-center justify-center gap-2 rounded border-2 p-4 text-center transition-colors cursor-pointer',
        active ? 'border-primary bg-primary-soft/50 text-primary' : 'border-border bg-surface hover:bg-subtle',
      ].join(' ')}
    >
      {icon}
      <span className="text-base font-semibold">{title}</span>
      <span className="text-xs text-muted">{hint}</span>
    </button>
  );
}
