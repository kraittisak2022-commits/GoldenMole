import { useState } from 'react';
import { Truck, Droplets, FileText } from 'lucide-react';
import MachineWorkLog from './MachineWorkLog';
import SandProductionLog from './SandProductionLog';
import GeneralEventLog from './GeneralEventLog';
import { AppSettings, Transaction, Employee } from '../../types';

interface DailyLogModuleProps {
    settings: AppSettings;
    onSaveTransaction: (t: Transaction) => void;
    transactions: Transaction[];
    employees: Employee[];
}

const DailyLogModule = ({ settings, onSaveTransaction, transactions, employees }: DailyLogModuleProps) => {
    const [activeTab, setActiveTab] = useState<'Machine' | 'Sand' | 'Event'>('Machine');

    return (
        <div className="space-y-6 animate-fade-in">
            <h2 className="text-2xl font-bold text-slate-800">บันทึกประจำวัน</h2>

            <div className="flex justify-center bg-white p-1 rounded-xl shadow-sm w-fit mx-auto">
                <button
                    onClick={() => setActiveTab('Machine')}
                    className={`flex items-center gap-2 px-4 py-2.5 rounded-lg transition-all ${activeTab === 'Machine' ? 'bg-amber-500 text-white shadow' : 'text-slate-500 hover:bg-slate-50'}`}
                >
                    <Truck size={18} /> <span className="text-sm font-medium">เครื่องจักร</span>
                </button>
                <button
                    onClick={() => setActiveTab('Sand')}
                    className={`flex items-center gap-2 px-4 py-2.5 rounded-lg transition-all ${activeTab === 'Sand' ? 'bg-blue-500 text-white shadow' : 'text-slate-500 hover:bg-slate-50'}`}
                >
                    <Droplets size={18} /> <span className="text-sm font-medium">ล้างทราย</span>
                </button>
                <button
                    onClick={() => setActiveTab('Event')}
                    className={`flex items-center gap-2 px-4 py-2.5 rounded-lg transition-all ${activeTab === 'Event' ? 'bg-purple-500 text-white shadow' : 'text-slate-500 hover:bg-slate-50'}`}
                >
                    <FileText size={18} /> <span className="text-sm font-medium">เหตุการณ์</span>
                </button>
            </div>

            <div className="animate-slide-up">
                {activeTab === 'Machine' && <MachineWorkLog settings={settings} onSave={onSaveTransaction} transactions={transactions} />}
                {activeTab === 'Sand' && <SandProductionLog onSave={onSaveTransaction} transactions={transactions} employees={employees} />}
                {activeTab === 'Event' && <GeneralEventLog onSave={onSaveTransaction} transactions={transactions} />}
            </div>
        </div>
    );
};

export default DailyLogModule;
