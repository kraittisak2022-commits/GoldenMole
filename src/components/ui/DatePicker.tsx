import React, { useState, useRef, useEffect, useLayoutEffect } from 'react';
import { createPortal } from 'react-dom';
import { Calendar as CalendarIcon, ChevronLeft, ChevronRight } from 'lucide-react';
import { formatDateBE } from '../../utils';

interface DatePickerProps {
    label?: string;
    value: string; // YYYY-MM-DD
    onChange: (date: string) => void;
    className?: string;
}

const DatePicker: React.FC<DatePickerProps> = ({ label, value, onChange, className = '' }) => {
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
            {label && <label className="block text-sm font-medium text-slate-700 mb-1">{label}</label>}

            <div
                ref={triggerRef}
                className="relative cursor-pointer"
                onClick={() => (isOpen ? setIsOpen(false) : openCalendar())}
            >
                <div className="flex items-center w-full px-4 py-3 rounded-xl border border-slate-200 bg-white text-slate-800 hover:border-emerald-400 transition-colors shadow-sm">
                    <span className="flex-1 text-center font-bold text-lg">{value ? formatDateBE(value) : 'เลือกวันที่'}</span>
                    <CalendarIcon className="text-slate-400 shrink-0 ml-2" />
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
                            className="p-2 hover:bg-slate-100 rounded-full text-slate-600 transition-colors"
                        >
                            <ChevronLeft size={24} />
                        </button>
                        <div className="font-bold text-xl text-slate-800">
                            {monthNames[currentMonth.getMonth()]} {currentMonth.getFullYear() + 543}
                        </div>
                        <button
                            type="button"
                            onClick={handleNextMonth}
                            className="p-2 hover:bg-slate-100 rounded-full text-slate-600 transition-colors"
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

                    <div className="grid grid-cols-7 gap-2">
                        {days.map((date, index) => {
                            if (!date) return <div key={`empty-${index}`} className="h-10 w-10"></div>;

                            const dateString = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
                            const isSelected = value === dateString;
                            const isToday = new Date().toDateString() === date.toDateString();

                            return (
                                <button
                                    key={index}
                                    type="button"
                                    onClick={() => handleSelectDate(date)}
                                    className={`
                                        h-10 w-10 rounded-full flex items-center justify-center text-base transition-all font-medium
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
                            className="text-sm font-bold text-emerald-600 hover:text-emerald-700"
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
