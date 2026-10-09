import { BarChart3, ClipboardList, FileCheck2, LayoutDashboard, Settings, Truck, Users, Wallet, type LucideIcon } from 'lucide-react';

export interface NavItem {
  to: string;
  label: string;
  icon: LucideIcon;
  end?: boolean;
}

export const NAV_ITEMS: NavItem[] = [
  { to: '/', label: 'หน้าหลัก', icon: LayoutDashboard, end: true },
  { to: '/orders', label: 'ออเดอร์', icon: ClipboardList },
  { to: '/customers', label: 'ลูกค้า', icon: Users },
  { to: '/statements', label: 'เคลียร์บิล', icon: FileCheck2 },
  { to: '/driver-pay', label: 'เคลียร์ค่ารถ', icon: Wallet },
  { to: '/bill-summary', label: 'สรุปบิล', icon: BarChart3 },
  { to: '/drivers', label: 'รถ / คนขับ', icon: Truck },
  { to: '/settings', label: 'ตั้งค่า', icon: Settings },
];

/** The nav item a path belongs to (e.g. /orders/123 → ออเดอร์). */
export function navItemFor(pathname: string): NavItem | undefined {
  return NAV_ITEMS.find((item) => (item.end ? pathname === item.to : pathname === item.to || pathname.startsWith(`${item.to}/`)));
}
