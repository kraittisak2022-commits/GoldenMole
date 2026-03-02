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

        if (!username || !password) {
            setError('กรุณากรอกข้อมูลให้ครบ');
            triggerShake();
            return;
        }

        setIsLoading(true);

        // Simulate network delay for UX
        await new Promise(r => setTimeout(r, 800));

        const admin = admins.find(a => a.username === username && a.password === password);
        if (admin) {
            onLogin(admin);
        } else {
            setError('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
            triggerShake();
        }

        setIsLoading(false);
    };

    const triggerShake = () => {
        setShake(true);
        setTimeout(() => setShake(false), 600);
    };

    return (
        <div className={`min-h-screen min-h-[100dvh] flex items-center justify-center relative overflow-hidden transition-colors duration-500 ${darkMode ? 'bg-gray-950' : 'bg-gradient-to-br from-slate-50 via-white to-emerald-50'}`}>

            {/* Dark Mode Toggle */}
            <button
                onClick={onToggleDarkMode}
                className={`absolute top-6 right-6 z-20 p-3 rounded-xl transition-all shadow-lg ${darkMode
                    ? 'bg-gray-800 text-yellow-400 hover:bg-gray-700 border border-gray-700'
                    : 'bg-white text-slate-600 hover:bg-slate-50 border border-slate-200'
                    }`}
                title={darkMode ? 'เปลี่ยนเป็นโหมดสว่าง' : 'เปลี่ยนเป็นโหมดมืด'}
            >
                {darkMode ? <Sun size={20} /> : <Moon size={20} />}
            </button>

            {/* --- DARK MODE Background --- */}
            {darkMode && (
                <>
                    <div className="absolute inset-0 bg-gradient-to-br from-gray-950 via-gray-900 to-emerald-950" />
                    <div className="absolute inset-0 opacity-30">
                        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-emerald-500/20 rounded-full blur-3xl animate-float" />
                        <div className="absolute bottom-1/4 right-1/4 w-80 h-80 bg-blue-500/20 rounded-full blur-3xl animate-float" style={{ animationDelay: '2s' }} />
                        <div className="absolute top-1/2 left-1/2 w-64 h-64 bg-purple-500/15 rounded-full blur-3xl animate-float" style={{ animationDelay: '4s' }} />
                    </div>
                    <div className="absolute inset-0 opacity-[0.03]" style={{
                        backgroundImage: 'linear-gradient(rgba(255,255,255,0.1) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.1) 1px, transparent 1px)',
                        backgroundSize: '60px 60px'
                    }} />
                </>
            )}

            {/* --- LIGHT MODE Background --- */}
            {!darkMode && (
                <>
                    <div className="absolute inset-0 opacity-40">
                        <div className="absolute top-1/4 left-1/3 w-96 h-96 bg-emerald-200/40 rounded-full blur-3xl animate-float" />
                        <div className="absolute bottom-1/3 right-1/4 w-80 h-80 bg-blue-200/30 rounded-full blur-3xl animate-float" style={{ animationDelay: '2s' }} />
                        <div className="absolute top-1/2 right-1/3 w-64 h-64 bg-purple-200/20 rounded-full blur-3xl animate-float" style={{ animationDelay: '4s' }} />
                    </div>
                    <div className="absolute inset-0 opacity-[0.02]" style={{
                        backgroundImage: 'linear-gradient(rgba(0,0,0,0.05) 1px, transparent 1px), linear-gradient(90deg, rgba(0,0,0,0.05) 1px, transparent 1px)',
                        backgroundSize: '60px 60px'
                    }} />
                </>
            )}

            {/* Login Card */}
            <div className={`relative z-10 w-full max-w-md mx-4 ${shake ? 'animate-shake' : ''}`}>
                {/* Glass Card */}
                <div className={`backdrop-blur-xl rounded-3xl shadow-2xl p-8 sm:p-10 border transition-colors duration-300 ${darkMode
                    ? 'bg-white/10 border-white/20'
                    : 'bg-white/80 border-slate-200/60 shadow-slate-200/50'
                    }`}>
                    {/* Logo & Branding */}
                    <div className="text-center mb-8">
                        <div className={`w-20 h-20 mx-auto mb-5 rounded-2xl flex items-center justify-center shadow-lg transform hover:scale-105 transition-transform overflow-hidden ${darkMode
                            ? 'bg-gradient-to-br from-emerald-400 to-emerald-600 shadow-emerald-500/30'
                            : 'bg-gradient-to-br from-emerald-500 to-emerald-700 shadow-emerald-500/20'
                            }`}>
                            {appIcon.startsWith('http') || appIcon.startsWith('data:') ? (
                                <img src={appIcon} alt="Logo" className="w-full h-full object-cover" />
                            ) : (
                                <span className="text-white text-2xl font-bold">{appIcon}</span>
                            )}
                        </div>
                        <h1 className={`text-2xl sm:text-3xl font-bold mb-1 ${darkMode ? 'text-white' : 'text-slate-800'}`}>{appName}</h1>
                        <p className={`text-sm ${darkMode ? 'text-emerald-300/70' : 'text-emerald-600/70'}`}>ระบบจัดการโครงการ</p>
                    </div>

                    {/* Login Form */}
                    <form onSubmit={handleSubmit} className="space-y-5">
                        {/* Username */}
                        <div className="relative group">
                            <div className={`absolute left-4 top-1/2 -translate-y-1/2 transition-colors ${darkMode ? 'text-slate-400 group-focus-within:text-emerald-400' : 'text-slate-400 group-focus-within:text-emerald-500'}`}>
                                <User size={18} />
                            </div>
                            <input
                                type="text"
                                placeholder="ชื่อผู้ใช้ (Username)"
                                value={username}
                                onChange={(e) => setUsername(e.target.value)}
                                className={`w-full rounded-xl pl-12 pr-4 py-3.5 focus:outline-none transition-all ${darkMode
                                    ? 'bg-white/5 border border-white/10 text-white placeholder:text-slate-500 focus:border-emerald-400/50 focus:bg-white/10 focus:ring-2 focus:ring-emerald-400/20'
                                    : 'bg-slate-50 border border-slate-200 text-slate-800 placeholder:text-slate-400 focus:border-emerald-500 focus:bg-white focus:ring-2 focus:ring-emerald-500/20'
                                    }`}
                                autoComplete="username"
                            />
                        </div>

                        {/* Password */}
                        <div className="relative group">
                            <div className={`absolute left-4 top-1/2 -translate-y-1/2 transition-colors ${darkMode ? 'text-slate-400 group-focus-within:text-emerald-400' : 'text-slate-400 group-focus-within:text-emerald-500'}`}>
                                <Lock size={18} />
                            </div>
                            <input
                                type={showPassword ? 'text' : 'password'}
                                placeholder="รหัสผ่าน (Password)"
                                value={password}
                                onChange={(e) => setPassword(e.target.value)}
                                className={`w-full rounded-xl pl-12 pr-12 py-3.5 focus:outline-none transition-all ${darkMode
                                    ? 'bg-white/5 border border-white/10 text-white placeholder:text-slate-500 focus:border-emerald-400/50 focus:bg-white/10 focus:ring-2 focus:ring-emerald-400/20'
                                    : 'bg-slate-50 border border-slate-200 text-slate-800 placeholder:text-slate-400 focus:border-emerald-500 focus:bg-white focus:ring-2 focus:ring-emerald-500/20'
                                    }`}
                                autoComplete="current-password"
                            />
                            <button
                                type="button"
                                onClick={() => setShowPassword(!showPassword)}
                                className={`absolute right-4 top-1/2 -translate-y-1/2 transition-colors ${darkMode ? 'text-slate-400 hover:text-white' : 'text-slate-400 hover:text-slate-700'}`}
                            >
                                {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                            </button>
                        </div>

                        {/* Error Message */}
                        {error && (
                            <div className="flex items-center gap-2 text-red-400 text-sm bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-3 animate-fade-in">
                                <Shield size={16} className="shrink-0" />
                                <span>{error}</span>
                            </div>
                        )}

                        {/* Submit Button */}
                        <button
                            type="submit"
                            disabled={isLoading}
                            className="w-full bg-gradient-to-r from-emerald-500 to-emerald-600 hover:from-emerald-400 hover:to-emerald-500 text-white font-bold py-3.5 rounded-xl shadow-lg shadow-emerald-500/25 hover:shadow-emerald-500/40 transition-all duration-300 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2 group"
                        >
                            {isLoading ? (
                                <>
                                    <Loader2 size={20} className="animate-spin" />
                                    <span>กำลังตรวจสอบ...</span>
                                </>
                            ) : (
                                <>
                                    <Lock size={18} className="group-hover:scale-110 transition-transform" />
                                    <span>เข้าสู่ระบบ</span>
                                </>
                            )}
                        </button>
                    </form>

                    {/* Footer hint */}
                    <div className="mt-6 text-center">
                        <p className={`text-xs ${darkMode ? 'text-slate-500' : 'text-slate-400'}`}>ติดต่อผู้ดูแลระบบหากลืมรหัสผ่าน</p>
                    </div>
                </div>

                {/* Bottom branding */}
                <div className="text-center mt-6">
                    <p className={`text-xs ${darkMode ? 'text-slate-500' : 'text-slate-400'}`}>© 2024 {appName}. All rights reserved.</p>
                </div>
            </div>
        </div>
    );
};

export default LoginPage;
