import { useState, useEffect } from 'react';
import { Plus, Trash2, Pencil, Check, X, RefreshCw, Globe, Wifi, Database, Server, ShieldAlert, Droplets, Building2, SlidersHorizontal, Info, UserCircle, Lock, Sun, Moon, Monitor } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import { AppSettings, AdminUser, AdminUiTheme } from '../../types';
import { supabase } from '../../lib/supabase';

interface SettingsModuleProps {
    settings: AppSettings;
    setSettings: (settings: AppSettings | ((prev: AppSettings) => AppSettings)) => void;
    onClearAllData?: () => Promise<void>;
    currentAdmin?: AdminUser | null;
    onUpdateAdminProfile?: (updates: {
        displayName?: string;
        avatar?: string;
        uiTheme?: AdminUiTheme;
        currentPassword?: string;
        newPassword?: string;
    }) => Promise<{ ok: boolean; message?: string }>;
}

const TAB_HELP: Record<string, string> = {
    cars: 'รายชื่อรถ/แม็คโคร/ดรัม ใช้ในเมนู «การใช้รถ», «น้ำมัน», และบันทึกงานประจำวัน (เที่ยวรถ / เติมน้ำมัน)',
    jobDescriptions: 'ตัวเลือก «งานที่ทำ» สำหรับค่าแรงและรายงานที่เกี่ยวข้อง',
    incomeTypes: 'ประเภทรายรับ ใช้ตอนบันทึกรายรับและบางรายงานสรุป',
    expenseTypes: 'ประเภทค่าใช้จ่ายในเมนู «สาธารณูปโภค» (ไฟ น้ำ ฯลฯ)',
    maintenanceTypes: 'ประเภทซ่อม เช่น เปลี่ยนถ่ายน้ำมันเครื่อง ปะยาง — ใช้ในเมนูซ่อมบำรุง',
    locations: 'สถานที่/หน้างาน ให้เลือกตอนบันทึกการใช้รถและที่เกี่ยวข้อง',
    landGroups: 'กลุ่ม/โครงการที่ดิน ใช้จัดหมวดโครงการที่ดิน',
};

const LIST_TAB_KEYS = ['cars', 'jobDescriptions', 'incomeTypes', 'expenseTypes', 'maintenanceTypes', 'locations', 'landGroups'] as const;

const POSITIONS_STORAGE_KEY = 'app_employee_positions';

type StatusState = 'checking' | 'online' | 'offline' | 'degraded' | 'unknown';

