import { Smartphone, Monitor, Sun, Moon, ClipboardList, CalendarClock, ArrowRight } from 'lucide-react';
import { AdminUser } from '../../types';

interface PostLoginModeSelectProps {
    appName: string;
    appIcon: string;
    currentAdmin: AdminUser;
    darkMode: boolean;
    onToggleDarkMode: () => void;
    onChooseMobile: () => void;
    onChooseDesktop: () => void;
    onChooseDesktopMenu: (menuId: string) => void;
}

const PostLoginModeSelect = ({
    appName,
    appIcon,
    currentAdmin,
    darkMode,
    onToggleDarkMode,
    onChooseMobile,
    onChooseDesktop,
    onChooseDesktopMenu,
}: PostLoginModeSelectProps) => {
    const iconSrc = appIcon;

    return (
        <div
            className={`mobile-shell-root flex min-h-0 flex-col items-center justify-center pb-[max(2.5rem,env(safe-area-inset-bottom,0px))] ps-[max(1rem,env(safe-area-inset-left,0px))] pe-[max(1rem,env(safe-area-inset-right,0px))] pt-[max(2.5rem,env(safe-area-inset-top,0px))] transition-colors duration-300 ${
                darkMode ? 'app-shell-dark' : 'app-shell-light'
            }`}
        >
            <button
                type="button"
                onClick={onToggleDarkMode}
                style={{
                    top: 'max(1rem, env(safe-area-inset-top, 0px))',
                    right: 'max(1rem, env(safe-area-inset-right, 0px))',
                }}
                className={`fixed z-10 flex h-11 w-11 items-center justify-center rounded-full border shadow-sm touch-manipulation ${
                    darkMode ? 'border-white/10 bg-white/10 text-amber-300' : 'border-stone-200 bg-white text-stone-600'
                }`}
                aria-label="สลับโหมดสว่าง/มืด"
            >
                {darkMode ? <Sun size={20} /> : <Moon size={20} />}
            </button>

            <div className="w-full max-w-3xl space-y-7">
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

                <div className="grid gap-4 md:grid-cols-2">
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

                <section
                    className={`rounded-2xl border p-4 sm:p-5 ${
                        darkMode ? 'border-blue-500/30 bg-blue-500/10' : 'border-blue-200 bg-blue-50/70'
                    }`}
                >
                    <div className="mb-3">
                        <h2 className="text-base font-bold">บันทึกการทำงานประจำวัน</h2>
                        <p className={`mt-1 text-sm ${darkMode ? 'text-slate-300' : 'text-slate-700'}`}>
                            เลือกเข้าใช้งานได้ทันทีหลังล็อกอิน
                        </p>
                    </div>
                    <div className="grid gap-2.5 sm:grid-cols-2">
                        <button
                            type="button"
                            onClick={() => onChooseDesktopMenu('DailyWizard')}
                            className={`group min-h-[52px] rounded-xl border px-4 py-2 text-left text-sm font-semibold transition ${
                                darkMode
                                    ? 'border-blue-400/40 bg-blue-500/20 hover:bg-blue-500/25'
                                    : 'border-blue-300 bg-white hover:bg-blue-50'
                            }`}
                        >
                            <span className="inline-flex items-center gap-2">
                                <ClipboardList size={16} />
                                เปิดบันทึกงานประจำวัน
                            </span>
                        </button>
                        <button
                            type="button"
                            onClick={() => onChooseDesktopMenu('WorkPlanner')}
                            className={`group min-h-[52px] rounded-xl border px-4 py-2 text-left text-sm font-semibold transition ${
                                darkMode
                                    ? 'border-indigo-400/40 bg-indigo-500/20 hover:bg-indigo-500/25'
                                    : 'border-indigo-300 bg-white hover:bg-indigo-50'
                            }`}
                        >
                            <span className="inline-flex items-center gap-2">
                                <CalendarClock size={16} />
                                วางแผนงาน เดือน/สัปดาห์/วัน
                            </span>
                        </button>
                    </div>
                </section>

                <section
                    className={`rounded-2xl border p-4 sm:p-5 ${
                        darkMode ? 'border-white/10 bg-white/[0.03]' : 'border-stone-200 bg-white/80'
                    }`}
                >
                    <h2 className="mb-3 text-base font-bold">เมนูที่เข้าไว</h2>
                    <div className="grid gap-2.5 sm:grid-cols-2">
                        {[
                            { id: 'DailyWizard', label: 'บันทึกงานประจำวัน (Daily Wizard)' },
                            { id: 'WorkPlanner', label: 'วางแผนงานประจำวัน' },
                            { id: 'Dashboard', label: 'ดูภาพรวมแดชบอร์ด' },
                            { id: 'DataList', label: 'ดูรายการบันทึกย้อนหลัง' },
                        ].map(item => (
                            <button
                                key={item.id}
                                type="button"
                                onClick={() => onChooseDesktopMenu(item.id)}
                                className={`flex min-h-[48px] items-center justify-between rounded-xl border px-3.5 py-2 text-left text-sm font-medium transition ${
                                    darkMode
                                        ? 'border-white/10 bg-white/[0.02] hover:bg-white/[0.07]'
                                        : 'border-stone-200 bg-white hover:bg-stone-50'
                                }`}
                            >
                                <span>{item.label}</span>
                                <ArrowRight size={15} className={darkMode ? 'text-slate-500' : 'text-slate-400'} />
                            </button>
                        ))}
                    </div>
                </section>
            </div>
        </div>
    );
};

export default PostLoginModeSelect;
