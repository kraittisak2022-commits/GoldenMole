import { supabase } from '../lib/supabase';
import { Employee, Transaction, LandProject, AppSettings, AdminUser, AdminLog, AdminUiTheme, WorkPlan } from '../types';

// ============================================
// Helper: camelCase <-> snake_case conversion
// ============================================
const toSnake = (str: string) => str.replace(/[A-Z]/g, c => '_' + c.toLowerCase());
const toCamel = (str: string) => str.replace(/_([a-z])/g, (_, c) => c.toUpperCase());

const keysToSnake = (obj: any): any => {
    if (Array.isArray(obj)) return obj.map(keysToSnake);
    if (obj && typeof obj === 'object' && !(obj instanceof Date)) {
        return Object.fromEntries(
            Object.entries(obj).map(([k, v]) => [toSnake(k), (typeof v === 'object' && v !== null && !Array.isArray(v)) ? keysToSnake(v) : v])
        );
    }
    return obj;
};

const keysToCamel = (obj: any): any => {
    if (Array.isArray(obj)) return obj.map(keysToCamel);
    if (obj && typeof obj === 'object' && !(obj instanceof Date)) {
        return Object.fromEntries(
            Object.entries(obj).map(([k, v]) => [toCamel(k), (typeof v === 'object' && v !== null && !Array.isArray(v)) ? keysToCamel(v) : v])
        );
    }
    return obj;
};

// ============================================
// EMPLOYEES
// ============================================
export const fetchEmployees = async (): Promise<Employee[]> => {
    const { data, error } = await supabase.from('employees').select('*').order('created_at');
    if (error) { console.error('fetchEmployees error:', error); return []; }
    return (data || []).map(keysToCamel);
};

export const saveEmployee = async (emp: Employee): Promise<boolean> => {
    const row = keysToSnake(emp);
    // Ensure JSON fields are arrays
    if (!row.salary_history) row.salary_history = [];
    if (!row.kpi_history) row.kpi_history = [];
    // Remove computed fields
    delete row.full_days; delete row.half_days; delete row.income; delete row.net;
    delete row.ot; delete row.adv; delete row.special; delete row.base_pay; delete row.is_paid;
    const { error } = await supabase.from('employees').upsert(row, { onConflict: 'id' });
    if (error) { console.error('saveEmployee error:', error); return false; }
    return true;
};

export const deleteEmployee = async (id: string): Promise<boolean> => {
    const { error } = await supabase.from('employees').delete().eq('id', id);
    if (error) { console.error('deleteEmployee error:', error); return false; }
    return true;
};

// ============================================
// TRANSACTIONS
// ============================================
export const fetchTransactions = async (): Promise<Transaction[]> => {
    const { data, error } = await supabase.from('transactions').select('*').order('created_at', { ascending: false });
    if (error) { console.error('fetchTransactions error:', error); return []; }
    return (data || []).map(keysToCamel);
};

export const saveTransaction = async (t: Transaction): Promise<boolean> => {
    const row = keysToSnake(t);
    // Ensure JSON array fields
    if (row.employee_ids && !Array.isArray(row.employee_ids)) row.employee_ids = [];
    if (row.sand_operators && !Array.isArray(row.sand_operators)) row.sand_operators = [];
    const { error } = await supabase.from('transactions').upsert(row, { onConflict: 'id' });
    if (error) { console.error('saveTransaction error:', error); return false; }
    return true;
};

export const deleteTransaction = async (id: string): Promise<boolean> => {
    const { error } = await supabase.from('transactions').delete().eq('id', id);
    if (error) { console.error('deleteTransaction error:', error); return false; }
    return true;
};

/** ลบรายการธุรกรรมทั้งหมด (ใช้ตอนล้างข้อมูลที่บันทึก) */
export const deleteAllTransactions = async (): Promise<void> => {
    const { data } = await supabase.from('transactions').select('id');
    const ids = (data || []).map((r: any) => r.id);
    for (const id of ids) await deleteTransaction(id);
};

// ============================================
// LAND PROJECTS
// ============================================
export const fetchProjects = async (): Promise<LandProject[]> => {
    const { data, error } = await supabase.from('land_projects').select('*').order('created_at');
    if (error) { console.error('fetchProjects error:', error); return []; }
    return (data || []).map((row: any) => {
        const camel = keysToCamel(row);
        // Map group_name -> group
        camel.group = camel.groupName;
        delete camel.groupName;
        camel.sellerName = camel.sellerName;
        camel.titleDeed = camel.titleDeed;
        camel.sqWah = camel.sqWah;
        camel.fullPrice = camel.fullPrice;
        camel.purchaseDate = camel.purchaseDate;
        return camel;
    });
};

