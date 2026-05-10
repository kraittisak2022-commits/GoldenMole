import type { Transaction } from '../types';

const fmt = (n: number | undefined | null): string => {
    if (n == null || Number.isNaN(Number(n))) return '';
    return new Intl.NumberFormat('th-TH', { maximumFractionDigits: 2 }).format(Number(n));
};

const trunc = (s: string | undefined, max: number): string => {
    if (!s) return '';
    const t = s.trim();
    if (t.length <= max) return t;
    return `${t.slice(0, max - 1)}…`;
};

/** ข้อความรวมสำหรับค้นหา — ครอบคลุมฟิลด์ที่แอนดรอยด์/เว็บบันทึกลง transactions */
export function transactionSearchBlob(t: Transaction): string {
    const parts: string[] = [
        t.description,
        t.category,
        t.subCategory,
        t.note,
        t.workDetails,
        t.laborStatus,
        t.leaveReason,
        t.otDescription,
        t.eventType,
        t.eventPriority,
        t.eventTime,
        t.incomePaymentStatus,
        t.fuelType,
        t.fuelMovement,
        t.workType,
        t.sandMachineType,
        t.tripBillingMode,
        t.employeeId,
        ...(t.employeeIds || []),
        t.driverId,
        t.vehicleId,
        ...(t.sandOperators || []),
    ];
    if (t.workAssignments && typeof t.workAssignments === 'object') {
        for (const [k, v] of Object.entries(t.workAssignments)) {
            parts.push(k, ...(v || []));
        }
    }
    if (t.workTypeByEmployee && typeof t.workTypeByEmployee === 'object') {
        for (const [empId, wt] of Object.entries(t.workTypeByEmployee)) {
            parts.push(empId, wt);
        }
    }
    if (Array.isArray(t.customWorkCategories)) {
        for (const c of t.customWorkCategories) {
            if (c?.id) parts.push(c.id);
            if (c?.label) parts.push(c.label);
        }
    }
    return parts
        .filter((x): x is string => typeof x === 'string' && x.trim().length > 0)
        .join(' ')
        .toLowerCase();
}

