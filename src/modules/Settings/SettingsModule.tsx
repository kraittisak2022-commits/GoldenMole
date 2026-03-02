import { useState } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import { AppSettings } from '../../types';

interface SettingsModuleProps {
    settings: AppSettings;
    setSettings: (settings: AppSettings) => void;
}

const SettingsModule = ({ settings, setSettings }: SettingsModuleProps) => {
    const [activeTab, setActiveTab] = useState('general');
    const [newItem, setNewItem] = useState('');

    // General Form
    const [generalForm, setGeneralForm] = useState({ name: settings.appName, icon: settings.appIcon });

    const handleAdd = () => { if (!newItem) return; setSettings({ ...settings, [activeTab]: [...(settings as any)[activeTab], newItem] }); setNewItem(''); };
    const handleDelete = (index: number) => { if (confirm('ยืนยันลบ?')) { const newList = [...(settings as any)[activeTab]]; newList.splice(index, 1); setSettings({ ...settings, [activeTab]: newList }); } };

    const saveGeneral = () => {
        setSettings({ ...settings, appName: generalForm.name, appIcon: generalForm.icon });
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
        { key: 'landGroups', l: 'กลุ่มที่ดิน' }
    ];

    return (
        <div className="space-y-6 animate-fade-in"><h2 className="text-2xl font-bold">ตั้งค่า</h2>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
                <Card className="p-4 h-fit md:col-span-1"><div className="flex flex-col gap-2">{tabs.map(t => (<button key={t.key} onClick={() => setActiveTab(t.key)} className={`text-left px-4 py-3 rounded-lg text-sm font-medium ${activeTab === t.key ? 'bg-slate-800 text-white' : 'hover:bg-slate-50'}`}>{t.l}</button>))}</div></Card>
                <Card className="p-6 md:col-span-3 min-h-[500px]">
                    {activeTab === 'general' ? (
                        <div className="space-y-4 max-w-md">
                            <h3 className="font-bold text-lg mb-4">ตั้งค่าทั่วไป</h3>
                            <Input label="ชื่อเว็บไซต์/แอพ" value={generalForm.name} onChange={(e: any) => setGeneralForm({ ...generalForm, name: e.target.value })} />

                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">โลโก้ (URL รูปภาพ หรือ อักษรย่อ)</label>
                                <div className="flex gap-4 items-center">
                                    <div className="w-16 h-16 bg-slate-100 rounded-xl border flex items-center justify-center overflow-hidden shrink-0">
                                        {generalForm.icon.startsWith('http') || generalForm.icon.startsWith('data:') ? (
                                            <img src={generalForm.icon} alt="Preview" className="w-full h-full object-cover" />
                                        ) : (
                                            <span className="text-2xl font-bold text-slate-400">{generalForm.icon.substring(0, 2)}</span>
                                        )}
                                    </div>
                                    <Input value={generalForm.icon} onChange={(e: any) => setGeneralForm({ ...generalForm, icon: e.target.value })} placeholder="https://example.com/logo.png" />
                                </div>
                            </div>

                            <Button onClick={saveGeneral} className="mt-4">บันทึกการเปลี่ยนแปลง</Button>
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
