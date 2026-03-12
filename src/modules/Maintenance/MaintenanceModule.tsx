import { useState } from 'react';
import { Wrench, Droplets, Package, History, Calendar, Pencil, Trash2 } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import { getToday, formatDateBE } from '../../utils';
import { Transaction, AppSettings } from '../../types';

const MAINTENANCE_MACHINES = [
    'เครื่องรถไถคูโบต้า',
    'รถแม็คโคร SK200-8 (น้องโกลเด้น)',
    'รถแม็คโคร SK200-8 (พี่ยักษ์ใหญ่)',
    'รถเครื่องในท่าทราย'
];

const OIL_CHANGE_TYPE = 'เปลี่ยนถ่ายน้ำมันเครื่อง';
const PARTS_TYPE = 'เปลี่ยนอะไหล่';

interface MaintenanceModuleProps {
    settings: AppSettings;
    transactions: Transaction[];
    onSave: (t: Transaction) => void;
    onDelete?: (id: string) => void;
}

const MaintenanceModule = ({ settings, transactions, onSave, onDelete }: MaintenanceModuleProps) => {
    const [activeTab, setActiveTab] = useState<'record' | 'overview'>('record');
    const [editingId, setEditingId] = useState<string | null>(null);
    const [form, setForm] = useState({
        date: getToday(),
        machine: '',
        maintenanceType: OIL_CHANGE_TYPE,
        detail: '',
        amount: '',
        note: ''
    });

    const maintenanceTx = transactions.filter(t => t.category === 'Maintenance');
    const historyList = maintenanceTx.slice(-30).reverse();

    const loadForEdit = (t: Transaction) => {
        const detailPart = (t.description || '').replace((t.subCategory || '') + ': ', '').trim();
        setForm({
            date: t.date?.slice(0, 10) || form.date,
            machine: t.vehicleId || '',
            maintenanceType: t.subCategory || OIL_CHANGE_TYPE,
            detail: detailPart,
            amount: t.amount != null ? String(t.amount) : '',
            note: (t as any).note || ''
        });
        setEditingId(t.id);
        setActiveTab('record');
    };

    const handleSave = () => {
        if (!form.machine) return alert('กรุณาเลือกเครื่องจักร');
        if (!form.amount || Number(form.amount) <= 0) return alert('กรุณาระบุจำนวนเงิน');
        if (editingId && onDelete) {
            onDelete(editingId);
            setEditingId(null);
        }
        const desc = form.detail.trim() ? `${form.maintenanceType}: ${form.detail}` : form.maintenanceType;
        onSave({
            id: Date.now().toString(),
            date: form.date,
            type: 'Expense',
            category: 'Maintenance',
            subCategory: form.maintenanceType,
            description: desc,
            amount: Number(form.amount),
            vehicleId: form.machine,
            note: form.note || undefined
        } as Transaction);
        setForm({ ...form, amount: '', detail: '', note: '' });
    };

    const getMachineHistory = (machine: string) =>
        maintenanceTx.filter(t => t.vehicleId === machine).sort((a, b) => b.date.localeCompare(a.date));

    const getLastByType = (machine: string, type: string) => {
        const list = getMachineHistory(machine).filter(t => t.subCategory === type);
        return list[0] || null;
    };

    const oilChangeLabel = OIL_CHANGE_TYPE;
    const partsLabels = [PARTS_TYPE, 'อะไหล่สิ้นเปลือง'];

    return (
        <div className="max-w-5xl mx-auto space-y-6 animate-fade-in">
            <div className="flex flex-wrap gap-2 border-b border-slate-200 pb-4">
                <button
                    onClick={() => setActiveTab('record')}
                    className={`px-4 py-2.5 rounded-xl text-sm font-medium transition-all flex items-center gap-2 ${activeTab === 'record' ? 'bg-amber-600 text-white shadow-md' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}
                >
                    <Wrench size={18} /> บันทึกซ่อมบำรุง
                </button>
                <button
                    onClick={() => setActiveTab('overview')}
                    className={`px-4 py-2.5 rounded-xl text-sm font-medium transition-all flex items-center gap-2 ${activeTab === 'overview' ? 'bg-amber-600 text-white shadow-md' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}
                >
                    <Calendar size={18} /> หน้าต่างบำรุงรักษา
                </button>
            </div>

            {activeTab === 'record' && (
                <Card className="p-6">
                    <h3 className="font-bold text-lg mb-4 flex items-center gap-2 text-slate-800">
                        <Wrench className="text-amber-500" /> บันทึกซ่อมบำรุง / เปลี่ยนน้ำมันเครื่อง / เปลี่ยนอะไหล่
                    </h3>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <Select
                            label="เครื่องจักร / รถ"
                            value={form.machine}
                            onChange={(e: any) => setForm({ ...form, machine: e.target.value })}
                        >
                            <option value="">-- เลือกเครื่อง --</option>
                            {MAINTENANCE_MACHINES.map(m => (
                                <option key={m} value={m}>{m}</option>
                            ))}
                        </Select>
                        <Select
                            label="ประเภท"
                            value={form.maintenanceType}
                            onChange={(e: any) => setForm({ ...form, maintenanceType: e.target.value })}
                        >
                            <option value={OIL_CHANGE_TYPE}>{OIL_CHANGE_TYPE}</option>
                            <option value={PARTS_TYPE}>{PARTS_TYPE}</option>
                            {settings.maintenanceTypes.filter(t => t !== OIL_CHANGE_TYPE && t !== PARTS_TYPE).map(t => (
                                <option key={t} value={t}>{t}</option>
                            ))}
                        </Select>
                        <Input label="วันที่" type="date" value={form.date} onChange={(e: any) => { setForm({ ...form, date: e.target.value }); setEditingId(null); }} />
                        <Input label="จำนวนเงิน (บาท)" type="number" value={form.amount} onChange={(e: any) => setForm({ ...form, amount: e.target.value })} placeholder="0" />
                        <div className="md:col-span-2">
                            <Input label="รายละเอียด (ถ้ามี)" value={form.detail} onChange={(e: any) => setForm({ ...form, detail: e.target.value })} placeholder="เช่น รอบที่ 5, เปลี่ยนฟิลเตอร์น้ำมันเครื่อง" />
                        </div>
                        <div className="md:col-span-2">
                            <Input label="หมายเหตุ" value={form.note} onChange={(e: any) => setForm({ ...form, note: e.target.value })} placeholder="หมายเหตุเพิ่มเติม" />
                        </div>
                    </div>
                    {editingId && <p className="text-xs text-amber-600 mt-2">กำลังแก้ไขรายการ — บันทึกจะแทนที่รายการเดิม</p>}
                    <Button onClick={handleSave} className="mt-4 bg-amber-600 hover:bg-amber-700">
                        บันทึก
                    </Button>
                </Card>
            )}

            {activeTab === 'overview' && (
                <div className="space-y-4">
                    <h3 className="font-bold text-lg text-slate-800 flex items-center gap-2">
                        <Calendar className="text-amber-500" /> การบำรุงรักษาเครื่องจักร
                    </h3>
                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                        {MAINTENANCE_MACHINES.map(machine => {
                            const history = getMachineHistory(machine);
                            const lastOil = getLastByType(machine, OIL_CHANGE_TYPE);
                            const lastParts = history.filter(t => partsLabels.includes(t.subCategory || '')).sort((a, b) => b.date.localeCompare(a.date))[0] || null;
                            const oilCount = history.filter(t => t.subCategory === OIL_CHANGE_TYPE).length;
                            const partsCount = history.filter(t => partsLabels.includes(t.subCategory || '')).length;

                            return (
                                <Card key={machine} className="p-4 border-2 border-amber-100 bg-amber-50/30">
                                    <div className="font-bold text-slate-800 mb-3 flex items-center gap-2">
                                        <Wrench size={18} className="text-amber-600" />
                                        {machine}
                                    </div>
                                    <div className="grid grid-cols-2 gap-3 mb-4">
                                        <div className="bg-white rounded-xl p-3 border border-amber-200/80">
                                            <div className="flex items-center gap-1.5 text-amber-700 text-xs font-bold mb-1">
                                                <Droplets size={14} /> รอบการเปลี่ยนถ่ายน้ำมันเครื่อง
                                            </div>
                                            {lastOil ? (
                                                <>
                                                    <div className="text-sm font-semibold text-slate-800">ล่าสุด: {formatDateBE(lastOil.date)}</div>
                                                    <div className="text-xs text-slate-500">รวม {oilCount} ครั้ง • ฿{(lastOil.amount || 0).toLocaleString()}</div>
                                                </>
                                            ) : (
                                                <div className="text-xs text-slate-400">ยังไม่มีบันทึก</div>
                                            )}
                                        </div>
                                        <div className="bg-white rounded-xl p-3 border border-slate-200">
                                            <div className="flex items-center gap-1.5 text-slate-700 text-xs font-bold mb-1">
                                                <Package size={14} /> การเปลี่ยนอะไหล่
                                            </div>
                                            {lastParts ? (
                                                <>
                                                    <div className="text-sm font-semibold text-slate-800">ล่าสุด: {formatDateBE(lastParts.date)}</div>
                                                    <div className="text-xs text-slate-500">รวม {partsCount} ครั้ง • ฿{(lastParts.amount || 0).toLocaleString()}</div>
                                                </>
                                            ) : (
                                                <div className="text-xs text-slate-400">ยังไม่มีบันทึก</div>
                                            )}
                                        </div>
                                    </div>
                                    <details className="group">
                                        <summary className="text-xs font-medium text-slate-500 cursor-pointer hover:text-amber-600 flex items-center gap-1">
                                            <History size={12} /> ประวัติบำรุงรักษา ({history.length} รายการ)
                                        </summary>
                                        <div className="mt-2 max-h-40 overflow-y-auto space-y-1.5">
                                            {history.length === 0 ? (
                                                <p className="text-xs text-slate-400 py-2">ยังไม่มีรายการ</p>
                                            ) : (
                                                history.slice(0, 20).map(t => (
                                                    <div key={t.id} className="flex justify-between items-center text-xs py-1.5 px-2 rounded-lg bg-white border border-slate-100">
                                                        <span className={t.subCategory === OIL_CHANGE_TYPE ? 'text-amber-700' : 'text-slate-700'}>{t.subCategory}</span>
                                                        <span className="text-slate-500">{formatDateBE(t.date)}</span>
                                                        <span className="font-semibold text-slate-800">฿{(t.amount || 0).toLocaleString()}</span>
                                                    </div>
                                                ))
                                            )}
                                        </div>
                                    </details>
                                </Card>
                            );
                        })}
                    </div>
                </div>
            )}

            <Card className="p-0 overflow-hidden border border-slate-200 shadow-sm">
                <div className="p-4 bg-gradient-to-r from-amber-50 to-orange-50/50 border-b flex items-center justify-between">
                    <span className="flex items-center gap-2 text-amber-800 font-bold">
                        <History size={18} /> ประวัติซ่อมบำรุง ({historyList.length} รายการ)
                    </span>
                </div>
                <div className="divide-y divide-slate-100 max-h-[400px] overflow-y-auto">
                    {historyList.length === 0 ? (
                        <div className="p-8 text-center text-slate-400 text-sm">ยังไม่มีรายการซ่อมบำรุง</div>
                    ) : (
                        historyList.map(t => (
                            <div key={t.id} className={`p-4 flex justify-between items-center gap-3 hover:bg-slate-50/80 transition-colors group ${editingId === t.id ? 'bg-amber-50 ring-1 ring-amber-200' : ''}`}>
                                <div className="min-w-0 flex-1">
                                    <div className="font-medium text-slate-800">{t.vehicleId || '—'} • {t.subCategory || t.description}</div>
                                    <div className="text-xs text-slate-500 mt-0.5">{formatDateBE(t.date)} {t.description !== (t.subCategory || '') ? `• ${t.description}` : ''}</div>
                                </div>
                                <div className="flex items-center gap-2 shrink-0">
                                    <span className="font-bold text-amber-700 tabular-nums">฿{(t.amount || 0).toLocaleString()}</span>
                                    <button type="button" onClick={() => loadForEdit(t)} className="p-2 rounded-lg text-slate-400 hover:text-amber-600 hover:bg-amber-50 opacity-0 group-hover:opacity-100 transition-all" title="แก้ไข"><Pencil size={16} /></button>
                                    {onDelete && <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) { onDelete(t.id); setEditingId(null); } }} className="p-2 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50 opacity-0 group-hover:opacity-100 transition-all" title="ลบ"><Trash2 size={16} /></button>}
                                </div>
                            </div>
                        ))
                    )}
                </div>
            </Card>
        </div>
    );
};

export default MaintenanceModule;
