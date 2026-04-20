import { useEffect, useMemo, useRef, useState } from 'react';
import { CalendarDays, CalendarRange, CalendarClock, CheckCircle2, Circle, Plus, Pencil, Save, X, ChevronLeft, ChevronRight, Printer, Sparkles } from 'lucide-react';
import { AppSettings } from '../../types';
import * as db from '../../services/dataService';

type PlanScope = 'Monthly' | 'Weekly' | 'Daily';
type PlanStatus = 'Todo' | 'Done';
type PlanLane = 'ท่าทราย' | 'แม่สุข' | 'ทดลองน้ำ';

interface WorkPlanItem {
    id: string;
    title: string;
    note?: string;
    planDate: string;
    scope: PlanScope;
    status: PlanStatus;
    createdAt: string;
    ownerAdminId: string;
    lane: PlanLane;
    carryHistory?: string[];
    workType?: string;
}

interface WorkPlannerProps {
    adminId: string;
    adminName: string;
    settings: AppSettings;
    setSettings: (updater: AppSettings | ((prev: AppSettings) => AppSettings)) => void;
    addLog: (action: string, details: string) => void;
    darkMode?: boolean;
}

interface AiPlanDraft {
    reply?: string;
    title?: string;
    note?: string;
    workType?: string;
    lane?: PlanLane;
    planDate?: string;
}

interface AiChatMessage {
    id: string;
    role: 'user' | 'assistant';
    text: string;
    rawJson?: string;
    createdAt: string;
}

const toInputDate = (d: Date) => {
    const y = d.getFullYear();
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    return `${y}-${m}-${day}`;
};

const formatDateDMY = (value: string): string => {
    const [y, m, d] = value.split('-');
    if (!y || !m || !d) return value;
    return `${d}/${m}/${y}`;
};

const formatDateDMYBE = (value: string): string => {
    const [y, m, d] = value.split('-');
    if (!y || !m || !d) return value;
    const yearBe = Number(y) + 543;
    return `${d}/${m}/${yearBe}`;
};

const parseDateDMYBEToISO = (value: string): string | null => {
    const m = value.trim().match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
    if (!m) return null;
    const day = Number(m[1]);
    const month = Number(m[2]);
    const yearRaw = Number(m[3]);
    const yearCe = yearRaw > 2400 ? yearRaw - 543 : yearRaw;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    const dt = new Date(yearCe, month - 1, day);
    if (dt.getFullYear() !== yearCe || dt.getMonth() !== month - 1 || dt.getDate() !== day) return null;
    return toInputDate(dt);
};

const parseAiDateToIso = (value: string | undefined): string | null => {
    if (!value) return null;
    const normalized = value.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(normalized)) return normalized;
    return parseDateDMYBEToISO(normalized);
};

const addOneDay = (dateStr: string): string => {
    const d = new Date(dateStr);
    d.setDate(d.getDate() + 1);
    return toInputDate(d);
};

const isSameMonth = (a: string, b: string) => a.slice(0, 7) === b.slice(0, 7);

const getWeekRange = (dateStr: string) => {
    const d = new Date(dateStr);
    const day = d.getDay();
    const diffToMonday = (day + 6) % 7;
    const start = new Date(d);
    start.setDate(d.getDate() - diffToMonday);
    const end = new Date(start);
    end.setDate(start.getDate() + 6);
    return { start: toInputDate(start), end: toInputDate(end) };
};

const isInWeek = (planDate: string, selectedDate: string) => {
    const { start, end } = getWeekRange(selectedDate);
    return planDate >= start && planDate <= end;
};

const normalizeWorkTypes = (input: unknown): string[] => {
    if (!Array.isArray(input)) return [];
    return input.filter((x): x is string => typeof x === 'string' && x.trim().length > 0).map(x => x.trim());
};

const normalizePlans = (input: unknown, adminId: string): WorkPlanItem[] => {
    if (!Array.isArray(input)) return [];
    return input
        .filter((item: unknown): item is WorkPlanItem => {
            if (!item || typeof item !== 'object') return false;
            const rec = item as Partial<WorkPlanItem>;
            if (!rec.id || !rec.title || !rec.planDate || !rec.scope || !rec.status || !rec.createdAt) return false;
            if (rec.ownerAdminId && rec.ownerAdminId !== adminId) return false;
            return true;
        })
        .map(item => ({
            ...item,
            ownerAdminId: item.ownerAdminId || adminId,
            lane: item.lane === 'ทำทราย' ? 'ท่าทราย' : (item.lane || 'ท่าทราย'),
            carryHistory: Array.isArray(item.carryHistory) ? item.carryHistory : [],
            workType: item.workType || '',
        }));
};

