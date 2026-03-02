import { useState } from 'react';
import { Lock, User, Eye, EyeOff, Shield, Loader2, Sun, Moon } from 'lucide-react';
import { AdminUser } from '../../types';

interface LoginPageProps {
    admins: AdminUser[];
    onLogin: (admin: AdminUser) => void;
    appName: string;
    appIcon: string;
    darkMode: boolean;
    onToggleDarkMode: () => void;
}

const LoginPage = ({ admins, onLogin, appName, appIcon, darkMode, onToggleDarkMode }: LoginPageProps) => {
    const [username, setUsername] = useState('');
    const [password, setPassword] = useState('');
    const [showPassword, setShowPassword] = useState(false);
    const [error, setError] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const [shake, setShake] = useState(false);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        if (!username || !password) { setError('กรุณากรอกข้อมูลให้ครบ'); triggerShake(); return; }
        setIsLoading(true);
        await new Promise(r => setTimeout(r, 800));
        const admin = admins.find(a => a.username === username && a.password === password);
        if (admin) { onLogin(admin); } else { setError('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'); triggerShake(); }
        setIsLoading(false);
    };

    const triggerShake = () => { setShake(true); setTimeout(() => setShake(false), 600); };

    // Gold color palette
    const gold = '#C5A55A';
    const goldLight = '#E8D5A0';
    const goldDark = '#8B7A3E';

    return (
        <div className={`min-h-screen min-h-[100dvh] flex items-center justify-center relative overflow-hidden transition-colors duration-700 ${darkMode ? 'bg-black' : 'bg-gradient-to-br from-gray-50 via-white to-stone-50'}`}>

            {/* Dark Mode Toggle */}
            <button onClick={onToggleDarkMode}
                className={`absolute top-5 right-5 z-30 p-2.5 rounded-full transition-all duration-300 ${darkMode
                    ? 'bg-white/10 text-amber-400 hover:bg-white/20 border border-white/10'
                    : 'bg-black/5 text-gray-600 hover:bg-black/10 border border-black/5'
                    }`}>
                {darkMode ? <Sun size={18} /> : <Moon size={18} />}
            </button>

            {/* ========= DARK MODE BG ========= */}
            {darkMode && (
                <>
                    {/* Gold geometric lines */}
                    <div className="absolute inset-0 opacity-[0.04]" style={{
                        backgroundImage: `linear-gradient(${gold} 1px, transparent 1px), linear-gradient(90deg, ${gold} 1px, transparent 1px)`,
                        backgroundSize: '80px 80px'
                    }} />
                    {/* Floating gold particles */}
                    {[...Array(6)].map((_, i) => (
                        <div key={i} className="absolute animate-particle"
                            style={{
                                width: `${6 + i * 3}px`, height: `${6 + i * 3}px`,
                                borderRadius: '50%',
                                background: `radial-gradient(circle, ${gold}, transparent)`,
                                left: `${10 + i * 15}%`, top: `${20 + (i % 3) * 25}%`,
                                animationDelay: `${i * 1.2}s`, opacity: 0.4
                            }} />
                    ))}
                    {/* Corner gold accents */}
                    <div className="absolute top-0 left-0 w-40 h-40 opacity-20">
                        <div className="absolute top-0 left-0 w-full h-[1px]" style={{ background: `linear-gradient(90deg, ${gold}, transparent)` }} />
                        <div className="absolute top-0 left-0 h-full w-[1px]" style={{ background: `linear-gradient(180deg, ${gold}, transparent)` }} />
                    </div>
                    <div className="absolute bottom-0 right-0 w-40 h-40 opacity-20">
                        <div className="absolute bottom-0 right-0 w-full h-[1px]" style={{ background: `linear-gradient(270deg, ${gold}, transparent)` }} />
                        <div className="absolute bottom-0 right-0 h-full w-[1px]" style={{ background: `linear-gradient(0deg, ${gold}, transparent)` }} />
                    </div>
                    {/* Ambient gold glow */}
                    <div className="absolute top-1/3 left-1/2 -translate-x-1/2 w-[600px] h-[600px] rounded-full opacity-[0.06]"
                        style={{ background: `radial-gradient(circle, ${gold}, transparent 70%)` }} />
                    {/* Rotating ring */}
                    <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] animate-rotate-slow opacity-[0.03]">
                        <div className="w-full h-full rounded-full border" style={{ borderColor: gold }} />
                    </div>
                </>
            )}

            {/* ========= LIGHT MODE BG ========= */}
            {!darkMode && (
                <>
                    <div className="absolute inset-0 opacity-[0.015]" style={{
                        backgroundImage: `linear-gradient(${goldDark} 1px, transparent 1px), linear-gradient(90deg, ${goldDark} 1px, transparent 1px)`,
                        backgroundSize: '80px 80px'
                    }} />
                    {/* Soft gold orbs */}
                    <div className="absolute top-1/4 left-1/3 w-96 h-96 rounded-full blur-3xl animate-float opacity-20"
                        style={{ background: `radial-gradient(circle, ${goldLight}40, transparent)` }} />
                    <div className="absolute bottom-1/3 right-1/4 w-80 h-80 rounded-full blur-3xl animate-float opacity-15"
                        style={{ background: `radial-gradient(circle, ${goldLight}30, transparent)`, animationDelay: '3s' }} />
                </>
            )}

            {/* ========= LOGIN CARD ========= */}
            <div className={`relative z-10 w-full max-w-md mx-4 animate-card-entrance ${shake ? 'animate-shake' : ''}`}>

                {/* Shimmer line on top */}
                <div className="animate-shimmer h-[2px] w-full rounded-full mb-0" />

                <div className={`relative rounded-3xl p-8 sm:p-10 border transition-all duration-500 animate-glow-pulse ${darkMode
                    ? 'bg-gray-950/80 backdrop-blur-2xl border-white/[0.08] shadow-2xl shadow-amber-900/10'
                    : 'bg-white/90 backdrop-blur-xl border-stone-200/60 shadow-xl shadow-stone-300/20'
                    }`}>

                    {/* Inner shimmer accent */}
                    <div className="absolute top-0 left-8 right-8 h-[1px] opacity-40"
                        style={{ background: `linear-gradient(90deg, transparent, ${darkMode ? gold : goldDark}40, transparent)` }} />

                    {/* Logo & Branding */}
                    <div className="text-center mb-8">
                        <div className="relative inline-block">
                            <div className={`w-24 h-24 mx-auto rounded-2xl flex items-center justify-center shadow-xl transform hover:scale-105 transition-all duration-300 overflow-hidden ${darkMode
                                ? 'shadow-amber-900/20 ring-1 ring-white/10'
                                : 'shadow-stone-300/30 ring-1 ring-stone-200/50'
                                }`} style={{ background: darkMode ? `linear-gradient(135deg, #1a1a1a, #0a0a0a)` : `linear-gradient(135deg, #fafafa, #f0f0f0)` }}>
                                {appIcon.startsWith('http') || appIcon.startsWith('data:') ? (
                                    <img src={appIcon} alt="Logo" className="w-full h-full object-cover" />
                                ) : (
                                    <span className="text-2xl font-bold" style={{ color: gold }}>{appIcon}</span>
                                )}
                            </div>
                            {/* Gold ring decoration */}
                            <div className="absolute -inset-1 rounded-2xl opacity-20 animate-pulse"
                                style={{ border: `1px solid ${gold}` }} />
                        </div>

                        <h1 className={`text-2xl sm:text-3xl font-bold mt-5 mb-1 ${darkMode ? 'gold-gradient-text' : 'text-gray-900'}`}>
                            {appName}
                        </h1>
                        <p className="text-sm" style={{ color: darkMode ? `${gold}90` : goldDark }}>ระบบจัดการโครงการ</p>
                    </div>

                    {/* Login Form */}
                    <form onSubmit={handleSubmit} className="space-y-4">
                        {/* Username */}
                        <div className="relative group">
                            <div className={`absolute left-4 top-1/2 -translate-y-1/2 transition-colors duration-300 ${darkMode ? 'text-gray-500 group-focus-within:text-amber-500' : 'text-stone-400 group-focus-within:text-amber-700'}`}>
                                <User size={18} />
                            </div>
                            <input type="text" placeholder="ชื่อผู้ใช้ (Username)" value={username}
                                onChange={(e) => setUsername(e.target.value)}
                                className={`w-full rounded-xl pl-12 pr-4 py-3.5 transition-all duration-300 focus:outline-none ${darkMode
                                    ? 'bg-white/[0.04] border border-white/[0.08] text-white placeholder:text-gray-600 focus:border-amber-500/40 focus:bg-white/[0.06] focus:ring-1 focus:ring-amber-500/20'
                                    : 'bg-stone-50 border border-stone-200 text-gray-900 placeholder:text-stone-400 focus:border-amber-500 focus:bg-white focus:ring-1 focus:ring-amber-500/20'
                                    }`}
                                autoComplete="username" />
                        </div>

                        {/* Password */}
                        <div className="relative group">
                            <div className={`absolute left-4 top-1/2 -translate-y-1/2 transition-colors duration-300 ${darkMode ? 'text-gray-500 group-focus-within:text-amber-500' : 'text-stone-400 group-focus-within:text-amber-700'}`}>
                                <Lock size={18} />
                            </div>
                            <input type={showPassword ? 'text' : 'password'} placeholder="รหัสผ่าน (Password)" value={password}
                                onChange={(e) => setPassword(e.target.value)}
                                className={`w-full rounded-xl pl-12 pr-12 py-3.5 transition-all duration-300 focus:outline-none ${darkMode
                                    ? 'bg-white/[0.04] border border-white/[0.08] text-white placeholder:text-gray-600 focus:border-amber-500/40 focus:bg-white/[0.06] focus:ring-1 focus:ring-amber-500/20'
                                    : 'bg-stone-50 border border-stone-200 text-gray-900 placeholder:text-stone-400 focus:border-amber-500 focus:bg-white focus:ring-1 focus:ring-amber-500/20'
                                    }`}
                                autoComplete="current-password" />
                            <button type="button" onClick={() => setShowPassword(!showPassword)}
                                className={`absolute right-4 top-1/2 -translate-y-1/2 transition-colors ${darkMode ? 'text-gray-500 hover:text-white' : 'text-stone-400 hover:text-stone-700'}`}>
                                {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                            </button>
                        </div>

                        {/* Error */}
                        {error && (
                            <div className="flex items-center gap-2 text-red-400 text-sm bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-3 animate-fade-in">
                                <Shield size={16} className="shrink-0" /><span>{error}</span>
                            </div>
                        )}

                        {/* Submit Button */}
                        <button type="submit" disabled={isLoading}
                            className="w-full font-bold py-3.5 rounded-xl transition-all duration-300 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2 group text-white shadow-lg hover:shadow-xl"
                            style={{
                                background: `linear-gradient(135deg, ${gold}, ${goldDark})`,
                                boxShadow: `0 4px 20px ${gold}30`
                            }}>
                            {isLoading ? (
                                <><Loader2 size={20} className="animate-spin" /><span>กำลังตรวจสอบ...</span></>
                            ) : (
                                <><Lock size={18} className="group-hover:scale-110 transition-transform" /><span>เข้าสู่ระบบ</span></>
                            )}
                        </button>
                    </form>

                    {/* Divider */}
                    <div className="mt-6 flex items-center gap-3">
                        <div className={`flex-1 h-[1px] ${darkMode ? 'bg-white/[0.06]' : 'bg-stone-200'}`} />
                        <span className={`text-xs ${darkMode ? 'text-gray-600' : 'text-stone-400'}`}>Goldenmole</span>
                        <div className={`flex-1 h-[1px] ${darkMode ? 'bg-white/[0.06]' : 'bg-stone-200'}`} />
                    </div>

                    <div className="mt-4 text-center">
                        <p className={`text-xs ${darkMode ? 'text-gray-600' : 'text-stone-400'}`}>ติดต่อผู้ดูแลระบบหากลืมรหัสผ่าน</p>
                    </div>
                </div>

                {/* Bottom branding */}
                <div className="text-center mt-6">
                    <p className={`text-xs ${darkMode ? 'text-gray-700' : 'text-stone-400'}`}>© 2024 {appName}. All rights reserved.</p>
                </div>
            </div>
        </div>
    );
};

export default LoginPage;
