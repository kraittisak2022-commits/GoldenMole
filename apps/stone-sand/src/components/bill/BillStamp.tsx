import stampUrl from '../../assets/pirasit-stamp.png';

interface Props {
  /** Shown under the seal when the bill is paid, e.g. "8 ต.ค. 2569". */
  paidDate?: string;
  /** Seal width in px. */
  size?: number;
  rotate?: number;
}

/** Company seal stamped in ink color; the image is pre-tinted so html2canvas exports it unchanged. */
export default function BillStamp({ paidDate, size = 140, rotate = -8 }: Props) {
  return (
    <div
      className="flex flex-col items-center"
      style={{ transform: `rotate(${rotate}deg)`, opacity: 0.9, color: 'var(--color-stamp)' }}
    >
      <img src={stampUrl} width={size} alt="ตราประทับบริษัท" draggable={false} style={{ height: 'auto' }} />
      {paidDate ? (
        <div className="-mt-1 rounded border-2 border-current px-2.5 py-0.5 text-center font-bold leading-tight">
          <p className="text-[13px]">ชำระเงินแล้ว</p>
          <p className="text-[11px]">{paidDate}</p>
        </div>
      ) : null}
    </div>
  );
}
