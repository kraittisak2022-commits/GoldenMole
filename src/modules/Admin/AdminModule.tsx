import { useMemo, useState } from 'react';
import { Shield, Pencil, Key, Trash2, XCircle, Clock, UserPlus, ShieldCheck, Search, History } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import { AdminUser, AdminLog, AppSettings, AdminRole, AdminDataAccess } from '../../types';
import { hashPasswordForStorage, validateNewPasswordPolicy } from '../../utils/passwordAuth';

interface AdminModuleProps {
    admins: AdminUser[];
    setAdmins: (updater: AdminUser[] | ((prev: AdminUser[]) => AdminUser[])) => void;
    currentAdmin: AdminUser;
    logs: AdminLog[];
    addLog: (action: string, details: string) => void;
    settings: AppSettings;
    setSettings: (updater: AppSettings | ((prev: AppSettings) => AppSettings)) => void;
}

const MENU_PERMISSION_OPTIONS = [
    { id: 'Dashboard', label: 'ภาพรวม' },
    { id: 'DailyWizard', label: 'บันทึกงานประจำวัน' },
    { id: 'WorkPlanner', label: 'วางแผนงาน' },
    { id: 'MonthDataAudit', label: 'ตรวจสอบข้อมูล' },
    { id: 'Employees', label: 'พนักงาน' },
    { id: 'Labor', label: 'ค่าแรง/ลา' },
    { id: 'Vehicle', label: 'การใช้รถ' },
    { id: 'Fuel', label: 'น้ำมัน' },
    { id: 'Maintenance', label: 'ซ่อมบำรุง' },
    { id: 'Land', label: 'ที่ดิน' },
    { id: 'Utilities', label: 'สาธารณูปโภค' },
    { id: 'Income', label: 'รายรับ' },
    { id: 'Payroll', label: 'เงินเดือน' },
    { id: 'DataList', label: 'รายการบันทึก' },
    { id: 'Settings', label: 'ตั้งค่า' },
];

const TX_CATEGORY_PERMISSION_OPTIONS = [
    { id: 'Labor', label: 'ค่าแรง/แรงงาน' },
    { id: 'Vehicle', label: 'การใช้รถ' },
    { id: 'Fuel', label: 'น้ำมัน' },
    { id: 'Maintenance', label: 'ซ่อมบำรุง' },
    { id: 'Land', label: 'ที่ดิน' },
    { id: 'Utilities', label: 'สาธารณูปโภค' },
    { id: 'Income', label: 'รายรับ' },
    { id: 'Payroll', label: 'เงินเดือน' },
    { id: 'PayrollUnlock', label: 'ปลดล็อกงวดเงินเดือน' },
    { id: 'DailyLog', label: 'บันทึกงานประจำวัน (DailyLog)' },
];

const DEFAULT_TRANSACTION_PERMISSIONS = { view: true, create: true, edit: true, delete: true };
type PermissionTemplateKey = 'Assistant' | 'HR' | 'Viewer' | 'Auditor';
const PERMISSION_TEMPLATES: Record<PermissionTemplateKey, { label: string; access: AdminDataAccess }> = {
    Assistant: {
        label: 'Assistant (คีย์ DailyWizard)',
        access: {
            visibleMenus: ['Dashboard', 'DailyWizard'],
            visibleTransactionCategories: ['Labor', 'Vehicle', 'Fuel', 'DailyLog'],
            maskFinancialAmountsAsPercent: true,
            dataEntryDailyWizardOnly: true,
            transactionPermissions: { view: true, create: true, edit: true, delete: false },
        },
    },
    HR: {
        label: 'HR (พนักงาน/ค่าแรง)',
        access: {
            visibleMenus: ['Dashboard', 'Employees', 'Labor', 'Payroll', 'DataList'],
            visibleTransactionCategories: ['Labor', 'Payroll', 'PayrollUnlock'],
            transactionPermissions: { view: true, create: true, edit: true, delete: false },
        },
    },
    Viewer: {
        label: 'Viewer (ดูอย่างเดียว)',
        access: {
            visibleMenus: ['Dashboard', 'MonthDataAudit', 'DataList'],
            visibleTransactionCategories: TX_CATEGORY_PERMISSION_OPTIONS.map(x => x.id),
            transactionPermissions: { view: true, create: false, edit: false, delete: false },
        },
    },
    Auditor: {
        label: 'Auditor (ตรวจสอบ)',
        access: {
            visibleMenus: ['Dashboard', 'MonthDataAudit', 'DataList', 'WorkPlanner'],
            visibleTransactionCategories: TX_CATEGORY_PERMISSION_OPTIONS.map(x => x.id),
            maskFinancialAmountsAsPercent: true,
            transactionPermissions: { view: true, create: false, edit: false, delete: false },
        },
    },
};

