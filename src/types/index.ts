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
    /** กลุ่มงานรายวัน: รหัสกลุ่ม -> รายชื่อ employeeId */
    workAssignments?: Record<string, string[]>;
    /** กลุ่มงานที่ผู้ใช้เพิ่มเองใน Daily Wizard */
    customWorkCategories?: Array<{ id: string; label: string }>;
    otAmount?: number; advanceAmount?: number; specialAmount?: number;
    otHours?: number; // Added for detailed OT tracking
    otDescription?: string; // Added for detailed OT tracking
    leaveReason?: string; leaveDays?: number;
    note?: string;
    workDetails?: string; // Added for Vehicle/General work details
    fuelType?: 'Diesel' | 'Benzine';
    fuelMovement?: 'stock_in' | 'stock_out';
    payrollPeriod?: { start: string; end: string; };
    payrollSnapshot?: any;
    // Daily Log Fields
    machineId?: string;
    machineHours?: number;
    machineWorkType?: string;
    tripCount?: number;
    tripMorning?: number;
    tripAfternoon?: number;
    cubicPerTrip?: number;
    totalCubic?: number;
    perCarTrips?: number;
    perCarCubic?: number;
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
    eventType?: string;
    eventPriority?: string;
    eventTime?: string;
}

export interface SandProduction {
    id: string; date: string; morning: number; afternoon: number; total: number; note?: string;
}

export interface DailyEvent {
    id: string; date: string; time: string; description: string; category?: string;
}

export interface OrgProfile {
    name?: string;
    phone?: string;
    address?: string;
    taxId?: string;
}

export interface AppDefaults {
    sandCubicPerTrip?: number;
    laborWorkCategories?: Array<{ id: string; label: string }>;
    openRouterApiKey?: string;
    workPlannerByAdmin?: Record<string, {
        plans: Array<{
            id: string;
            title: string;
            note?: string;
            planDate: string;
            scope: 'Monthly' | 'Weekly' | 'Daily';
            status: 'Todo' | 'Done';
            createdAt: string;
            ownerAdminId: string;
            lane: 'ท่าทราย' | 'แม่สุข' | 'ทดลองน้ำ';
            carryHistory?: string[];
            workType?: string;
        }>;
        customWorkTypes: string[];
    }>;
    aiUsageLogs?: Array<{
        id: string;
        adminId: string;
        adminName: string;
        prompt: string;
        model: string;
        status: 'success' | 'error';
        message?: string;
        createdAt: string;
    }>;
}

export interface AppSettings {
    appName: string; appSubtext: string; appIcon: string; appIconDark?: string;
    cars: string[]; jobDescriptions: string[]; incomeTypes: string[]; expenseTypes: string[]; maintenanceTypes: string[]; locations: string[]; landGroups: string[];
    employeePositions?: string[];
    versionNotes?: string[];
    fuelOpeningStockLiters?: { Diesel?: number; Benzine?: number };
    orgProfile?: OrgProfile;
    appDefaults?: AppDefaults;
}

export type AdminUiTheme = 'light' | 'dark' | 'system';

export interface AdminUser {
    id: string;
    username: string;
    password: string;
    displayName: string;
    role: 'SuperAdmin' | 'Admin';
    createdAt: string;
    lastLogin?: string;
    avatar?: string;
    mustChangePassword?: boolean;
    uiTheme?: AdminUiTheme;
    /** เซสชันล่าสุดของแอดมิน (ใช้ restore หลังรีเฟรชจากฐานข้อมูล) */
    sessionActive?: boolean;
    /** โหมดหน้าจอล่าสุดที่เลือกไว้ */
    lastClientSurface?: 'select' | 'desktop' | 'mobile';
}

export interface AdminLog {
    id: string;
    adminId: string;
    adminName: string;
    action: string;
    details: string;
    timestamp: string;
}

export interface WorkPlan {
    id: string;
    adminId: string;
    title: string;
    note?: string;
    planDate: string;
    scope: 'Monthly' | 'Weekly' | 'Daily';
    status: 'Todo' | 'Done';
    lane: 'ท่าทราย' | 'แม่สุข' | 'ทดลองน้ำ';
    carryHistory?: string[];
    workType?: string;
    createdAt: string;
    updatedAt?: string;
}
