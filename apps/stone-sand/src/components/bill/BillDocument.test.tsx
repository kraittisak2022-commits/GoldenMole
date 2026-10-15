import { render, screen } from '@testing-library/react';
import type { PaymentMethod } from '../../types';
import BillDocument from './BillDocument';
import type { BillData } from './billData';

const company = { nameTh: 'หจก. ทดสอบ', nameEn: 'TEST', address: 'ที่อยู่', taxId: '0000000000000', phone: '0800000000' };
const payment = {
  promptPayId: '',
  bankText: '',
  bankName: 'กสิกรไทย',
  bankAccountNo: '123-4-56789-0',
  bankAccountName: 'ร้านทดสอบ',
  qrPayload: 'shop-qr',
};

const bill = (paymentMethod: PaymentMethod): BillData => ({
  kind: 'delivery',
  docNo: 'SS-0001',
  refs: [],
  date: '2026-10-11',
  customer: { name: 'สมชาย', phone: '', address: '', taxId: '' },
  lines: [{ description: 'หินคลุก', quantity: 5, unit: 'คิว', unitPrice: 400, amount: 2000 }],
  gross: 2000,
  discountAmount: 0,
  total: 2000,
  paymentMethod,
  paid: false,
  cancelled: false,
  verifyToken: 't',
});

const renderBill = (method: PaymentMethod) =>
  render(<BillDocument bill={bill(method)} copy="original" company={company} payment={payment} />);

describe('BillDocument payment', () => {
  it('names cash outright and drops the whole payment channel from the header', () => {
    renderBill('cash');
    expect(screen.getByText('เงินสด')).toBeInTheDocument();
    expect(screen.queryByText('จ่ายปลายทาง')).not.toBeInTheDocument();
    expect(screen.queryByLabelText('QR รับเงิน')).not.toBeInTheDocument();
    expect(screen.queryByText('ช่องทางรับเงิน')).not.toBeInTheDocument();
    expect(screen.queryByText('123-4-56789-0')).not.toBeInTheDocument();
  });

  it('names transfer outright and drops the header QR but keeps the bank account', () => {
    renderBill('transfer');
    expect(screen.getByText('โอนเงิน')).toBeInTheDocument();
    expect(screen.queryByText('จ่ายปลายทาง')).not.toBeInTheDocument();
    expect(screen.queryByLabelText('QR รับเงิน')).not.toBeInTheDocument();
    expect(screen.getByText('123-4-56789-0')).toBeInTheDocument();
  });

  it('keeps the method checklist and the header QR for cash on delivery', () => {
    renderBill('cod');
    expect(screen.getByText('เงินสด')).toBeInTheDocument();
    expect(screen.getByText('จ่ายปลายทาง')).toBeInTheDocument();
    expect(screen.getByLabelText('QR รับเงิน')).toBeInTheDocument();
  });
});

describe('BillDocument discount column', () => {
  it('is left out when no line has a discount', () => {
    renderBill('cash');
    expect(screen.queryByRole('columnheader', { name: 'ส่วนลด' })).not.toBeInTheDocument();
  });

  it('shows each line discount when there is one', () => {
    const discounted: BillData = {
      ...bill('cash'),
      lines: [{ description: 'หินคลุก', quantity: 5, unit: 'คิว', unitPrice: 400, discount: 250, discountPerUnit: 50, amount: 2000 }],
    };
    render(<BillDocument bill={discounted} copy="original" company={company} payment={payment} />);
    expect(screen.getByRole('columnheader', { name: 'ส่วนลด' })).toBeInTheDocument();
    expect(screen.getByText('-250.00')).toBeInTheDocument();
    expect(screen.getByText('คิวละ 50')).toBeInTheDocument();
  });
});
