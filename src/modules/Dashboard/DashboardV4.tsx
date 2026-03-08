import { useState, useEffect, useRef, useMemo } from 'react';
import { Sparkles, TrendingUp, Wallet, Activity, Send, Bot, PieChart, Cpu } from 'lucide-react';
import FormatNumber from '../../components/ui/FormatNumber';
import { Transaction } from '../../types';

// --- Components ---

const GlassCard = ({ children, className = '', glow = false }: { children: React.ReactNode, className?: string, glow?: boolean }) => (
    <div className={`glass-panel rounded-3xl p-6 transition-all duration-500 ${glow ? 'shadow-[0_0_30px_-10px_rgba(168,85,247,0.3)] border-purple-500/30' : 'hover:border-slate-700/50'} ${className}`}>
        {children}
    </div>
);

const NeuralCore = ({ isActive }: { isActive: boolean }) => {
    // Generate static nodes for consistency
    const nodes = useMemo(() => Array.from({ length: 12 }).map((_, i) => ({
        id: i,
        x: 100 + Math.cos(i * 0.5) * 60 + Math.random() * 20,
        y: 100 + Math.sin(i * 0.5) * 60 + Math.random() * 20,
        r: Math.random() * 2 + 2
    })), []);

    // Generate connections
    const links = useMemo(() => {
        const lines = [];
        for (let i = 0; i < nodes.length; i++) {
            for (let j = i + 1; j < nodes.length; j++) {
                if (Math.random() > 0.6) { // 40% chance of connection
                    lines.push({ source: nodes[i], target: nodes[j] });
                }
            }
        }
        return lines;
    }, [nodes]);

    return (
        <div className="relative w-40 h-40 sm:w-52 sm:h-52 lg:w-64 lg:h-64 flex items-center justify-center">
            {/* Background Glow */}
            <div className={`absolute inset-0 bg-indigo-500/10 rounded-full blur-3xl transition-all duration-1000 ${isActive ? 'scale-125 opacity-80' : 'scale-100 opacity-40'}`}></div>

            <svg viewBox="0 0 200 200" className={`w-full h-full drop-shadow-[0_0_10px_rgba(99,102,241,0.5)] transition-all duration-700 ${isActive ? 'animate-spin-slow' : ''}`} style={{ animationDuration: '20s' }}>
                <defs>
                    <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" stopColor="#818cf8" stopOpacity="0.8" />
                        <stop offset="100%" stopColor="#c084fc" stopOpacity="0.8" />
                    </linearGradient>
                </defs>

                {/* Connecting Lines */}
                {links.map((link, i) => (
                    <line
                        key={i}
                        x1={link.source.x} y1={link.source.y}
                        x2={link.target.x} y2={link.target.y}
                        stroke="url(#grad)"
                        strokeWidth="0.5"
                        className={`transition-all duration-300 ${isActive ? 'animate-dash opacity-80' : 'opacity-20'}`}
                        style={{ animationDuration: `${Math.random() * 2 + 1}s` }}
                    />
                ))}

                {/* Nodes */}
                {nodes.map((node, i) => (
                    <circle
                        key={i}
                        cx={node.x} cy={node.y} r={node.r}
                        fill="#fff"
                        className={`transition-all duration-500 ${isActive ? 'animate-pulse' : ''}`}
                        style={{ animationDelay: `${i * 0.1}s` }}
                    />
                ))}

                {/* Central Core */}
                <circle cx="100" cy="100" r="15" fill="none" stroke="#6366f1" strokeWidth="1" className={`animate-ping ${isActive ? 'opacity-100' : 'opacity-0'}`} style={{ animationDuration: '3s' }} />
                <circle cx="100" cy="100" r="8" fill="#4f46e5" className="animate-pulse-slow" />
            </svg>

            {/* Overlay Icon */}
            <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
                <div className={`bg-slate-900/80 p-3 rounded-full border border-indigo-500/50 backdrop-blur-sm transition-all duration-300 ${isActive ? 'scale-110 shadow-[0_0_20px_rgba(99,102,241,0.6)]' : ''}`}>
                    <Cpu size={24} className="text-white" />
                </div>
            </div>
        </div>
    );
};

