import { navItemFor } from '../components/navItems';
import { menuHints } from './menuHints';

describe('menuHints', () => {
  it('shows counts once they are known', () => {
    const h = menuHints({ ordersToday: 3, waitingDelivery: 0, customers: 1250, openStatements: 2, driverUnpaid: 5, drivers: 4, products: 6 });
    expect(h['/']).toBe('วันนี้ 3 ออเดอร์');
    expect(h['/orders']).toBe('รอส่ง 0 ออเดอร์');
    expect(h['/customers']).toBe('1,250 ราย');
    expect(h['/statements']).toBe('รอเก็บเงิน 2 ใบ');
    expect(h['/drivers']).toBe('4 คัน');
  });

  it('falls back to a description while loading', () => {
    expect(menuHints({})['/customers']).toBe('ข้อมูลลูกค้า');
  });
});

describe('navItemFor', () => {
  it('maps nested pages to their menu item, and home only to /', () => {
    expect(navItemFor('/orders/ord-1')?.to).toBe('/orders');
    expect(navItemFor('/')?.to).toBe('/');
    expect(navItemFor('/menu')).toBeUndefined();
  });
});
