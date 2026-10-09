import { useState } from 'react';
import { Check, CheckCircle2, Copy, FileText } from 'lucide-react';
import Button from '../../components/ui/Button';
import Modal from '../../components/ui/Modal';
import { useCatalog } from '../../context/CatalogProvider';
import { driverMessage } from '../../lib/orderStatus';
import type { Order } from '../../types';

/** Shown after a delivery order is saved: send the job to the driver, then open the bill. */
export default function OrderCreatedModal({ order, onBill }: { order: Order; onBill: () => void }) {
  const { zoneById, driverById } = useCatalog();
  const [copied, setCopied] = useState(false);
  const message = driverMessage(order, zoneById(order.zoneId), driverById(order.driverId));

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(message);
      setCopied(true);
    } catch {
      window.prompt('คัดลอกข้อความนี้', message);
    }
  };

  return (
    <Modal open title={`บันทึกออเดอร์ ${order.orderNo} แล้ว`} onClose={onBill}>
      <div className="flex flex-col gap-4">
        <p className="flex items-center gap-2 text-sm text-success">
          <CheckCircle2 size={18} aria-hidden /> คัดลอกข้อความไปวางใน LINE ส่งคนขับ แล้วออกบิลให้ลูกค้า
        </p>
        <pre className="max-h-48 overflow-y-auto whitespace-pre-wrap rounded bg-subtle px-3 py-2 font-sans text-sm text-muted">
          {message}
        </pre>
        <div className="grid gap-2 sm:grid-cols-2">
          <Button size="lg" variant="secondary" onClick={copy}>
            {copied ? <Check size={18} aria-hidden /> : <Copy size={18} aria-hidden />}
            {copied ? 'คัดลอกแล้ว' : 'คัดลอกข้อความส่งคนขับ'}
          </Button>
          <Button size="lg" onClick={onBill}>
            <FileText size={18} aria-hidden /> ออกบิล
          </Button>
        </div>
      </div>
    </Modal>
  );
}
