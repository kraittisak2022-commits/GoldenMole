import { useState, useEffect, useRef, useCallback } from 'react';
import { Lock, User, Eye, EyeOff, Shield, Loader2, Sun, Moon } from 'lucide-react';
import { AdminUser } from '../../types';
import { verifyStoredPassword } from '../../utils/passwordAuth';

interface LoginPageProps {
    admins: AdminUser[];
    onLogin: (admin: AdminUser, plainPassword: string) => void | Promise<void>;
    appName: string;
    appIcon: string;
    appVersion: string;
    appLastUpdated?: string;
    latestVersionNote?: string;
    darkMode: boolean;
    onToggleDarkMode: () => void;
}

// ─── Network Background Canvas ─────────────────────────────────────────
interface Particle {
    x: number; y: number; vx: number; vy: number;
    radius: number; opacity: number; pulseSpeed: number; pulseOffset: number;
}

const NetworkBackground = ({ darkMode }: { darkMode: boolean }) => {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const animationRef = useRef<number>(0);
    const particlesRef = useRef<Particle[]>([]);
    const mouseRef = useRef({ x: -1000, y: -1000 });

    const initParticles = useCallback((w: number, h: number) => {
        const count = Math.floor((w * h) / 12000);
        const particles: Particle[] = [];
        for (let i = 0; i < count; i++) {
            particles.push({
                x: Math.random() * w, y: Math.random() * h,
                vx: (Math.random() - 0.5) * 0.6, vy: (Math.random() - 0.5) * 0.6,
                radius: Math.random() * 2 + 1,
                opacity: Math.random() * 0.5 + 0.2,
                pulseSpeed: Math.random() * 0.02 + 0.01,
                pulseOffset: Math.random() * Math.PI * 2
            });
        }
        particlesRef.current = particles;
    }, []);

    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return;
        const ctx = canvas.getContext('2d');
        if (!ctx) return;

        const resize = () => {
            canvas.width = window.innerWidth;
            canvas.height = window.innerHeight;
            initParticles(canvas.width, canvas.height);
        };
        resize();
        window.addEventListener('resize', resize);

        const handleMouse = (e: MouseEvent) => {
            mouseRef.current = { x: e.clientX, y: e.clientY };
        };
        window.addEventListener('mousemove', handleMouse);

        let time = 0;
        const animate = () => {
            time += 1;
            const w = canvas.width, h = canvas.height;
            ctx.clearRect(0, 0, w, h);

            const particles = particlesRef.current;
            const mouse = mouseRef.current;
            const connectionDist = 150;
            const mouseDist = 200;

            const primary = darkMode ? [0, 200, 255] : [197, 165, 90];
            const secondary = darkMode ? [120, 80, 255] : [139, 122, 62];

            // Update & draw particles
            for (let i = 0; i < particles.length; i++) {
                const p = particles[i];
                p.x += p.vx; p.y += p.vy;

                // Bounce off edges
                if (p.x < 0 || p.x > w) p.vx *= -1;
                if (p.y < 0 || p.y > h) p.vy *= -1;
                p.x = Math.max(0, Math.min(w, p.x));
                p.y = Math.max(0, Math.min(h, p.y));

                // Mouse attraction
                const mdx = mouse.x - p.x, mdy = mouse.y - p.y;
                const md = Math.sqrt(mdx * mdx + mdy * mdy);
                if (md < mouseDist && md > 0) {
                    p.vx += (mdx / md) * 0.03;
                    p.vy += (mdy / md) * 0.03;
                }

                // Damping
                p.vx *= 0.99; p.vy *= 0.99;

                // Pulse glow
                const pulse = Math.sin(time * p.pulseSpeed + p.pulseOffset) * 0.3 + 0.7;
                const alpha = p.opacity * pulse;

                // Draw particle
                const grad = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.radius * 3);
                grad.addColorStop(0, `rgba(${primary[0]},${primary[1]},${primary[2]},${alpha})`);
                grad.addColorStop(0.5, `rgba(${primary[0]},${primary[1]},${primary[2]},${alpha * 0.3})`);
                grad.addColorStop(1, 'transparent');
                ctx.beginPath();
                ctx.arc(p.x, p.y, p.radius * 3, 0, Math.PI * 2);
                ctx.fillStyle = grad;
                ctx.fill();

                // Core dot
                ctx.beginPath();
                ctx.arc(p.x, p.y, p.radius * 0.8, 0, Math.PI * 2);
                ctx.fillStyle = `rgba(${primary[0]},${primary[1]},${primary[2]},${alpha * 1.2})`;
                ctx.fill();

                // Connections
                for (let j = i + 1; j < particles.length; j++) {
                    const p2 = particles[j];
                    const dx = p.x - p2.x, dy = p.y - p2.y;
                    const dist = Math.sqrt(dx * dx + dy * dy);
                    if (dist < connectionDist) {
                        const lineAlpha = (1 - dist / connectionDist) * 0.25;
                        ctx.beginPath();
                        ctx.moveTo(p.x, p.y);
                        ctx.lineTo(p2.x, p2.y);
                        ctx.strokeStyle = `rgba(${secondary[0]},${secondary[1]},${secondary[2]},${lineAlpha})`;
                        ctx.lineWidth = 0.8;
                        ctx.stroke();
                    }
                }

                // Mouse connections
                if (md < mouseDist) {
                    const lineAlpha = (1 - md / mouseDist) * 0.5;
                    ctx.beginPath();
                    ctx.moveTo(p.x, p.y);
                    ctx.lineTo(mouse.x, mouse.y);
                    ctx.strokeStyle = `rgba(${primary[0]},${primary[1]},${primary[2]},${lineAlpha})`;
                    ctx.lineWidth = 1;
                    ctx.stroke();
                }
            }

            // Floating hex grid overlay (very subtle)
            ctx.save();
            ctx.globalAlpha = darkMode ? 0.02 : 0.015;
            const hexSize = 60;
            for (let row = -1; row < h / (hexSize * 1.5) + 1; row++) {
                for (let col = -1; col < w / (hexSize * 1.73) + 1; col++) {
                    const cx = col * hexSize * 1.73 + (row % 2 ? hexSize * 0.866 : 0) + Math.sin(time * 0.005 + row) * 5;
                    const cy = row * hexSize * 1.5 + Math.cos(time * 0.005 + col) * 5;
                    ctx.beginPath();
                    for (let s = 0; s < 6; s++) {
                        const angle = (Math.PI / 3) * s - Math.PI / 6;
                        const sx = cx + hexSize * 0.4 * Math.cos(angle);
                        const sy = cy + hexSize * 0.4 * Math.sin(angle);
                        s === 0 ? ctx.moveTo(sx, sy) : ctx.lineTo(sx, sy);
                    }
                    ctx.closePath();
                    ctx.strokeStyle = `rgb(${primary[0]},${primary[1]},${primary[2]})`;
                    ctx.lineWidth = 0.5;
                    ctx.stroke();
                }
            }
            ctx.restore();

            animationRef.current = requestAnimationFrame(animate);
        };

        animate();
        return () => {
            cancelAnimationFrame(animationRef.current);
            window.removeEventListener('resize', resize);
            window.removeEventListener('mousemove', handleMouse);
        };
    }, [darkMode, initParticles]);

    return <canvas ref={canvasRef} className="fixed inset-0 w-full h-full" style={{ zIndex: 0 }} />;
};

