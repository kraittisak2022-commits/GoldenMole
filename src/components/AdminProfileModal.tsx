import { useState, useEffect } from 'react';
import { X, UserCircle, Lock, Sun, Moon, Monitor } from 'lucide-react';
import Button from './ui/Button';
import Input from './ui/Input';
import { AdminUser, AdminUiTheme } from '../types';

export interface AdminProfileModalProps {
    open: boolean;
    onClose: () => void;
    currentAdmin: AdminUser;
    darkMode: boolean;
    onUpdateAdminProfile: (updates: {
        displayName?: string;
        avatar?: string;
        uiTheme?: AdminUiTheme;
        currentPassword?: string;
        newPassword?: string;
    }) => Promise<{ ok: boolean; message?: string }>;
}

const AdminProfileModal = ({ open, onClose, currentAdmin, darkMode, onUpdateAdminProfile }: AdminProfileModalProps) => {
    const [accountForm, setAccountForm] = useState({
        displayName: '',
        avatar: '',
        uiTheme: 'system' as AdminUiTheme,
        currentPassword: '',
        newPassword: '',
        confirmPassword: '',
    });
    const [saving, setSaving] = useState(false);
    const [msg, setMsg] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);

    useEffect(() => {
        if (!open || !currentAdmin) return;
        setAccountForm({
            displayName: currentAdmin.displayName,
            avatar: currentAdmin.avatar || '',
            uiTheme: currentAdmin.uiTheme ?? 'system',
            currentPassword: '',
            newPassword: '',
            confirmPassword: '',
        });
        setMsg(null);
    }, [open, currentAdmin?.id, currentAdmin?.displayName, currentAdmin?.avatar, currentAdmin?.uiTheme]);

    useEffect(() => {
        if (!open) return;
        const onKey = (e: KeyboardEvent) => {
            if (e.key === 'Escape') onClose();
        };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    }, [open, onClose]);

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

    const saveProfile = async () => {
        setSaving(true);
        setMsg(null);
        const r = await onUpdateAdminProfile({
            displayName: accountForm.displayName,
            avatar: accountForm.avatar,
            uiTheme: accountForm.uiTheme,
        });
        setSaving(false);
        if (r.ok) setMsg({ type: 'ok', text: 'บันทึกโปรไฟล์แล้ว' });
        else setMsg({ type: 'err', text: r.message || 'เกิดข้อผิดพลาด' });
    };

    const savePassword = async () => {
        if (accountForm.newPassword !== accountForm.confirmPassword) {
            setMsg({ type: 'err', text: 'รหัสผ่านใหม่ไม่ตรงกัน' });
            return;
        }
        if (!accountForm.newPassword) {
            setMsg({ type: 'err', text: 'กรุณากรอกรหัสผ่านใหม่' });
            return;
        }
        setSaving(true);
        setMsg(null);
        const r = await onUpdateAdminProfile({
            currentPassword: accountForm.currentPassword,
            newPassword: accountForm.newPassword,
        });
        setSaving(false);
        if (r.ok) {
            setAccountForm(prev => ({ ...prev, currentPassword: '', newPassword: '', confirmPassword: '' }));
            setMsg({ type: 'ok', text: 'เปลี่ยนรหัสผ่านแล้ว' });
        } else setMsg({ type: 'err', text: r.message || 'เกิดข้อผิดพลาด' });
    };

    if (!open) return null;

    const panelClass = darkMode
        ? 'border-white/[0.08] bg-[#12121a]/95 text-gray-100 shadow-2xl ring-1 ring-white/[0.06]'
        : 'border-stone-200/90 bg-white text-slate-800 shadow-2xl ring-1 ring-black/[0.04]';

    return (
        <div
            className="fixed inset-0 z-[120] flex items-center justify-center p-4 sm:p-6"
            role="dialog"
            aria-modal="true"
            aria-labelledby="admin-profile-modal-title"
        >
            <button
                type="button"
                className="absolute inset-0 bg-black/50 dark:bg-black/65 backdrop-blur-[2px]"
                onClick={onClose}
                aria-label="ปิด"
            />
            <div
                className={`relative z-10 flex max-h-[min(92vh,880px)] w-full max-w-lg flex-col overflow-hidden rounded-2xl border ${panelClass}`}
            >
                <div
                    className={`flex shrink-0 items-center justify-between gap-3 border-b px-4 py-3 sm:px-5 sm:py-4 ${
                        darkMode ? 'border-white/[0.08] bg-white/[0.03]' : 'border-stone-200/80 bg-stone-50/80'
                    }`}
                >
                    <div className="flex min-w-0 items-center gap-2.5">
                        <UserCircle className={`shrink-0 ${darkMode ? 'text-amber-400' : 'text-amber-600'}`} size={22} />
                        <div className="min-w-0">
                            <h2 id="admin-profile-modal-title" className="truncate text-base font-bold sm:text-lg">
                                บัญชีแอดมิน
                            </h2>
                            <p className="truncate text-xs text-slate-500 dark:text-slate-400">@{currentAdmin.username}</p>
                        </div>
                    </div>
                    <button
                        type="button"
                        onClick={onClose}
                        className={`shrink-0 rounded-xl p-2 transition-colors ${
                            darkMode ? 'text-slate-400 hover:bg-white/10 hover:text-white' : 'text-slate-500 hover:bg-stone-200/80 hover:text-slate-800'
                        }`}
                        aria-label="ปิดหน้าต่าง"
                    >
                        <X size={20} />
                    </button>
                </div>

                <div className="min-h-0 flex-1 overflow-y-auto px-4 py-4 sm:px-5 sm:py-5">
                    <p className="mb-4 text-sm text-slate-500 dark:text-slate-400">
                        แก้ชื่อที่แสดง รูปประจำตัว โหมดสว่าง/มืด และรหัสผ่านของบัญชีนี้
                    </p>

                    {msg && (
                        <div
                            className={`mb-4 rounded-xl border px-4 py-3 text-sm ${
                                msg.type === 'ok'
                                    ? 'border-emerald-200 bg-emerald-50 text-emerald-800 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200'
                                    : 'border-red-200 bg-red-50 text-red-800 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-200'
                            }`}
                        >
                            {msg.text}
                        </div>
                    )}

                    <div className="space-y-4">
                        <Input
                            label="ชื่อที่แสดง"
                            value={accountForm.displayName}
                            onChange={(e: React.ChangeEvent<HTMLInputElement>) => setAccountForm({ ...accountForm, displayName: e.target.value })}
                        />
                        <div className="flex flex-col gap-2">
                            <span className="text-sm font-medium text-slate-700 dark:text-slate-300">รูปประจำตัว</span>
                            <div className="flex flex-wrap items-center gap-4">
                                <div className="flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-full border-2 border-slate-200 bg-slate-100 dark:border-white/15 dark:bg-slate-800">
                                    {accountForm.avatar && (accountForm.avatar.startsWith('http') || accountForm.avatar.startsWith('data:')) ? (
                                        <img src={accountForm.avatar} alt="" className="h-full w-full object-cover" />
                                    ) : (
                                        <span className="text-xl font-bold text-slate-500">{accountForm.displayName.charAt(0) || '?'}</span>
                                    )}
                                </div>
                                <div className="min-w-[200px] flex-1 space-y-2">
                                    <Input
                                        value={accountForm.avatar}
                                        onChange={(e: React.ChangeEvent<HTMLInputElement>) => setAccountForm({ ...accountForm, avatar: e.target.value })}
                                        placeholder="URL รูป หรืออัปโหลด"
                                    />
                                    <label className="inline-flex cursor-pointer items-center gap-2 text-sm text-slate-600 dark:text-slate-400">
                                        <input type="file" accept="image/*" className="hidden" onChange={onAvatarFile} />
                                        <span className="underline decoration-dotted">อัปโหลดรูปจากเครื่อง</span>
                                        <span className="text-xs">(สูงสุด ~600 KB)</span>
                                    </label>
                                </div>
                            </div>
                        </div>

                        <div>
                            <p className="mb-2 text-sm font-medium text-slate-700 dark:text-slate-300">โหมดแสดงผล</p>
                            <div className="flex flex-wrap gap-2">
                                {(
                                    [
                                        { v: 'system' as const, label: 'ตามระบบ', Icon: Monitor },
                                        { v: 'light' as const, label: 'สว่าง', Icon: Sun },
                                        { v: 'dark' as const, label: 'มืด', Icon: Moon },
                                    ] as const
                                ).map(({ v, label, Icon }) => (
                                    <button
                                        key={v}
                                        type="button"
                                        onClick={() => setAccountForm({ ...accountForm, uiTheme: v })}
                                        className={`flex items-center gap-2 rounded-xl border px-3 py-2.5 text-sm font-medium transition-all sm:px-4 ${
                                            accountForm.uiTheme === v
                                                ? 'border-slate-800 bg-slate-800 text-white dark:border-amber-500/40 dark:bg-amber-500/20 dark:text-amber-100'
                                                : 'border-slate-200 bg-slate-50 text-slate-700 hover:bg-slate-100 dark:border-white/10 dark:bg-white/[0.04] dark:text-slate-300 dark:hover:bg-white/[0.08]'
                                        }`}
                                    >
                                        <Icon size={18} /> {label}
                                    </button>
                                ))}
                            </div>
                            <p className="mt-2 text-xs text-slate-400">«ตามระบบ» จะสลับตามการตั้งค่าของเครื่อง</p>
                        </div>

                        <Button onClick={saveProfile} disabled={saving} className="w-full sm:w-auto">
                            {saving ? 'กำลังบันทึก...' : 'บันทึกโปรไฟล์'}
                        </Button>
                    </div>

                    <div className="mt-8 space-y-4 border-t border-slate-200 pt-8 dark:border-white/10">
                        <div className="flex items-center gap-2">
                            <Lock className="text-slate-500" size={18} />
                            <h3 className="font-bold text-slate-800 dark:text-slate-100">เปลี่ยนรหัสผ่าน</h3>
                        </div>
                        <Input
                            type="password"
                            label="รหัสผ่านปัจจุบัน"
                            value={accountForm.currentPassword}
                            onChange={(e: React.ChangeEvent<HTMLInputElement>) => setAccountForm({ ...accountForm, currentPassword: e.target.value })}
                            autoComplete="current-password"
                        />
                        <Input
                            type="password"
                            label="รหัสผ่านใหม่"
                            value={accountForm.newPassword}
                            onChange={(e: React.ChangeEvent<HTMLInputElement>) => setAccountForm({ ...accountForm, newPassword: e.target.value })}
                            autoComplete="new-password"
                        />
                        <Input
                            type="password"
                            label="ยืนยันรหัสผ่านใหม่"
                            value={accountForm.confirmPassword}
                            onChange={(e: React.ChangeEvent<HTMLInputElement>) => setAccountForm({ ...accountForm, confirmPassword: e.target.value })}
                            autoComplete="new-password"
                        />
                        <Button onClick={savePassword} disabled={saving} variant="outline" className="w-full sm:w-auto">
                            {saving ? 'กำลังบันทึก...' : 'เปลี่ยนรหัสผ่าน'}
                        </Button>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default AdminProfileModal;
