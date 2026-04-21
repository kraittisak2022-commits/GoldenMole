import React, { useState, useRef, useEffect, useLayoutEffect } from 'react';
import { createPortal } from 'react-dom';
import { Calendar as CalendarIcon, ChevronLeft, ChevronRight } from 'lucide-react';
import { formatDateBE } from '../../utils';

interface DatePickerProps {
    label?: string;
    value: string; // YYYY-MM-DD
    onChange: (date: string) => void;
    className?: string;
    /** ปุ่มวันและช่องกดใหญ่ขึ้น (จอสัมผัส / Daily Wizard) */
    touchFriendly?: boolean;
}

const DatePicker: React.FC<DatePickerProps> = ({ label, value, onChange, className = '', touchFriendly = false }) => {
    const [isOpen, setIsOpen] = useState(false);
    const [dropdownPosition, setDropdownPosition] = useState({ top: 0, left: 0 });
    const [currentMonth, setCurrentMonth] = useState(() => {
        const d = value ? new Date(value) : new Date();
        return new Date(d.getFullYear(), d.getMonth(), 1);
    });

    // Auto-update current month if value changes
    useEffect(() => {
        if (value && !isOpen) {
            const d = new Date(value);
            setCurrentMonth(new Date(d.getFullYear(), d.getMonth(), 1));
        }
    }, [value, isOpen]);

    const containerRef = useRef<HTMLDivElement>(null);
    const triggerRef = useRef<HTMLDivElement>(null);

    const openCalendar = () => {
        if (triggerRef.current) {
            const rect = triggerRef.current.getBoundingClientRect();
            setDropdownPosition({ top: rect.bottom + 8, left: rect.left + rect.width / 2 });
        }
        setIsOpen(true);
    };

    // Keep position in sync on scroll/resize while open
    useLayoutEffect(() => {
        if (!isOpen || !triggerRef.current) return;
        const rect = triggerRef.current.getBoundingClientRect();
        setDropdownPosition({ top: rect.bottom + 8, left: rect.left + rect.width / 2 });
    }, [isOpen]);

    // Close on click outside (ไม่ปิดเมื่อคลิกภายในปฏิทินที่แสดงใน portal)
    useEffect(() => {
        const handleOutsideClick = (e: MouseEvent) => {
            const target = e.target as Node;
            if ((target as Element).closest?.('[data-datepicker-dropdown]')) return;
            if (containerRef.current && !containerRef.current.contains(target)) {
                setIsOpen(false);
            }
        };
        if (isOpen) document.addEventListener('mousedown', handleOutsideClick);
        return () => document.removeEventListener('mousedown', handleOutsideClick);
    }, [isOpen]);

    const getDaysInMonth = (year: number, month: number) => {
        return new Date(year, month + 1, 0).getDate();
    };

    const generateCalendar = () => {
        const year = currentMonth.getFullYear();
        const month = currentMonth.getMonth();
        const daysInMonth = getDaysInMonth(year, month);
        const firstDayOfMonth = new Date(year, month, 1).getDay();

        const days = [];
        for (let i = 0; i < firstDayOfMonth; i++) {
            days.push(null);
        }
        for (let i = 1; i <= daysInMonth; i++) {
            days.push(new Date(year, month, i));
        }
        return days;
    };

    const days = generateCalendar();

    const monthNames = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];
    const dayNames = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

    const handlePrevMonth = (e: React.MouseEvent) => {
        e.stopPropagation();
        setCurrentMonth(new Date(currentMonth.getFullYear(), currentMonth.getMonth() - 1, 1));
    };

    const handleNextMonth = (e: React.MouseEvent) => {
        e.stopPropagation();
        setCurrentMonth(new Date(currentMonth.getFullYear(), currentMonth.getMonth() + 1, 1));
    };

    const handleSelectDate = (date: Date) => {
        const formatted = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
        onChange(formatted);
        setIsOpen(false);
    };

    return (
        <div className={`relative ${className}`} ref={containerRef}>
            {label && <label className="block text-sm font-medium text-slate-700 dark:text-slate-200 mb-1">{label}</label>}

            <div
                ref={triggerRef}
                className="relative cursor-pointer"
                onClick={() => (isOpen ? setIsOpen(false) : openCalendar())}
            >
                <div
                    className={`flex w-full items-center rounded-xl border border-slate-200 bg-white text-slate-800 shadow-sm transition-colors hover:border-emerald-400 dark:border-white/15 dark:bg-white/5 dark:text-slate-100 dark:hover:border-emerald-500/50 touch-manipulation ${touchFriendly ? 'min-h-[52px] px-4 py-4' : 'px-4 py-3'}`}
                >
                    <span className={`flex-1 text-center font-bold ${touchFriendly ? 'text-xl' : 'text-lg'}`}>{value ? formatDateBE(value) : 'เลือกวันที่'}</span>
                    <CalendarIcon className={`shrink-0 text-slate-400 dark:text-slate-500 ml-2 ${touchFriendly ? 'h-6 w-6' : ''}`} />
                </div>
            </div>

            {isOpen && typeof document !== 'undefined' && createPortal(
                <div
                    data-datepicker-dropdown
                    className="fixed p-6 bg-white rounded-2xl shadow-2xl border border-slate-100 z-[9999] w-[360px] animate-fade-in shadow-emerald-500/10"
                    style={{
                        top: dropdownPosition.top,
                        left: dropdownPosition.left,
                        transform: 'translateX(-50%)'
                    }}
                >
                    <div className="flex justify-between items-center mb-6">
                        <button
                            type="button"
                            onClick={handlePrevMonth}
                            className={`rounded-full text-slate-600 transition-colors hover:bg-slate-100 touch-manipulation ${touchFriendly ? 'min-h-11 min-w-11 p-2' : 'p-2'}`}
                        >
                            <ChevronLeft size={24} />
                        </button>
                        <div className="font-bold text-xl text-slate-800">
                            {monthNames[currentMonth.getMonth()]} {currentMonth.getFullYear() + 543}
                        </div>
                        <button
                            type="button"
                            onClick={handleNextMonth}
                            className={`rounded-full text-slate-600 transition-colors hover:bg-slate-100 touch-manipulation ${touchFriendly ? 'min-h-11 min-w-11 p-2' : 'p-2'}`}
                        >
                            <ChevronRight size={24} />
                        </button>
                    </div>

                    <div className="grid grid-cols-7 gap-2 mb-2">
                        {dayNames.map(day => (
                            <div key={day} className="text-center text-sm font-bold text-slate-400 pb-2">
                                {day}
                            </div>
                        ))}
                    </div>

                    <div className={`grid grid-cols-7 ${touchFriendly ? 'gap-2.5' : 'gap-2'}`}>
                        {days.map((date, index) => {
                            const cell = touchFriendly ? 'h-11 w-11' : 'h-10 w-10';
                            if (!date) return <div key={`empty-${index}`} className={cell}></div>;

                            const dateString = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
                            const isSelected = value === dateString;
                            const isToday = new Date().toDateString() === date.toDateString();

                            return (
                                <button
                                    key={index}
                                    type="button"
                                    onClick={() => handleSelectDate(date)}
                                    className={`
                                        ${cell} rounded-full flex items-center justify-center transition-all font-medium touch-manipulation
                                        ${touchFriendly ? 'text-lg' : 'text-base'}
                                        ${isSelected
                                            ? 'bg-emerald-600 text-white shadow-md shadow-emerald-500/30 font-bold scale-110'
                                            : isToday
                                                ? 'bg-slate-100 text-emerald-600 font-bold'
                                                : 'text-slate-700 hover:bg-slate-100 hover:text-slate-900'
                                        }
                                    `}
                                >
                                    {date.getDate()}
                                </button>
                            );
                        })}
                    </div>
                    <div className="mt-6 pt-4 border-t flex justify-center">
                        <button
                            type="button"
                            onClick={() => handleSelectDate(new Date())}
                            className={`font-bold text-emerald-600 hover:text-emerald-700 touch-manipulation ${touchFriendly ? 'min-h-12 rounded-xl px-4 py-3 text-base' : 'text-sm'}`}
                        >
                            วันนี้: {formatDateBE(new Date().toISOString().split('T')[0])}
                        </button>
                    </div>
                </div>,
                document.body
            )}
        </div>
    );
};

export default DatePicker;