export const saveProject = async (p: LandProject): Promise<boolean> => {
    const row: any = keysToSnake(p);
    // Map group -> group_name (avoid SQL reserved word conflict)
    if (row.group !== undefined) {
        row.group_name = row.group;
        delete row.group;
    }
    const { error } = await supabase.from('land_projects').upsert(row, { onConflict: 'id' });
    if (error) { console.error('saveProject error:', error); return false; }
    return true;
};

export const deleteProject = async (id: string): Promise<boolean> => {
    const { error } = await supabase.from('land_projects').delete().eq('id', id);
    if (error) { console.error('deleteProject error:', error); return false; }
    return true;
};

/** ลบโครงการที่ดินทั้งหมด (ใช้ตอนล้างข้อมูลที่บันทึก) */
export const deleteAllProjects = async (): Promise<void> => {
    const { data } = await supabase.from('land_projects').select('id');
    const ids = (data || []).map((r: any) => r.id);
    for (const id of ids) await deleteProject(id);
};

// ============================================
// APP SETTINGS (Singleton)
// ============================================
export const fetchSettings = async (): Promise<AppSettings | null> => {
    const { data, error } = await supabase.from('app_settings').select('*').eq('id', 'default').single();
    if (error) {
        if (error.code === 'PGRST116') return null; // No rows
        console.error('fetchSettings error:', error);
        return null;
    }
    if (!data) return null;
    const s: AppSettings = {
        appName: data.app_name,
        appSubtext: data.app_subtext,
        appIcon: data.app_icon,
        appIconDark: data.app_icon_dark,
        cars: data.cars || [],
        jobDescriptions: data.job_descriptions || [],
        incomeTypes: data.income_types || [],
        expenseTypes: data.expense_types || [],
        maintenanceTypes: data.maintenance_types || [],
        locations: data.locations || [],
        landGroups: data.land_groups || [],
        employeePositions: data.employee_positions || [],
        versionNotes: data.version_notes || [],
        fuelOpeningStockLiters: data.fuel_opening_stock || undefined,
        orgProfile: data.org_profile || undefined,
        appDefaults: data.app_defaults || undefined,
    };
    return s;
};

export const saveSettings = async (s: AppSettings): Promise<boolean> => {
    const row = {
        id: 'default',
        app_name: s.appName,
        app_subtext: s.appSubtext,
        app_icon: s.appIcon,
        app_icon_dark: s.appIconDark || '',
        cars: s.cars,
        job_descriptions: s.jobDescriptions,
        income_types: s.incomeTypes,
        expense_types: s.expenseTypes,
        maintenance_types: s.maintenanceTypes,
        locations: s.locations,
        land_groups: s.landGroups,
        employee_positions: s.employeePositions ?? [],
        version_notes: s.versionNotes ?? [],
        fuel_opening_stock: s.fuelOpeningStockLiters ?? { Diesel: 0, Benzine: 0 },
        org_profile: s.orgProfile ?? {},
        app_defaults: s.appDefaults ?? {},
        updated_at: new Date().toISOString(),
    };
    const { error } = await supabase.from('app_settings').upsert(row, { onConflict: 'id' });
    if (error) { console.error('saveSettings error:', error); return false; }
    return true;
};

// ============================================
// ADMIN USERS
// ============================================
export const fetchAdmins = async (): Promise<AdminUser[]> => {
    const { data, error } = await supabase.from('admin_users').select('*').order('created_at');
    if (error) { console.error('fetchAdmins error:', error); return []; }
    return (data || []).map((row: any) => ({
        id: row.id,
        username: row.username,
        password: row.password,
        displayName: row.display_name,
        role: row.role,
        createdAt: row.created_at,
        lastLogin: row.last_login,
        avatar: row.avatar,
        mustChangePassword: !!row.must_change_password,
        uiTheme: (row.ui_theme as AdminUiTheme | undefined) || 'system',
        sessionActive: !!row.session_active,
        lastClientSurface: (row.last_client_surface as 'select' | 'desktop' | 'mobile' | null) || 'select',
    }));
};

export const saveAdmin = async (admin: AdminUser): Promise<boolean> => {
    const row = {
        id: admin.id,
        username: admin.username,
        password: admin.password,
        display_name: admin.displayName,
        role: admin.role,
        created_at: admin.createdAt,
        last_login: admin.lastLogin || null,
        avatar: admin.avatar || null,
        must_change_password: admin.mustChangePassword ?? false,
        ui_theme: admin.uiTheme ?? 'system',
        session_active: admin.sessionActive ?? false,
        last_client_surface: admin.lastClientSurface ?? 'select',
    };
    const { error } = await supabase.from('admin_users').upsert(row, { onConflict: 'id' });
    if (error) { console.error('saveAdmin error:', error); return false; }
    return true;
};

