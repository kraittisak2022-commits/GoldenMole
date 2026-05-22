import { Calendar, ChevronLeft, Home, LogOut, Settings } from 'lucide-react';

type MobileNavRailProps = {
    open: boolean;
    homeSelected: boolean;
    onHome: () => void;
    onCalendar: () => void;
    onSettings: () => void;
    onToggleRail: () => void;
    onLogout: () => void;
};

const SquircleNavButton = ({
    icon: Icon,
    selected,
    label,
    onClick,
}: {
    icon: typeof Home;
    selected?: boolean;
    label: string;
    onClick: () => void;
}) => (
    <button
        type="button"
        onClick={onClick}
        title={label}
        aria-label={label}
        className={`flex h-12 w-12 items-center justify-center rounded-[14px] border bg-white touch-manipulation transition-colors active:scale-95 ${
            selected ? 'border-[#00897B] border-2 text-[#00897B]' : 'border-[#E0E0E0] text-[#9E9E9E]'
        }`}
    >
        <Icon size={22} strokeWidth={2} />
    </button>
);

const MobileNavRail = ({
    open,
    homeSelected,
    onHome,
    onCalendar,
    onSettings,
    onToggleRail,
    onLogout,
}: MobileNavRailProps) => {
    if (!open) return null;

    return (
        <nav
            className="flex w-[72px] shrink-0 flex-col items-center border-r border-slate-200/80 bg-white py-2.5"
            aria-label="เมนูหลัก"
        >
            <SquircleNavButton icon={Home} selected={homeSelected} label="หน้าแรก" onClick={onHome} />
            <div className="mt-2">
                <SquircleNavButton icon={Calendar} label="ปฏิทิน" onClick={onCalendar} />
            </div>
            <div className="mt-2">
                <SquircleNavButton icon={Settings} label="ตั้งค่า" onClick={onSettings} />
            </div>
            <div className="flex flex-1 items-center justify-center">
                <button
                    type="button"
                    onClick={onToggleRail}
                    title="ซ่อนเมนู"
                    aria-label="ซ่อนเมนู"
                    className="flex items-center justify-center rounded-[22px] bg-[#F5F5F5] px-2 py-2.5 touch-manipulation active:scale-95"
                >
                    <ChevronLeft size={22} className="text-[#546E7A]" />
                </button>
            </div>
            <SquircleNavButton icon={LogOut} label="ออกจากระบบ" onClick={onLogout} />
            <div className="h-3" />
        </nav>
    );
};

export default MobileNavRail;
