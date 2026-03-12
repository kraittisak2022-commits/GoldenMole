export type TransactionType = 'Income' | 'Expense' | 'Leave';
export type EmployeeType = 'Daily' | 'Monthly';
export type LandStatus = 'Deposit' | 'PaidFull' | 'Transferred';
export type WorkType = 'FullDay' | 'HalfDay';

export interface SalaryHistoryItem {
    id: string;
    date: string;
    oldWage: number;
    newWage: number;
    reason?: string;
    type: EmployeeType; // To track if they switched from Daily <-> Monthly
}

export interface KPIEvaluation {
    id: string;
    date: string;
    score: number;
    maxScore: number;
    evaluator: string;
    notes?: string;
    criteria?: { label: string; score: number; max: number }[];
}

export interface Employee {
    id: string; name: string; nickname: string; type: EmployeeType; baseWage?: number; phone?: string; startDate?: string;
    /** ตำแหน่งเดียว (เก่า) — ใช้ positions แทนได้ */
    position?: string;
    /** หลายตำแหน่ง เช่น ['คนขับรถ', 'รับจ้างรายวัน'] */
    positions?: string[];
    salaryHistory?: SalaryHistoryItem[];
    kpiHistory?: KPIEvaluation[];
    // Computed fields often added in runtime
    fullDays?: number;
    halfDays?: number;
    income?: number;
    net?: number;
    ot?: number;
    adv?: number;
    special?: number;
    basePay?: number;
    isPaid?: boolean;
}

export interface LandProject {
    id: string; name: string; group?: string; sellerName?: string; titleDeed?: string; rai?: number; ngan?: number; sqWah?: number; fullPrice: number; deposit: number; purchaseDate: string; status: LandStatus; details?: string;
}

export interface Transaction {
    id: string; date: string; type: TransactionType; category: string; subCategory?: string; description: string; amount: number;
    employeeId?: string; employeeIds?: string[]; driverId?: string; driverWage?: number; vehicleWage?: number; vehicleId?: string;
    quantity?: number; unit?: string; unitPrice?: number; projectId?: string; mileage?: number; imageUrl?: string; location?: string;
    laborStatus?: 'Work' | 'Leave' | 'Sick' | 'Personal' | 'OT' | 'Advance';
    workType?: WorkType;
    /** กำหนดเต็มวัน/ครึ่งวันรายคน (บันทึกงานประจำวัน) — ไม่มี = เต็มวัน */
    workTypeByEmployee?: Record<string, WorkType>;
    otAmount?: number; advanceAmount?: number; specialAmount?: number;
    otHours?: number; // Added for detailed OT tracking
    otDescription?: string; // Added for detailed OT tracking
    leaveReason?: string; leaveDays?: number;
    note?: string;
    workDetails?: string; // Added for Vehicle/General work details
    fuelType?: 'Diesel' | 'Benzine';
    payrollPeriod?: { start: string; end: string; };
    payrollSnapshot?: any;
    // Daily Log Fields
    machineId?: string;
    machineHours?: number;
    machineWorkType?: string;
    sandMorning?: number;
    sandAfternoon?: number;
    sandMachineType?: 'Old' | 'New';
    sandOperators?: string[];
    sandTransport?: number;
    /** จำนวนถังที่ได้วันนี้ (จากบันทึกการล้างทราย) */
    drumsObtained?: number;
    /** จำนวนถังที่ล้างที่บ้านวันนี้ (จากขั้นค่าแรง เมื่อมีงานล้างทรายที่บ้าน) */
    drumsWashedAtHome?: number;
    /** บันทึกการล้างทราย: วันเวลาเริ่มงาน (HH:mm) */
    sandWorkStart?: string;
    /** บันทึกการล้างทราย: ช่วงเช้าเริ่มงาน น. (HH:mm) */
    sandMorningStart?: string;
    /** บันทึกการล้างทราย: ช่วงบ่ายเริ่มงาน น. (HH:mm) */
    sandAfternoonStart?: string;
    /** บันทึกการล้างทราย: เย็นหยุดล้าง กี่โมง (HH:mm) */
    sandEveningEnd?: string;
    eventTime?: string;
}

export interface SandProduction {
    id: string; date: string; morning: number; afternoon: number; total: number; note?: string;
}

export interface DailyEvent {
    id: string; date: string; time: string; description: string; category?: string;
}

export interface AppSettings {
    appName: string; appSubtext: string; appIcon: string; appIconDark?: string;
    cars: string[]; jobDescriptions: string[]; incomeTypes: string[]; expenseTypes: string[]; maintenanceTypes: string[]; locations: string[]; landGroups: string[];
}

export interface AdminUser {
    id: string;
    username: string;
    password: string;
    displayName: string;
    role: 'SuperAdmin' | 'Admin';
    createdAt: string;
    lastLogin?: string;
    avatar?: string;
}

export interface AdminLog {
    id: string;
    adminId: string;
    adminName: string;
    action: string;
    details: string;
    timestamp: string;
}