const AnimatedStats = ({ value }: { value: number }) => {
    const [display, setDisplay] = useState(0);
    useEffect(() => {
        let start = display;
        const end = value;
        if (start === end) return;
        const duration = 1500;
        const startTime = performance.now();

        const animate = (currentTime: number) => {
            const elapsed = currentTime - startTime;
            const progress = Math.min(elapsed / duration, 1);
            const ease = 1 - Math.pow(1 - progress, 3);
            setDisplay(start + (end - start) * ease);
            if (progress < 1) requestAnimationFrame(animate);
        };
        requestAnimationFrame(animate);
    }, [value]);
    return <FormatNumber value={display} />;
};

// --- Chat Logic ---

interface ChatMessage {
    id: string;
    role: 'user' | 'assistant';
    text: string;
    timestamp: Date;
}

const processAIQuery = (query: string, transactions: Transaction[]): string => {
    const q = query.toLowerCase().trim();
    const today = new Date();
    const todayStr = today.toISOString().split('T')[0];
    const currentMonth = today.getMonth();
    const currentYear = today.getFullYear();
    const currentDateTh = today.toLocaleDateString('th-TH', { year: 'numeric', month: 'long', day: 'numeric' });

    // Filter Helpers
    const getMonthTrans = () => transactions.filter(t => {
        const d = new Date(t.date);
        return d.getMonth() === currentMonth && d.getFullYear() === currentYear;
    });

    const getTodayTrans = () => transactions.filter(t => t.date === todayStr);

    const sumAmount = (trans: Transaction[]) => trans.reduce((s, t) => s + t.amount, 0);

    // --- Time Analysis ---
    if (q.includes('วันนี้เดือนอะไร') || q.includes('วันที่เท่าไหร่')) {
        return `วันนี้คือวันที่ ${currentDateTh} ครับ`;
    }

    // --- Complex Queries ---

    // 1. Profit / Overview
    if (q.includes('กำไร') || q.includes('สถานะการเงิน') || q.includes('profit')) {
        const income = sumAmount(transactions.filter(t => t.type === 'Income'));
        const expense = sumAmount(transactions.filter(t => t.type === 'Expense'));
        const prof = income - expense;
        const monthIncome = sumAmount(getMonthTrans().filter(t => t.type === 'Income'));
        const monthExpense = sumAmount(getMonthTrans().filter(t => t.type === 'Expense'));
        return `กำไรสุทธิรวมทั้งหมดอยู่ที่ ${prof.toLocaleString()} บาทครับ (รับรวม: ${income.toLocaleString()} - จ่ายรวม: ${expense.toLocaleString()}) สำหรับเดือนนี้มีรายได้ ${monthIncome.toLocaleString()} บาท และรายจ่าย ${monthExpense.toLocaleString()} บาทครับ`;
    }

    // 2. Today's Summary
    if (q.includes('วันนี้เรา') || q.includes('ยอดวันนี้') || (q.includes('วันนี้') && (q.includes('สรุป') || q.includes('ทั้งหมด')))) {
        const todayTrans = getTodayTrans();
        if (todayTrans.length === 0) return 'วันนี้ยังไม่มีการบันทึกข้อมูลใดๆ เข้าระบบเลยครับ';

        const inToday = sumAmount(todayTrans.filter(t => t.type === 'Income'));
        const exToday = sumAmount(todayTrans.filter(t => t.type === 'Expense'));
        const sand = todayTrans.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand').reduce((s, t) => s + (t.sandMorning || 0) + (t.sandAfternoon || 0), 0);
        return `📅 สรุปข้อมูลวันนี้ (${todayStr}): มีรายรับ ${inToday.toLocaleString()} บาท, รายจ่าย ${exToday.toLocaleString()} บาท, และล้างทรายได้ ${sand} คิวครับ`;
    }

    // 3. Specific Categories (Fuel)
    if (q.includes('น้ำมัน') || q.includes('fuel')) {
        const fuelTrans = transactions.filter(t => t.category === 'Fuel');
        const fuelTotal = sumAmount(fuelTrans);
        const fuelLiters = fuelTrans.reduce((s, t) => s + (t.quantity || 0), 0);

        if (q.includes('วันนี้')) {
            const todayFuel = fuelTrans.filter(t => t.date === todayStr);
            const todayLiters = todayFuel.reduce((s, t) => s + (t.quantity || 0), 0);
            return `วันนี้เราเติมน้ํามันไปทั้งหมด ${todayLiters.toLocaleString()} ลิตร เป็นเงิน ${sumAmount(todayFuel).toLocaleString()} บาทครับ`;
        }
        return `ยอดใช้จ่ายน้ำมันรวมทั้งหมดตั้งแต่เริ่มโครงการคือ ${fuelTotal.toLocaleString()} บาทครับ ใช้น้ำมันไปแล้ว ${fuelLiters.toLocaleString()} ลิตร`;
    }

    // 4. Sand Production
    if (q.includes('ทราย') || q.includes('ล้างทราย')) {
        const dLogs = transactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand');
        const totalQ = dLogs.reduce((s, t) => s + (t.sandMorning || 0) + (t.sandAfternoon || 0), 0);
        if (q.includes('วันนี้')) {
            const todayQ = dLogs.filter(t => t.date === todayStr).reduce((s, t) => s + (t.sandMorning || 0) + (t.sandAfternoon || 0), 0);
            return `วันนี้เราล้างทรายได้ทั้งหมด ${todayQ} คิวครับ 🌊`;
        }
        return `ปริมาณทรายที่ล้างได้ทั้งหมดตามที่บันทึกไว้ในระบบคือ ${totalQ} คิวครับ`;
    }

    // 5. Labor / Workers
    if (q.includes('คนงาน') || q.includes('แรงงาน') || q.includes('พนักงาน')) {
        const labor = sumAmount(transactions.filter(t => t.category === 'Labor'));
        if (q.includes('วันนี้')) {
            const todayWorkers = getTodayTrans().filter(t => t.category === 'Labor' && t.laborStatus === 'Work').reduce((acc, t) => acc + (t.employeeIds?.length || 0), 0);
            return `วันนี้มีคนงานมาทำงานทั้งหมด ${todayWorkers} คนครับ`;
        }
        return `เราจ่ายค่าแรงไปแล้วรวมทั้งสิ้น ${labor.toLocaleString()} บาทครับ`;
    }

    // 6. Vehicles
    if (q.includes('รถ') || q.includes('เครื่องจักร')) {
        const veh = transactions.filter(t => t.category === 'Vehicle');
        if (q.includes('วันนี้มา')) {
            const tVeh = getTodayTrans().filter(t => t.category === 'Vehicle');
            if (tVeh.length === 0) return 'ไม่ได้บันทึกข้อมูลรถเข้าทำงานในวันนี้ครับ';
            const vNames = tVeh.map(t => t.vehicleId).join(', ');
            return `วันนี้มีรถเข้าทำงาน ${tVeh.length} คัน ได้แก่: ${vNames} ครับ`;
        }
        return `มีการบันทึกการทำงานของรถ/เครื่องจักรในระบบทั้งหมด ${veh.length} รายการ`;
    }

    // 7. Salary / Payroll
    if (q.includes('เงินเดือน') || q.includes('ค่าจ้าง')) {
        const pRoll = sumAmount(transactions.filter(t => t.category === 'Payroll'));
        return `ยอดรวมการจ่ายเงินเดือนพนักงานในระบบที่ตัดยอดแล้วคือ ${pRoll.toLocaleString()} บาทครับ`;
    }

    // 8. General Greetings & Help
    if (q.includes('สวัสดี') || q.includes('hi') || q.includes('ทำอะไรได้บ้าง')) {
        return `สวัสดีครับ! 🤖 ผมคือ AI Manager ประจำโครงการครับ\nผมสามารถอ่านข้อมูลทุกอย่างในระบบและสรุปให้คุณได้ทันที เช่น:\n- "ยอดสรุปวันนี้"\n- "เราล้างทรายได้กี่คิวแล้ว"\n- "วันนี้ใช้น้ำมันไปเท่าไหร่"\n- "กำไรเดือนนี้เท่าไหร่"\nลองถามผมมาได้เลยครับ!`;
    }

    return 'ผมกำลังรวบรวมข้อมูลส่วนนี้อยู่ อาจจะยังไม่มีในฐานข้อมูลที่ผมเข้าถึงได้ ลองถามเกี่ยวกับ "สรุปยอดวันนี้", "กำไรทั้งหมด", "ทรายที่ล้างได้", "รถที่มาทำงาน" หรือ "ยอดน้ำมัน" ดูก่อนนะครับ';
};

