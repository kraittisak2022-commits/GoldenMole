import type { DailyModuleDef } from './mobileDailyModules';

export type MobileModuleRoute =
    | { type: 'wizard'; step: number }
    | { type: 'labor'; tab: 'Attendance' | 'OT' | 'Advance' | 'Leave' };

/** แมปเมนู Android → ขั้น Wizard หรือแท็บค่าแรงบนเว็บ */
export function routeForDailyModule(mod: DailyModuleDef): MobileModuleRoute {
    switch (mod.category) {
        case 'บันทึกการร่อนทราย':
        case 'ทรายที่ล้างที่บ้าน':
            return { type: 'wizard', step: 4 };
        case 'จำนวนเที่ยวรถ':
            return { type: 'wizard', step: 3 };
        case 'การใช้รถแม็คโคร':
            return { type: 'wizard', step: 2 };
        case 'น้ำมัน':
            return { type: 'wizard', step: 5 };
        case 'เหตุการณ์':
            return { type: 'wizard', step: 7 };
        case 'รายจ่ายรายรับ':
            return { type: 'wizard', step: 6 };
        case 'OT':
            return { type: 'labor', tab: 'OT' };
        case 'ลางาน':
            return { type: 'labor', tab: 'Leave' };
        case 'เบิกเงิน':
            return { type: 'labor', tab: 'Advance' };
        case 'ค่าแรง':
        case 'บันทึกการทำงาน':
        default:
            return { type: 'labor', tab: 'Attendance' };
    }
}