const AdminModule = ({ admins, setAdmins, currentAdmin, logs, addLog, settings, setSettings }: AdminModuleProps) => {
    const [activeTab, setActiveTab] = useState<'list' | 'logs'>('list');
    const [showCreateModal, setShowCreateModal] = useState(false);
    const [showEditModal, setShowEditModal] = useState<AdminUser | null>(null);
    const [showPasswordModal, setShowPasswordModal] = useState<AdminUser | null>(null);
    const [search, setSearch] = useState('');
    const [logSearch, setLogSearch] = useState('');
    const [cloneSourceAdminId, setCloneSourceAdminId] = useState('');

    // Create form
    const [createForm, setCreateForm] = useState({ username: '', password: '', confirmPassword: '', displayName: '', role: 'Admin' as AdminRole });
    // Edit form
    const [editForm, setEditForm] = useState({
        displayName: '',
        role: 'Admin' as AdminRole,
        visibleMenus: [] as string[],
        visibleTransactionCategories: [] as string[],
        maskFinancialAmountsAsPercent: false,
        dataEntryDailyWizardOnly: false,
        canView: true,
        canCreate: true,
        canEdit: true,
        canDelete: true,
    });
    // Password form
    const [passwordForm, setPasswordForm] = useState({ newPassword: '', confirmPassword: '' });
    const applyTemplateToEditForm = (key: PermissionTemplateKey) => {
        const access = PERMISSION_TEMPLATES[key].access;
        setEditForm(prev => ({
            ...prev,
            visibleMenus: [...(access.visibleMenus || [])],
            visibleTransactionCategories: [...(access.visibleTransactionCategories || [])],
            maskFinancialAmountsAsPercent: !!access.maskFinancialAmountsAsPercent,
            dataEntryDailyWizardOnly: !!access.dataEntryDailyWizardOnly,
            canView: access.transactionPermissions?.view ?? true,
            canCreate: access.transactionPermissions?.create ?? true,
            canEdit: access.transactionPermissions?.edit ?? true,
            canDelete: access.transactionPermissions?.delete ?? true,
        }));
    };
    const summarizeAccess = (access: AdminDataAccess | undefined) => {
        if (!access) return 'ยังไม่กำหนด';
        const tx = access.transactionPermissions || DEFAULT_TRANSACTION_PERMISSIONS;
        const crud = [
            tx.view ? 'V' : '-',
            tx.create ? 'C' : '-',
            tx.edit ? 'E' : '-',
            tx.delete ? 'D' : '-',
        ].join('');
        return `เมนู ${access.visibleMenus?.length || 0} | หมวด ${access.visibleTransactionCategories?.length || 0} | CRUD ${crud}${access.maskFinancialAmountsAsPercent ? ' | Mask%' : ''}${access.dataEntryDailyWizardOnly ? ' | DW only' : ''}`;
    };
    const parsePermissionLogDiff = (details: string): { before?: AdminDataAccess; after?: AdminDataAccess } | null => {
        const markerBefore = 'before=';
        const markerAfter = ' | after=';
        const iBefore = details.indexOf(markerBefore);
        const iAfter = details.indexOf(markerAfter);
        if (iBefore === -1 || iAfter === -1) return null;
        try {
            const beforeStr = details.slice(iBefore + markerBefore.length, iAfter).trim();
            const afterStr = details.slice(iAfter + markerAfter.length).trim();
            return {
                before: beforeStr ? JSON.parse(beforeStr) : undefined,
                after: afterStr ? JSON.parse(afterStr) : undefined,
            };
        } catch {
            return null;
        }
    };

    const handleCreate = async () => {
        const username = createForm.username.trim();
        const displayName = createForm.displayName.trim();
        if (!username || !createForm.password || !displayName) return alert('กรุณากรอกข้อมูลให้ครบ');
        if (createForm.password !== createForm.confirmPassword) return alert('รหัสผ่านไม่ตรงกัน');
        const policy = validateNewPasswordPolicy(createForm.password);
        if (!policy.ok) return alert(policy.message);
        if (admins.some(a => a.username.toLowerCase() === username.toLowerCase())) return alert('ชื่อผู้ใช้ซ้ำ');

        const hashed = await hashPasswordForStorage(createForm.password);
        const newAdmin: AdminUser = {
            id: typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
                ? crypto.randomUUID()
                : Date.now().toString(),
            username,
            password: hashed,
            displayName,
            role: createForm.role,
            createdAt: new Date().toISOString(),
            mustChangePassword: true,
            uiTheme: 'system',
        };
        setAdmins(prev => [...prev, newAdmin]);
        if (newAdmin.role === 'Assistant') {
            const assistantAccess = PERMISSION_TEMPLATES.Assistant.access;
            setSettings(prev => ({
                ...prev,
                appDefaults: {
                    ...(prev.appDefaults || {}),
                    adminDataAccessByAdminId: {
                        ...(prev.appDefaults?.adminDataAccessByAdminId || {}),
                        [newAdmin.id]: {
                            visibleMenus: [...(assistantAccess.visibleMenus || [])],
                            visibleTransactionCategories: [...(assistantAccess.visibleTransactionCategories || [])],
                            maskFinancialAmountsAsPercent: !!assistantAccess.maskFinancialAmountsAsPercent,
                            dataEntryDailyWizardOnly: !!assistantAccess.dataEntryDailyWizardOnly,
                            transactionPermissions: {
                                ...DEFAULT_TRANSACTION_PERMISSIONS,
                                ...(assistantAccess.transactionPermissions || {}),
                            },
                        },
                    },
                },
            }));
            addLog('permission_template_applied', `กำหนดสิทธิ์อัตโนมัติจาก Template Assistant ให้ @${newAdmin.username}`);
        }
        addLog('create_admin', `สร้างแอดมินใหม่: ${newAdmin.displayName} (@${newAdmin.username}) — ต้องเปลี่ยนรหัสเมื่อเข้าครั้งแรก`);
        setCreateForm({ username: '', password: '', confirmPassword: '', displayName: '', role: 'Admin' });
        setShowCreateModal(false);
    };

    const handleEdit = () => {
        const displayName = editForm.displayName.trim();
        if (!showEditModal || !displayName) return;
        const prevAccess = settings.appDefaults?.adminDataAccessByAdminId?.[showEditModal.id] || {};
        const nextAccess: AdminDataAccess = {
            visibleMenus: [...editForm.visibleMenus],
            visibleTransactionCategories: [...editForm.visibleTransactionCategories],
            maskFinancialAmountsAsPercent: editForm.maskFinancialAmountsAsPercent,
            dataEntryDailyWizardOnly: editForm.dataEntryDailyWizardOnly,
            transactionPermissions: {
                view: editForm.canView,
                create: editForm.canCreate,
                edit: editForm.canEdit,
                delete: editForm.canDelete,
            },
        };
        setAdmins(prev => prev.map(a => a.id === showEditModal.id ? { ...a, displayName, role: editForm.role } : a));
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                adminDataAccessByAdminId: {
                    ...(prev.appDefaults?.adminDataAccessByAdminId || {}),
                    [showEditModal.id]: nextAccess,
                },
            },
        }));
        addLog('edit_admin', `แก้ไขข้อมูล: ${showEditModal.displayName} → ${editForm.displayName}`);
        addLog('permission_change', `ปรับสิทธิ์ @${showEditModal.username} | before=${JSON.stringify(prevAccess)} | after=${JSON.stringify(nextAccess)}`);
        setShowEditModal(null);
    };

    const handleChangePassword = async () => {
        if (!showPasswordModal || !passwordForm.newPassword) return;
        if (passwordForm.newPassword !== passwordForm.confirmPassword) return alert('รหัสผ่านไม่ตรงกัน');
        const policy = validateNewPasswordPolicy(passwordForm.newPassword);
        if (!policy.ok) return alert(policy.message);
        const hashed = await hashPasswordForStorage(passwordForm.newPassword);
        setAdmins(prev => prev.map(a => a.id === showPasswordModal!.id ? { ...a, password: hashed, mustChangePassword: false } : a));
        addLog('change_password', `เปลี่ยนรหัสผ่าน: ${showPasswordModal.displayName}`);
        setPasswordForm({ newPassword: '', confirmPassword: '' });
        setShowPasswordModal(null);
    };

    const handleDelete = (admin: AdminUser) => {
        if (admin.id === currentAdmin.id) return alert('ไม่สามารถลบตัวเองได้');
        if (!confirm(`ยืนยันลบ "${admin.displayName}"?`)) return;
        setAdmins(prev => prev.filter(a => a.id !== admin.id));
        setSettings(prev => {
            const prevAccess = prev.appDefaults?.adminDataAccessByAdminId || {};
            if (!(admin.id in prevAccess)) return prev;
            const nextAccess = { ...prevAccess };
            delete nextAccess[admin.id];
            return {
                ...prev,
                appDefaults: {
                    ...(prev.appDefaults || {}),
                    adminDataAccessByAdminId: nextAccess,
                },
            };
        });
        addLog('delete_admin', `ลบแอดมิน: ${admin.displayName} (@${admin.username})`);
    };

    const openEditModal = (admin: AdminUser) => {
        const access = settings.appDefaults?.adminDataAccessByAdminId?.[admin.id];
        setEditForm({
            displayName: admin.displayName,
            role: admin.role,
            visibleMenus: [...(access?.visibleMenus || [])],
            visibleTransactionCategories: [...(access?.visibleTransactionCategories || [])],
            maskFinancialAmountsAsPercent: !!access?.maskFinancialAmountsAsPercent,
            dataEntryDailyWizardOnly: !!access?.dataEntryDailyWizardOnly,
            canView: access?.transactionPermissions?.view ?? true,
            canCreate: access?.transactionPermissions?.create ?? true,
            canEdit: access?.transactionPermissions?.edit ?? true,
            canDelete: access?.transactionPermissions?.delete ?? true,
        });
        setShowEditModal(admin);
        setCloneSourceAdminId('');
    };
    const toggleFromList = (arr: string[], id: string) => (
        arr.includes(id) ? arr.filter(x => x !== id) : [...arr, id]
    );

    const filteredAdmins = admins.filter(a => a.displayName.toLowerCase().includes(search.toLowerCase()) || a.username.toLowerCase().includes(search.toLowerCase()));
    const filteredLogs = logs.filter(l => l.action.includes(logSearch) || l.details.includes(logSearch) || l.adminName.includes(logSearch));
    const permissionMatrixRows = useMemo(() => admins.map(admin => ({
        admin,
        access: settings.appDefaults?.adminDataAccessByAdminId?.[admin.id],
    })), [admins, settings.appDefaults?.adminDataAccessByAdminId]);

    return (
        <div className="space-y-6 animate-fade-in">
            {/* Tab Switcher */}
            <div className="flex justify-center">
                <div className="bg-white p-1 rounded-xl shadow-sm flex gap-1">
                    <button onClick={() => setActiveTab('list')} className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all ${activeTab === 'list' ? 'bg-slate-800 text-white' : 'text-slate-500 hover:bg-slate-50'}`}>
                        <Shield size={16} /> จัดการสมาชิก
                    </button>
                    <button onClick={() => setActiveTab('logs')} className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all ${activeTab === 'logs' ? 'bg-slate-800 text-white' : 'text-slate-500 hover:bg-slate-50'}`}>
                        <History size={16} /> ประวัติการใช้งาน
                    </button>
                </div>
            </div>

            {activeTab === 'list' ? (
                <>
                    {/* Admin Stats */}
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                        <Card className="p-5 flex items-center gap-4">
                            <div className="w-12 h-12 rounded-xl bg-emerald-50 flex items-center justify-center"><Shield className="text-emerald-600" size={24} /></div>
                            <div><p className="text-2xl font-bold text-slate-800">{admins.length}</p><p className="text-xs text-slate-500">แอดมินทั้งหมด</p></div>
                        </Card>
                        <Card className="p-5 flex items-center gap-4">
                            <div className="w-12 h-12 rounded-xl bg-purple-50 flex items-center justify-center"><ShieldCheck className="text-purple-600" size={24} /></div>
                            <div><p className="text-2xl font-bold text-slate-800">{admins.filter(a => a.role === 'SuperAdmin').length}</p><p className="text-xs text-slate-500">SuperAdmin</p></div>
                        </Card>
                        <Card className="p-5 flex items-center gap-4">
                            <div className="w-12 h-12 rounded-xl bg-blue-50 flex items-center justify-center"><Clock className="text-blue-600" size={24} /></div>
                            <div><p className="text-2xl font-bold text-slate-800">{logs.length}</p><p className="text-xs text-slate-500">กิจกรรมทั้งหมด</p></div>
                        </Card>
                    </div>

                    {/* Toolbar */}
                    <Card className="p-3 sm:p-4 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
                        <div className="relative w-full sm:w-64">
                            <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="ค้นหาแอดมิน..." className="w-full pl-9 pr-4 py-2 text-sm border rounded-lg focus:outline-none focus:border-emerald-400 focus:ring-1 focus:ring-emerald-400/30" />
                        </div>
                        <Button onClick={() => setShowCreateModal(true)} className="flex items-center gap-2 whitespace-nowrap">
                            <UserPlus size={16} /> เพิ่มแอดมิน
                        </Button>
                    </Card>

                    {/* Admin List */}
                    <div className="grid grid-cols-1 gap-3">
                        {filteredAdmins.map(admin => (
                            <Card key={admin.id} className={`p-4 sm:p-5 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 ${admin.id === currentAdmin.id ? 'ring-2 ring-emerald-200' : ''}`}>
                                <div className="flex items-center gap-4">
                                    <div className="w-12 h-12 rounded-full bg-gradient-to-br from-slate-700 to-slate-900 flex items-center justify-center text-white font-bold text-lg shrink-0">
                                        {admin.displayName.charAt(0)}
                                    </div>
                                    <div>
                                        <div className="flex items-center gap-2 flex-wrap">
                                            <h4 className="font-bold text-lg text-slate-800">{admin.displayName}</h4>
                                            <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${
                                                admin.role === 'SuperAdmin'
                                                    ? 'bg-purple-100 text-purple-700'
                                                    : admin.role === 'Assistant'
                                                        ? 'bg-emerald-100 text-emerald-700'
                                                        : 'bg-blue-100 text-blue-700'
                                            }`}>
                                                {admin.role}
                                            </span>
                                            {admin.id === currentAdmin.id && (
                                                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-700">คุณ</span>
                                            )}
                                        </div>
                                        <p className="text-sm text-slate-500">@{admin.username}</p>
                                        <p className="text-xs text-slate-400 mt-0.5">สร้างเมื่อ {admin.createdAt}{admin.lastLogin ? ` • เข้าใช้ล่าสุด: ${admin.lastLogin}` : ''}</p>
                                    </div>
                                </div>
                                <div className="flex gap-2 shrink-0">
                                    <button onClick={() => openEditModal(admin)} className="p-2 hover:bg-slate-100 rounded-lg text-slate-400 hover:text-slate-700 transition-colors" title="แก้ไข">
                                        <Pencil size={16} />
                                    </button>
                                    <button onClick={() => { setPasswordForm({ newPassword: '', confirmPassword: '' }); setShowPasswordModal(admin); }} className="p-2 hover:bg-amber-50 rounded-lg text-slate-400 hover:text-amber-600 transition-colors" title="เปลี่ยนรหัส">
                                        <Key size={16} />
                                    </button>
                                    <button onClick={() => handleDelete(admin)} className="p-2 hover:bg-red-50 rounded-lg text-slate-400 hover:text-red-500 transition-colors" title="ลบ" disabled={admin.id === currentAdmin.id}>
                                        <Trash2 size={16} />
                                    </button>
                                </div>
                            </Card>
                        ))}
                    </div>
                    <Card className="p-0 overflow-hidden">
                        <div className="p-3 sm:p-4 bg-slate-50 border-b">
                            <h3 className="font-bold text-slate-800">Permission Matrix</h3>
                            <p className="text-xs text-slate-500">ภาพรวมสิทธิ์ของแต่ละบัญชี (Role + เมนู + หมวดข้อมูล + CRUD)</p>
                        </div>
                        <div className="max-h-[320px] overflow-auto">
                            <table className="w-full text-xs sm:text-sm">
                                <thead className="sticky top-0 bg-white border-b">
                                    <tr>
                                        <th className="p-2 sm:p-3 text-left text-slate-500">ผู้ใช้</th>
                                        <th className="p-2 sm:p-3 text-left text-slate-500">Role</th>
                                        <th className="p-2 sm:p-3 text-left text-slate-500">Matrix</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y">
                                    {permissionMatrixRows.map(({ admin, access }) => (
                                        <tr key={`${admin.id}_matrix`}>
                                            <td className="p-2 sm:p-3 text-slate-700">{admin.displayName} <span className="text-slate-400">@{admin.username}</span></td>
                                            <td className="p-2 sm:p-3 text-slate-600">{admin.role}</td>
                                            <td className="p-2 sm:p-3 text-slate-600">{summarizeAccess(access)}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    </Card>
                </>
            ) : (
                /* Activity Logs Tab */
                <Card className="p-0 overflow-hidden">
                    <div className="p-3 sm:p-4 bg-slate-50 border-b flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2">
                        <h3 className="font-bold flex items-center gap-2"><Clock size={18} /> ประวัติการใช้งาน (Activity Log)</h3>
                        <div className="relative w-full sm:w-48">
                            <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                            <input value={logSearch} onChange={e => setLogSearch(e.target.value)} placeholder="ค้นหา..." className="w-full pl-8 pr-3 py-1.5 text-xs border rounded-lg focus:outline-none focus:border-emerald-400" />
                        </div>
                    </div>
                    <div className="max-h-[600px] overflow-y-auto overflow-x-auto">
                        <table className="w-full text-sm text-left min-w-[500px]">
                            <thead className="bg-white sticky top-0 border-b">
                                <tr>
                                    <th className="p-3 sm:p-4 text-slate-500 font-medium">เวลา</th>
                                    <th className="p-3 sm:p-4 text-slate-500 font-medium">ผู้ดำเนินการ</th>
                                    <th className="p-3 sm:p-4 text-slate-500 font-medium">การดำเนินการ</th>
                                    <th className="p-3 sm:p-4 text-slate-500 font-medium">รายละเอียด</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y">
                                {filteredLogs.length === 0 ? (
                                    <tr><td colSpan={4} className="p-8 text-center text-slate-400">ไม่มีประวัติ</td></tr>
                                ) : (
                                    filteredLogs.map(log => (
                                        <tr key={log.id} className="hover:bg-slate-50">
                                            <td className="p-3 sm:p-4 whitespace-nowrap text-slate-500 text-xs">{log.timestamp}</td>
                                            <td className="p-3 sm:p-4 whitespace-nowrap">
                                                <span className="font-medium text-slate-700">{log.adminName}</span>
                                            </td>
                                            <td className="p-3 sm:p-4">
                                                <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${log.action === 'login' ? 'bg-emerald-100 text-emerald-700' :
                                                    log.action === 'logout' ? 'bg-slate-100 text-slate-700' :
                                                        log.action === 'create_admin' ? 'bg-blue-100 text-blue-700' :
                                                            log.action === 'delete_admin' ? 'bg-red-100 text-red-700' :
                                                                log.action === 'change_password' ? 'bg-amber-100 text-amber-700' :
                                                                    log.action === 'profile_update' ? 'bg-teal-100 text-teal-700' :
                                                                    'bg-purple-100 text-purple-700'
                                                    }`}>
                                                    {log.action === 'login' ? 'เข้าสู่ระบบ' :
                                                        log.action === 'logout' ? 'ออกจากระบบ' :
                                                            log.action === 'create_admin' ? 'สร้างแอดมิน' :
                                                                log.action === 'delete_admin' ? 'ลบแอดมิน' :
                                                                    log.action === 'change_password' ? 'เปลี่ยนรหัส' :
                                                                        log.action === 'profile_update' ? 'โปรไฟล์' :
                                                                        log.action === 'edit_admin' ? 'แก้ไขข้อมูล' : log.action}
                                                </span>
                                            </td>
                                            <td className="p-3 sm:p-4 text-slate-600">
                                                {log.action === 'permission_change' ? (() => {
                                                    const parsed = parsePermissionLogDiff(log.details);
                                                    if (!parsed) return log.details;
                                                    return (
                                                        <div className="space-y-1">
                                                            <p className="text-[11px] text-slate-500">เปลี่ยนสิทธิ์ {log.adminName}</p>
                                                            <p className="text-[11px]"><span className="font-semibold">ก่อน:</span> {summarizeAccess(parsed.before)}</p>
                                                            <p className="text-[11px]"><span className="font-semibold">หลัง:</span> {summarizeAccess(parsed.after)}</p>
                                                        </div>
                                                    );
                                                })() : log.details}
                                            </td>
                                        </tr>
                                    ))
                                )}
                            </tbody>
                        </table>
                    </div>
                </Card>
            )}

            {/* Create Admin Modal */}
            {showCreateModal && (
                <div className="fixed inset-0 bg-black/50 flex items-start sm:items-center justify-center z-[110] p-4 overflow-y-auto">
                    <Card className="w-full max-w-md p-6 relative animate-slide-up my-4 max-h-[calc(100dvh-2rem)] overflow-y-auto">
                        <button onClick={() => setShowCreateModal(false)} className="absolute top-4 right-4 text-slate-400 hover:text-slate-600"><XCircle /></button>
                        <h3 className="text-lg font-bold mb-6 flex items-center gap-2"><UserPlus className="text-emerald-500" size={20} /> เพิ่มแอดมินใหม่</h3>
                        <div className="space-y-4">
                            <Input label="ชื่อที่แสดง (Display Name)" value={createForm.displayName} onChange={(e: any) => setCreateForm({ ...createForm, displayName: e.target.value })} placeholder="เช่น Admin สมชาย" />
                            <Input label="ชื่อผู้ใช้ (Username)" value={createForm.username} onChange={(e: any) => setCreateForm({ ...createForm, username: e.target.value })} placeholder="ตัวอักษรภาษาอังกฤษ" />
                            <Input label="รหัสผ่าน" type="password" value={createForm.password} onChange={(e: any) => setCreateForm({ ...createForm, password: e.target.value })} />
                            <Input label="ยืนยันรหัสผ่าน" type="password" value={createForm.confirmPassword} onChange={(e: any) => setCreateForm({ ...createForm, confirmPassword: e.target.value })} />
                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">บทบาท (Role)</label>
                                <div className="flex gap-3">
                                    <button onClick={() => setCreateForm({ ...createForm, role: 'Admin' })} className={`flex-1 px-4 py-2.5 rounded-lg border text-sm font-medium transition-all ${createForm.role === 'Admin' ? 'bg-blue-50 border-blue-300 text-blue-700' : 'bg-white'}`}>Admin</button>
                                    <button onClick={() => setCreateForm({ ...createForm, role: 'Assistant' })} className={`flex-1 px-4 py-2.5 rounded-lg border text-sm font-medium transition-all ${createForm.role === 'Assistant' ? 'bg-emerald-50 border-emerald-300 text-emerald-700' : 'bg-white'}`}>Assistant</button>
                                    <button onClick={() => setCreateForm({ ...createForm, role: 'SuperAdmin' })} className={`flex-1 px-4 py-2.5 rounded-lg border text-sm font-medium transition-all ${createForm.role === 'SuperAdmin' ? 'bg-purple-50 border-purple-300 text-purple-700' : 'bg-white'}`}>SuperAdmin</button>
                                </div>
                                {createForm.role === 'Assistant' && (
                                    <p className="text-xs text-emerald-700">ระบบจะตั้งสิทธิ์พื้นฐาน Assistant อัตโนมัติ (DailyWizard only + mask ยอดเงิน + จำกัดสิทธิ์ลบ)</p>
                                )}
                            </div>
                            <Button onClick={handleCreate} className="w-full mt-2">สร้างแอดมิน</Button>
                        </div>
                    </Card>
                </div>
            )}

            {/* Edit Admin Modal */}
            {showEditModal && (
                <div className="fixed inset-0 bg-black/50 flex items-start sm:items-center justify-center z-[110] p-4 overflow-y-auto">
                    <Card className="w-full max-w-md p-6 relative animate-slide-up my-4 max-h-[calc(100dvh-2rem)] overflow-y-auto">
                        <button onClick={() => setShowEditModal(null)} className="absolute top-4 right-4 text-slate-400 hover:text-slate-600"><XCircle /></button>
                        <h3 className="text-lg font-bold mb-6 flex items-center gap-2"><Pencil className="text-blue-500" size={20} /> แก้ไขข้อมูล: {showEditModal.username}</h3>
                        <div className="space-y-4">
                            <Input label="ชื่อที่แสดง" value={editForm.displayName} onChange={(e: any) => setEditForm({ ...editForm, displayName: e.target.value })} />
                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">บทบาท (Role)</label>
                                <div className="flex gap-3">
                                    <button onClick={() => setEditForm({ ...editForm, role: 'Admin' })} className={`flex-1 px-4 py-2.5 rounded-lg border text-sm font-medium transition-all ${editForm.role === 'Admin' ? 'bg-blue-50 border-blue-300 text-blue-700' : 'bg-white'}`}>Admin</button>
                                    <button onClick={() => { setEditForm({ ...editForm, role: 'Assistant' }); applyTemplateToEditForm('Assistant'); }} className={`flex-1 px-4 py-2.5 rounded-lg border text-sm font-medium transition-all ${editForm.role === 'Assistant' ? 'bg-emerald-50 border-emerald-300 text-emerald-700' : 'bg-white'}`}>Assistant</button>
                                    <button onClick={() => setEditForm({ ...editForm, role: 'SuperAdmin' })} className={`flex-1 px-4 py-2.5 rounded-lg border text-sm font-medium transition-all ${editForm.role === 'SuperAdmin' ? 'bg-purple-50 border-purple-300 text-purple-700' : 'bg-white'}`}>SuperAdmin</button>
                                </div>
                            </div>
                            {editForm.role !== 'SuperAdmin' && (
                                <>
                                    <div className="flex flex-col gap-2 rounded-xl border border-emerald-200 bg-emerald-50/60 p-3">
                                        <label className="text-xs font-bold text-emerald-700 uppercase tracking-wider">Clone Permission</label>
                                        <div className="flex flex-col sm:flex-row gap-2">
                                            <select
                                                value={cloneSourceAdminId}
                                                onChange={(e) => setCloneSourceAdminId(e.target.value)}
                                                className="flex-1 rounded-lg border border-emerald-200 bg-white px-3 py-2 text-sm text-slate-700"
                                            >
                                                <option value="">เลือกบัญชีต้นแบบ...</option>
                                                {admins.filter(a => a.id !== showEditModal.id).map(a => (
                                                    <option key={`${a.id}_clone`} value={a.id}>{a.displayName} (@{a.username})</option>
                                                ))}
                                            </select>
                                            <button
                                                type="button"
                                                className="rounded-lg border border-emerald-300 bg-white px-3 py-2 text-sm font-medium text-emerald-800 hover:bg-emerald-100"
                                                onClick={() => {
                                                    if (!cloneSourceAdminId) return;
                                                    const source = settings.appDefaults?.adminDataAccessByAdminId?.[cloneSourceAdminId];
                                                    if (!source) return;
                                                    setEditForm(prev => ({
                                                        ...prev,
                                                        visibleMenus: [...(source.visibleMenus || [])],
                                                        visibleTransactionCategories: [...(source.visibleTransactionCategories || [])],
                                                        maskFinancialAmountsAsPercent: !!source.maskFinancialAmountsAsPercent,
                                                        dataEntryDailyWizardOnly: !!source.dataEntryDailyWizardOnly,
                                                        canView: source.transactionPermissions?.view ?? true,
                                                        canCreate: source.transactionPermissions?.create ?? true,
                                                        canEdit: source.transactionPermissions?.edit ?? true,
                                                        canDelete: source.transactionPermissions?.delete ?? true,
                                                    }));
                                                }}
                                            >
                                                คัดลอกสิทธิ์
                                            </button>
                                        </div>
                                    </div>
                                    <div className="flex flex-col gap-2 rounded-xl border border-violet-200 bg-violet-50/60 p-3">
                                        <label className="text-xs font-bold text-violet-700 uppercase tracking-wider">Permission Templates</label>
                                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                                            {(Object.keys(PERMISSION_TEMPLATES) as PermissionTemplateKey[]).map((key) => (
                                                <button
                                                    key={key}
                                                    type="button"
                                                    className="rounded-lg border border-violet-200 bg-white px-3 py-2 text-left text-xs font-medium text-violet-800 hover:bg-violet-100"
                                                    onClick={() => applyTemplateToEditForm(key)}
                                                >
                                                    {PERMISSION_TEMPLATES[key].label}
                                                </button>
                                            ))}
                                        </div>
                                    </div>
                                    <div className="flex flex-col gap-2 rounded-xl border border-cyan-200 bg-cyan-50/60 p-3">
                                        <label className="text-xs font-bold text-cyan-700 uppercase tracking-wider">สิทธิ์จัดการข้อมูล (CRUD)</label>
                                        <div className="grid grid-cols-2 gap-2">
                                            <label className="flex items-center gap-2 text-sm text-slate-700"><input type="checkbox" checked={editForm.canView} onChange={(e) => setEditForm({ ...editForm, canView: e.target.checked })} /> ดูข้อมูล (View)</label>
                                            <label className="flex items-center gap-2 text-sm text-slate-700"><input type="checkbox" checked={editForm.canCreate} onChange={(e) => setEditForm({ ...editForm, canCreate: e.target.checked })} /> สร้าง (Create)</label>
                                            <label className="flex items-center gap-2 text-sm text-slate-700"><input type="checkbox" checked={editForm.canEdit} onChange={(e) => setEditForm({ ...editForm, canEdit: e.target.checked })} /> แก้ไข (Edit)</label>
                                            <label className="flex items-center gap-2 text-sm text-slate-700"><input type="checkbox" checked={editForm.canDelete} onChange={(e) => setEditForm({ ...editForm, canDelete: e.target.checked })} /> ลบ (Delete)</label>
                                        </div>
                                    </div>
                                    <div className="flex flex-col gap-2 rounded-xl border border-slate-200 p-3">
                                        <div className="flex items-center justify-between">
                                            <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">เมนูที่มองเห็นได้</label>
                                            <button
                                                type="button"
                                                className="text-xs text-blue-600 hover:underline"
                                                onClick={() => setEditForm({ ...editForm, visibleMenus: MENU_PERMISSION_OPTIONS.map(x => x.id) })}
                                            >
                                                เลือกทั้งหมด
                                            </button>
                                        </div>
                                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                                            {MENU_PERMISSION_OPTIONS.map(option => (
                                                <label key={option.id} className="flex items-center gap-2 text-sm text-slate-700">
                                                    <input
                                                        type="checkbox"
                                                        checked={editForm.visibleMenus.includes(option.id)}
                                                        onChange={() => setEditForm({ ...editForm, visibleMenus: toggleFromList(editForm.visibleMenus, option.id) })}
                                                    />
                                                    <span>{option.label}</span>
                                                </label>
                                            ))}
                                        </div>
                                    </div>
                                    <div className="flex flex-col gap-2 rounded-xl border border-slate-200 p-3">
                                        <div className="flex items-center justify-between">
                                            <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">หมวดข้อมูลที่มองเห็นได้</label>
                                            <button
                                                type="button"
                                                className="text-xs text-blue-600 hover:underline"
                                                onClick={() => setEditForm({ ...editForm, visibleTransactionCategories: TX_CATEGORY_PERMISSION_OPTIONS.map(x => x.id) })}
                                            >
                                                เลือกทั้งหมด
                                            </button>
                                        </div>
                                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                                            {TX_CATEGORY_PERMISSION_OPTIONS.map(option => (
                                                <label key={option.id} className="flex items-center gap-2 text-sm text-slate-700">
                                                    <input
                                                        type="checkbox"
                                                        checked={editForm.visibleTransactionCategories.includes(option.id)}
                                                        onChange={() => setEditForm({ ...editForm, visibleTransactionCategories: toggleFromList(editForm.visibleTransactionCategories, option.id) })}
                                                    />
                                                    <span>{option.label}</span>
                                                </label>
                                            ))}
                                        </div>
                                    </div>
                                    <label className="mt-1 flex items-center gap-2 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900">
                                        <input
                                            type="checkbox"
                                            checked={editForm.maskFinancialAmountsAsPercent}
                                            onChange={(e) => setEditForm({ ...editForm, maskFinancialAmountsAsPercent: e.target.checked })}
                                        />
                                        <span>ซ่อนยอดเงินทั้งหมด และแสดงเฉพาะสัดส่วนเป็นเปอร์เซ็นต์ (%)</span>
                                    </label>
                                    <label className="mt-1 flex items-center gap-2 rounded-xl border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-900">
                                        <input
                                            type="checkbox"
                                            checked={editForm.dataEntryDailyWizardOnly}
                                            onChange={(e) => setEditForm({ ...editForm, dataEntryDailyWizardOnly: e.target.checked })}
                                        />
                                        <span>สิทธิ์คีย์ข้อมูลได้เฉพาะเมนู บันทึกงานประจำวัน (Daily Wizard)</span>
                                    </label>
                                </>
                            )}
                            <Button onClick={handleEdit} className="w-full mt-2">บันทึก</Button>
                        </div>
                    </Card>
                </div>
            )}

            {/* Change Password Modal */}
            {showPasswordModal && (
                <div className="fixed inset-0 bg-black/50 flex items-start sm:items-center justify-center z-[110] p-4 overflow-y-auto">
                    <Card className="w-full max-w-md p-6 relative animate-slide-up my-4 max-h-[calc(100dvh-2rem)] overflow-y-auto">
                        <button onClick={() => setShowPasswordModal(null)} className="absolute top-4 right-4 text-slate-400 hover:text-slate-600"><XCircle /></button>
                        <h3 className="text-lg font-bold mb-6 flex items-center gap-2"><Key className="text-amber-500" size={20} /> เปลี่ยนรหัสผ่าน: {showPasswordModal.displayName}</h3>
                        <div className="space-y-4">
                            <Input label="รหัสผ่านใหม่" type="password" value={passwordForm.newPassword} onChange={(e: any) => setPasswordForm({ ...passwordForm, newPassword: e.target.value })} />
                            <Input label="ยืนยันรหัสผ่านใหม่" type="password" value={passwordForm.confirmPassword} onChange={(e: any) => setPasswordForm({ ...passwordForm, confirmPassword: e.target.value })} />
                            <Button onClick={handleChangePassword} className="w-full mt-2">เปลี่ยนรหัสผ่าน</Button>
                        </div>
                    </Card>
                </div>
            )}
        </div>
    );
};

export default AdminModule;