const WorkPlanner = ({ adminId, adminName, settings, setSettings, addLog, darkMode = false }: WorkPlannerProps) => {
    const defaultWorkTypes = ['ร่อนทราย', 'ล้างทราย', 'ขนส่งทราย', 'ซ่อมบำรุง', 'งานทั่วไป', 'วางแผน'];
    const today = toInputDate(new Date());
    const [selectedDate, setSelectedDate] = useState(today);
    const [scopeFilter, setScopeFilter] = useState<PlanScope>('Daily');
    const [title, setTitle] = useState('');
    const [note, setNote] = useState('');
    const [lane, setLane] = useState<PlanLane>('ท่าทราย');
    const [workType, setWorkType] = useState('ร่อนทราย');
    const [customWorkTypes, setCustomWorkTypes] = useState<string[]>(() => normalizeWorkTypes(settings.appDefaults?.workPlannerByAdmin?.[adminId]?.customWorkTypes));
    const [newWorkTypeLabel, setNewWorkTypeLabel] = useState('');
    const [dateInputText, setDateInputText] = useState(formatDateDMYBE(today));
    const [editingId, setEditingId] = useState<string | null>(null);
    const [editTitle, setEditTitle] = useState('');
    const [editNote, setEditNote] = useState('');
    const [editLane, setEditLane] = useState<PlanLane>('ท่าทราย');
    const [editWorkType, setEditWorkType] = useState('ร่อนทราย');
    const [plans, setPlans] = useState<WorkPlanItem[]>([]);
    const dailyReportRef = useRef<HTMLDivElement | null>(null);
    const [entryMode, setEntryMode] = useState<'normal' | 'ai'>('normal');
    const [aiPrompt, setAiPrompt] = useState('');
    const [aiLoading, setAiLoading] = useState(false);
    const [aiError, setAiError] = useState<string | null>(null);
    const [aiMessages, setAiMessages] = useState<AiChatMessage[]>([]);

    useEffect(() => {
        const planner = settings.appDefaults?.workPlannerByAdmin?.[adminId];
        setCustomWorkTypes(normalizeWorkTypes(planner?.customWorkTypes));
    }, [adminId, settings.appDefaults?.workPlannerByAdmin]);

    useEffect(() => {
        let mounted = true;
        const loadPlans = async () => {
            const rows = await db.fetchWorkPlansByAdmin(adminId);
            if (!mounted) return;
            setPlans(normalizePlans(rows, adminId));
        };
        loadPlans();
        return () => { mounted = false; };
    }, [adminId]);

    useEffect(() => {
        setDateInputText(formatDateDMYBE(selectedDate));
    }, [selectedDate]);

    useEffect(() => {
        const next = plans.map((item) => {
            if (item.scope !== 'Daily' || item.status === 'Done' || item.planDate >= today) return item;
            let from = item.planDate;
            const history = [...(item.carryHistory || [])];
            while (from < today) {
                const to = addOneDay(from);
                history.push(`เลื่อนจาก ${formatDateDMY(from)} ไป ${formatDateDMY(to)}`);
                from = to;
            }
            return { ...item, planDate: from, carryHistory: history };
        });
        const changed = next.some((item, idx) => {
            const prev = plans[idx];
            return prev.planDate !== item.planDate || (prev.carryHistory || []).length !== (item.carryHistory || []).length;
        });
        if (changed) persist(next);
    }, [plans, today]);

    const persist = async (next: WorkPlanItem[], nextCustomTypes: string[] = customWorkTypes) => {
        const nextIds = new Set(next.map(item => item.id));
        const removedIds = plans.filter(item => !nextIds.has(item.id)).map(item => item.id);
        setPlans(next);
        setCustomWorkTypes(nextCustomTypes);
        // Sync plans to dedicated Supabase table
        for (const item of next) {
            await db.saveWorkPlan({
                id: item.id,
                adminId: item.ownerAdminId,
                title: item.title,
                note: item.note,
                planDate: item.planDate,
                scope: item.scope,
                status: item.status,
                lane: item.lane,
                carryHistory: item.carryHistory || [],
                workType: item.workType,
                createdAt: item.createdAt,
            });
        }
        for (const removedId of removedIds) {
            await db.deleteWorkPlan(removedId);
        }
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...prev.appDefaults,
                workPlannerByAdmin: {
                    ...(prev.appDefaults?.workPlannerByAdmin || {}),
                    [adminId]: {
                        // Keep only custom work type config in app_defaults
                        plans: [],
                        customWorkTypes: nextCustomTypes,
                    },
                },
            },
        }));
    };

    const plansForScope = useMemo(() => {
        const sorted = [...plans].sort((a, b) => b.planDate.localeCompare(a.planDate));
        if (scopeFilter === 'Daily') return sorted.filter(p => p.planDate === selectedDate);
        if (scopeFilter === 'Weekly') return sorted.filter(p => isInWeek(p.planDate, selectedDate));
        return sorted.filter(p => isSameMonth(p.planDate, selectedDate));
    }, [plans, scopeFilter, selectedDate]);

    const todayPlans = useMemo(() => plans.filter(p => p.planDate === today), [plans, today]);
    const doneToday = todayPlans.filter(p => p.status === 'Done');
    const pendingToday = todayPlans.filter(p => p.status !== 'Done');
    const dailyPlansByLane = useMemo(() => {
        const onlyDailyDate = plans.filter(p => p.planDate === selectedDate && p.scope === 'Daily');
        return {
            'ท่าทราย': onlyDailyDate.filter(p => p.lane === 'ท่าทราย'),
            'แม่สุข': onlyDailyDate.filter(p => p.lane === 'แม่สุข'),
            'ทดลองน้ำ': onlyDailyDate.filter(p => p.lane === 'ทดลองน้ำ'),
        };
    }, [plans, selectedDate]);

    const addPlan = () => {
        const trimmed = title.trim();
        if (!trimmed) return;
        const item: WorkPlanItem = {
            id: `${Date.now()}_${Math.random().toString(16).slice(2)}`,
            title: trimmed,
            note: note.trim() || undefined,
            planDate: selectedDate,
            scope: scopeFilter,
            status: 'Todo',
            createdAt: new Date().toISOString(),
            ownerAdminId: adminId,
            lane,
            carryHistory: [],
            workType,
        };
        persist([item, ...plans]);
        setTitle('');
        setNote('');
    };

    const toggleDone = (id: string) => {
        const next = plans.map(p => (p.id === id ? { ...p, status: p.status === 'Done' ? 'Todo' : 'Done' } : p));
        persist(next);
    };

    const deletePlan = (id: string) => persist(plans.filter(p => p.id !== id));
    const startEdit = (item: WorkPlanItem) => {
        setEditingId(item.id);
        setEditTitle(item.title);
        setEditNote(item.note || '');
        setEditLane(item.lane);
        setEditWorkType(item.workType || 'ร่อนทราย');
    };
    const cancelEdit = () => {
        setEditingId(null);
        setEditTitle('');
        setEditNote('');
    };
    const saveEdit = () => {
        if (!editingId) return;
        const trimmed = editTitle.trim();
        if (!trimmed) return;
        const next = plans.map(p => p.id === editingId ? {
            ...p,
            title: trimmed,
            note: editNote.trim() || undefined,
            lane: editLane,
            workType: editWorkType,
        } : p);
        persist(next);
        cancelEdit();
    };
    const shiftSelectedDate = (days: number) => {
        const d = new Date(selectedDate);
        d.setDate(d.getDate() + days);
        setSelectedDate(toInputDate(d));
    };
    const recentDates = useMemo(() => {
        const uniq = Array.from(new Set(plans.map(p => p.planDate)));
        return uniq.sort((a, b) => b.localeCompare(a)).slice(0, 8);
    }, [plans]);
    const workTypeOptions = useMemo(() => Array.from(new Set([...defaultWorkTypes, ...customWorkTypes])), [customWorkTypes]);
    const addCustomWorkType = () => {
        const label = newWorkTypeLabel.trim();
        if (!label) return;
        if (workTypeOptions.includes(label)) {
            setWorkType(label);
            setEditWorkType(label);
            setNewWorkTypeLabel('');
            return;
        }
        const next = [...customWorkTypes, label];
        persist(plans, next);
        setWorkType(label);
        setEditWorkType(label);
        setNewWorkTypeLabel('');
    };
    const appendAiUsageLog = (status: 'success' | 'error', prompt: string, message?: string) => {
        const lockedAiModel = 'openai/gpt-5.4-mini';
        const entry = {
            id: `ai_${Date.now()}_${Math.random().toString(16).slice(2)}`,
            adminId,
            adminName,
            prompt: prompt.slice(0, 400),
            model: lockedAiModel,
            status,
            message: message ? message.slice(0, 300) : undefined,
            createdAt: new Date().toISOString(),
        };
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...prev.appDefaults,
                aiUsageLogs: [entry, ...(prev.appDefaults?.aiUsageLogs || [])].slice(0, 200),
            },
        }));
        addLog('ai_planner_usage', `AI Planner ${status} | by=${adminName} | prompt=${entry.prompt}`);
    };
    const applyAiDraft = (draft: AiPlanDraft) => {
        if (draft.title && draft.title.trim()) setTitle(draft.title.trim());
        if (draft.note && draft.note.trim()) setNote(draft.note.trim());
        if (draft.workType && draft.workType.trim()) {
            const nextType = draft.workType.trim();
            if (!workTypeOptions.includes(nextType)) {
                const next = [...customWorkTypes, nextType];
                persist(plans, next);
            }
            setWorkType(nextType);
        }
        if (draft.lane && ['ท่าทราย', 'แม่สุข', 'ทดลองน้ำ'].includes(draft.lane)) {
            setLane(draft.lane);
        }
        const parsedDate = parseAiDateToIso(draft.planDate);
        if (parsedDate) setSelectedDate(parsedDate);
    };
    const autoFillWithAi = async () => {
        const prompt = aiPrompt.trim();
        if (!prompt) return;
        const savedKey = settings.appDefaults?.openRouterApiKey?.trim() || '';
        if (!savedKey) {
            setAiError('ยังไม่พบ OpenRouter API Key ในตั้งค่า');
            return;
        }
        setAiError(null);
        setAiLoading(true);
        try {
            const conversation = aiMessages.slice(-10).map(m => ({
                role: m.role,
                content: m.text,
            }));
            const resp = await fetch('https://openrouter.ai/api/v1/chat/completions', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    Authorization: `Bearer ${savedKey}`,
                },
                body: JSON.stringify({
                    model: 'openai/gpt-5.4-mini',
                    temperature: 0.2,
                    messages: [
                        {
                            role: 'system',
                            content: 'ตอบเป็น JSON เท่านั้นด้วย keys: reply, title, note, workType, lane, planDate. ใช้ reply เพื่อคุยโต้ตอบกับผู้ใช้และถามกลับเมื่อข้อมูลไม่พอ. lane ต้องเป็นหนึ่งใน: ท่าทราย, แม่สุข, ทดลองน้ำ. planDate ใช้รูปแบบ DD/MM/YYYY หรือ DD/MM/BBBB (พ.ศ.) หรือ YYYY-MM-DD',
                        },
                        ...conversation,
                        {
                            role: 'user',
                            content: prompt,
                        },
                    ],
                    response_format: { type: 'json_object' },
                }),
            });
            if (!resp.ok) throw new Error(`OpenRouter error ${resp.status}`);
            const data = await resp.json();
            const raw = data?.choices?.[0]?.message?.content;
            if (!raw) throw new Error('AI ไม่ได้ส่งข้อมูลกลับมา');
            const draft = JSON.parse(raw) as AiPlanDraft;
            applyAiDraft(draft);
            const assistantText = draft.reply?.trim() || 'AI อัปเดตข้อมูลให้แล้ว';
            setAiMessages(prev => [
                ...prev,
                { id: `u_${Date.now()}`, role: 'user', text: prompt, createdAt: new Date().toISOString() },
                { id: `a_${Date.now()}_1`, role: 'assistant', text: assistantText, rawJson: raw, createdAt: new Date().toISOString() },
            ]);
            setAiPrompt('');
            appendAiUsageLog('success', prompt);
        } catch (e) {
            const msg = e instanceof Error ? e.message : 'AI ทำงานไม่สำเร็จ';
            setAiError(msg);
            setAiMessages(prev => [
                ...prev,
                { id: `u_${Date.now()}`, role: 'user', text: prompt, createdAt: new Date().toISOString() },
                { id: `a_${Date.now()}_err`, role: 'assistant', text: `เกิดข้อผิดพลาด: ${msg}`, createdAt: new Date().toISOString() },
            ]);
            appendAiUsageLog('error', prompt, msg);
        } finally {
            setAiLoading(false);
        }
    };
    const printDailyA4 = () => {
        const target = dailyReportRef.current;
        if (!target) return;
        const popup = window.open('', '_blank', 'width=900,height=1200');
        if (!popup) return;
        popup.document.write(`
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>แบบฟอร์มบันทึกงานรายวัน</title>
  <style>
    @page { size: A4 portrait; margin: 12mm; }
    body { font-family: "Sarabun", "Tahoma", Arial, sans-serif; color: #111; margin: 0; }
    .print-root { width: 100%; }
    .print-root .print-hide { display: none !important; }
    .print-root .border { border: 1px solid #9ca3af; }
    .print-root .rounded-xl, .print-root .rounded-2xl { border-radius: 0; }
  </style>
</head>
<body>
  <div class="print-root">${target.innerHTML}</div>
</body>
</html>`);
        popup.document.close();
        popup.focus();
        setTimeout(() => {
            popup.print();
            popup.close();
        }, 200);
    };

    const cardClass = darkMode ? 'border-white/10 bg-slate-900/70' : 'border-slate-200 bg-white';
    const textSub = darkMode ? 'text-slate-400' : 'text-slate-600';

    return (
        <div className="mx-auto w-full max-w-4xl space-y-3 pb-[max(1rem,env(safe-area-inset-bottom,0px))]">
            <section className={`rounded-2xl border p-3.5 sm:p-4 ${cardClass}`}>
                <h3 className="mb-1.5 text-base font-bold sm:text-lg">วางแผนงาน (เดือน/สัปดาห์/วัน)</h3>
                <p className={`text-sm ${textSub}`}>
                    ระบบวางแผนงานเฉพาะสำหรับรายเดือน รายสัปดาห์ และรายวัน
                </p>
                <div className="mt-3 flex flex-wrap items-center gap-2">
                    <span className={`text-sm ${textSub}`}>โหมดการกรอกข้อมูล:</span>
                    <button
                        type="button"
                        onClick={() => setEntryMode('normal')}
                        className={`rounded-full border px-3 py-1 text-xs font-semibold ${entryMode === 'normal' ? 'border-blue-500 bg-blue-500/10 text-blue-700 dark:text-blue-300' : darkMode ? 'border-white/15 bg-slate-800 text-slate-300' : 'border-slate-300 bg-white text-slate-700'}`}
                    >
                        โหมดปกติ
                    </button>
                    <button
                        type="button"
                        onClick={() => setEntryMode('ai')}
                        className={`inline-flex items-center gap-1 rounded-full border px-3 py-1 text-xs font-semibold ${entryMode === 'ai' ? 'border-purple-500 bg-purple-500/10 text-purple-700 dark:text-purple-300' : darkMode ? 'border-white/15 bg-slate-800 text-slate-300' : 'border-slate-300 bg-white text-slate-700'}`}
                    >
                        <Sparkles size={12} />
                        โหมด AI
                    </button>
                </div>
                <div className="mt-3 grid grid-cols-3 gap-2">
                    {[
                        { id: 'Monthly' as const, label: 'รายเดือน', icon: CalendarDays },
                        { id: 'Weekly' as const, label: 'รายสัปดาห์', icon: CalendarRange },
                        { id: 'Daily' as const, label: 'รายวัน', icon: CalendarClock },
                    ].map(row => (
                        <button
                            key={row.id}
                            type="button"
                            onClick={() => setScopeFilter(row.id)}
                            className={`min-h-[46px] touch-manipulation rounded-xl border px-2 py-2 text-xs font-semibold transition-colors sm:text-sm ${
                                scopeFilter === row.id
                                    ? 'border-amber-500 bg-amber-500/10 text-amber-600 dark:text-amber-300'
                                    : darkMode
                                      ? 'border-white/10 hover:bg-white/5'
                                      : 'border-slate-200 hover:bg-slate-50'
                            }`}
                        >
                            <span className="mx-auto inline-flex items-center gap-1.5">
                                <row.icon size={14} />
                                {row.label}
                            </span>
                        </button>
                    ))}
                </div>
            </section>

            {entryMode === 'ai' && (
                <section className={`rounded-2xl border p-3.5 sm:p-4 ${cardClass}`}>
                    <h4 className="font-bold">AI Auto คีย์ข้อมูล</h4>
                    <p className={`mt-1 text-sm ${textSub}`}>พิมพ์บรีฟงาน แล้วให้ AI เติมข้อมูลฟอร์มอัตโนมัติ</p>
                    <label className="mt-2 block text-sm">
                        <span className={`mb-1 block ${textSub}`}>ข้อความคำสั่ง</span>
                        <textarea
                            rows={3}
                            value={aiPrompt}
                            onChange={e => setAiPrompt(e.target.value)}
                            placeholder="เช่น พรุ่งนี้ท่าทราย ทำงานร่อนทราย รายละเอียดตรวจเครื่องก่อนเริ่ม"
                            className={`w-full rounded-lg border px-3 py-2 text-sm ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                        />
                    </label>
                    <div className="mt-2 flex items-center gap-2">
                        <button
                            type="button"
                            onClick={autoFillWithAi}
                            disabled={aiLoading}
                            className="inline-flex min-h-[40px] items-center gap-2 rounded-lg border border-purple-500/40 bg-purple-500/10 px-3 text-sm font-semibold text-purple-700 disabled:opacity-60 dark:text-purple-300"
                        >
                            <Sparkles size={14} />
                            {aiLoading ? 'AI กำลังช่วยกรอก...' : 'ให้ AI กรอกข้อมูล'}
                        </button>
                        {aiError ? <span className="text-xs text-red-500">{aiError}</span> : null}
                    </div>
                    <div className="mt-3 space-y-2">
                        {aiMessages.length === 0 ? (
                            <p className={`text-xs ${textSub}`}>ยังไม่มีบทสนทนา AI</p>
                        ) : (
                            aiMessages.slice(-12).map(m => (
                                <div
                                    key={m.id}
                                    className={`rounded-lg border px-3 py-2 text-sm ${
                                        m.role === 'user'
                                            ? darkMode
                                                ? 'border-blue-500/30 bg-blue-500/10'
                                                : 'border-blue-200 bg-blue-50'
                                            : darkMode
                                              ? 'border-purple-500/30 bg-purple-500/10'
                                              : 'border-purple-200 bg-purple-50'
                                    }`}
                                >
                                    <p className="mb-1 text-xs font-semibold">{m.role === 'user' ? 'คุณ' : 'AI'}</p>
                                    <p>{m.text}</p>
                                    {m.rawJson ? (
                                        <details className="mt-1">
                                            <summary className="cursor-pointer text-xs opacity-80">ดูผลลัพธ์ JSON</summary>
                                            <pre className="mt-1 whitespace-pre-wrap text-[11px]">{m.rawJson}</pre>
                                        </details>
                                    ) : null}
                                </div>
                            ))
                        )}
                    </div>
                </section>
            )}

            <section className={`rounded-2xl border p-3.5 sm:p-4 ${cardClass}`}>
                <div className="mb-3 flex items-center justify-between gap-2">
                    <h4 className="font-bold">เพิ่มแผนงาน</h4>
                    <button
                        type="button"
                        onClick={() => setSelectedDate(today)}
                        className={`min-h-[38px] rounded-lg border px-2.5 text-xs font-semibold touch-manipulation ${
                            darkMode ? 'border-white/15 bg-slate-800/80' : 'border-slate-300 bg-slate-50'
                        }`}
                    >
                        กลับเป็นวันนี้
                    </button>
                </div>
                <div className="grid gap-2.5 sm:grid-cols-2">
                    <label className="text-sm">
                        <span className={`mb-1 block ${textSub}`}>วันที่แผน</span>
                        <input
                            type="text"
                            inputMode="numeric"
                            value={dateInputText}
                            onChange={e => setDateInputText(e.target.value)}
                            onBlur={() => {
                                const parsed = parseDateDMYBEToISO(dateInputText);
                                if (parsed) {
                                    setSelectedDate(parsed);
                                    setDateInputText(formatDateDMYBE(parsed));
                                } else {
                                    setDateInputText(formatDateDMYBE(selectedDate));
                                }
                            }}
                            placeholder="DD/MM/พ.ศ."
                            className={`min-h-[46px] w-full rounded-lg border px-3 py-2.5 text-base ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                        />
                        <span className={`mt-1 block text-xs ${textSub}`}>วันที่ที่เลือก: {formatDateDMYBE(selectedDate)}</span>
                    </label>
                    <label className="text-sm">
                        <span className={`mb-1 block ${textSub}`}>หัวข้องาน</span>
                        <input
                            type="text"
                            value={title}
                            onChange={e => setTitle(e.target.value)}
                            placeholder="เช่น ตรวจรถก่อนออกงาน"
                            className={`min-h-[46px] w-full rounded-lg border px-3 py-2.5 text-base ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                        />
                    </label>
                </div>
                <label className="mt-2 block text-sm">
                    <span className={`mb-1 block ${textSub}`}>โซนงาน</span>
                    <select
                        value={lane}
                        onChange={e => setLane(e.target.value as PlanLane)}
                        className={`min-h-[46px] w-full rounded-lg border px-3 py-2.5 text-base ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                    >
                        <option value="ท่าทราย">ท่าทราย</option>
                        <option value="แม่สุข">แม่สุข</option>
                        <option value="ทดลองน้ำ">ทดลองน้ำ</option>
                    </select>
                </label>
                <label className="mt-2 block text-sm">
                    <span className={`mb-1 block ${textSub}`}>ประเภทงาน</span>
                    <select
                        value={workType}
                        onChange={e => setWorkType(e.target.value)}
                        className={`min-h-[46px] w-full rounded-lg border px-3 py-2.5 text-base ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                    >
                        {workTypeOptions.map(option => (
                            <option key={option} value={option}>{option}</option>
                        ))}
                    </select>
                </label>
                <div className="mt-2 flex gap-2">
                    <input
                        type="text"
                        value={newWorkTypeLabel}
                        onChange={e => setNewWorkTypeLabel(e.target.value)}
                        placeholder="เพิ่มประเภทงานใหม่"
                        className={`min-h-[42px] flex-1 rounded-lg border px-3 py-2 text-sm ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                    />
                    <button
                        type="button"
                        onClick={addCustomWorkType}
                        className="min-h-[42px] rounded-lg border border-blue-500/40 bg-blue-500/10 px-3 text-sm font-semibold text-blue-700 dark:text-blue-300"
                    >
                        เพิ่มตัวเลือก
                    </button>
                </div>
                <label className="mt-3 block text-sm">
                    <span className={`mb-1 block ${textSub}`}>รายละเอียด (ไม่บังคับ)</span>
                    <textarea
                        value={note}
                        onChange={e => setNote(e.target.value)}
                        rows={2}
                        className={`w-full rounded-lg border px-3 py-2.5 text-base ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                        placeholder="รายละเอียดงานเพิ่มเติม"
                    />
                </label>
                <button
                    type="button"
                    onClick={addPlan}
                    className="mt-3 inline-flex min-h-[46px] w-full items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-2 text-sm font-semibold text-white touch-manipulation transition-colors hover:bg-blue-700 sm:w-auto"
                >
                    <Plus size={16} />
                    เพิ่มแผนงาน
                </button>
            </section>

            <section className={`rounded-2xl border p-3.5 sm:p-4 ${cardClass}`}>
                <h4 className="font-bold">สรุปงานวันนี้</h4>
                <p className={`mt-1 text-sm ${textSub}`}>
                    วันนี้ทั้งหมด {todayPlans.length} งาน | เสร็จแล้ว {doneToday.length} | ยังไม่เสร็จ {pendingToday.length}
                </p>
                <div className="mt-3 grid gap-2.5 sm:grid-cols-2">
                    <div className={`rounded-xl border p-3 ${darkMode ? 'border-emerald-500/30 bg-emerald-500/10' : 'border-emerald-200 bg-emerald-50/50'}`}>
                        <p className="mb-2 text-sm font-semibold text-emerald-700 dark:text-emerald-300">งานที่เสร็จแล้ว</p>
                        {doneToday.length === 0 ? (
                            <p className={`text-sm ${textSub}`}>ยังไม่มีงานที่เสร็จในวันนี้</p>
                        ) : (
                            <ul className="space-y-1 text-sm">
                                {doneToday.map(item => (
                                    <li key={item.id} className="flex items-start gap-2">
                                        <CheckCircle2 size={16} className="mt-0.5 shrink-0 text-emerald-500" />
                                        <span>{item.title}</span>
                                    </li>
                                ))}
                            </ul>
                        )}
                    </div>
                    <div className={`rounded-xl border p-3 ${darkMode ? 'border-amber-500/30 bg-amber-500/10' : 'border-amber-200 bg-amber-50/50'}`}>
                        <p className="mb-2 text-sm font-semibold text-amber-700 dark:text-amber-300">งานค้างวันนี้</p>
                        {pendingToday.length === 0 ? (
                            <p className={`text-sm ${textSub}`}>ไม่มีงานค้างสำหรับวันนี้</p>
                        ) : (
                            <ul className="space-y-1 text-sm">
                                {pendingToday.map(item => (
                                    <li key={item.id} className="flex items-start gap-2">
                                        <Circle size={16} className="mt-0.5 shrink-0 text-amber-500" />
                                        <span>{item.title}</span>
                                    </li>
                                ))}
                            </ul>
                        )}
                    </div>
                </div>
            </section>

            <section className={`rounded-2xl border p-3.5 sm:p-4 ${cardClass}`}>
                <div className="flex flex-wrap items-center gap-2">
                    <h4 className="font-bold">ดูข้อมูลย้อนหลัง</h4>
                    <button type="button" onClick={() => shiftSelectedDate(-1)} className={`rounded-lg border px-2 py-1 text-xs ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-slate-50'}`}>
                        <ChevronLeft size={14} />
                    </button>
                    <span className={`text-sm ${textSub}`}>{formatDateDMYBE(selectedDate)}</span>
                    <button type="button" onClick={() => shiftSelectedDate(1)} className={`rounded-lg border px-2 py-1 text-xs ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-slate-50'}`}>
                        <ChevronRight size={14} />
                    </button>
                </div>
                <div className="mt-2 flex flex-wrap gap-2">
                    {recentDates.map(d => (
                        <button
                            key={d}
                            type="button"
                            onClick={() => { setSelectedDate(d); setScopeFilter('Daily'); }}
                            className={`rounded-full border px-3 py-1 text-xs ${selectedDate === d ? 'border-blue-500 bg-blue-500/10 text-blue-600 dark:text-blue-300' : darkMode ? 'border-white/15 bg-slate-800/80' : 'border-slate-300 bg-slate-50'}`}
                        >
                            {formatDateDMYBE(d)}
                        </button>
                    ))}
                </div>
            </section>

            {scopeFilter === 'Daily' && (
                <section className={`rounded-2xl border p-3.5 sm:p-4 ${cardClass}`}>
                    <div className="mb-3 flex items-center justify-between">
                        <h4 className="font-bold">แบบฟอร์มบันทึกงานรายวัน</h4>
                        <div className="flex items-center gap-2">
                            <p className={`text-sm ${textSub}`}>วันที่ {formatDateDMY(selectedDate)}</p>
                            <button
                                type="button"
                                onClick={printDailyA4}
                                className="print-hide inline-flex items-center gap-1 rounded-lg border border-slate-300 bg-white px-2.5 py-1.5 text-xs font-semibold text-slate-700 hover:bg-slate-50 dark:border-white/20 dark:bg-slate-800 dark:text-slate-200"
                            >
                                <Printer size={14} />
                                พิมพ์ A4
                            </button>
                        </div>
                    </div>
                    <div ref={dailyReportRef} className={`overflow-hidden rounded-xl border ${darkMode ? 'border-white/10' : 'border-slate-300'}`}>
                        {[
                            { lane: 'ท่าทราย' as PlanLane, headClass: darkMode ? 'bg-red-500/70' : 'bg-red-400', minH: 'min-h-[220px]' },
                            { lane: 'แม่สุข' as PlanLane, headClass: darkMode ? 'bg-amber-500/70' : 'bg-amber-400', minH: 'min-h-[90px]' },
                            { lane: 'ทดลองน้ำ' as PlanLane, headClass: darkMode ? 'bg-blue-500/70' : 'bg-blue-400', minH: 'min-h-[100px]' },
                        ].map(section => (
                            <div key={section.lane} className={`border-b last:border-b-0 ${darkMode ? 'border-white/10' : 'border-slate-300'}`}>
                                <div className={`grid grid-cols-[110px_1fr] ${section.headClass} text-white`}>
                                    <div className="border-r border-white/40 px-3 py-1.5 text-sm font-semibold">{section.lane}</div>
                                    <div className="px-3 py-1.5 text-sm font-semibold">รายละเอียดงาน</div>
                                </div>
                                <div className={`grid grid-cols-[110px_1fr] ${section.minH}`}>
                                    <div className={`border-r p-2.5 ${darkMode ? 'border-white/10 bg-slate-900/40' : 'border-slate-300 bg-slate-50/70'}`}>
                                        {dailyPlansByLane[section.lane].length === 0 ? (
                                            <p className={`text-sm ${textSub}`}>-</p>
                                        ) : (
                                            <ul className="space-y-1.5 text-sm">
                                                {dailyPlansByLane[section.lane].map((item) => (
                                                    <li key={`left_${item.id}`} className="leading-snug">
                                                        - {item.title || item.workType || '-'}
                                                    </li>
                                                ))}
                                            </ul>
                                        )}
                                    </div>
                                    <div className="p-2.5">
                                        {dailyPlansByLane[section.lane].length === 0 ? (
                                            <p className={`text-sm ${textSub}`}>-</p>
                                        ) : (
                                            <ul className="space-y-1.5">
                                                {dailyPlansByLane[section.lane].map((item) => (
                                                    <li key={`right_${item.id}`} className="flex items-start gap-2 text-sm">
                                                        {item.status === 'Done' ? (
                                                            <CheckCircle2 size={16} className="mt-0.5 shrink-0 text-emerald-500" />
                                                        ) : (
                                                            <Circle size={16} className="mt-0.5 shrink-0 text-slate-400" />
                                                        )}
                                                        <span className="min-w-0 flex-1">
                                                            {editingId === item.id ? (
                                                                <div className="space-y-1.5">
                                                                    <input
                                                                        type="text"
                                                                        value={editTitle}
                                                                        onChange={e => setEditTitle(e.target.value)}
                                                                        className={`w-full rounded border px-2 py-1 text-sm ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                                                                    />
                                                                    <textarea
                                                                        rows={2}
                                                                        value={editNote}
                                                                        onChange={e => setEditNote(e.target.value)}
                                                                        className={`w-full rounded border px-2 py-1 text-sm ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                                                                    />
                                                                    <select
                                                                        value={editLane}
                                                                        onChange={e => setEditLane(e.target.value as PlanLane)}
                                                                        className={`w-full rounded border px-2 py-1 text-sm ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                                                                    >
                                                                        <option value="ท่าทราย">ท่าทราย</option>
                                                                        <option value="แม่สุข">แม่สุข</option>
                                                                        <option value="ทดลองน้ำ">ทดลองน้ำ</option>
                                                                    </select>
                                                                    <select
                                                                        value={editWorkType}
                                                                        onChange={e => setEditWorkType(e.target.value)}
                                                                        className={`w-full rounded border px-2 py-1 text-sm ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                                                                    >
                                                                        {workTypeOptions.map(option => (
                                                                            <option key={option} value={option}>{option}</option>
                                                                        ))}
                                                                    </select>
                                                                    <div className="flex gap-1.5">
                                                                        <button type="button" onClick={saveEdit} className="rounded border border-emerald-400 px-2 py-1 text-xs text-emerald-600"><Save size={12} /></button>
                                                                        <button type="button" onClick={cancelEdit} className="rounded border border-slate-300 px-2 py-1 text-xs"><X size={12} /></button>
                                                                    </div>
                                                                </div>
                                                            ) : (
                                                                <>
                                                                    <span className={`block ${item.status === 'Done' ? 'line-through opacity-70' : ''}`}>
                                                                        - ประเภทงาน: {item.workType || '-'}
                                                                    </span>
                                                                    <span className={`block ${item.status === 'Done' ? 'line-through opacity-70' : ''}`}>
                                                                        - รายละเอียด: {item.note || item.title || '-'}
                                                                    </span>
                                                                    {item.carryHistory && item.carryHistory.length > 0 ? (
                                                                        <span className={`block text-xs ${textSub}`}>
                                                                            ประวัติ: {item.carryHistory[item.carryHistory.length - 1]}
                                                                        </span>
                                                                    ) : null}
                                                                </>
                                                            )}
                                                        </span>
                                                        {editingId !== item.id && (
                                                            <span className="print-hide flex shrink-0 items-center gap-1">
                                                                <button type="button" onClick={() => startEdit(item)} className="rounded border border-amber-300 px-1.5 py-0.5 text-xs text-amber-700 dark:border-amber-500/40 dark:text-amber-300">
                                                                    <Pencil size={12} />
                                                                </button>
                                                                <button type="button" onClick={() => deletePlan(item.id)} className="rounded border border-red-300 px-1.5 py-0.5 text-xs text-red-600 dark:border-red-500/40 dark:text-red-300">
                                                                    ลบ
                                                                </button>
                                                            </span>
                                                        )}
                                                    </li>
                                                ))}
                                            </ul>
                                        )}
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>
                </section>
            )}

            <section className={`rounded-2xl border p-3.5 sm:p-4 ${cardClass}`}>
                <h4 className="mb-2 font-bold">
                    รายการแผนงาน{scopeFilter === 'Daily' ? 'รายวัน' : scopeFilter === 'Weekly' ? 'รายสัปดาห์' : 'รายเดือน'}
                </h4>
                {plansForScope.length === 0 ? (
                    <p className={`text-sm ${textSub}`}>ยังไม่มีแผนงานในช่วงที่เลือก</p>
                ) : (
                    <div className="space-y-2">
                        {plansForScope.map(item => (
                            <div
                                key={item.id}
                                className={`flex flex-wrap items-start gap-2 rounded-xl border p-3 ${darkMode ? 'border-white/10 bg-white/[0.02]' : 'border-slate-200 bg-slate-50/40'}`}
                            >
                                <button
                                    type="button"
                                    onClick={() => toggleDone(item.id)}
                                    className={`mt-0.5 rounded-full p-1 touch-manipulation ${item.status === 'Done' ? 'text-emerald-500' : textSub}`}
                                    aria-label="สลับสถานะงาน"
                                >
                                    {item.status === 'Done' ? <CheckCircle2 size={20} /> : <Circle size={20} />}
                                </button>
                                <div className="min-w-0 flex-1">
                                    {editingId === item.id ? (
                                        <div className="space-y-2">
                                            <input
                                                type="text"
                                                value={editTitle}
                                                onChange={e => setEditTitle(e.target.value)}
                                                className={`w-full rounded border px-2.5 py-1.5 text-sm ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                                            />
                                            <textarea
                                                rows={2}
                                                value={editNote}
                                                onChange={e => setEditNote(e.target.value)}
                                                className={`w-full rounded border px-2.5 py-1.5 text-sm ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                                            />
                                            <select
                                                value={editLane}
                                                onChange={e => setEditLane(e.target.value as PlanLane)}
                                                className={`w-full rounded border px-2.5 py-1.5 text-sm ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                                            >
                                                <option value="ท่าทราย">ท่าทราย</option>
                                                <option value="แม่สุข">แม่สุข</option>
                                                <option value="ทดลองน้ำ">ทดลองน้ำ</option>
                                            </select>
                                            <select
                                                value={editWorkType}
                                                onChange={e => setEditWorkType(e.target.value)}
                                                className={`w-full rounded border px-2.5 py-1.5 text-sm ${darkMode ? 'border-white/15 bg-slate-800' : 'border-slate-300 bg-white'}`}
                                            >
                                                {workTypeOptions.map(option => (
                                                    <option key={option} value={option}>{option}</option>
                                                ))}
                                            </select>
                                            <div className="flex gap-2">
                                                <button type="button" onClick={saveEdit} className="rounded-lg border border-emerald-400 px-2.5 py-1 text-xs font-semibold text-emerald-600">บันทึกแก้ไข</button>
                                                <button type="button" onClick={cancelEdit} className="rounded-lg border border-slate-300 px-2.5 py-1 text-xs font-semibold">ยกเลิก</button>
                                            </div>
                                        </div>
                                    ) : (
                                        <>
                                            <p className={`font-semibold ${item.status === 'Done' ? 'line-through opacity-70' : ''}`}>{item.workType || item.title}</p>
                                            <p className={`text-xs ${textSub}`}>
                                                {formatDateDMY(item.planDate)} · {item.scope === 'Monthly' ? 'รายเดือน' : item.scope === 'Weekly' ? 'รายสัปดาห์' : 'รายวัน'} · {item.lane}
                                            </p>
                                            <p className={`mt-1 text-sm ${textSub}`}>รายละเอียด: {item.note || item.title}</p>
                                            {item.carryHistory && item.carryHistory.length > 0 ? (
                                                <p className={`mt-1 text-xs ${textSub}`}>
                                                    ประวัติการเลื่อน: {item.carryHistory.join(' | ')}
                                                </p>
                                            ) : null}
                                        </>
                                    )}
                                </div>
                                {editingId !== item.id && (
                                    <div className="print-hide flex gap-1.5">
                                        <button
                                            type="button"
                                            onClick={() => startEdit(item)}
                                            className="min-h-[36px] rounded-lg border border-amber-300 px-2.5 py-1 text-xs font-semibold text-amber-700 touch-manipulation transition-colors hover:bg-amber-50 dark:border-amber-500/40 dark:text-amber-300 dark:hover:bg-amber-500/10"
                                        >
                                            แก้ไข
                                        </button>
                                        <button
                                            type="button"
                                            onClick={() => deletePlan(item.id)}
                                            className="min-h-[36px] rounded-lg border border-red-200 px-2.5 py-1 text-xs font-semibold text-red-600 touch-manipulation transition-colors hover:bg-red-50 dark:border-red-500/40 dark:text-red-300 dark:hover:bg-red-500/10"
                                        >
                                            ลบ
                                        </button>
                                    </div>
                                )}
                            </div>
                        ))}
                    </div>
                )}
            </section>
        </div>
    );
};

export default WorkPlanner;
