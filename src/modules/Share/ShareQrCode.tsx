import { useEffect, useRef } from 'react';

interface ShareQrCodeProps {
    value: string;
    size?: number;
    className?: string;
}

/** Render QR code to canvas (loads from public QR API, draws on canvas per plan). */
const ShareQrCode = ({ value, size = 180, className = '' }: ShareQrCodeProps) => {
    const canvasRef = useRef<HTMLCanvasElement>(null);

    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas || !value) return;

        const img = new Image();
        img.crossOrigin = 'anonymous';
        img.onload = () => {
            const ctx = canvas.getContext('2d');
            if (!ctx) return;
            canvas.width = size;
            canvas.height = size;
            ctx.fillStyle = '#ffffff';
            ctx.fillRect(0, 0, size, size);
            ctx.drawImage(img, 0, 0, size, size);
        };
        img.onerror = () => {
            const ctx = canvas.getContext('2d');
            if (!ctx) return;
            canvas.width = size;
            canvas.height = size;
            ctx.fillStyle = '#f8fafc';
            ctx.fillRect(0, 0, size, size);
            ctx.fillStyle = '#64748b';
            ctx.font = '12px sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('QR ไม่พร้อม', size / 2, size / 2);
        };
        img.src = `https://api.qrserver.com/v1/create-qr-code/?size=${size}x${size}&data=${encodeURIComponent(value)}`;
    }, [value, size]);

    return (
        <canvas
            ref={canvasRef}
            className={`rounded-xl border border-slate-200 bg-white ${className}`}
            style={{ width: size, height: size }}
            aria-label="QR Code ลิงก์แชร์"
        />
    );
};

export default ShareQrCode;
