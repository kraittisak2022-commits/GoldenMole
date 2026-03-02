import { CheckCircle2, XCircle } from 'lucide-react';

const Toast = ({ message, onClose }: { message: string, onClose: () => void }) => (
    <div className="fixed bottom-4 right-4 bg-slate-900 text-white px-6 py-3 rounded-xl shadow-2xl flex items-center gap-3 animate-slide-up z-[110] border border-slate-700">
        <CheckCircle2 className="text-emerald-400" size={20} />
        <span className="text-sm font-medium">{message}</span>
        <button onClick={onClose} className="ml-2 hover:text-slate-300"><XCircle size={16} /></button>
    </div>
);

export default Toast;
