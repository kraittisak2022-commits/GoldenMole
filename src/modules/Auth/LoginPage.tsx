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

    const gold = '#C5A55A';
    const goldLight = '#E8D5A0';
    const goldDark = '#8B7A3E';

    return (
        <div className={`min-h-screen min-h-[100dvh] flex transition-colors duration-700 ${darkMode ? 'bg-[#0a0a0f]' : 'bg-gradient-to-br from-stone-50 via-white to-amber-50/30'}`}>

            {/* Dark Mode Toggle - Fixed top right */}
            <button onClick={onToggleDarkMode}
                className={`fixed top-5 right-5 z-50 p-2.5 rounded-full transition-all duration-300 backdrop-blur-sm ${darkMode
                    ? 'bg-white/10 text-amber-400 hover:bg-white/20 border border-white/10'
                    : 'bg-black/5 text-gray-600 hover:bg-black/10 border border-black/5'
                    }`}>
                {darkMode ? <Sun size={18} /> : <Moon size={18} />}
            </button>

            {/* ===================== LEFT PANEL - Decorative ===================== */}
            <div className={`hidden lg:flex lg:w-[52%] relative overflow-hidden items-center justify-center ${darkMode ? '' : ''}`}
                style={{
                    background: darkMode
                        ? `linear-gradient(135deg, #0d0d15 0%, #111118 40%, #15131f 100%)`
                        : `linear-gradient(135deg, #1a1810 0%, #0f0e0a 50%, #1a1612 100%)`
                }}>

                {/* Grid pattern */}
                <div className="absolute inset-0 opacity-[0.04]" style={{
                    backgroundImage: `linear-gradient(${gold} 1px, transparent 1px), linear-gradient(90deg, ${gold} 1px, transparent 1px)`,
                    backgroundSize: '60px 60px'
                }} />

                {/* Animated floating circles */}
                <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2">
                    {/* Large outer ring */}
                    <div className="absolute -inset-[180px] animate-rotate-slow">
                        <div className="w-full h-full rounded-full" style={{
                            border: `1.5px solid ${gold}30`,
                        }} />
                        <div className="absolute top-0 left-1/2 w-3 h-3 rounded-full -translate-x-1/2 -translate-y-1/2"
                            style={{ background: gold, boxShadow: `0 0 15px ${gold}60` }} />
                    </div>
                    {/* Medium ring */}
                    <div className="absolute -inset-[120px] animate-spin-reverse-slow">
                        <div className="w-full h-full rounded-full" style={{
                            border: `1px solid ${gold}20`,
                            borderStyle: 'dashed',
                        }} />
                        <div className="absolute bottom-0 left-1/2 w-2 h-2 rounded-full -translate-x-1/2 translate-y-1/2"
                            style={{ background: goldLight, boxShadow: `0 0 10px ${gold}40` }} />
                    </div>
                    {/* Inner ring */}
                    <div className="absolute -inset-[70px] animate-spin-slow" style={{ animationDuration: '30s' }}>
                        <div className="w-full h-full rounded-full" style={{
                            border: `1px solid ${gold}15`,
                        }} />
                    </div>
                </div>

                {/* Floating gold particles */}
                {[...Array(8)].map((_, i) => (
                    <div key={i} className="absolute animate-particle"
                        style={{
                            width: `${4 + i * 2}px`, height: `${4 + i * 2}px`,
                            borderRadius: '50%',
                            background: `radial-gradient(circle, ${gold}90, transparent)`,
                            left: `${8 + i * 11}%`, top: `${15 + (i % 4) * 20}%`,
                            animationDelay: `${i * 0.8}s`, opacity: 0.5
                        }} />
                ))}

                {/* Center Logo + Branding */}
                <div className="relative z-10 text-center px-8">
                    <div className="w-32 h-32 mx-auto rounded-3xl flex items-center justify-center shadow-2xl overflow-hidden mb-8 animate-card-entrance"
                        style={{
                            background: 'linear-gradient(135deg, #1a1a1a, #0a0a0a)',
                            boxShadow: `0 0 60px ${gold}15, 0 20px 40px rgba(0,0,0,0.5)`,
                            border: `1px solid ${gold}25`
                        }}>
                        {appIcon.startsWith('http') || appIcon.startsWith('data:') ? (
                            <img src={appIcon} alt="Logo" className="w-full h-full object-cover" />
                        ) : (
                            <span className="text-4xl font-bold" style={{ color: gold }}>{appIcon}</span>
                        )}
                    </div>

                    <h1 className="text-4xl font-bold mb-3 gold-gradient-text">{appName}</h1>
                    <p className="text-lg mb-6" style={{ color: `${gold}80` }}>ระบบจัดการโครงการ</p>

                    {/* Shimmer line */}
                    <div className="animate-shimmer h-[1px] w-48 mx-auto rounded-full mb-8" />

                    {/* Feature badges */}
                    <div className="flex flex-wrap gap-3 justify-center">
                        {['📊 วิเคราะห์ข้อมูล', '🏗️ จัดการงาน', '💰 บันทึกรายรับ-จ่าย'].map((feat, i) => (
                            <div key={i} className="px-4 py-2 rounded-xl text-sm font-medium animate-fade-in"
                                style={{
                                    background: `${gold}10`,
                                    border: `1px solid ${gold}15`,
                                    color: `${gold}90`,
                                    animationDelay: `${0.5 + i * 0.15}s`
                                }}>
                                {feat}
                            </div>
                        ))}
                    </div>

                    {/* Bottom corner accents */}
                    <div className="absolute bottom-0 left-0 right-0 h-[1px] opacity-10"
                        style={{ background: `linear-gradient(90deg, transparent, ${gold}, transparent)` }} />
                </div>

                {/* Ambient glow */}
                <div className="absolute top-1/3 left-1/2 -translate-x-1/2 w-[500px] h-[500px] rounded-full opacity-[0.04]"
                    style={{ background: `radial-gradient(circle, ${gold}, transparent 60%)` }} />

                {/* Corner decorations */}
                <div className="absolute top-0 left-0 w-32 h-32 opacity-30">
                    <div className="absolute top-0 left-0 w-full h-[1px]" style={{ background: `linear-gradient(90deg, ${gold}60, transparent)` }} />
                    <div className="absolute top-0 left-0 h-full w-[1px]" style={{ background: `linear-gradient(180deg, ${gold}60, transparent)` }} />
                </div>
                <div className="absolute bottom-0 right-0 w-32 h-32 opacity-30">
                    <div className="absolute bottom-0 right-0 w-full h-[1px]" style={{ background: `linear-gradient(270deg, ${gold}60, transparent)` }} />
                    <div className="absolute bottom-0 right-0 h-full w-[1px]" style={{ background: `linear-gradient(0deg, ${gold}60, transparent)` }} />
                </div>
            </div>

            {/* ===================== RIGHT PANEL - Login Form ===================== */}
            <div className="flex-1 flex items-center justify-center p-6 sm:p-10 relative">

                {/* Subtle background pattern for right panel */}
                {darkMode && (
                    <div className="absolute inset-0 opacity-[0.02]" style={{
                        backgroundImage: `linear-gradient(${gold} 1px, transparent 1px), linear-gradient(90deg, ${gold} 1px, transparent 1px)`,
                        backgroundSize: '40px 40px'
                    }} />
                )}

                <div className={`w-full max-w-md relative z-10 ${shake ? 'animate-shake' : ''}`}>

                    {/* Mobile: Logo shown above form (hidden on lg+) */}
                    <div className="lg:hidden text-center mb-8">
                        <div className="w-20 h-20 mx-auto rounded-2xl flex items-center justify-center shadow-xl overflow-hidden mb-4"
                            style={{
                                background: 'linear-gradient(135deg, #1a1a1a, #0a0a0a)',
                                border: `1px solid ${gold}25`
                            }}>
                            {appIcon.startsWith('http') || appIcon.startsWith('data:') ? (
                                <img src={appIcon} alt="Logo" className="w-full h-full object-cover" />
                            ) : (
                                <span className="text-xl font-bold" style={{ color: gold }}>{appIcon}</span>
                            )}
                        </div>
                        <h1 className={`text-2xl font-bold ${darkMode ? 'gold-gradient-text' : 'text-gray-900'}`}>{appName}</h1>
                        <p className="text-sm mt-1" style={{ color: darkMode ? `${gold}80` : goldDark }}>ระบบจัดการโครงการ</p>
                    </div>

                    {/* Welcome Text */}
                    <div className="mb-8">
                        <h2 className={`text-2xl sm:text-3xl font-bold mb-2 ${darkMode ? 'text-white' : 'text-gray-900'}`}>
                            ยินดีต้อนรับ 👋
                        </h2>
                        <p className={`text-sm ${darkMode ? 'text-gray-500' : 'text-gray-400'}`}>
                            เข้าสู่ระบบเพื่อเริ่มใช้งาน <span style={{ color: gold }} className="font-medium">{appName}</span>
                        </p>
                    </div>

                    {/* Login Form Card */}
                    <div className={`rounded-2xl p-6 sm:p-8 transition-all duration-500 ${darkMode
                        ? 'bg-white/[0.03] border border-white/[0.06] backdrop-blur-xl'
                        : 'bg-white border border-stone-200/60 shadow-lg shadow-stone-200/30'
                        }`}>
                        <form onSubmit={handleSubmit} className="space-y-5">
                            {/* Username */}
                            <div>
                                <label className={`block text-xs font-medium mb-2 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>
                                    ชื่อผู้ใช้ (Username)
                                </label>
                                <div className="relative group">
                                    <div className={`absolute left-4 top-1/2 -translate-y-1/2 transition-colors ${darkMode ? 'text-gray-600 group-focus-within:text-amber-500' : 'text-stone-400 group-focus-within:text-amber-600'}`}>
                                        <User size={18} />
                                    </div>
                                    <input type="text" placeholder="กรอกชื่อผู้ใช้" value={username}
                                        onChange={(e) => setUsername(e.target.value)}
                                        className={`w-full rounded-xl pl-12 pr-4 py-3.5 transition-all duration-300 focus:outline-none text-sm ${darkMode
                                            ? 'bg-white/[0.04] border border-white/[0.08] text-white placeholder:text-gray-600 focus:border-amber-500/40 focus:bg-white/[0.06] focus:ring-1 focus:ring-amber-500/20'
                                            : 'bg-stone-50 border border-stone-200 text-gray-900 placeholder:text-stone-400 focus:border-amber-500 focus:bg-white focus:ring-1 focus:ring-amber-500/20'
                                            }`}
                                        autoComplete="username" />
                                </div>
                            </div>

                            {/* Password */}
                            <div>
                                <label className={`block text-xs font-medium mb-2 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>
                                    รหัสผ่าน (Password)
                                </label>
                                <div className="relative group">
                                    <div className={`absolute left-4 top-1/2 -translate-y-1/2 transition-colors ${darkMode ? 'text-gray-600 group-focus-within:text-amber-500' : 'text-stone-400 group-focus-within:text-amber-600'}`}>
                                        <Lock size={18} />
                                    </div>
                                    <input type={showPassword ? 'text' : 'password'} placeholder="กรอกรหัสผ่าน" value={password}
                                        onChange={(e) => setPassword(e.target.value)}
                                        className={`w-full rounded-xl pl-12 pr-12 py-3.5 transition-all duration-300 focus:outline-none text-sm ${darkMode
                                            ? 'bg-white/[0.04] border border-white/[0.08] text-white placeholder:text-gray-600 focus:border-amber-500/40 focus:bg-white/[0.06] focus:ring-1 focus:ring-amber-500/20'
                                            : 'bg-stone-50 border border-stone-200 text-gray-900 placeholder:text-stone-400 focus:border-amber-500 focus:bg-white focus:ring-1 focus:ring-amber-500/20'
                                            }`}
                                        autoComplete="current-password" />
                                    <button type="button" onClick={() => setShowPassword(!showPassword)}
                                        className={`absolute right-4 top-1/2 -translate-y-1/2 transition-colors ${darkMode ? 'text-gray-500 hover:text-white' : 'text-stone-400 hover:text-stone-700'}`}>
                                        {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                                    </button>
                                </div>
                            </div>

                            {/* Error */}
                            {error && (
                                <div className="flex items-center gap-2 text-red-400 text-sm bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-3 animate-fade-in">
                                    <Shield size={16} className="shrink-0" /><span>{error}</span>
                                </div>
                            )}

                            {/* Remember + Forgot */}
                            <div className="flex justify-between items-center">
                                <label className="flex items-center gap-2 cursor-pointer">
                                    <input type="checkbox" className="w-4 h-4 rounded border-gray-300 accent-amber-500" />
                                    <span className={`text-xs ${darkMode ? 'text-gray-500' : 'text-gray-400'}`}>จดจำฉัน</span>
                                </label>
                                <span className={`text-xs cursor-pointer hover:underline ${darkMode ? 'text-amber-500/70 hover:text-amber-400' : 'text-amber-700/70 hover:text-amber-700'}`}>
                                    ลืมรหัสผ่าน?
                                </span>
                            </div>

                            {/* Submit Button */}
                            <button type="submit" disabled={isLoading}
                                className="w-full font-bold py-3.5 rounded-xl transition-all duration-300 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2 group text-white shadow-lg hover:shadow-xl hover:scale-[1.01] active:scale-[0.99]"
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
                    </div>

                    {/* Footer */}
                    <div className="mt-6 text-center">
                        <p className={`text-xs ${darkMode ? 'text-gray-700' : 'text-stone-400'}`}>
                            ติดต่อผู้ดูแลระบบหากลืมรหัสผ่าน
                        </p>
                        <p className={`text-xs mt-2 ${darkMode ? 'text-gray-800' : 'text-stone-300'}`}>
                            © 2024 {appName}. All rights reserved.
                        </p>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default LoginPage;
