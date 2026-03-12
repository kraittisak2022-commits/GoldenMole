import { useState, useEffect } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import { AppSettings } from '../../types';

interface SettingsModuleProps {
    settings: AppSettings;
    setSettings: (settings: AppSettings) => void;
    onClearAllData?: () => Promise<void>;
}

const POSITIONS_STORAGE_KEY = 'app_employee_positions';

const SettingsModule = ({ settings, setSettings, onClearAllData }: SettingsModuleProps) => {
    const [activeTab, setActiveTab] = useState('general');
    const [newItem, setNewItem] = useState('');

    // General Form
    const [generalForm, setGeneralForm] = useState({ name: settings.appName, icon: settings.appIcon, iconDark: settings.appIconDark || '' });

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
        setSettings({ ...settings, appName: generalForm.name, appIcon: generalForm.icon, appIconDark: generalForm.iconDark || undefined });
        alert('บันทึกตั้งค่าทั่วไปแล้ว');
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
        { key: 'positionsLocal', l: 'ตำแหน่งพนักงาน' },
        { key: 'clearData', l: 'ล้างข้อมูล' }
    ];

    return (
        <div className="space-y-6 animate-fade-in"><h2 className="text-2xl font-bold">ตั้งค่า</h2>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
                <Card className="p-4 h-fit md:col-span-1"><div className="flex flex-col gap-2">{tabs.map(t => (<button key={t.key} onClick={() => setActiveTab(t.key)} className={`text-left px-4 py-3 rounded-lg text-sm font-medium ${activeTab === t.key ? 'bg-slate-800 text-white' : 'hover:bg-slate-50'}`}>{t.l}</button>))}</div></Card>
                <Card className="p-6 md:col-span-3 min-h-[500px]">
                    {activeTab === 'general' ? (
                        <div className="space-y-6 max-w-lg">
                            <h3 className="font-bold text-lg mb-4">ตั้งค่าทั่วไป</h3>
                            <Input label="ชื่อเว็บไซต์/แอพ" value={generalForm.name} onChange={(e: any) => setGeneralForm({ ...generalForm, name: e.target.value })} />

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
                    ) : activeTab === 'positionsLocal' ? (
                        <div className="space-y-6 max-w-lg">
                            <h3 className="font-bold text-lg mb-2">ตั้งค่าตำแหน่งพนักงาน</h3>
                            <p className="text-sm text-slate-500 mb-4">เพิ่ม/ลบชื่อตำแหน่งที่ใช้กำหนดให้พนักงาน เช่น คนงาน, ช่างเชื่อม, หัวหน้าทีม ฯลฯ</p>
                            <div className="flex gap-2 mb-4">
                                <Input placeholder="ชื่อตำแหน่งใหม่..." value={newPosition} onChange={(e: any) => setNewPosition(e.target.value)} />
                                <Button onClick={() => { if (!newPosition.trim()) return; setPositions(prev => [...prev, newPosition.trim()]); setNewPosition(''); }}><Plus size={18} /> เพิ่ม</Button>
                            </div>
                            <div className="space-y-2">
                                {positions.map((p, idx) => (
                                    <div key={idx} className="flex justify-between items-center p-3 bg-slate-50 rounded-lg group">
                                        <span className="text-slate-700">{p}</span>
                                        <button onClick={() => { if (confirm('ลบตำแหน่งนี้?')) setPositions(prev => prev.filter((_, i) => i !== idx)); }} className="text-slate-400 hover:text-red-500 opacity-0 group-hover:opacity-100">
                                            <Trash2 size={16} />
                                        </button>
                                    </div>
                                ))}
                                {positions.length === 0 && <p className="text-sm text-slate-400">ยังไม่มีตำแหน่งที่บันทึกไว้</p>}
                            </div>
                        </div>
                    ) : (
                        <>
                            <div className="flex gap-2 mb-6"><Input placeholder="รายการใหม่..." value={newItem} onChange={(e: any) => setNewItem(e.target.value)} /><Button onClick={handleAdd}><Plus size={18} /> เพิ่ม</Button></div>
                            <div className="space-y-2">{(settings as any)[activeTab].map((item: string, idx: number) => (<div key={idx} className="flex justify-between items-center p-3 bg-slate-50 rounded-lg group"><span className="text-slate-700">{item}</span><button onClick={() => handleDelete(idx)} className="text-slate-400 hover:text-red-500 opacity-0 group-hover:opacity-100"><Trash2 size={16} /></button></div>))}</div>
                        </>
                    )}
                </Card>
            </div>
        </div>
    );
};

export default SettingsModule;
