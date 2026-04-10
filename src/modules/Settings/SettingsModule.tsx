import { useState, useEffect } from 'react';
import { Plus, Trash2, Pencil, Check, X, RefreshCw, Globe, Wifi, Database, Server, ShieldAlert } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import { AppSettings } from '../../types';
import { supabase } from '../../lib/supabase';

interface SettingsModuleProps {
    settings: AppSettings;
    setSettings: (settings: AppSettings) => void;
    onClearAllData?: () => Promise<void>;
}

const POSITIONS_STORAGE_KEY = 'app_employee_positions';

type StatusState = 'checking' | 'online' | 'offline' | 'degraded' | 'unknown';

const SettingsModule = ({ settings, setSettings, onClearAllData }: SettingsModuleProps) => {
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
        if (!newItem || activeTab === 'positionsLocal') return;
        setSettings({ ...settings, [activeTab]: [...(settings as any)[activeTab], newItem] });
        setNewItem('');
    };
    const handleDelete = (index: number) => {
        if (activeTab === 'positionsLocal') return;
        if (confirm('ยืนยันลบ?')) {
            const newList = [...(settings as any)[activeTab]];
            newList.splice(index, 1);
            setSettings({ ...settings, [activeTab]: newList });
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

    const startEdit = (index: number, value: string) => {
        setEditingItem({ index, value });
    };
    const cancelEdit = () => setEditingItem(null);
    const saveEdit = () => {
        if (editingItem == null || activeTab === 'positionsLocal' || activeTab === 'general' || activeTab === 'clearData') return;
        const key = activeTab as keyof AppSettings;
        const arr = [...(settings[key] as string[])];
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

    const tabs = [
        { key: 'general', l: 'ทั่วไป (General)' },
        { key: 'cars', l: 'รถ/เครื่องจักร' },
        { key: 'jobDescriptions', l: 'รายละเอียดงาน (Labor)' },
        { key: 'incomeTypes', l: 'ประเภทรายรับ' },
        { key: 'expenseTypes', l: 'สาธารณูปโภค (Utilities)' },
        { key: 'maintenanceTypes', l: 'ประเภทซ่อมบำรุง' },
        { key: 'locations', l: 'สถานที่/หน้างาน' },
        { key: 'landGroups', l: 'กลุ่มที่ดิน' },
        { key: 'systemStatus', l: 'สถานะระบบ' },
        { key: 'positionsLocal', l: 'ตำแหน่งพนักงาน' },
        { key: 'clearData', l: 'ล้างข้อมูล' }
    ];

    return (
        <div className="space-y-6 animate-fade-in"><h2 className="text-2xl font-bold">ตั้งค่า</h2>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
                <Card className="p-4 h-fit md:col-span-1"><div className="flex flex-col gap-2">{tabs.map(t => (<button key={t.key} onClick={() => clearEditOnTabChange(t.key)} className={`text-left px-4 py-3 rounded-lg text-sm font-medium ${activeTab === t.key ? 'bg-slate-800 text-white' : 'hover:bg-slate-50'}`}>{t.l}</button>))}</div></Card>
                <Card className="p-6 md:col-span-3 min-h-[500px]">
                    {activeTab === 'general' ? (
                        <div className="space-y-6 max-w-lg">
                            <h3 className="font-bold text-lg mb-4">ตั้งค่าทั่วไป</h3>
                            <Input label="ชื่อเว็บไซต์/แอพ" value={generalForm.name} onChange={(e: any) => setGeneralForm({ ...generalForm, name: e.target.value })} />
                            <Input label="ข้อความใต้ชื่อ (Subtext)" value={generalForm.subtext} onChange={(e: any) => setGeneralForm({ ...generalForm, subtext: e.target.value })} placeholder="เช่น ระบบจัดการ" />

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
                    ) : (
                        <>
                            <div className="flex gap-2 mb-6"><Input placeholder="รายการใหม่..." value={newItem} onChange={(e: any) => setNewItem(e.target.value)} /><Button onClick={handleAdd}><Plus size={18} /> เพิ่ม</Button></div>
                            <div className="space-y-2">
                                {(settings as any)[activeTab].map((item: string, idx: number) => {
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
                    )}
                </Card>
            </div>
        </div>
    );
};

export default SettingsModule;
