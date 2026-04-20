import { Smartphone, Monitor, Sun, Moon } from 'lucide-react';
import { AdminUser } from '../../types';

interface PostLoginModeSelectProps {
    appName: string;
    appIcon: string;
    currentAdmin: AdminUser;
    darkMode: boolean;
    onToggleDarkMode: () => void;
    onChooseMobile: () => void;
    onChooseDesktop: () => void;
}

const PostLoginModeSelect = ({
    appName,
    appIcon,
    currentAdmin,
    darkMode,
    onToggleDarkMode,
    onChooseMobile,
    onChooseDesktop,
}: PostLoginModeSelectProps) => {
    const iconSrc = appIcon;

    return (
        <div
            className={`min-h-screen min-h-[100dvh] flex flex-col items-center justify-center px-4 py-10 transition-colors duration-300 ${
                darkMode ? 'bg-[#0a0a0f] text-gray-100' : 'bg-gradient-to-b from-stone-50 to-amber-50/40 text-slate-900'
            }`}
        >
            <button
                type="button"
                onClick={onToggleDarkMode}
                className={`fixed top-4 right-4 z-10 flex h-11 w-11 items-center justify-center rounded-full border shadow-sm touch-manipulation ${
                    darkMode ? 'border-white/10 bg-white/10 text-amber-300' : 'border-stone-200 bg-white text-stone-600'
                }`}
                aria-label="สลับโหมดสว่าง/มืด"
            >
                {darkMode ? <Sun size={20} /> : <Moon size={20} />}
            </button>

            <div className="w-full max-w-md space-y-8">
                <div className="text-center space-y-3">
                    <div
                        className={`mx-auto flex h-20 w-20 items-center justify-center overflow-hidden rounded-2xl shadow-lg ${
                            darkMode ? 'bg-white/5 ring-1 ring-amber-500/30' : 'bg-white ring-1 ring-stone-200'
                        }`}
                    >
                        {iconSrc.startsWith('http') || iconSrc.startsWith('data:') ? (
                            <img src={iconSrc} alt="" className="h-full w-full object-cover" />
                        ) : (
                            <span className="text-2xl font-bold text-amber-600 dark:text-amber-400">{iconSrc}</span>
                        )}
                    </div>
                    <div>
                        <p className={`text-sm ${darkMode ? 'text-slate-400' : 'text-slate-600'}`}>สวัสดี {currentAdmin.displayName}</p>
                        <h1 className="text-xl font-bold tracking-tight">{appName}</h1>
                        <p className={`mt-2 text-sm ${darkMode ? 'text-slate-500' : 'text-slate-600'}`}>
                            เลือกประเภทการใช้งาน — โหมดมือถือเน้นกรอกข้อมูลง่ายและปุ่มใหญ่
                        </p>
                    </div>
                </div>

                <div className="grid gap-4">
                    <button
                        type="button"
                        onClick={onChooseMobile}
                        className={`group flex w-full items-start gap-4 rounded-2xl border p-5 text-left shadow-sm transition active:scale-[0.99] touch-manipulation min-h-[96px] ${
                            darkMode
                                ? 'border-emerald-500/30 bg-emerald-500/10 hover:bg-emerald-500/15'
                                : 'border-emerald-200 bg-white hover:bg-emerald-50/80'
                        }`}
                    >
                        <span
                            className={`flex h-14 w-14 shrink-0 items-center justify-center rounded-xl ${
                                darkMode ? 'bg-emerald-500/20 text-emerald-300' : 'bg-emerald-100 text-emerald-700'
                            }`}
                        >
                            <Smartphone size={28} strokeWidth={2} aria-hidden />
                        </span>
                        <span className="min-w-0 flex-1">
                            <span className="block text-lg font-bold">สำหรับมือถือ</span>
                            <span className={`mt-1 block text-sm leading-snug ${darkMode ? 'text-slate-400' : 'text-slate-600'}`}>
                                หน้าจอเต็มแบบแอป ปุ่มใหญ่ เหมาะกับบันทึกหน้างาน
                            </span>
                        </span>
                    </button>

                    <button
                        type="button"
                        onClick={onChooseDesktop}
                        className={`group flex w-full items-start gap-4 rounded-2xl border p-5 text-left shadow-sm transition active:scale-[0.99] touch-manipulation min-h-[96px] ${
                            darkMode
                                ? 'border-slate-600 bg-white/[0.04] hover:bg-white/[0.07]'
                                : 'border-stone-200 bg-white hover:bg-stone-50'
                        }`}
                    >
                        <span
                            className={`flex h-14 w-14 shrink-0 items-center justify-center rounded-xl ${
                                darkMode ? 'bg-slate-700 text-slate-200' : 'bg-slate-100 text-slate-700'
                            }`}
                        >
                            <Monitor size={28} strokeWidth={2} aria-hidden />
                        </span>
                        <span className="min-w-0 flex-1">
                            <span className="block text-lg font-bold">เว็บแอปปกติ</span>
                            <span className={`mt-1 block text-sm leading-snug ${darkMode ? 'text-slate-400' : 'text-slate-600'}`}>
                                เมนูครบ แดชบอร์ด รายงาน และการตั้งค่าแบบเดสก์ท็อป
                            </span>
                        </span>
                    </button>
                </div>
            </div>
        </div>
    );
};

export default PostLoginModeSelect;
