import { useState } from 'react';
import { Lock, User, Eye, EyeOff, Shield, Loader2 } from 'lucide-react';
import { AdminUser } from '../../types';

interface LoginPageProps {
    admins: AdminUser[];
    onLogin: (admin: AdminUser) => void;
    appName: string;
    appIcon: string;
}

const LoginPage = ({ admins, onLogin, appName, appIcon }: LoginPageProps) => {
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
        <div className="min-h-screen min-h-[100dvh] flex items-center justify-center relative overflow-hidden login-bg">
            {/* Animated Background */}
            <div className="absolute inset-0 bg-gradient-to-br from-slate-900 via-slate-800 to-emerald-900" />
            <div className="absolute inset-0 opacity-30">
                <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-emerald-500/20 rounded-full blur-3xl animate-float" />
                <div className="absolute bottom-1/4 right-1/4 w-80 h-80 bg-blue-500/20 rounded-full blur-3xl animate-float" style={{ animationDelay: '2s' }} />
                <div className="absolute top-1/2 left-1/2 w-64 h-64 bg-purple-500/15 rounded-full blur-3xl animate-float" style={{ animationDelay: '4s' }} />
            </div>

            {/* Grid pattern overlay */}
            <div className="absolute inset-0 opacity-[0.03]" style={{
                backgroundImage: 'linear-gradient(rgba(255,255,255,0.1) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.1) 1px, transparent 1px)',
                backgroundSize: '60px 60px'
            }} />

            {/* Login Card */}
            <div className={`relative z-10 w-full max-w-md mx-4 ${shake ? 'animate-shake' : ''}`}>
                {/* Glass Card */}
                <div className="backdrop-blur-xl bg-white/10 border border-white/20 rounded-3xl shadow-2xl p-8 sm:p-10">
                    {/* Logo & Branding */}
                    <div className="text-center mb-8">
                        <div className="w-20 h-20 mx-auto mb-5 bg-gradient-to-br from-emerald-400 to-emerald-600 rounded-2xl flex items-center justify-center shadow-lg shadow-emerald-500/30 transform hover:scale-105 transition-transform overflow-hidden">
                            {appIcon.startsWith('http') || appIcon.startsWith('data:') ? (
                                <img src={appIcon} alt="Logo" className="w-full h-full object-cover" />
                            ) : (
                                <span className="text-white text-2xl font-bold">{appIcon}</span>
                            )}
                        </div>
                        <h1 className="text-2xl sm:text-3xl font-bold text-white mb-1">{appName}</h1>
                        <p className="text-emerald-300/70 text-sm">ระบบจัดการโครงการ</p>
                    </div>

                    {/* Login Form */}
                    <form onSubmit={handleSubmit} className="space-y-5">
                        {/* Username */}
                        <div className="relative group">
                            <div className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-emerald-400 transition-colors">
                                <User size={18} />
                            </div>
                            <input
                                type="text"
                                placeholder="ชื่อผู้ใช้ (Username)"
                                value={username}
                                onChange={(e) => setUsername(e.target.value)}
                                className="w-full bg-white/5 border border-white/10 rounded-xl pl-12 pr-4 py-3.5 text-white placeholder:text-slate-500 focus:outline-none focus:border-emerald-400/50 focus:bg-white/10 focus:ring-2 focus:ring-emerald-400/20 transition-all"
                                autoComplete="username"
                            />
                        </div>

                        {/* Password */}
                        <div className="relative group">
                            <div className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-emerald-400 transition-colors">
                                <Lock size={18} />
                            </div>
                            <input
                                type={showPassword ? 'text' : 'password'}
                                placeholder="รหัสผ่าน (Password)"
                                value={password}
                                onChange={(e) => setPassword(e.target.value)}
                                className="w-full bg-white/5 border border-white/10 rounded-xl pl-12 pr-12 py-3.5 text-white placeholder:text-slate-500 focus:outline-none focus:border-emerald-400/50 focus:bg-white/10 focus:ring-2 focus:ring-emerald-400/20 transition-all"
                                autoComplete="current-password"
                            />
                            <button
                                type="button"
                                onClick={() => setShowPassword(!showPassword)}
                                className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400 hover:text-white transition-colors"
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
                        <p className="text-slate-500 text-xs">ติดต่อผู้ดูแลระบบหากลืมรหัสผ่าน</p>
                    </div>
                </div>

                {/* Bottom branding */}
                <div className="text-center mt-6">
                    <p className="text-slate-500 text-xs">© 2024 {appName}. All rights reserved.</p>
                </div>
            </div>
        </div>
    );
};

export default LoginPage;
