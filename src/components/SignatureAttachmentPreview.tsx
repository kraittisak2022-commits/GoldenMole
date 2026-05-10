import type { EmbeddedSignatureMeta } from '../utils/signatureNote';
import { hasSignaturePaths } from '../utils/signatureNote';

type Props = { meta: EmbeddedSignatureMeta };

export const SignatureAttachmentPreview = ({ meta }: Props) => {
    if (!hasSignaturePaths(meta)) return null;
    const paths = (meta.paths || []).filter(path => Array.isArray(path) && path.length >= 2);
    let maxX = 1;
    let maxY = 1;
    paths.forEach(path => {
        path.forEach((point) => {
            const x = Number(point?.[0] || 0);
            const y = Number(point?.[1] || 0);
            if (x > maxX) maxX = x;
            if (y > maxY) maxY = y;
        });
    });
    return (
        <div className="mt-1 rounded-md border border-cyan-200 bg-white px-1.5 py-1 dark:border-cyan-500/30 dark:bg-slate-900/30">
            <div className="mb-1 text-[10px] font-semibold text-cyan-700 dark:text-cyan-200">ลายเซ็นแนบ</div>
            <svg
                viewBox={`0 0 ${Math.max(10, maxX + 4)} ${Math.max(10, maxY + 4)}`}
                className="h-14 w-full rounded border border-slate-200 bg-slate-50 dark:border-white/10 dark:bg-slate-950/40"
            >
                {paths.map((path, idx) => {
                    const points = path.map(point => `${Number(point?.[0] || 0)},${Number(point?.[1] || 0)}`).join(' ');
                    return (
                        <polyline
                            key={`sig-path-${idx}`}
                            points={points}
                            fill="none"
                            stroke="#0f172a"
                            strokeWidth="2.4"
                            strokeLinecap="round"
                            strokeLinejoin="round"
                        />
                    );
                })}
            </svg>
        </div>
    );
};
