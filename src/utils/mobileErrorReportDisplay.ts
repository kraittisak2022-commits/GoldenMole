import type { MobileErrorReportRow } from '../types/mobileErrorReport';

const labeledLine = (text: string | null | undefined, prefix: string): string | null => {
    if (!text) return null;
    for (const line of text.split('\n')) {
        const t = line.trim();
        if (t.startsWith(prefix)) return t.slice(prefix.length).trim() || null;
    }
    return null;
};

export type MobileErrorContextDisplay = {
    page: string | null;
    action: string | null;
    button: string | null;
    field: string | null;
};

/** บริบทจากคอลัมน์ใหม่ หรือ parse จาก error_detail รายงานเก่า */
export function mobileErrorContextFromRow(row: MobileErrorReportRow): MobileErrorContextDisplay {
    const detail = row.error_detail ?? '';
    return {
        page: row.screen_page?.trim() || labeledLine(detail, 'หน้า:'),
        action: row.screen_action?.trim() || labeledLine(detail, 'รายการ:'),
        button: row.screen_button?.trim() || labeledLine(detail, 'ปุ่ม:'),
        field: row.error_field?.trim() || labeledLine(detail, 'จุดที่ผิด:'),
    };
}

export function mobileErrorHasContext(ctx: MobileErrorContextDisplay): boolean {
    return !!(ctx.page || ctx.action || ctx.button || ctx.field);
}

export function mobileErrorSourceLabel(source: string | null | undefined): string {
    switch (source) {
        case 'save_failed':
            return 'บันทึกไม่สำเร็จ';
        case 'uncaught_flutter':
            return 'ข้อผิดพลาดใน UI (Flutter)';
        case 'uncaught_zone':
            return 'ข้อผิดพลาดไม่คาดคิด (Zone)';
        case 'manual_settings':
            return 'รายงานด้วยตนเอง (แอป)';
        case 'bootstrap':
            return 'เริ่มต้นแอป';
        default:
            return source?.trim() || 'ไม่ระบุ';
    }
}