/** บรรทัดรองใต้หัวข้อ — สรุปฟิลด์จากมือถือ (OT, เบิก, รถ, ทราย, เหตุการณ์, ฯลฯ) */
export function transactionMetaSummary(t: Transaction): string {
    const bits: string[] = [];

    if (t.subCategory?.trim()) bits.push(t.subCategory.trim());
    if (t.laborStatus?.trim()) bits.push(`สถานะ ${t.laborStatus}`);

    if (t.type === 'Leave') {
        if (t.leaveReason?.trim()) bits.push(t.leaveReason.trim());
        if (t.leaveDays != null && t.leaveDays !== 0) bits.push(`${fmt(t.leaveDays)} วัน`);
    }

    const otParts: string[] = [];
    if (t.otAmount != null && Number(t.otAmount) !== 0) otParts.push(`OT ${fmt(t.otAmount)}`);
    if (t.otHours != null && Number(t.otHours) !== 0) otParts.push(`${fmt(t.otHours)} ชม.`);
    if (t.otDescription?.trim()) otParts.push(trunc(t.otDescription, 36));
    if (otParts.length) bits.push(otParts.join(' · '));

    if (t.advanceAmount != null && Number(t.advanceAmount) !== 0) bits.push(`เบิก ${fmt(t.advanceAmount)}`);

    const tripParts: string[] = [];
    if (t.tripBillingMode?.trim()) {
        tripParts.push(t.tripBillingMode === 'LumpSum' ? 'ค่ารถเหมา' : t.tripBillingMode === 'PerTrip' ? 'ค่ารถรายเที่ยว' : t.tripBillingMode);
    }
    if (t.tripCount != null && Number(t.tripCount) !== 0) tripParts.push(`เที่ยว ${fmt(t.tripCount)}`);
    if (t.tripMorning != null && Number(t.tripMorning) !== 0) tripParts.push(`เช้า ${fmt(t.tripMorning)}`);
    if (t.tripAfternoon != null && Number(t.tripAfternoon) !== 0) tripParts.push(`บ่าย ${fmt(t.tripAfternoon)}`);
    if (t.totalCubic != null && Number(t.totalCubic) !== 0) tripParts.push(`ลบ.ม. ${fmt(t.totalCubic)}`);
    if (t.cubicPerTrip != null && Number(t.cubicPerTrip) !== 0) tripParts.push(`ลบ.ม./เที่ยว ${fmt(t.cubicPerTrip)}`);
    if (t.perCarTrips != null && Number(t.perCarTrips) !== 0) tripParts.push(`เที่ยว/คัน ${fmt(t.perCarTrips)}`);
    if (t.perCarCubic != null && Number(t.perCarCubic) !== 0) tripParts.push(`ลบ.ม./คัน ${fmt(t.perCarCubic)}`);
    if (tripParts.length) bits.push(tripParts.join(' · '));

    const sandParts: string[] = [];
    if (t.sandMorning != null && Number(t.sandMorning) !== 0) sandParts.push(`ทรายเช้า ${fmt(t.sandMorning)}`);
    if (t.sandAfternoon != null && Number(t.sandAfternoon) !== 0) sandParts.push(`ทรายบ่าย ${fmt(t.sandAfternoon)}`);
    if (t.drumsObtained != null && Number(t.drumsObtained) !== 0) sandParts.push(`ถังได้ ${fmt(t.drumsObtained)}`);
    if (t.drumsWashedAtHome != null && Number(t.drumsWashedAtHome) !== 0) sandParts.push(`ล้างบ้าน ${fmt(t.drumsWashedAtHome)}`);
    if (t.sandMachineType?.trim()) sandParts.push(`เครื่อง ${t.sandMachineType}`);
    const sandTime = [t.sandMorningStart, t.sandAfternoonStart, t.sandEveningEnd].filter(Boolean).join('–');
    if (sandTime) sandParts.push(sandTime);
    if (sandParts.length) bits.push(sandParts.join(' · '));

    if (t.category === 'Fuel' || t.fuelType || t.fuelMovement) {
        const f: string[] = [];
        if (t.fuelType?.trim()) f.push(t.fuelType);
        if (t.fuelMovement === 'stock_in') f.push('รับเข้า');
        else if (t.fuelMovement === 'stock_out') f.push('จ่ายออก');
        if (t.quantity != null && Number(t.quantity) !== 0) f.push(`${fmt(t.quantity)} ${t.unit || 'ลิตร'}`);
        if (f.length) bits.push(f.join(' · '));
    }

    if (t.eventType?.trim() || t.eventPriority?.trim() || t.eventTime?.trim()) {
        const ev: string[] = [];
        if (t.eventTime?.trim()) ev.push(t.eventTime.trim());
        if (t.eventType?.trim()) ev.push(t.eventType.trim());
        if (t.eventPriority?.trim()) ev.push(t.eventPriority.trim());
        bits.push(`เหตุการณ์: ${ev.join(' · ')}`);
    }

    if (t.type === 'Income' && t.incomePaymentStatus?.trim()) {
        bits.push(t.incomePaymentStatus === 'Paid' ? 'รับเงินแล้ว' : 'ยังไม่รับเงิน');
    }

    if (t.workType?.trim()) bits.push(`งาน ${t.workType}`);

    if (t.driverWage != null && Number(t.driverWage) !== 0) bits.push(`ค่าคนขับ ${fmt(t.driverWage)}`);
    if (t.vehicleWage != null && Number(t.vehicleWage) !== 0) bits.push(`ค่ารถ ${fmt(t.vehicleWage)}`);

    if (t.note?.trim()) bits.push(trunc(t.note, 48));
    else if (t.workDetails?.trim()) bits.push(trunc(t.workDetails, 48));

    return bits.join(' · ');
}

export function transactionRecordedTimeLabel(t: Transaction): string {
    if (!t.createdAt) return '';
    const d = new Date(t.createdAt);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleTimeString('th-TH', {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'Asia/Bangkok',
    });
}
