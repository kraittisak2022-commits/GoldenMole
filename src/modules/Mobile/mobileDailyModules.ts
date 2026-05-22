import type { LucideIcon } from 'lucide-react';
import {
    Droplets,
    Truck,
    Fuel,
    Waves,
    AlertTriangle,
    Wallet,
    Users,
    Clock,
    CalendarX,
    PiggyBank,
    CircleDollarSign,
} from 'lucide-react';

export type DailyModuleDef = {
    title: string;
    icon: LucideIcon;
    category: string;
    quickInputTitle: string;
    color: string;
};

/** รายการเมนูบันทึกประจำวัน — สอดคล้อง `mobile-flutter` `_kDailyModules` */
export const MOBILE_DAILY_MODULES: DailyModuleDef[] = [
    {
        title: 'บันทึกการร่อนทราย',
        icon: Droplets,
        category: 'บันทึกการร่อนทราย',
        quickInputTitle: 'บันทึกการร่อนทราย',
        color: '#FF2D97',
    },
    {
        title: 'บันทึกรถดรัมและจำนวนเที่ยว',
        icon: Truck,
        category: 'จำนวนเที่ยวรถ',
        quickInputTitle: 'บันทึกรถดรัมและจำนวนเที่ยว',
        color: '#00D4F5',
    },
    {
        title: 'การใช้รถแม็คโคร',
        icon: Truck,
        category: 'การใช้รถแม็คโคร',
        quickInputTitle: 'บันทึกการใช้รถแม็คโคร',
        color: '#FFA020',
    },
    {
        title: 'น้ำมัน',
        icon: Fuel,
        category: 'น้ำมัน',
        quickInputTitle: 'บันทึกน้ำมัน',
        color: '#FFAB00',
    },
    {
        title: 'ทรายที่ล้างที่บ้าน',
        icon: Waves,
        category: 'ทรายที่ล้างที่บ้าน',
        quickInputTitle: 'ทรายที่ล้างที่บ้าน',
        color: '#3D6CFF',
    },
    {
        title: 'เหตุการณ์',
        icon: AlertTriangle,
        category: 'เหตุการณ์',
        quickInputTitle: 'เหตุการณ์สำคัญประจำวัน',
        color: '#FF7A1A',
    },
    {
        title: 'บันทึกการทำงาน',
        icon: Wallet,
        category: 'ค่าแรง',
        quickInputTitle: 'บันทึกการทำงาน',
        color: '#9145FF',
    },
    {
        title: 'การทำงานล่วงเวลา (OT)',
        icon: Users,
        category: 'OT',
        quickInputTitle: 'บันทึกการทำงานล่วงเวลา',
        color: '#FF3D6B',
    },
    {
        title: 'ลางาน',
        icon: CalendarX,
        category: 'ลางาน',
        quickInputTitle: 'บันทึกลางาน',
        color: '#00A896',
    },
    {
        title: 'เบิกเงิน',
        icon: PiggyBank,
        category: 'เบิกเงิน',
        quickInputTitle: 'ส่งคำขอเบิกเงิน',
        color: '#FF8500',
    },
    {
        title: 'รายรับ-รายจ่าย',
        icon: CircleDollarSign,
        category: 'รายจ่ายรายรับ',
        quickInputTitle: 'รายรับ-รายจ่าย',
        color: '#6370E8',
    },
];

const WASH_HOME_KEYS = ['washHome', 'wash_home', 'wash_yard_house', 'sift_home'];

export function laborWorkRecordAssignsWashHome(dayTransactions: import('../../types').Transaction[]): boolean {
    for (const t of dayTransactions) {
        if (t.category !== 'Labor') continue;
        const wa = t.workAssignments;
        if (!wa || Object.keys(wa).length === 0) continue;
        for (const key of WASH_HOME_KEYS) {
            const ids = wa[key];
            if (ids && ids.length > 0) return true;
        }
    }
    return false;
}

/** เมนูที่นับในชิป «บันทึกครบ X/Y เมนู» */
export function dailyHeaderCountedModules(dayTransactions: import('../../types').Transaction[]): DailyModuleDef[] {
    const core = new Set([
        'บันทึกการร่อนทราย',
        'น้ำมัน',
        'ค่าแรง',
        'เหตุการณ์',
        'การใช้รถแม็คโคร',
    ]);
    const needHomeSand = laborWorkRecordAssignsWashHome(dayTransactions);
    return MOBILE_DAILY_MODULES.filter(m => {
        if (core.has(m.category)) return true;
        if (m.category === 'ทรายที่ล้างที่บ้าน' && needHomeSand) return true;
        return false;
    });
}
