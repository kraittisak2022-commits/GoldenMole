import { useCallback, useRef, useState } from 'react';
import { buildSignatureNoteJson } from '../utils/signatureNote';
import type { AdminUser } from '../types';
import Button from './ui/Button';

type Stroke = [number, number][];

export type WebSignatureDialogProps = {
    admin: AdminUser;
    onConfirm: (note: string) => void;
    onCancel: () => void;
};

const round2 = (n: number) => Math.round(n * 100) / 100;

export const WebSignatureDialog = ({ admin, onConfirm, onCancel }: WebSignatureDialogProps) => {
    const wrapRef = useRef<HTMLDivElement>(null);
    const [strokes, setStrokes] = useState<Stroke[]>([]);
    const drawing = useRef(false);

    const signer =
        admin.displayName?.trim() ||
        (admin as { email?: string }).email?.trim() ||
        'web-user';

    const toLocal = (clientX: number, clientY: number): [number, number] | null => {
        const el = wrapRef.current;
        if (!el) return null;
        const r = el.getBoundingClientRect();
        const x = round2(clientX - r.left);
        const y = round2(clientY - r.top);
        return [x, y];
    };

    const onPointerDown = useCallback((e: React.PointerEvent) => {
        const p = toLocal(e.clientX, e.clientY);
        if (!p) return;
        (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
        drawing.current = true;
        setStrokes(s => [...s, [p]]);
    }, []);

    const onPointerMove = useCallback((e: React.PointerEvent) => {
        if (!drawing.current) return;
        const p = toLocal(e.clientX, e.clientY);
        if (!p) return;
        setStrokes(s => {
            if (s.length === 0) return s;
            const next = [...s];
            const last = [...(next[next.length - 1] || [])];
            last.push(p);
            next[next.length - 1] = last;
            return next;
        });
    }, []);

    const onPointerUp = useCallback(() => {
        drawing.current = false;
    }, []);

    const clear = () => setStrokes([]);

    const confirm = () => {
        const paths: number[][][] = [];
        for (const stroke of strokes) {
            if (stroke.length < 2) continue;
            const sampled: number[][] = [];
            const step = stroke.length > 180 ? Math.ceil(stroke.length / 180) : 1;
            for (let i = 0; i < stroke.length; i += step) {
                sampled.push([stroke[i][0], stroke[i][1]]);
            }
            const last = stroke[stroke.length - 1];
            const prev = sampled[sampled.length - 1];
            if (!prev || prev[0] !== last[0] || prev[1] !== last[1]) {
                sampled.push([last[0], last[1]]);
            }
            if (sampled.length >= 2) paths.push(sampled);
        }
        if (paths.length === 0) return;
        onConfirm(buildSignatureNoteJson({ source: 'web', signedBy: signer, paths }));
    };

    const hasInk = strokes.some(s => s.length > 1);

    return (
        <div className="fixed inset-0 z-[200] flex items-center justify-center bg-black/50 p-4">
            <div className="w-full max-w-lg rounded-2xl border border-slate-200 bg-white p-5 shadow-2xl dark:border-white/10 dark:bg-slate-900">
                <h2 className="text-lg font-bold text-slate-900 dark:text-white">ลงลายเซ็นก่อนบันทึก</h2>
                <p className="mt-1 text-sm text-slate-600 dark:text-slate-400">
                    เซ็นในกรอบด้านล่าง แล้วกดยืนยัน — สอดคล้องกับแอปมือถือ Android
                </p>
                <div
                    ref={wrapRef}
                    className="mt-4 h-52 w-full touch-none rounded-xl border-2 border-dashed border-slate-300 bg-slate-50 dark:border-slate-600 dark:bg-slate-950/50"
                    onPointerDown={onPointerDown}
                    onPointerMove={onPointerMove}
                    onPointerUp={onPointerUp}
                    onPointerLeave={onPointerUp}
                    onPointerCancel={onPointerUp}
                >
                    <svg className="h-full w-full cursor-crosshair">
                        {strokes.map((stroke, si) =>
                            stroke.length < 2 ? null : (
                                <polyline
                                    key={`s-${si}`}
                                    fill="none"
                                    stroke="#0f172a"
                                    strokeWidth="2.5"
                                    strokeLinecap="round"
                                    strokeLinejoin="round"
                                    points={stroke.map(([x, y]) => `${x},${y}`).join(' ')}
                                />
                            ),
                        )}
                    </svg>
                </div>
                <div className="mt-4 flex flex-wrap justify-end gap-2">
                    <Button type="button" variant="ghost" onClick={onCancel}>
                        ยกเลิก
                    </Button>
                    <Button type="button" variant="ghost" onClick={clear}>
                        ล้างลายเซ็น
                    </Button>
                    <Button type="button" onClick={confirm} disabled={!hasInk}>
                        ยืนยันลายเซ็น
                    </Button>
                </div>
            </div>
        </div>
    );
};