export const deleteAdmin = async (id: string): Promise<boolean> => {
    const { error } = await supabase.from('admin_users').delete().eq('id', id);
    if (error) { console.error('deleteAdmin error:', error); return false; }
    return true;
};

// ============================================
// ADMIN LOGS
// ============================================
export const fetchAdminLogs = async (): Promise<AdminLog[]> => {
    const { data, error } = await supabase.from('admin_logs').select('*').order('created_at', { ascending: false }).limit(200);
    if (error) { console.error('fetchAdminLogs error:', error); return []; }
    return (data || []).map((row: any) => ({
        id: row.id,
        adminId: row.admin_id,
        adminName: row.admin_name,
        action: row.action,
        details: row.details,
        timestamp: row.timestamp,
    }));
};

export const saveAdminLog = async (log: AdminLog): Promise<boolean> => {
    const row = {
        id: log.id,
        admin_id: log.adminId,
        admin_name: log.adminName,
        action: log.action,
        details: log.details,
        timestamp: log.timestamp,
    };
    const { error } = await supabase.from('admin_logs').insert(row);
    if (error) { console.error('saveAdminLog error:', error); return false; }
    return true;
};

// ============================================
// WORK PLANS
// ============================================
export const fetchWorkPlansByAdmin = async (adminId: string): Promise<WorkPlan[]> => {
    const { data, error } = await supabase
        .from('work_plans')
        .select('*')
        .eq('admin_id', adminId)
        .order('plan_date', { ascending: false })
        .order('created_at', { ascending: false });
    if (error) { console.error('fetchWorkPlansByAdmin error:', error); return []; }
    return (data || []).map((row: any) => ({
        id: row.id,
        adminId: row.admin_id,
        title: row.title,
        note: row.note || undefined,
        planDate: row.plan_date,
        scope: row.scope,
        status: row.status,
        lane: row.lane,
        carryHistory: row.carry_history || [],
        workType: row.work_type || undefined,
        createdAt: row.created_at,
        updatedAt: row.updated_at || undefined,
    }));
};

export const saveWorkPlan = async (plan: WorkPlan): Promise<boolean> => {
    const row = {
        id: plan.id,
        admin_id: plan.adminId,
        title: plan.title,
        note: plan.note || '',
        plan_date: plan.planDate,
        scope: plan.scope,
        status: plan.status,
        lane: plan.lane,
        carry_history: plan.carryHistory || [],
        work_type: plan.workType || '',
        created_at: plan.createdAt,
        updated_at: new Date().toISOString(),
    };
    const { error } = await supabase.from('work_plans').upsert(row, { onConflict: 'id' });
    if (error) { console.error('saveWorkPlan error:', error); return false; }
    return true;
};

export const deleteWorkPlan = async (id: string): Promise<boolean> => {
    const { error } = await supabase.from('work_plans').delete().eq('id', id);
    if (error) { console.error('deleteWorkPlan error:', error); return false; }
    return true;
};

// ============================================
// SEED DATA (first-time initialization)
// ============================================
export const seedDefaultData = async (
    defaultEmployees: Employee[],
    defaultTransactions: Transaction[],
    defaultProjects: LandProject[],
    defaultSettings: AppSettings,
    defaultAdmins: AdminUser[]
): Promise<void> => {
    // Check if data already exists
    const { count: empCount } = await supabase.from('employees').select('*', { count: 'exact', head: true });
    const { count: settingsCount } = await supabase.from('app_settings').select('*', { count: 'exact', head: true });
    const { count: adminCount } = await supabase.from('admin_users').select('*', { count: 'exact', head: true });

    if (!empCount || empCount === 0) {
        console.log('Seeding employees...');
        for (const emp of defaultEmployees) {
            await saveEmployee(emp);
        }
    }

    if (!settingsCount || settingsCount === 0) {
        console.log('Seeding settings...');
        await saveSettings(defaultSettings);
    }

    if (!adminCount || adminCount === 0) {
        console.log('Seeding admin users...');
        for (const admin of defaultAdmins) {
            await saveAdmin(admin);
        }
    }

    // Seed transactions
    const { count: txCount } = await supabase.from('transactions').select('*', { count: 'exact', head: true });
    if (!txCount || txCount === 0) {
        console.log('Seeding transactions...');
        for (const tx of defaultTransactions) {
            await saveTransaction(tx);
        }
    }

    // Seed projects
    const { count: projCount } = await supabase.from('land_projects').select('*', { count: 'exact', head: true });
    if (!projCount || projCount === 0) {
        console.log('Seeding land projects...');
        for (const proj of defaultProjects) {
            await saveProject(proj);
        }
    }

    console.log('Database seed check complete.');
};
