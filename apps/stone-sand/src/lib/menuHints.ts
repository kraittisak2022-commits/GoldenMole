import { formatNumber } from './format';

export interface MenuCounts {
  ordersToday?: number;
  waitingDelivery?: number;
  customers?: number;
  openStatements?: number;
  driverUnpaid?: number;
  drivers?: number;
  products?: number;
}

/** Caption under each menu card, keyed by route; a count that is still loading falls back to a description. */
export function menuHints(c: MenuCounts): Record<string, string> {
  const n = (v: number | undefined, text: (v: string) => string, fallback: string) =>
    v === undefined ? fallback : text(formatNumber(v));
  return {
    '/': n(c.ordersToday, (v) => `วันนี้ ${v} ออเดอร์`, 'สรุปยอดวันนี้'),
    '/orders': n(c.waitingDelivery, (v) => `รอส่ง ${v} ออเดอร์`, 'ติดตามออเดอร์'),
    '/customers': n(c.customers, (v) => `${v} ราย`, 'ข้อมูลลูกค้า'),
    '/statements': n(c.openStatements, (v) => `รอเก็บเงิน ${v} ใบ`, 'ใบวางบิล'),
    '/driver-pay': n(c.driverUnpaid, (v) => `รอจ่าย ${v} ออเดอร์`, 'ค่าจ้างคนขับ'),
    '/bill-summary': 'กำไรและสถานะแต่ละบิล',
    '/drivers': n(c.drivers, (v) => `${v} คัน`, 'รถและคนขับ'),
    '/settings': n(c.products, (v) => `สินค้า ${v} รายการ`, 'สินค้า ราคา ค่าส่ง'),
    '/new': 'เปิดออเดอร์ใหม่',
  };
}