const SettingsModule = ({ settings, setSettings, onClearAllData, currentAdmin, onUpdateAdminProfile }: SettingsModuleProps) => {
    const [activeTab, setActiveTab] = useState('general');
    const [newItem, setNewItem] = useState('');
    const [isCheckingStatus, setIsCheckingStatus] = useState(false);
    const [lastCheckedAt, setLastCheckedAt] = useState<string | null>(null);
    const [status, setStatus] = useState<{
        online: StatusState;
        host: StatusState;
        dns: StatusState;
        database: StatusState;
        latencyMs: number | null;
        browser: string;
        networkType: string;
        hostname: string;
        notes: string[];
    }>({
        online: 'unknown',
        host: 'unknown',
        dns: 'unknown',
        database: 'unknown',
        latencyMs: null,
        browser: navigator.userAgent,
        networkType: 'unknown',
        hostname: window.location.host || 'localhost',
        notes: [],
    });
    const appVersion = import.meta.env.VITE_APP_VERSION || '0.0.0';
    const rawUpdatedAt = import.meta.env.VITE_APP_UPDATED_AT || document.lastModified || '';
    const parsedUpdatedAt = rawUpdatedAt ? new Date(rawUpdatedAt) : null;
    const appUpdatedAt = parsedUpdatedAt && !Number.isNaN(parsedUpdatedAt.getTime())
        ? parsedUpdatedAt.toLocaleString('th-TH')
        : (rawUpdatedAt || '-');

    // General Form (รวม appSubtext)
    const [generalForm, setGeneralForm] = useState({
        name: settings.appName,
        subtext: settings.appSubtext,
        icon: settings.appIcon,
        iconDark: settings.appIconDark || ''
    });
    // แก้ไขรายการใน list: { tabKey: { index: number, value: string } }
    const [editingItem, setEditingItem] = useState<{ index: number; value: string } | null>(null);

    const [orgForm, setOrgForm] = useState({
        name: settings.orgProfile?.name || '',
        phone: settings.orgProfile?.phone || '',
        address: settings.orgProfile?.address || '',
        taxId: settings.orgProfile?.taxId || '',
    });
    const [fuelStockForm, setFuelStockForm] = useState({
        diesel: String(settings.fuelOpeningStockLiters?.Diesel ?? 0),
        benzine: String(settings.fuelOpeningStockLiters?.Benzine ?? 0),
    });
    const [defaultsForm, setDefaultsForm] = useState({
        sandCubicPerTrip: String(settings.appDefaults?.sandCubicPerTrip ?? 3),
    });

    const [accountForm, setAccountForm] = useState({
        displayName: '',
        avatar: '',
        uiTheme: 'system' as AdminUiTheme,
        currentPassword: '',
        newPassword: '',
        confirmPassword: '',
    });
    const [accountSaving, setAccountSaving] = useState(false);
    const [accountMsg, setAccountMsg] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);

    useEffect(() => {
        if (!currentAdmin) return;
        setAccountForm({
            displayName: currentAdmin.displayName,
            avatar: currentAdmin.avatar || '',
            uiTheme: currentAdmin.uiTheme ?? 'system',
            currentPassword: '',
            newPassword: '',
            confirmPassword: '',
        });
        setAccountMsg(null);
    }, [currentAdmin?.id]);

    useEffect(() => {
        setOrgForm({
            name: settings.orgProfile?.name || '',
            phone: settings.orgProfile?.phone || '',
            address: settings.orgProfile?.address || '',
            taxId: settings.orgProfile?.taxId || '',
        });
    }, [settings.orgProfile]);

    useEffect(() => {
        setFuelStockForm({
            diesel: String(settings.fuelOpeningStockLiters?.Diesel ?? 0),
            benzine: String(settings.fuelOpeningStockLiters?.Benzine ?? 0),
        });
    }, [settings.fuelOpeningStockLiters]);

    useEffect(() => {
        setDefaultsForm({ sandCubicPerTrip: String(settings.appDefaults?.sandCubicPerTrip ?? 3) });
    }, [settings.appDefaults]);

    const DEFAULT_POSITIONS = ['คนขับรถ', 'รับจ้างรายวัน'];
    const [positions, setPositions] = useState<string[]>(() => {
        try {
            const s = localStorage.getItem(POSITIONS_STORAGE_KEY);
            if (s) return JSON.parse(s);
            return [...DEFAULT_POSITIONS];
        } catch { return [...DEFAULT_POSITIONS]; }
    });
    const [newPosition, setNewPosition] = useState('');

    useEffect(() => {
        try { localStorage.setItem(POSITIONS_STORAGE_KEY, JSON.stringify(positions)); } catch { }
    }, [positions]);

    // sync general form เมื่อ settings เปลี่ยน
    useEffect(() => {
        setGeneralForm({
            name: settings.appName,
            subtext: settings.appSubtext,
            icon: settings.appIcon,
            iconDark: settings.appIconDark || ''
        });
    }, [settings.appName, settings.appSubtext, settings.appIcon, settings.appIconDark]);

    const handleAdd = () => {
        if (!newItem || activeTab === 'positionsLocal' || !LIST_TAB_KEYS.includes(activeTab as any)) return;
        const key = activeTab as keyof AppSettings;
        const cur = (settings[key] as string[]) || [];
        setSettings({ ...settings, [key]: [...cur, newItem.trim()] });
        setNewItem('');
    };
    const handleDelete = (index: number) => {
        if (activeTab === 'positionsLocal' || !LIST_TAB_KEYS.includes(activeTab as any)) return;
        if (confirm('ยืนยันลบ?')) {
            const key = activeTab as keyof AppSettings;
            const newList = [...((settings[key] as string[]) || [])];
            newList.splice(index, 1);
            setSettings({ ...settings, [key]: newList });
        }
    };

    const saveGeneral = () => {
        setSettings({
            ...settings,
            appName: generalForm.name,
            appSubtext: generalForm.subtext,
            appIcon: generalForm.icon,
            appIconDark: generalForm.iconDark || undefined
        });
        alert('บันทึกตั้งค่าทั่วไปแล้ว');
    };

    const saveOrgProfile = () => {
        setSettings({
            ...settings,
            orgProfile: {
                name: orgForm.name.trim() || undefined,
                phone: orgForm.phone.trim() || undefined,
                address: orgForm.address.trim() || undefined,
                taxId: orgForm.taxId.trim() || undefined,
            },
        });
        alert('บันทึกข้อมูลองค์กรแล้ว');
    };

    const saveFuelOpening = () => {
        setSettings({
            ...settings,
            fuelOpeningStockLiters: {
                Diesel: Number(fuelStockForm.diesel.replace(/,/g, '')) || 0,
                Benzine: Number(fuelStockForm.benzine.replace(/,/g, '')) || 0,
            },
        });
        alert('บันทึกยอดยกมาสต็อกน้ำมันแล้ว');
    };

    const saveAppDefaults = () => {
        const v = Number(defaultsForm.sandCubicPerTrip);
        setSettings({
            ...settings,
            appDefaults: {
                ...settings.appDefaults,
                sandCubicPerTrip: v > 0 ? v : 3,
            },
        });
        alert('บันทึกค่าเริ่มต้นระบบแล้ว');
    };

    const startEdit = (index: number, value: string) => {
        setEditingItem({ index, value });
    };
    const cancelEdit = () => setEditingItem(null);
    const saveEdit = () => {
        if (editingItem == null || activeTab === 'positionsLocal' || activeTab === 'general' || activeTab === 'clearData' || !LIST_TAB_KEYS.includes(activeTab as any)) return;
        const key = activeTab as keyof AppSettings;
        const arr = [...((settings[key] as string[]) || [])];
        if (editingItem.index >= 0 && editingItem.index < arr.length) {
            arr[editingItem.index] = editingItem.value.trim();
            if (arr[editingItem.index]) {
                setSettings({ ...settings, [key]: arr });
                setEditingItem(null);
            }
        }
    };

    const clearEditOnTabChange = (key: string) => {
        setEditingItem(null);
        setActiveTab(key);
    };

    const withTimeout = async <T,>(promise: Promise<T>, timeoutMs = 8000): Promise<T> => {
        return await Promise.race([
            promise,
            new Promise<T>((_, reject) => {
                window.setTimeout(() => reject(new Error('timeout')), timeoutMs);
            }),
        ]);
    };

    const checkSystemStatus = async () => {
        setIsCheckingStatus(true);
        const startedAt = performance.now();
        const hostname = window.location.host || 'localhost';
        const notes: string[] = [];

        let online: StatusState = navigator.onLine ? 'online' : 'offline';
        let host: StatusState = hostname ? 'online' : 'degraded';
        let dns: StatusState = 'unknown';
        let database: StatusState = 'unknown';

        try {
            const conn = (navigator as any).connection;
            const networkType = conn?.effectiveType || conn?.type || 'unknown';
            setStatus(prev => ({ ...prev, networkType, browser: navigator.userAgent, hostname }));
        } catch {
            // no-op for unsupported browsers
        }

        try {
            // DNS/host check (same-origin ping)
            await withTimeout(fetch(`${window.location.origin}/`, { method: 'GET', cache: 'no-store' }), 6000);
            dns = 'online';
        } catch {
            dns = online === 'offline' ? 'offline' : 'degraded';
            notes.push('ไม่สามารถตรวจสอบ DNS/Host จากหน้าเว็บได้');
        }

        try {
            const { error } = await withTimeout(
                supabase.from('app_settings').select('id').limit(1),
                8000
            );
            database = error ? 'degraded' : 'online';
            if (error) notes.push(`Database: ${error.message}`);
        } catch (e: any) {
            database = online === 'offline' ? 'offline' : 'degraded';
            notes.push(`Database request failed: ${e?.message || 'unknown error'}`);
        }

        const latencyMs = Math.round(performance.now() - startedAt);
        setStatus(prev => ({
            ...prev,
            online,
            host,
            dns,
            database,
            latencyMs,
            notes,
            hostname,
            browser: navigator.userAgent,
        }));
        setLastCheckedAt(new Date().toLocaleString('th-TH'));
        setIsCheckingStatus(false);
    };

    useEffect(() => {
        if (activeTab === 'systemStatus') checkSystemStatus();
    }, [activeTab]);

    useEffect(() => {
        const onOnline = () => setStatus(prev => ({ ...prev, online: 'online' }));
        const onOffline = () => setStatus(prev => ({ ...prev, online: 'offline' }));
        window.addEventListener('online', onOnline);
        window.addEventListener('offline', onOffline);
        return () => {
            window.removeEventListener('online', onOnline);
            window.removeEventListener('offline', onOffline);
        };
    }, []);

    const statusLabel = (value: StatusState) => {
        if (value === 'online') return { text: 'ออนไลน์', cls: 'bg-emerald-100 text-emerald-700' };
        if (value === 'offline') return { text: 'ออฟไลน์', cls: 'bg-red-100 text-red-700' };
        if (value === 'checking') return { text: 'กำลังตรวจสอบ', cls: 'bg-blue-100 text-blue-700' };
        if (value === 'degraded') return { text: 'ผิดปกติ', cls: 'bg-amber-100 text-amber-700' };
        return { text: 'ไม่ทราบ', cls: 'bg-slate-100 text-slate-700' };
    };

    const saveAccountProfile = async () => {
        if (!onUpdateAdminProfile || !currentAdmin) return;
        setAccountSaving(true);
        setAccountMsg(null);
        const r = await onUpdateAdminProfile({
            displayName: accountForm.displayName,
            avatar: accountForm.avatar,
            uiTheme: accountForm.uiTheme,
        });
        setAccountSaving(false);
        if (r.ok) setAccountMsg({ type: 'ok', text: 'บันทึกโปรไฟล์แล้ว' });
        else setAccountMsg({ type: 'err', text: r.message || 'เกิดข้อผิดพลาด' });
    };

    const saveAccountPassword = async () => {
        if (!onUpdateAdminProfile || !currentAdmin) return;
        if (accountForm.newPassword !== accountForm.confirmPassword) {
            setAccountMsg({ type: 'err', text: 'รหัสผ่านใหม่ไม่ตรงกัน' });
            return;
        }
        if (!accountForm.newPassword) {
            setAccountMsg({ type: 'err', text: 'กรุณากรอกรหัสผ่านใหม่' });
            return;
        }
        setAccountSaving(true);
        setAccountMsg(null);
        const r = await onUpdateAdminProfile({
            currentPassword: accountForm.currentPassword,
            newPassword: accountForm.newPassword,
        });
        setAccountSaving(false);
        if (r.ok) {
            setAccountForm(prev => ({ ...prev, currentPassword: '', newPassword: '', confirmPassword: '' }));
            setAccountMsg({ type: 'ok', text: 'เปลี่ยนรหัสผ่านแล้ว' });
        } else setAccountMsg({ type: 'err', text: r.message || 'เกิดข้อผิดพลาด' });
    };

    const onAvatarFile = (e: React.ChangeEvent<HTMLInputElement>) => {
        const f = e.target.files?.[0];
        if (!f || !f.type.startsWith('image/')) return;
        if (f.size > 600 * 1024) {
            alert('รูปต้องไม่เกิน 600 KB');
            e.target.value = '';
            return;
        }
        const reader = new FileReader();
        reader.onload = () => setAccountForm(prev => ({ ...prev, avatar: String(reader.result || '') }));
        reader.readAsDataURL(f);
        e.target.value = '';
    };

    const tabs = [
        { key: 'myAccount', l: 'บัญชีแอดมิน' },
        { key: 'general', l: 'ทั่วไป' },
        { key: 'organization', l: 'ข้อมูลองค์กร' },
        { key: 'cars', l: 'รถ / เครื่องจักร' },
        { key: 'jobDescriptions', l: 'รายละเอียดงาน' },
        { key: 'incomeTypes', l: 'ประเภทรายรับ' },
        { key: 'expenseTypes', l: 'สาธารณูปโภค' },
        { key: 'maintenanceTypes', l: 'ซ่อมบำรุง' },
        { key: 'locations', l: 'สถานที่ / หน้างาน' },
        { key: 'landGroups', l: 'กลุ่มที่ดิน' },
        { key: 'fuelStock', l: 'น้ำมัน & สต็อกยกมา' },
        { key: 'defaults', l: 'ค่าเริ่มต้นระบบ' },
        { key: 'systemStatus', l: 'สถานะระบบ' },
        { key: 'positionsLocal', l: 'ตำแหน่งพนักงาน' },
        { key: 'clearData', l: 'ล้างข้อมูล' },
    ];

    return (
        <div className="space-y-6 animate-fade-in"><h2 className="text-2xl font-bold">ตั้งค่า</h2>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
                <Card className="p-4 h-fit md:col-span-1"><div className="flex flex-col gap-1.5">{tabs.map(t => (<button key={t.key} type="button" onClick={() => clearEditOnTabChange(t.key)} className={`text-left px-3 py-2.5 rounded-lg text-sm font-medium transition-colors ${activeTab === t.key ? 'bg-slate-800 text-white dark:bg-slate-100 dark:text-slate-900' : 'hover:bg-slate-50 dark:hover:bg-white/[0.06] text-slate-700 dark:text-slate-300'}`}>{t.l}</button>))}</div></Card>
                <Card className="p-6 md:col-span-3 min-h-[500px]">
                    {activeTab === 'myAccount' ? (
                        currentAdmin && onUpdateAdminProfile ? (
                            <div className="space-y-8 max-w-xl">
                                <div className="flex items-center gap-2 mb-2">
                                    <UserCircle className="text-amber-600" size={22} />
                                    <h3 className="font-bold text-lg">บัญชีแอดมิน</h3>
                                </div>
                                <p className="text-sm text-slate-500 dark:text-slate-400">
                                    แก้ชื่อที่แสดง รูปประจำตัว โหมดสว่าง/มืดของคุณ และรหัสผ่าน — บันทึกลงบัญชีนี้ (@{currentAdmin.username})
                                </p>

                                {accountMsg && (
                                    <div className={`rounded-xl px-4 py-3 text-sm border ${accountMsg.type === 'ok' ? 'bg-emerald-50 border-emerald-200 text-emerald-800 dark:bg-emerald-500/10 dark:border-emerald-500/30 dark:text-emerald-200' : 'bg-red-50 border-red-200 text-red-800 dark:bg-red-500/10 dark:border-red-500/30 dark:text-red-200'}`}>
                                        {accountMsg.text}
                                    </div>
                                )}

                                <div className="space-y-4">
                                    <Input label="ชื่อที่แสดง" value={accountForm.displayName} onChange={(e: any) => setAccountForm({ ...accountForm, displayName: e.target.value })} />
                                    <div className="flex flex-col gap-2">
                                        <label className="text-sm font-medium text-slate-700 dark:text-slate-300">รูปประจำตัว</label>
                                        <div className="flex flex-wrap items-center gap-4">
                                            <div className="w-16 h-16 rounded-full border-2 border-slate-200 dark:border-white/15 overflow-hidden bg-slate-100 dark:bg-slate-800 flex items-center justify-center shrink-0">
                                                {accountForm.avatar && (accountForm.avatar.startsWith('http') || accountForm.avatar.startsWith('data:')) ? (
                                                    <img src={accountForm.avatar} alt="" className="w-full h-full object-cover" />
                                                ) : (
                                                    <span className="text-xl font-bold text-slate-500">{accountForm.displayName.charAt(0) || '?'}</span>
                                                )}
                                            </div>
                                            <div className="flex-1 min-w-[200px] space-y-2">
                                                <Input value={accountForm.avatar} onChange={(e: any) => setAccountForm({ ...accountForm, avatar: e.target.value })} placeholder="URL รูป หรืออัปโหลดด้านล่าง" />
                                                <label className="inline-flex items-center gap-2 text-sm text-slate-600 dark:text-slate-400 cursor-pointer">
                                                    <input type="file" accept="image/*" className="hidden" onChange={onAvatarFile} />
                                                    <span className="underline decoration-dotted">อัปโหลดรูปจากเครื่อง</span>
                                                    <span className="text-xs">(สูงสุด ~600 KB)</span>
                                                </label>
                                            </div>
                                        </div>
                                    </div>

                                    <div>
                                        <p className="text-sm font-medium text-slate-700 dark:text-slate-300 mb-2">โหมดแสดงผล</p>
                                        <div className="flex flex-wrap gap-2">
                                            {([
                                                { v: 'system' as const, label: 'ตามระบบ', Icon: Monitor },
                                                { v: 'light' as const, label: 'สว่าง', Icon: Sun },
                                                { v: 'dark' as const, label: 'มืด', Icon: Moon },
                                            ]).map(({ v, label, Icon }) => (
                                                <button
                                                    key={v}
                                                    type="button"
                                                    onClick={() => setAccountForm({ ...accountForm, uiTheme: v })}
                                                    className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-medium border transition-all ${
                                                        accountForm.uiTheme === v
                                                            ? 'bg-slate-800 text-white border-slate-800 dark:bg-amber-500/20 dark:text-amber-200 dark:border-amber-500/40'
                                                            : 'bg-slate-50 dark:bg-white/[0.04] text-slate-700 dark:text-slate-300 border-slate-200 dark:border-white/10 hover:bg-slate-100 dark:hover:bg-white/[0.08]'
                                                    }`}
                                                >
                                                    <Icon size={18} /> {label}
                                                </button>
                                            ))}
                                        </div>
                                        <p className="text-xs text-slate-400 mt-2">«ตามระบบ» จะสลับตามการตั้งค่าของเครื่อง/เบราว์เซอร์</p>
                                    </div>

                                    <Button onClick={saveAccountProfile} disabled={accountSaving} className="mt-2">
                                        {accountSaving ? 'กำลังบันทึก...' : 'บันทึกโปรไฟล์'}
                                    </Button>
                                </div>

                                <div className="border-t border-slate-200 dark:border-white/10 pt-8 space-y-4">
                                    <div className="flex items-center gap-2 mb-1">
                                        <Lock className="text-slate-500" size={18} />
                                        <h4 className="font-bold text-slate-800 dark:text-slate-100">เปลี่ยนรหัสผ่าน</h4>
                                    </div>
                                    <Input type="password" label="รหัสผ่านปัจจุบัน" value={accountForm.currentPassword} onChange={(e: any) => setAccountForm({ ...accountForm, currentPassword: e.target.value })} autoComplete="current-password" />
                                    <Input type="password" label="รหัสผ่านใหม่" value={accountForm.newPassword} onChange={(e: any) => setAccountForm({ ...accountForm, newPassword: e.target.value })} autoComplete="new-password" />
                                    <Input type="password" label="ยืนยันรหัสผ่านใหม่" value={accountForm.confirmPassword} onChange={(e: any) => setAccountForm({ ...accountForm, confirmPassword: e.target.value })} autoComplete="new-password" />
                                    <Button onClick={saveAccountPassword} disabled={accountSaving} variant="outline">
                                        {accountSaving ? 'กำลังบันทึก...' : 'เปลี่ยนรหัสผ่าน'}
                                    </Button>
                                </div>
                            </div>
                        ) : (
                            <p className="text-sm text-slate-500">ไม่พบข้อมูลบัญชี</p>
                        )
                    ) : activeTab === 'general' ? (
                        <div className="space-y-6 max-w-lg">
                            <h3 className="font-bold text-lg mb-4">ตั้งค่าทั่วไป</h3>
                            <Input label="ชื่อเว็บไซต์/แอพ" value={generalForm.name} onChange={(e: any) => setGeneralForm({ ...generalForm, name: e.target.value })} />
                            <Input label="ข้อความใต้ชื่อ (Subtext)" value={generalForm.subtext} onChange={(e: any) => setGeneralForm({ ...generalForm, subtext: e.target.value })} placeholder="เช่น ระบบจัดการ" />
                            <p className="text-xs text-slate-500 flex items-start gap-2 rounded-lg bg-slate-50 dark:bg-white/[0.04] p-3 border border-slate-100 dark:border-white/10">
                                <Info size={16} className="shrink-0 mt-0.5 text-slate-400" />
                                <span>สกุลเงินที่ใช้ในระบบคือ <strong>บาท (THB)</strong> ชื่อแอปและโลโก้จะแสดงที่แถบด้านข้างและหน้าเข้าสู่ระบบ</span>
                            </p>

                            {/* Logo Light Mode */}
                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">☀️ โลโก้ (โหมดปกติ / Light)</label>
                                <div className="flex gap-4 items-center">
                                    <div className="w-16 h-16 bg-white rounded-xl border-2 border-slate-200 flex items-center justify-center overflow-hidden shrink-0">
                                        {generalForm.icon.startsWith('http') || generalForm.icon.startsWith('data:') ? (
                                            <img src={generalForm.icon} alt="Light Logo" className="w-full h-full object-cover" />
                                        ) : (
                                            <span className="text-2xl font-bold text-slate-400">{generalForm.icon.substring(0, 2)}</span>
                                        )}
                                    </div>
                                    <Input value={generalForm.icon} onChange={(e: any) => setGeneralForm({ ...generalForm, icon: e.target.value })} placeholder="https://example.com/logo.png" />
                                </div>
                            </div>

                            {/* Logo Dark Mode */}
                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">🌙 โลโก้ (โหมด Dark)</label>
                                <div className="flex gap-4 items-center">
                                    <div className="w-16 h-16 bg-slate-800 rounded-xl border-2 border-slate-600 flex items-center justify-center overflow-hidden shrink-0">
                                        {(generalForm.iconDark || generalForm.icon).startsWith('http') || (generalForm.iconDark || generalForm.icon).startsWith('data:') ? (
                                            <img src={generalForm.iconDark || generalForm.icon} alt="Dark Logo" className="w-full h-full object-cover" />
                                        ) : (
                                            <span className="text-2xl font-bold text-slate-400">{(generalForm.iconDark || generalForm.icon).substring(0, 2)}</span>
                                        )}
                                    </div>
                                    <Input value={generalForm.iconDark} onChange={(e: any) => setGeneralForm({ ...generalForm, iconDark: e.target.value })} placeholder="URL โลโก้ Dark (ว่างไว้ = ใช้ตัวเดียวกัน)" />
                                </div>
                                <p className="text-xs text-slate-400">หากไม่กรอก ระบบจะใช้โลโก้ปกติแทน</p>
                            </div>

                            <Button onClick={saveGeneral} className="mt-4">บันทึกการเปลี่ยนแปลง</Button>
                        </div>
                    ) : activeTab === 'organization' ? (
                        <div className="space-y-6 max-w-xl">
                            <div className="flex items-center gap-2 mb-2">
                                <Building2 className="text-indigo-600" size={22} />
                                <h3 className="font-bold text-lg">ข้อมูลองค์กร</h3>
                            </div>
                            <p className="text-sm text-slate-500 dark:text-slate-400">
                                ใช้เก็บชื่อ ที่อยู่ และเลขประจำตัวผู้เสียภาษีเพื่ออ้างอิงในเอกสารหรือรายงานในอนาคต — ไม่บังคับกรอกครบทุกช่อง
                            </p>
                            <Input label="ชื่อองค์กร / ชื่อกิจการ" value={orgForm.name} onChange={(e: any) => setOrgForm({ ...orgForm, name: e.target.value })} />
                            <Input label="เบอร์โทรติดต่อ" value={orgForm.phone} onChange={(e: any) => setOrgForm({ ...orgForm, phone: e.target.value })} />
                            <div className="flex flex-col gap-1">
                                <label className="text-sm font-medium text-slate-700 dark:text-slate-300">ที่อยู่</label>
                                <textarea
                                    className="border border-slate-200 dark:border-white/15 rounded-xl p-3 text-sm bg-white dark:bg-white/5 text-slate-800 dark:text-slate-100 min-h-[88px]"
                                    value={orgForm.address}
                                    onChange={e => setOrgForm({ ...orgForm, address: e.target.value })}
                                    placeholder="บ้านเลขที่ ถนน ตำบล อำเภอ จังหวัด รหัสไปรษณีย์"
                                />
                            </div>
                            <Input label="เลขประจำตัวผู้เสียภาษี (ถ้ามี)" value={orgForm.taxId} onChange={(e: any) => setOrgForm({ ...orgForm, taxId: e.target.value })} placeholder="เช่น 13 หลัก" />
                            <Button onClick={saveOrgProfile}>บันทึกข้อมูลองค์กร</Button>
                        </div>
                    ) : activeTab === 'fuelStock' ? (
                        <div className="space-y-6 max-w-xl">
                            <div className="flex items-center gap-2 mb-2">
                                <Droplets className="text-orange-500" size={22} />
                                <h3 className="font-bold text-lg">ยอดยกมาสต็อกน้ำมัน (ลิตร)</h3>
                            </div>
                            <p className="text-sm text-slate-500 dark:text-slate-400">
                                ใช้คำนวณสต็อกคงเหลือร่วมกับรายการ «รับน้ำมันเข้าสต็อก» และ «เติมรถ» ในเมนูน้ำมัน — แก้ที่นี่ได้เหมือนในหน้าน้ำมัน
                            </p>
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                <Input label="ดีเซล (ลิตร)" type="number" value={fuelStockForm.diesel} onChange={(e: any) => setFuelStockForm({ ...fuelStockForm, diesel: e.target.value })} />
                                <Input label="เบนซิน (ลิตร)" type="number" value={fuelStockForm.benzine} onChange={(e: any) => setFuelStockForm({ ...fuelStockForm, benzine: e.target.value })} />
                            </div>
                            <Button onClick={saveFuelOpening}>บันทึกยอดยกมา</Button>
                        </div>
                    ) : activeTab === 'defaults' ? (
                        <div className="space-y-6 max-w-xl">
                            <div className="flex items-center gap-2 mb-2">
                                <SlidersHorizontal className="text-teal-600" size={22} />
                                <h3 className="font-bold text-lg">ค่าเริ่มต้นระบบ</h3>
                            </div>
                            <p className="text-sm text-slate-500 dark:text-slate-400">
                                ตัวเลขที่ใช้เป็นค่าเริ่มในบันทึกงานประจำวัน (เช่น คำนวณปริมาณทรายจากจำนวนเที่ยวรถ)
                            </p>
                            <Input
                                label="คิวต่อ 1 เที่ยวรถ (ค่าเริ่ม)"
                                type="number"
                                min={0.1}
                                step={0.1}
                                value={defaultsForm.sandCubicPerTrip}
                                onChange={(e: any) => setDefaultsForm({ ...defaultsForm, sandCubicPerTrip: e.target.value })}
                            />
                            <p className="text-xs text-slate-400">ถ้าไม่แน่ใจ ใช้ 3 คิวต่อเที่ยวเป็นค่ามาตรฐาน</p>
                            <Button onClick={saveAppDefaults}>บันทึกค่าเริ่มต้น</Button>
                        </div>
                    ) : activeTab === 'clearData' ? (
                        <div className="space-y-6 max-w-lg">
                            <h3 className="font-bold text-lg mb-2 text-red-600">ล้างข้อมูลที่บันทึกทั้งหมด</h3>
                            <p className="text-sm text-slate-600">
                                การกระทำนี้จะลบ <strong>รายการธุรกรรมทั้งหมด</strong> และ <strong>โครงการที่ดินทั้งหมด</strong> ออกจากระบบ
                                <br />ข้อมูล <strong>พนักงาน</strong> และ <strong>ตั้งค่าทั้งหมด</strong> จะไม่ถูกลบ
                            </p>
                            {onClearAllData && (
                                <Button onClick={onClearAllData} className="bg-red-600 hover:bg-red-700 text-white border-0">
                                    ล้างข้อมูลที่บันทึกทั้งหมด
                                </Button>
                            )}
                        </div>
                    ) : activeTab === 'systemStatus' ? (
                        <div className="space-y-5">
                            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                                <div>
                                    <h3 className="font-bold text-lg">เช็คสถานะการเชื่อมต่อระบบ</h3>
                                    <p className="text-sm text-slate-500">ตรวจสอบ Host, DNS, สถานะออนไลน์ และฐานข้อมูล</p>
                                </div>
                                <Button onClick={checkSystemStatus} className="flex items-center gap-2" disabled={isCheckingStatus}>
                                    <RefreshCw size={16} className={isCheckingStatus ? 'animate-spin' : ''} />
                                    {isCheckingStatus ? 'กำลังตรวจสอบ...' : 'รีเฟรชสถานะ'}
                                </Button>
                            </div>

                            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                                {[
                                    { key: 'online', label: 'สถานะออนไลน์', icon: <Wifi size={16} className="text-slate-500" />, value: status.online, detail: navigator.onLine ? 'เชื่อมต่ออินเทอร์เน็ต' : 'ไม่มีอินเทอร์เน็ต' },
                                    { key: 'host', label: 'Host', icon: <Server size={16} className="text-slate-500" />, value: status.host, detail: status.hostname },
                                    { key: 'dns', label: 'DNS', icon: <Globe size={16} className="text-slate-500" />, value: status.dns, detail: `Origin: ${window.location.origin}` },
                                    { key: 'database', label: 'ฐานข้อมูล (Supabase)', icon: <Database size={16} className="text-slate-500" />, value: status.database, detail: status.latencyMs != null ? `Latency ~ ${status.latencyMs} ms` : 'ยังไม่เคยตรวจสอบ' },
                                ].map(item => {
                                    const badge = statusLabel(item.value);
                                    return (
                                        <div key={item.key} className="p-4 rounded-xl border bg-white">
                                            <div className="flex items-center justify-between mb-2">
                                                <div className="flex items-center gap-2 font-medium text-slate-700">{item.icon}{item.label}</div>
                                                <span className={`px-2 py-0.5 rounded-full text-xs font-bold ${badge.cls}`}>{badge.text}</span>
                                            </div>
                                            <p className="text-xs text-slate-500 break-all">{item.detail}</p>
                                        </div>
                                    );
                                })}
                            </div>

                            <Card className="p-4 bg-slate-50 border-slate-200">
                                <h4 className="font-semibold text-slate-700 mb-2">สถานะอื่นๆ</h4>
                                <div className="text-sm space-y-1 text-slate-600">
                                    <p><strong>เวอร์ชั่น:</strong> v{appVersion}</p>
                                    <p><strong>อัปเดตล่าสุดเมื่อ:</strong> {appUpdatedAt}</p>
                                    <p><strong>ตรวจสถานะล่าสุด:</strong> {lastCheckedAt || '-'}</p>
                                </div>
                                {status.notes.length > 0 && (
                                    <div className="mt-3 p-3 rounded-lg bg-amber-50 border border-amber-200">
                                        <div className="flex items-center gap-2 text-amber-700 font-medium text-sm mb-1">
                                            <ShieldAlert size={14} />
                                            หมายเหตุจากการตรวจสอบ
                                        </div>
                                        <ul className="text-xs text-amber-700 space-y-1">
                                            {status.notes.map((n, idx) => <li key={idx}>- {n}</li>)}
                                        </ul>
                                    </div>
                                )}
                            </Card>
                        </div>
                    ) : activeTab === 'positionsLocal' ? (
                        <div className="space-y-6 max-w-lg">
                            <h3 className="font-bold text-lg mb-2">ตั้งค่าตำแหน่งพนักงาน</h3>
                            <p className="text-sm text-slate-500 mb-4">เพิ่ม/แก้ไข/ลบชื่อตำแหน่งที่ใช้กำหนดให้พนักงาน เช่น คนงาน, ช่างเชื่อม, หัวหน้าทีม ฯลฯ</p>
                            <div className="flex gap-2 mb-4">
                                <Input placeholder="ชื่อตำแหน่งใหม่..." value={newPosition} onChange={(e: any) => setNewPosition(e.target.value)} />
                                <Button onClick={() => { if (!newPosition.trim()) return; setPositions(prev => [...prev, newPosition.trim()]); setNewPosition(''); }}><Plus size={18} /> เพิ่ม</Button>
                            </div>
                            <div className="space-y-2">
                                {positions.map((p, idx) => {
                                    const isEditingPos = editingItem?.index === idx && activeTab === 'positionsLocal';
                                    return (
                                        <div key={idx} className="flex justify-between items-center gap-2 p-3 bg-slate-50 rounded-lg group">
                                            {isEditingPos ? (
                                                <>
                                                    <Input
                                                        className="flex-1"
                                                        value={editingItem.value}
                                                        onChange={(e: any) => setEditingItem({ ...editingItem, value: e.target.value })}
                                                        onKeyDown={(e: any) => { if (e.key === 'Enter') { const v = editingItem.value.trim(); if (v) { setPositions(prev => { const n = [...prev]; n[idx] = v; return n; }); setEditingItem(null); } } if (e.key === 'Escape') setEditingItem(null); }}
                                                        autoFocus
                                                    />
                                                    <button onClick={() => { const v = editingItem.value.trim(); if (v) { setPositions(prev => { const n = [...prev]; n[idx] = v; return n; }); setEditingItem(null); }}} className="p-1.5 text-emerald-600 hover:bg-emerald-50 rounded" title="บันทึก"><Check size={18} /></button>
                                                    <button onClick={() => setEditingItem(null)} className="p-1.5 text-slate-400 hover:bg-slate-100 rounded" title="ยกเลิก"><X size={18} /></button>
                                                </>
                                            ) : (
                                                <>
                                                    <span className="text-slate-700 flex-1">{p}</span>
                                                    <button onClick={() => setEditingItem({ index: idx, value: p })} className="p-1.5 text-slate-400 hover:text-slate-600 opacity-0 group-hover:opacity-100" title="แก้ไข"><Pencil size={16} /></button>
                                                    <button onClick={() => { if (confirm('ลบตำแหน่งนี้?')) setPositions(prev => prev.filter((_, i) => i !== idx)); }} className="p-1.5 text-slate-400 hover:text-red-500 opacity-0 group-hover:opacity-100" title="ลบ"><Trash2 size={16} /></button>
                                                </>
                                            )}
                                        </div>
                                    );
                                })}
                                {positions.length === 0 && <p className="text-sm text-slate-400">ยังไม่มีตำแหน่งที่บันทึกไว้</p>}
                            </div>
                        </div>
                    ) : LIST_TAB_KEYS.includes(activeTab as (typeof LIST_TAB_KEYS)[number]) ? (
                        <>
                            <div className="mb-4">
                                <h3 className="font-bold text-lg text-slate-800 dark:text-slate-100">{tabs.find(t => t.key === activeTab)?.l}</h3>
                                {TAB_HELP[activeTab] && (
                                    <p className="text-sm text-slate-500 dark:text-slate-400 mt-2 flex items-start gap-2">
                                        <Info size={15} className="shrink-0 mt-0.5 opacity-70" />
                                        {TAB_HELP[activeTab]}
                                    </p>
                                )}
                            </div>
                            <div className="flex gap-2 mb-6"><Input placeholder="รายการใหม่..." value={newItem} onChange={(e: any) => setNewItem(e.target.value)} /><Button onClick={handleAdd}><Plus size={18} /> เพิ่ม</Button></div>
                            <div className="space-y-2">
                                {((settings[activeTab as keyof AppSettings] as string[]) || []).map((item: string, idx: number) => {
                                    const isEditing = editingItem?.index === idx;
                                    return (
                                        <div key={idx} className="flex justify-between items-center gap-2 p-3 bg-slate-50 rounded-lg group">
                                            {isEditing ? (
                                                <>
                                                    <Input
                                                        className="flex-1"
                                                        value={editingItem.value}
                                                        onChange={(e: any) => setEditingItem({ ...editingItem, value: e.target.value })}
                                                        onKeyDown={(e: any) => { if (e.key === 'Enter') saveEdit(); if (e.key === 'Escape') cancelEdit(); }}
                                                        autoFocus
                                                    />
                                                    <button onClick={saveEdit} className="p-1.5 text-emerald-600 hover:bg-emerald-50 rounded" title="บันทึก"><Check size={18} /></button>
                                                    <button onClick={cancelEdit} className="p-1.5 text-slate-400 hover:bg-slate-100 rounded" title="ยกเลิก"><X size={18} /></button>
                                                </>
                                            ) : (
                                                <>
                                                    <span className="text-slate-700 flex-1">{item}</span>
                                                    <button onClick={() => startEdit(idx, item)} className="p-1.5 text-slate-400 hover:text-slate-600 opacity-0 group-hover:opacity-100" title="แก้ไข"><Pencil size={16} /></button>
                                                    <button onClick={() => handleDelete(idx)} className="p-1.5 text-slate-400 hover:text-red-500 opacity-0 group-hover:opacity-100" title="ลบ"><Trash2 size={16} /></button>
                                                </>
                                            )}
                                        </div>
                                    );
                                })}
                            </div>
                        </>
                    ) : (
                        <p className="text-sm text-slate-500 dark:text-slate-400">เลือกหัวข้อจากเมนูด้านซ้าย</p>
                    )}
                </Card>
            </div>
        </div>
    );
};

export default SettingsModule;
