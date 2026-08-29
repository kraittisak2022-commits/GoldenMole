import { useCallback, useEffect, useMemo, useState } from 'react';
import { X, Link2, Copy, RefreshCw, Eye, EyeOff, Check, BarChart3, Pencil } from 'lucide-react';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import ShareQrCode from './ShareQrCode';
import {
    buildShareUrl,
    ensureShareSettings,
    generateShareToken,
    hashSharePinForStorage,
    saveShareSettings,
    type DashboardShareSettings,
} from '../../services/shareService';
import {
    fetchShareVisits,
    formatVisitWhen,
    updateShareVisitLabel,
    type DashboardShareVisit,
} from '../../services/shareVisitService';
import { isValidSharePinFormat } from '../../utils/shareAuth';

interface ShareLinkManagerProps {
    open: boolean;
    onClose: () => void;
}

const ShareLinkManager = ({ open, onClose }: ShareLinkManagerProps) => {
    const [settings, setSettings] = useState<DashboardShareSettings | null>(null);
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [newPin, setNewPin] = useState('');
    const [confirmPin, setConfirmPin] = useState('');
    const [copied, setCopied] = useState(false);
    const [message, setMessage] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);
    const [visits, setVisits] = useState<DashboardShareVisit[]>([]);
    const [visitsLoading, setVisitsLoading] = useState(false);
    const [editingVisitId, setEditingVisitId] = useState<string | null>(null);
    const [editingLabel, setEditingLabel] = useState('');

    const shareUrl = settings?.shareToken ? buildShareUrl(settings.shareToken) : '';

    const visitStats = useMemo(() => {
        const totalViews = visits.reduce((sum, v) => sum + v.visitCount, 0);
        return {
            devices: visits.length,
            totalViews,
            lastAt: visits[0]?.lastSeenAt ? formatVisitWhen(visits[0].lastSeenAt) : '—',
        };
    }, [visits]);

    const loadVisits = useCallback(async () => {
        setVisitsLoading(true);
        const rows = await fetchShareVisits();
        setVisits(rows);
        setVisitsLoading(false);
    }, []);

    const load = useCallback(async () => {
        setLoading(true);
        const data = await ensureShareSettings();
        setSettings(data);
        setLoading(false);
        void loadVisits();
    }, [loadVisits]);

    useEffect(() => {
        if (!open) return;
        void load();
        setNewPin('');
        setConfirmPin('');
        setCopied(false);
        setMessage(null);
        setEditingVisitId(null);
        setEditingLabel('');
    }, [open, load]);

    useEffect(() => {
        if (!open) return;
        const onKey = (e: KeyboardEvent) => {
            if (e.key === 'Escape') onClose();
        };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    }, [open, onClose]);

    const persist = async (next: DashboardShareSettings, successMsg?: string) => {
        setSaving(true);
        const ok = await saveShareSettings(next);
        setSaving(false);
        if (!ok) {
            setMessage({ type: 'err', text: 'บันทึกไม่สำเร็จ' });
            return false;
        }
        setSettings(next);
        if (successMsg) setMessage({ type: 'ok', text: successMsg });
        return true;
    };

    const toggleEnabled = async () => {
        if (!settings) return;
        if (!settings.enabled && !settings.pinHash) {
            setMessage({ type: 'err', text: 'กรุณาตั้งรหัส PIN ก่อนเปิดการแชร์' });
            return;
        }
        await persist({ ...settings, enabled: !settings.enabled }, settings.enabled ? 'ปิดการแชร์แล้ว' : 'เปิดการแชร์แล้ว');
    };

    const toggleFinancial = async () => {
        if (!settings) return;
        await persist({ ...settings, showFinancial: !settings.showFinancial }, 'อัปเดตการแสดงข้อมูลการเงินแล้ว');
    };

    const savePin = async () => {
        if (!settings) return;
        if (!isValidSharePinFormat(newPin)) {
            setMessage({ type: 'err', text: 'PIN ต้องเป็นตัวเลข 4-6 หลัก' });
            return;
        }
        if (newPin !== confirmPin) {
            setMessage({ type: 'err', text: 'PIN ยืนยันไม่ตรงกัน' });
            return;
        }
        const pinHash = await hashSharePinForStorage(newPin);
        const ok = await persist({ ...settings, pinHash }, 'บันทึก PIN แล้ว');
        if (ok) {
            setNewPin('');
            setConfirmPin('');
        }
    };

    const regenerateToken = async () => {
        if (!settings) return;
        if (!window.confirm('สุ่มลิงก์ใหม่? ลิงก์เดิมจะใช้ไม่ได้ทันที')) return;
        const token = generateShareToken();
        await persist({ ...settings, shareToken: token }, 'สร้างลิงก์ใหม่แล้ว');
        setCopied(false);
    };

    const copyLink = async () => {
        if (!shareUrl) return;
        try {
            await navigator.clipboard.writeText(shareUrl);
            setCopied(true);
            setMessage({ type: 'ok', text: 'คัดลอกลิงก์แล้ว' });
            window.setTimeout(() => setCopied(false), 2000);
        } catch {
            setMessage({ type: 'err', text: 'คัดลอกไม่สำเร็จ' });
        }
    };

    const startEditLabel = (visit: DashboardShareVisit) => {
        setEditingVisitId(visit.id);
        setEditingLabel(visit.deviceLabel);
    };

    const saveVisitLabel = async () => {
        if (!editingVisitId) return;
        const ok = await updateShareVisitLabel(editingVisitId, editingLabel);
        if (!ok) {
            setMessage({ type: 'err', text: 'บันทึกชื่ออุปกรณ์ไม่สำเร็จ' });
            return;
        }
        setVisits((prev) =>
            prev.map((v) => (v.id === editingVisitId ? { ...v, deviceLabel: editingLabel.trim() } : v)),
        );
        setEditingVisitId(null);
        setEditingLabel('');
        setMessage({ type: 'ok', text: 'อัปเดตชื่ออุปกรณ์แล้ว' });
    };

    if (!open) return null;

    return (
        <div className="fixed inset-0 z-[120] flex items-end justify-center bg-slate-950/60 p-0 backdrop-blur-sm sm:items-center sm:p-4">
            <div className="flex max-h-[92dvh] w-full max-w-lg flex-col overflow-hidden rounded-t-3xl border border-slate-200 bg-white shadow-2xl sm:rounded-2xl">
                <div className="flex items-center justify-between border-b border-slate-100 px-5 py-4">
                    <div className="flex items-center gap-2">
                        <Link2 size={18} className="text-indigo-600" />
                        <h2 className="text-lg font-bold text-slate-900">แชร์ลิงก์ Real-time V.4</h2>
                    </div>
                    <button
                        type="button"
                        onClick={onClose}
                        className="rounded-xl p-2 text-slate-500 hover:bg-slate-100"
                        aria-label="ปิด"
                    >
                        <X size={18} />
                    </button>
                </div>

                <div className="flex-1 overflow-y-auto px-5 py-4 space-y-5">
                    {loading || !settings ? (
                        <p className="text-sm text-slate-500">กำลังโหลด...</p>
                    ) : (
                        <>
                            <div className="flex items-center justify-between rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
                                <div>
                                    <p className="text-sm font-semibold text-slate-800">เปิดการแชร์ลิงก์</p>
                                    <p className="text-xs text-slate-500">ผู้รับลิงก์ต้องกรอก PIN ก่อนดู</p>
                                </div>
                                <button
                                    type="button"
                                    role="switch"
                                    aria-checked={settings.enabled}
                                    onClick={() => void toggleEnabled()}
                                    disabled={saving}
                                    className={`relative h-7 w-12 rounded-full transition ${settings.enabled ? 'bg-emerald-500' : 'bg-slate-300'}`}
                                >
                                    <span
                                        className={`absolute top-0.5 h-6 w-6 rounded-full bg-white shadow transition ${settings.enabled ? 'left-5' : 'left-0.5'}`}
                                    />
                                </button>
                            </div>

                            <div className="flex items-center justify-between rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
                                <div className="flex items-center gap-2">
                                    {settings.showFinancial ? <Eye size={16} className="text-slate-600" /> : <EyeOff size={16} className="text-slate-600" />}
                                    <div>
                                        <p className="text-sm font-semibold text-slate-800">แสดงข้อมูลการเงิน</p>
                                        <p className="text-xs text-slate-500">รายรับ รายจ่าย กำไรสุทธิ</p>
                                    </div>
                                </div>
                                <button
                                    type="button"
                                    role="switch"
                                    aria-checked={settings.showFinancial}
                                    onClick={() => void toggleFinancial()}
                                    disabled={saving}
                                    className={`relative h-7 w-12 rounded-full transition ${settings.showFinancial ? 'bg-indigo-500' : 'bg-slate-300'}`}
                                >
                                    <span
                                        className={`absolute top-0.5 h-6 w-6 rounded-full bg-white shadow transition ${settings.showFinancial ? 'left-5' : 'left-0.5'}`}
                                    />
                                </button>
                            </div>

                            <div className="space-y-2">
                                <p className="text-sm font-semibold text-slate-800">ลิงก์แชร์</p>
                                <div className="flex gap-2">
                                    <Input
                                        readOnly
                                        value={shareUrl}
                                        className="flex-1 text-xs font-mono"
                                    />
                                    <Button variant="outline" onClick={() => void copyLink()} disabled={!shareUrl}>
                                        {copied ? <Check size={16} /> : <Copy size={16} />}
                                    </Button>
                                </div>
                                <div className="flex flex-col items-center gap-3 rounded-2xl border border-slate-200 bg-slate-50 p-4 sm:flex-row sm:items-start">
                                    {shareUrl && <ShareQrCode value={shareUrl} size={160} />}
                                    <div className="flex-1 space-y-2 text-center sm:text-left">
                                        <p className="text-xs text-slate-500">สแกน QR เพื่อเปิดบนมือถือ</p>
                                        <Button variant="outline" className="w-full sm:w-auto" onClick={() => void regenerateToken()} disabled={saving}>
                                            <RefreshCw size={14} />
                                            สุ่มลิงก์ใหม่
                                        </Button>
                                    </div>
                                </div>
                            </div>

                            <div className="space-y-3 rounded-2xl border border-slate-200 p-4">
                                <p className="text-sm font-semibold text-slate-800">
                                    {settings.pinHash ? 'เปลี่ยนรหัส PIN' : 'ตั้งรหัส PIN'}
                                </p>
                                <Input
                                    type="password"
                                    inputMode="numeric"
                                    pattern="[0-9]*"
                                    placeholder="PIN 4-6 หลัก"
                                    value={newPin}
                                    onChange={(e) => setNewPin(e.target.value.replace(/\D/g, '').slice(0, 6))}
                                />
                                <Input
                                    type="password"
                                    inputMode="numeric"
                                    pattern="[0-9]*"
                                    placeholder="ยืนยัน PIN"
                                    value={confirmPin}
                                    onChange={(e) => setConfirmPin(e.target.value.replace(/\D/g, '').slice(0, 6))}
                                />
                                <Button onClick={() => void savePin()} disabled={saving || !newPin || !confirmPin}>
                                    บันทึก PIN
                                </Button>
                            </div>

                            <div className="space-y-3 rounded-2xl border border-indigo-100 bg-indigo-50/40 p-4">
                                <div className="flex items-center justify-between gap-2">
                                    <div className="flex items-center gap-2">
                                        <BarChart3 size={16} className="text-indigo-600" />
                                        <p className="text-sm font-semibold text-slate-800">สถิติการเข้าชม</p>
                                    </div>
                                    <Button variant="outline" className="h-8 px-2 text-xs" onClick={() => void loadVisits()} disabled={visitsLoading}>
                                        <RefreshCw size={12} className={visitsLoading ? 'animate-spin' : undefined} />
                                        รีเฟรช
                                    </Button>
                                </div>
                                <div className="grid grid-cols-3 gap-2">
                                    <div className="rounded-xl bg-white px-2.5 py-2 text-center shadow-sm">
                                        <p className="text-[10px] font-bold uppercase tracking-wide text-slate-400">อุปกรณ์</p>
                                        <p className="text-lg font-black tabular-nums text-slate-800">{visitStats.devices}</p>
                                    </div>
                                    <div className="rounded-xl bg-white px-2.5 py-2 text-center shadow-sm">
                                        <p className="text-[10px] font-bold uppercase tracking-wide text-slate-400">ครั้งทั้งหมด</p>
                                        <p className="text-lg font-black tabular-nums text-slate-800">{visitStats.totalViews}</p>
                                    </div>
                                    <div className="rounded-xl bg-white px-2.5 py-2 text-center shadow-sm">
                                        <p className="text-[10px] font-bold uppercase tracking-wide text-slate-400">ล่าสุด</p>
                                        <p className="truncate text-[11px] font-bold text-slate-700">{visitStats.lastAt}</p>
                                    </div>
                                </div>

                                {visits.length === 0 ? (
                                    <p className="text-center text-xs text-slate-500">
                                        {visitsLoading ? 'กำลังโหลดสถิติ...' : 'ยังไม่มีประวัติการเข้าชม'}
                                    </p>
                                ) : (
                                    <ul className="max-h-56 space-y-2 overflow-y-auto">
                                        {visits.map((visit) => (
                                            <li
                                                key={visit.id}
                                                className="rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-left shadow-sm"
                                            >
                                                {editingVisitId === visit.id ? (
                                                    <div className="flex gap-2">
                                                        <Input
                                                            value={editingLabel}
                                                            onChange={(e) => setEditingLabel(e.target.value.slice(0, 60))}
                                                            placeholder="ชื่ออุปกรณ์"
                                                            className="flex-1 text-sm"
                                                        />
                                                        <Button className="shrink-0" onClick={() => void saveVisitLabel()}>
                                                            บันทึก
                                                        </Button>
                                                        <Button
                                                            variant="outline"
                                                            className="shrink-0"
                                                            onClick={() => {
                                                                setEditingVisitId(null);
                                                                setEditingLabel('');
                                                            }}
                                                        >
                                                            ยกเลิก
                                                        </Button>
                                                    </div>
                                                ) : (
                                                    <>
                                                        <div className="flex items-start justify-between gap-2">
                                                            <div className="min-w-0">
                                                                <p className="truncate text-sm font-bold text-slate-800">
                                                                    {visit.deviceLabel || 'ยังไม่ตั้งชื่อ'}
                                                                </p>
                                                                <p className="mt-0.5 font-mono text-[11px] text-slate-500">
                                                                    IP: {visit.ipAddress || '—'}
                                                                </p>
                                                            </div>
                                                            <button
                                                                type="button"
                                                                onClick={() => startEditLabel(visit)}
                                                                className="rounded-lg p-1.5 text-slate-500 hover:bg-slate-100"
                                                                aria-label="ตั้งชื่ออุปกรณ์"
                                                                title="ตั้งชื่ออุปกรณ์"
                                                            >
                                                                <Pencil size={14} />
                                                            </button>
                                                        </div>
                                                        <div className="mt-1.5 flex flex-wrap gap-x-3 gap-y-0.5 text-[11px] text-slate-600">
                                                            <span>
                                                                เข้าชม <strong className="tabular-nums">{visit.visitCount}</strong> ครั้ง
                                                            </span>
                                                            <span>ล่าสุด {formatVisitWhen(visit.lastSeenAt)}</span>
                                                        </div>
                                                    </>
                                                )}
                                            </li>
                                        ))}
                                    </ul>
                                )}
                            </div>

                            {message && (
                                <p
                                    className={`rounded-xl px-3 py-2 text-sm font-medium ${
                                        message.type === 'ok'
                                            ? 'bg-emerald-50 text-emerald-700'
                                            : 'bg-rose-50 text-rose-700'
                                    }`}
                                >
                                    {message.text}
                                </p>
                            )}
                        </>
                    )}
                </div>

                <div className="border-t border-slate-100 px-5 py-3">
                    <Button variant="outline" className="w-full" onClick={onClose}>
                        ปิด
                    </Button>
                </div>
            </div>
        </div>
    );
};

export default ShareLinkManager;