// --- Main Dashboard ---

const DashboardV4 = ({ transactions }: { transactions: Transaction[] }) => {
    const [messages, setMessages] = useState<ChatMessage[]>([
        { id: '1', role: 'assistant', text: 'สวัสดีครับ ผมพร้อมให้ข้อมูลสรุปสถานะโครงการแล้วครับ ถามข้อมูลการเงินได้เลย!', timestamp: new Date() }
    ]);
    const [input, setInput] = useState('');
    const [isTyping, setIsTyping] = useState(false);
    const scrollRef = useRef<HTMLDivElement>(null);

    // Auto-scroll chat
    useEffect(() => {
        if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }, [messages, isTyping]);

    const handleSend = () => {
        if (!input.trim()) return;

        const userMsg: ChatMessage = { id: Date.now().toString(), role: 'user', text: input, timestamp: new Date() };
        setMessages(prev => [...prev, userMsg]);
        setInput('');
        setIsTyping(true);

        // Simulate AI Delay
        setTimeout(() => {
            const replyText = processAIQuery(userMsg.text, transactions);
            const aiMsg: ChatMessage = { id: (Date.now() + 1).toString(), role: 'assistant', text: replyText, timestamp: new Date() };
            setMessages(prev => [...prev, aiMsg]);
            setIsTyping(false);
        }, 1500); // Slightly longer for brain animation
    };

    // Stats
    const totalIncome = transactions.filter(t => t.type === 'Income').reduce((s, t) => s + t.amount, 0);
    const totalExpense = transactions.filter(t => t.type === 'Expense').reduce((s, t) => s + t.amount, 0);
    const netProfit = totalIncome - totalExpense;

    return (
        <div className="min-h-screen bg-slate-950 text-slate-200 font-sans selection:bg-indigo-500/30 overflow-hidden relative p-3 sm:p-5 lg:p-8">
            <div className="bg-mesh absolute inset-0 opacity-40 pointer-events-none"></div>

            {/* Header */}
            <div className="relative z-10 flex flex-col sm:flex-row justify-between items-start gap-4 mb-6 sm:mb-8 animate-slide-up">
                <div>
                    <h1 className="text-xl sm:text-2xl lg:text-3xl font-light tracking-tight text-white mb-2">
                        สวัสดี, <span className="font-medium text-transparent bg-clip-text bg-gradient-to-r from-indigo-400 to-purple-400">ผู้ดูแลระบบ</span>
                    </h1>
                    <p className="text-slate-400 text-sm flex items-center gap-2">
                        <Sparkles size={14} className="text-indigo-400" /> ระบบ AI พร้อมทำงาน (Gemini Integration Ready)
                    </p>
                </div>
            </div>

            <div className="relative z-10 grid grid-cols-1 lg:grid-cols-12 gap-4 sm:gap-6 lg:gap-8 lg:h-[calc(100vh-180px)]">

                {/* Left: Stats & Core (7 cols) */}
                <div className="lg:col-span-7 flex flex-col gap-6">
                    {/* Main Stats Row */}
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <GlassCard className="animate-float" glow>
                            <div className="flex items-center gap-3 mb-4 text-slate-400">
                                <div className="p-2 bg-indigo-500/10 rounded-xl"><Wallet size={18} className="text-indigo-400" /></div>
                                <span className="text-sm font-medium">กำไรสุทธิ (Net Profit)</span>
                            </div>
                            <div className="text-2xl sm:text-3xl lg:text-4xl font-medium text-white mb-2">
                                ฿<AnimatedStats value={netProfit} />
                            </div>
                            <div className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 text-xs font-medium border border-emerald-500/20">
                                <TrendingUp size={12} /> สถานะการเงินแข็งแกร่ง
                            </div>
                        </GlassCard>

                        <div className="space-y-4">
                            <GlassCard className="flex-1 py-4">
                                <p className="text-xs font-medium text-slate-500 uppercase tracking-wider mb-2">รายรับรวม (Income)</p>
                                <p className="text-2xl font-medium text-white mb-1">฿<AnimatedStats value={totalIncome} /></p>
                                <div className="h-1 w-full bg-slate-800 rounded-full overflow-hidden mt-2">
                                    <div className="h-full bg-indigo-500 rounded-full" style={{ width: '70%' }}></div>
                                </div>
                            </GlassCard>
                            <GlassCard className="flex-1 py-4">
                                <p className="text-xs font-medium text-slate-500 uppercase tracking-wider mb-2">รายจ่ายรวม (Expense)</p>
                                <p className="text-2xl font-medium text-white mb-1">฿<AnimatedStats value={totalExpense} /></p>
                                <div className="h-1 w-full bg-slate-800 rounded-full overflow-hidden mt-2">
                                    <div className="h-full bg-purple-500 rounded-full" style={{ width: '45%' }}></div>
                                </div>
                            </GlassCard>
                        </div>
                    </div>

                    {/* AI Visualization */}
                    <GlassCard className="flex-1 flex flex-col items-center justify-center relative overflow-hidden transition-colors duration-500" glow={isTyping}>
                        <div className="absolute top-4 left-4 text-xs font-medium text-slate-500 flex items-center gap-2">
                            <Activity size={14} className={isTyping ? "text-indigo-400 animate-spin" : "text-indigo-400"} />
                            {isTyping ? "PROCESSING DATA..." : "SYSTEM IDLE"}
                        </div>

                        <NeuralCore isActive={isTyping} />

                        <div className="mt-4 text-center">
                            <h3 className={`text-lg font-medium transition-colors ${isTyping ? 'text-indigo-300' : 'text-white opacity-90'}`}>
                                {isTyping ? 'AI is converting data to knowledge...' : 'Neural Network Standby'}
                            </h3>
                            <p className="text-sm text-slate-400 mt-1">
                                {isTyping ? 'Analyzing 42 data points...' : 'Ready for query'}
                            </p>
                        </div>
                    </GlassCard>
                </div>

                {/* Right: AI Chat Interface (5 cols) */}
                <div className="lg:col-span-5 flex flex-col">
                    <GlassCard className="flex-1 flex flex-col p-0 overflow-hidden border-indigo-500/30" glow>
                        {/* Chat Header */}
                        <div className="p-4 border-b border-white/5 bg-white/5 backdrop-blur-md flex justify-between items-center">
                            <div className="flex items-center gap-3">
                                <div className="w-8 h-8 rounded-full bg-indigo-500 flex items-center justify-center text-white"><Bot size={18} /></div>
                                <div>
                                    <h3 className="font-medium text-white text-sm">Gemini Assistant</h3>
                                    <div className="flex items-center gap-1.5 text-[10px] text-emerald-400">
                                        <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span> Online
                                    </div>
                                </div>
                            </div>
                            <button className="p-2 hover:bg-white/10 rounded-full text-slate-400 transition-colors"><PieChart size={18} /></button>
                        </div>

                        {/* Messages Area */}
                        <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-4 scrollbar-thin scrollbar-thumb-slate-700 scrollbar-track-transparent">
                            {messages.map((msg) => (
                                <div key={msg.id} className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                                    <div className={`max-w-[85%] rounded-2xl px-4 py-3 text-sm leading-relaxed ${msg.role === 'user'
                                        ? 'bg-indigo-600 text-white rounded-br-none shadow-lg shadow-indigo-500/20'
                                        : 'bg-slate-800 text-slate-200 rounded-bl-none border border-slate-700'}`}>
                                        {msg.text}
                                    </div>
                                </div>
                            ))}
                            {isTyping && (
                                <div className="flex justify-start">
                                    <div className="bg-slate-800 rounded-2xl rounded-bl-none px-4 py-3 border border-slate-700 flex gap-1">
                                        <span className="w-1.5 h-1.5 bg-slate-500 rounded-full animate-bounce"></span>
                                        <span className="w-1.5 h-1.5 bg-slate-500 rounded-full animate-bounce" style={{ animationDelay: '0.1s' }}></span>
                                        <span className="w-1.5 h-1.5 bg-slate-500 rounded-full animate-bounce" style={{ animationDelay: '0.2s' }}></span>
                                    </div>
                                </div>
                            )}
                        </div>

                        {/* Input Area */}
                        <div className="p-4 border-t border-white/5 bg-white/5">
                            <div className="flex gap-2">
                                <input
                                    type="text"
                                    value={input}
                                    onChange={(e) => setInput(e.target.value)}
                                    onKeyDown={(e) => e.key === 'Enter' && handleSend()}
                                    placeholder="ถามข้อมูลการเงินได้เลยครับ..."
                                    className="flex-1 bg-slate-900/50 border border-slate-700 rounded-xl px-4 py-2.5 text-sm text-white focus:outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500/50 transition-all placeholder:text-slate-500"
                                />
                                <button
                                    onClick={handleSend}
                                    className="p-2.5 bg-indigo-600 hover:bg-indigo-500 text-white rounded-xl transition-all shadow-lg hover:shadow-indigo-500/25 active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
                                    disabled={!input.trim()}
                                >
                                    <Send size={18} />
                                </button>
                            </div>
                        </div>
                    </GlassCard>
                </div>
            </div>
        </div>
    );
};

export default DashboardV4;
