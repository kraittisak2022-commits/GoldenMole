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

export interface Employee {
    id: string; name: string; nickname: string; type: EmployeeType; baseWage: number; phone?: string; startDate?: string;
    salaryHistory?: SalaryHistoryItem[];
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
    eventTime?: string;
}

export interface SandProduction {
    id: string; date: string; morning: number; afternoon: number; total: number; note?: string;
}

export interface DailyEvent {
    id: string; date: string; time: string; description: string; category?: string;
}

export interface AppSettings {
    appName: string; appSubtext: string; appIcon: string;
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