// ─── Login Page ─────────────────────────────────────────────────────────
const LoginPage = ({ admins, onLogin, appName, appIcon, appVersion, appLastUpdated, latestVersionNote, darkMode, onToggleDarkMode }: LoginPageProps) => {
    const [username, setUsername] = useState('');
    const [password, setPassword] = useState('');
    const [showPassword, setShowPassword] = useState(false);
    const [error, setError] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const [shake, setShake] = useState(false);
    const [mounted, setMounted] = useState(false);
    const [userKeyBurst, setUserKeyBurst] = useState(0);
    const [passKeyBurst, setPassKeyBurst] = useState(0);

    useEffect(() => { setMounted(true); }, []);

    const inputFillPct = (value: string, maxChars = 28) =>
        Math.min(100, (value.length / maxChars) * 100);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        const u = username.trim();
        if (!u || !password) { setError('กรุณากรอกข้อมูลให้ครบ'); triggerShake(); return; }
        if (!admins || admins.length === 0) {
            setError('ยังโหลดข้อมูลบัญชีไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
            triggerShake();
            return;
        }
        setIsLoading(true);
        try {
            const normalizedInput = u.toLowerCase();
            // รองรับข้อมูลเก่าที่อาจมีช่องว่างหน้า/ท้ายใน username
            const admin = admins.find(a => (a.username || '').trim().toLowerCase() === normalizedInput);
            if (!admin) {
                setError('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
                triggerShake();
                return;
            }
            const ok = await verifyStoredPassword(admin.password, password);
            if (!ok) {
                setError('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
                triggerShake();
                return;
            }
            await onLogin(admin, password);
        } finally {
            setIsLoading(false);
        }
    };

    const triggerShake = () => { setShake(true); setTimeout(() => setShake(false), 600); };

    const gold = '#C5A55A';
    const goldDark = '#8B7A3E';
    const lastUpdatedText = (() => {
        if (!appLastUpdated) return '-';
        const d = new Date(appLastUpdated);
        if (Number.isNaN(d.getTime())) return appLastUpdated;
        return d.toLocaleDateString('th-TH', { day: '2-digit', month: 'short', year: 'numeric' });
    })();

    return (
        <div className={`min-h-screen min-h-[100dvh] flex items-center justify-center relative overflow-hidden transition-colors duration-700 ${darkMode ? 'app-shell-dark' : 'app-shell-light'}`}>

            {/* Network Canvas Background */}
            <NetworkBackground darkMode={darkMode} />

            {/* Radial gradient overlays */}
            <div className="fixed inset-0 pointer-events-none" style={{ zIndex: 1 }}>
                <div className="absolute top-0 left-1/4 w-[600px] h-[600px] rounded-full"
                    style={{
                        background: darkMode
                            ? 'radial-gradient(circle, rgba(0,150,255,0.08), transparent 60%)'
                            : 'radial-gradient(circle, rgba(197,165,90,0.08), transparent 60%)',
                    }} />
                <div className="absolute bottom-0 right-1/4 w-[500px] h-[500px] rounded-full"
                    style={{
                        background: darkMode
                            ? 'radial-gradient(circle, rgba(120,80,255,0.05), transparent 60%)'
                            : 'radial-gradient(circle, rgba(139,122,62,0.05), transparent 60%)',
                    }} />
            </div>

            {/* Dark Mode Toggle */}
            <button onClick={onToggleDarkMode}
                className={`fixed top-4 right-4 z-50 p-3 rounded-full transition-all duration-300 backdrop-blur-md ${darkMode
                    ? 'bg-white/10 text-cyan-400 hover:bg-white/20 border border-white/10 hover:border-cyan-500/40'
                    : 'bg-black/5 text-gray-600 hover:bg-black/10 border border-black/5 hover:border-amber-500/40'
                    }`}>
                {darkMode ? <Sun size={18} /> : <Moon size={18} />}
            </button>

            {/* Main Login Card */}
            <div className={`relative z-10 w-full max-w-lg mx-4 transition-all duration-1000 ${mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-8'} ${shake ? 'animate-shake' : ''}`}>

                {/* Glassmorphism Card */}
                <div className={`relative rounded-3xl overflow-hidden transition-all duration-500 ${darkMode
                    ? 'bg-white/[0.04] border border-white/[0.08] shadow-2xl shadow-cyan-500/10'
                    : 'bg-white/70 border border-stone-200/60 shadow-2xl shadow-amber-200/30'
                    }`}
                    style={{ backdropFilter: 'blur(24px)', WebkitBackdropFilter: 'blur(24px)' }}>

                    {/* Top Glow Bar */}
                    <div className="absolute top-0 left-0 right-0 h-[2px]"
                        style={{
                            background: darkMode
                                ? 'linear-gradient(90deg, transparent, #00c8ff, #7850ff, transparent)'
                                : `linear-gradient(90deg, transparent, ${gold}, ${goldDark}, transparent)`
                        }}>
                        <div className="absolute inset-0 animate-shimmer-fast" />
                    </div>

                    {/* Inner scanning line animation */}
                    <div className="absolute inset-0 overflow-hidden pointer-events-none">
                        <div className={`absolute w-full h-[1px] animate-scan-line ${darkMode ? 'bg-gradient-to-r from-transparent via-cyan-400/20 to-transparent' : 'bg-gradient-to-r from-transparent via-amber-400/15 to-transparent'}`} />
                    </div>

                    <div className="relative p-8 sm:p-10">
                        {/* Logo */}
                        <div className={`w-24 h-24 mx-auto rounded-2xl flex items-center justify-center shadow-2xl overflow-hidden mb-6 transition-all duration-700 ${mounted ? 'scale-100 rotate-0' : 'scale-50 rotate-12'}`}
                            style={{
                                background: darkMode
                                    ? 'linear-gradient(135deg, #0a0a20, #111130)'
                                    : 'linear-gradient(135deg, #1a1a1a, #0a0a0a)',
                                boxShadow: darkMode
                                    ? '0 0 40px rgba(0,200,255,0.15), 0 10px 30px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.05)'
                                    : `0 0 40px ${gold}20, 0 10px 30px rgba(0,0,0,0.3)`,
                                border: darkMode ? '1px solid rgba(0,200,255,0.15)' : `1px solid ${gold}25`
                            }}>
                            {appIcon.startsWith('http') || appIcon.startsWith('data:') ? (
                                <img src={appIcon} alt="Logo" className="w-full h-full object-cover" />
                            ) : (
                                <span className="text-3xl font-bold" style={{ color: darkMode ? '#00c8ff' : gold }}>{appIcon}</span>
                            )}
                        </div>

                        {/* Title */}
                        <div className="text-center mb-8">
                            <h1 className={`text-2xl sm:text-3xl font-bold mb-2 transition-all duration-700 delay-200 ${mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'} ${darkMode ? 'bg-gradient-to-r from-cyan-400 via-blue-400 to-purple-400 bg-clip-text text-transparent' : 'text-black'}`}>
                                {appName}
                            </h1>
                            <p className={`text-sm transition-all duration-700 delay-300 ${mounted ? 'opacity-100' : 'opacity-0'} ${darkMode ? 'text-cyan-300/50' : 'text-black/70'}`}>
                                ระบบจัดการโครงการก่อสร้าง
                            </p>
                            <p className={`text-xs mt-2 transition-all duration-700 delay-300 ${mounted ? 'opacity-100' : 'opacity-0'} ${darkMode ? 'text-cyan-400/60' : 'text-black/60'}`}>
                                v{appVersion} • {latestVersionNote || 'พร้อมใช้งาน'}
                            </p>

                            {/* Feature badges */}
                            <div className={`flex flex-wrap gap-2 justify-center mt-4 transition-all duration-700 delay-500 ${mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'}`}>
                                {['📊 วิเคราะห์', '🏗️ จัดการงาน', '💰 รายรับ-จ่าย'].map((feat, i) => (
                                    <span key={i} className={`px-3 py-1 rounded-full text-xs font-medium ${darkMode
                                        ? 'bg-cyan-500/10 text-cyan-400/70 border border-cyan-500/15'
                                        : 'bg-black/5 text-black/80 border border-black/10'
                                        }`}
                                        style={{ animationDelay: `${i * 0.1}s` }}>
                                        {feat}
                                    </span>
                                ))}
                            </div>
                        </div>

                        {/* Login Form */}
                        <form onSubmit={handleSubmit} className="space-y-5">
                            {/* Username */}
                            <div className={`transition-all duration-700 delay-[400ms] ${mounted ? 'opacity-100 translate-x-0' : 'opacity-0 -translate-x-8'}`}>
                                <label className={`block text-xs font-medium mb-2 ${darkMode ? 'text-gray-400' : 'text-black'}`}>
                                    ชื่อผู้ใช้ (Username)
                                </label>
                                <div className="relative group">
                                    {userKeyBurst > 0 && (
                                        <div
                                            key={userKeyBurst}
                                            className={`pointer-events-none absolute inset-0 z-[1] rounded-xl ${darkMode ? 'animate-login-keystroke-dark' : 'animate-login-keystroke-light'}`}
                                            aria-hidden
                                        />
                                    )}
                                    <div className={`absolute left-4 top-1/2 z-[2] -translate-y-1/2 transition-colors duration-300 ${darkMode
                                        ? 'text-gray-600 group-focus-within:text-cyan-400'
                                        : 'text-stone-400 group-focus-within:text-amber-600'
                                        }`}>
                                        <span key={userKeyBurst} className="inline-flex login-icon-typing">
                                            <User size={18} />
                                        </span>
                                    </div>
                                    <input type="text" placeholder="กรอกชื่อผู้ใช้" value={username}
                                        onChange={(e) => setUsername(e.target.value)}
                                        onKeyDown={() => setUserKeyBurst((k) => k + 1)}
                                        className={`relative z-[2] w-full rounded-xl pl-12 pr-4 py-3.5 transition-all duration-300 focus:outline-none text-sm focus:scale-[1.01] motion-safe:transform-gpu ${darkMode
                                            ? 'bg-white/[0.04] border border-white/[0.08] text-white placeholder:text-gray-600 focus:border-cyan-500/40 focus:bg-white/[0.06] focus:ring-1 focus:ring-cyan-500/20 focus:shadow-[0_0_15px_rgba(0,200,255,0.08)]'
                                            : 'bg-white/60 border border-stone-200 text-black placeholder:text-black/40 focus:border-amber-500 focus:bg-white focus:ring-1 focus:ring-amber-500/20 focus:shadow-[0_0_15px_rgba(197,165,90,0.1)]'
                                            }`}
                                        autoComplete="username" />
                                    {/* Focus glow effect */}
                                    <div className={`pointer-events-none absolute inset-0 z-[3] rounded-xl opacity-0 group-focus-within:opacity-100 transition-opacity duration-500 ${darkMode
                                        ? 'shadow-[inset_0_0_0_1px_rgba(0,200,255,0.1)]'
                                        : 'shadow-[inset_0_0_0_1px_rgba(197,165,90,0.1)]'
                                        }`} />
                                </div>
                                <div
                                    className={`mt-2 h-1 rounded-full overflow-hidden ${darkMode ? 'bg-white/[0.06]' : 'bg-stone-200/80'}`}
                                    aria-hidden
                                >
                                    <div
                                        className={`h-full rounded-full origin-left transition-[width] duration-200 ease-out ${darkMode ? 'bg-cyan-400/70' : 'bg-amber-500/80'} ${username.length > 0 ? 'login-input-bar-pulse' : ''}`}
                                        style={{ width: `${inputFillPct(username)}%` }}
                                    />
                                </div>
                            </div>

                            {/* Password */}
                            <div className={`transition-all duration-700 delay-[500ms] ${mounted ? 'opacity-100 translate-x-0' : 'opacity-0 translate-x-8'}`}>
                                <label className={`block text-xs font-medium mb-2 ${darkMode ? 'text-gray-400' : 'text-black'}`}>
                                    รหัสผ่าน (Password)
                                </label>
                                <div className="relative group">
                                    {passKeyBurst > 0 && (
                                        <div
                                            key={passKeyBurst}
                                            className={`pointer-events-none absolute inset-0 z-[1] rounded-xl ${darkMode ? 'animate-login-keystroke-dark' : 'animate-login-keystroke-light'}`}
                                            aria-hidden
                                        />
                                    )}
                                    <div className={`absolute left-4 top-1/2 z-[2] -translate-y-1/2 transition-colors duration-300 ${darkMode
                                        ? 'text-gray-600 group-focus-within:text-cyan-400'
                                        : 'text-stone-400 group-focus-within:text-amber-600'
                                        }`}>
                                        <span key={passKeyBurst} className="inline-flex login-icon-typing">
                                            <Lock size={18} />
                                        </span>
                                    </div>
                                    <input type={showPassword ? 'text' : 'password'} placeholder="กรอกรหัสผ่าน" value={password}
                                        onChange={(e) => setPassword(e.target.value)}
                                        onKeyDown={() => setPassKeyBurst((k) => k + 1)}
                                        className={`relative z-[2] w-full rounded-xl pl-12 pr-12 py-3.5 transition-all duration-300 focus:outline-none text-sm focus:scale-[1.01] motion-safe:transform-gpu ${darkMode
                                            ? 'bg-white/[0.04] border border-white/[0.08] text-white placeholder:text-gray-600 focus:border-cyan-500/40 focus:bg-white/[0.06] focus:ring-1 focus:ring-cyan-500/20 focus:shadow-[0_0_15px_rgba(0,200,255,0.08)]'
                                            : 'bg-white/60 border border-stone-200 text-black placeholder:text-black/40 focus:border-amber-500 focus:bg-white focus:ring-1 focus:ring-amber-500/20 focus:shadow-[0_0_15px_rgba(197,165,90,0.1)]'
                                            }`}
                                        autoComplete="current-password" />
                                    <button type="button" onClick={() => setShowPassword(!showPassword)}
                                        className={`absolute right-4 top-1/2 z-[2] -translate-y-1/2 transition-colors ${darkMode ? 'text-gray-500 hover:text-cyan-400' : 'text-stone-400 hover:text-stone-700'}`}>
                                        {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                                    </button>
                                </div>
                                <div
                                    className={`mt-2 h-1 rounded-full overflow-hidden ${darkMode ? 'bg-white/[0.06]' : 'bg-stone-200/80'}`}
                                    aria-hidden
                                >
                                    <div
                                        className={`h-full rounded-full origin-left transition-[width] duration-200 ease-out ${darkMode ? 'bg-cyan-400/70' : 'bg-amber-500/80'} ${password.length > 0 ? 'login-input-bar-pulse' : ''}`}
                                        style={{ width: `${inputFillPct(password)}%` }}
                                    />
                                </div>
                            </div>

                            {/* Error */}
                            {error && (
                                <div className="flex items-center gap-2 text-red-400 text-sm bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-3 animate-fade-in">
                                    <Shield size={16} className="shrink-0" /><span>{error}</span>
                                </div>
                            )}

                            {/* Remember + Forgot */}
                            <div className={`flex justify-between items-center transition-all duration-700 delay-[600ms] ${mounted ? 'opacity-100' : 'opacity-0'}`}>
                                <label className="flex items-center gap-2 cursor-pointer">
                                    <input type="checkbox" className="w-4 h-4 rounded border-gray-300 accent-amber-500" />
                                    <span className={`text-xs ${darkMode ? 'text-gray-500' : 'text-black/70'}`}>จดจำฉัน</span>
                                </label>
                                <span className={`text-xs cursor-pointer hover:underline ${darkMode ? 'text-cyan-500/70 hover:text-cyan-400' : 'text-black/70 hover:text-black'}`}>
                                    ลืมรหัสผ่าน?
                                </span>
                            </div>

                            {/* Submit Button */}
                            <div className={`transition-all duration-700 delay-[700ms] ${mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'}`}>
                                <button type="submit" disabled={isLoading}
                                    className="w-full relative font-bold py-3.5 rounded-xl transition-all duration-300 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2 group text-white overflow-hidden hover:scale-[1.01] active:scale-[0.99]"
                                    style={{
                                        background: darkMode
                                            ? 'linear-gradient(135deg, #0080ff, #6020c0)'
                                            : `linear-gradient(135deg, ${gold}, ${goldDark})`,
                                        boxShadow: darkMode
                                            ? '0 4px 25px rgba(0,128,255,0.3), 0 0 60px rgba(0,128,255,0.1)'
                                            : `0 4px 25px ${gold}30, 0 0 60px ${gold}10`
                                    }}>
                                    {/* Button shine animation */}
                                    <div className="absolute inset-0 -translate-x-full animate-btn-shine bg-gradient-to-r from-transparent via-white/20 to-transparent" />
                                    {isLoading ? (
                                        <><Loader2 size={20} className="animate-spin" /><span>กำลังตรวจสอบ...</span></>
                                    ) : (
                                        <><Lock size={18} className="group-hover:scale-110 transition-transform" /><span>เข้าสู่ระบบ</span></>
                                    )}
                                </button>
                            </div>
                        </form>
                    </div>

                    {/* Bottom glow bar */}
                    <div className="absolute bottom-0 left-0 right-0 h-[1px]"
                        style={{
                            background: darkMode
                                ? 'linear-gradient(90deg, transparent, rgba(0,200,255,0.3), rgba(120,80,255,0.3), transparent)'
                                : `linear-gradient(90deg, transparent, ${gold}40, transparent)`
                        }} />
                </div>

                {/* Footer */}
                <div className={`mt-6 text-center transition-all duration-700 delay-[800ms] ${mounted ? 'opacity-100' : 'opacity-0'}`}>
                    <p className={`text-xs ${darkMode ? 'text-gray-600' : 'text-black/60'}`}>
                        ติดต่อผู้ดูแลระบบหากลืมรหัสผ่าน
                    </p>
                    <p className={`text-xs mt-2 ${darkMode ? 'text-gray-500' : 'text-black/60'}`}>
                        เวอร์ชัน {appVersion} • อัปเดตล่าสุด {lastUpdatedText}
                    </p>
                    <p className={`text-xs mt-2 ${darkMode ? 'text-gray-800' : 'text-black/50'}`}>
                        © 2024 {appName}. All rights reserved.
                    </p>
                </div>
            </div>
        </div>
    );
};

export default LoginPage;
