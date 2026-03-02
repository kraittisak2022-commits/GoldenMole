import { useState } from 'react';
import { Shield, Pencil, Key, Trash2, XCircle, Clock, UserPlus, ShieldCheck, Search, History } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import { AdminUser, AdminLog } from '../../types';

interface AdminModuleProps {
    admins: AdminUser[];
    setAdmins: (admins: AdminUser[]) => void;
    currentAdmin: AdminUser;
    logs: AdminLog[];
    addLog: (action: string, details: string) => void;
}

const AdminModule = ({ admins, setAdmins, currentAdmin, logs, addLog }: AdminModuleProps) => {
    const [activeTab, setActiveTab] = useState<'list' | 'logs'>('list');
    const [showCreateModal, setShowCreateModal] = useState(false);
    const [showEditModal, setShowEditModal] = useState<AdminUser | null>(null);
    const [showPasswordModal, setShowPasswordModal] = useState<AdminUser | null>(null);
    const [search, setSearch] = useState('');
    const [logSearch, setLogSearch] = useState('');

    // Create form
    const [createForm, setCreateForm] = useState({ username: '', password: '', confirmPassword: '', displayName: '', role: 'Admin' as 'SuperAdmin' | 'Admin' });
    // Edit form
    const [editForm, setEditForm] = useState({ displayName: '', role: 'Admin' as 'SuperAdmin' | 'Admin' });
    // Password form
    const [passwordForm, setPasswordForm] = useState({ newPassword: '', confirmPassword: '' });

    const handleCreate = () => {
        if (!createForm.username || !createForm.password || !createForm.displayName) return alert('กรุณากรอกข้อมูลให้ครบ');
        if (createForm.password !== createForm.confirmPassword) return alert('รหัสผ่านไม่ตรงกัน');
        if (admins.some(a => a.username === createForm.username)) return alert('ชื่อผู้ใช้ซ้ำ');

        const newAdmin: AdminUser = {
            id: Date.now().toString(),
            username: createForm.username,
            password: createForm.password,
            displayName: createForm.displayName,
            role: createForm.role,
            createdAt: new Date().toISOString().split('T')[0],
        };
        setAdmins([...admins, newAdmin]);
        addLog('create_admin', `สร้างแอดมินใหม่: ${newAdmin.displayName} (@${newAdmin.username})`);
        setCreateForm({ username: '', password: '', confirmPassword: '', displayName: '', role: 'Admin' });
        setShowCreateModal(false);
    };

    const handleEdit = () => {
        if (!showEditModal || !editForm.displayName) return;
        const updated = admins.map(a => a.id === showEditModal.id ? { ...a, displayName: editForm.displayName, role: editForm.role } : a);
        setAdmins(updated);
        addLog('edit_admin', `แก้ไขข้อมูล: ${showEditModal.displayName} → ${editForm.displayName}`);
        setShowEditModal(null);
    };

    const handleChangePassword = () => {
        if (!showPasswordModal || !passwordForm.newPassword) return;
        if (passwordForm.newPassword !== passwordForm.confirmPassword) return alert('รหัสผ่านไม่ตรงกัน');
        const updated = admins.map(a => a.id === showPasswordModal.id ? { ...a, password: passwordForm.newPassword } : a);
        setAdmins(updated);
        addLog('change_password', `เปลี่ยนรหัสผ่าน: ${showPasswordModal.displayName}`);
        setPasswordForm({ newPassword: '', confirmPassword: '' });
        setShowPasswordModal(null);
    };

    const handleDelete = (admin: AdminUser) => {
        if (admin.id === currentAdmin.id) return alert('ไม่สามารถลบตัวเองได้');
        if (!confirm(`ยืนยันลบ "${admin.displayName}"?`)) return;
        setAdmins(admins.filter(a => a.id !== admin.id));
        addLog('delete_admin', `ลบแอดมิน: ${admin.displayName} (@${admin.username})`);
    };

    const openEditModal = (admin: AdminUser) => {
        setEditForm({ displayName: admin.displayName, role: admin.role });
        setShowEditModal(admin);
    };

    const filteredAdmins = admins.filter(a => a.displayName.toLowerCase().includes(search.toLowerCase()) || a.username.toLowerCase().includes(search.toLowerCase()));
    const filteredLogs = logs.filter(l => l.action.includes(logSearch) || l.details.includes(logSearch) || l.adminName.includes(logSearch));

    return (
        <div className="space-y-6 animate-fade-in">
            {/* Tab Switcher */}
            <div className="flex justify-center">
                <div className="bg-white p-1 rounded-xl shadow-sm flex gap-1">
                    <button onClick={() => setActiveTab('list')} className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all ${activeTab === 'list' ? 'bg-slate-800 text-white' : 'text-slate-500 hover:bg-slate-50'}`}>
                        <Shield size={16} /> จัดการสมาชิก
                    </button>
                    <button onClick={() => setActiveTab('logs')} className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all ${activeTab === 'logs' ? 'bg-slate-800 text-white' : 'text-slate-500 hover:bg-slate-50'}`}>
                        <History size={16} /> ประวัติการใช้งาน
                    </button>
                </div>
            </div>

            {activeTab === 'list' ? (
                <>
                    {/* Admin Stats */}
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                        <Card className="p-5 flex items-center gap-4">
                            <div className="w-12 h-12 rounded-xl bg-emerald-50 flex items-center justify-center"><Shield className="text-emerald-600" size={24} /></div>
                            <div><p className="text-2xl font-bold text-slate-800">{admins.length}</p><p className="text-xs text-slate-500">แอดมินทั้งหมด</p></div>
                        </Card>
                        <Card className="p-5 flex items-center gap-4">
                            <div className="w-12 h-12 rounded-xl bg-purple-50 flex items-center justify-center"><ShieldCheck className="text-purple-600" size={24} /></div>
                            <div><p className="text-2xl font-bold text-slate-800">{admins.filter(a => a.role === 'SuperAdmin').length}</p><p className="text-xs text-slate-500">SuperAdmin</p></div>
                        </Card>
                        <Card className="p-5 flex items-center gap-4">
                            <div className="w-12 h-12 rounded-xl bg-blue-50 flex items-center justify-center"><Clock className="text-blue-600" size={24} /></div>
                            <div><p className="text-2xl font-bold text-slate-800">{logs.length}</p><p className="text-xs text-slate-500">กิจกรรมทั้งหมด</p></div>
                        </Card>
                    </div>

                    {/* Toolbar */}
                    <Card className="p-3 sm:p-4 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
                        <div className="relative w-full sm:w-64">
                            <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="ค้นหาแอดมิน..." className="w-full pl-9 pr-4 py-2 text-sm border rounded-lg focus:outline-none focus:border-emerald-400 focus:ring-1 focus:ring-emerald-400/30" />
                        </div>
                        <Button onClick={() => setShowCreateModal(true)} className="flex items-center gap-2 whitespace-nowrap">
                            <UserPlus size={16} /> เพิ่มแอดมิน
                        </Button>
                    </Card>

                    {/* Admin List */}
                    <div className="grid grid-cols-1 gap-3">
                        {filteredAdmins.map(admin => (
                            <Card key={admin.id} className={`p-4 sm:p-5 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 ${admin.id === currentAdmin.id ? 'ring-2 ring-emerald-200' : ''}`}>
                                <div className="flex items-center gap-4">
                                    <div className="w-12 h-12 rounded-full bg-gradient-to-br from-slate-700 to-slate-900 flex items-center justify-center text-white font-bold text-lg shrink-0">
                                        {admin.displayName.charAt(0)}
                                    </div>
                                    <div>
                                        <div className="flex items-center gap-2 flex-wrap">
                                            <h4 className="font-bold text-lg text-slate-800">{admin.displayName}</h4>
                                            <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${admin.role === 'SuperAdmin' ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'}`}>
                                                {admin.role}
                                            </span>
                                            {admin.id === currentAdmin.id && (
                                                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-700">คุณ</span>
                                            )}
                                        </div>
                                        <p className="text-sm text-slate-500">@{admin.username}</p>
                                        <p className="text-xs text-slate-400 mt-0.5">สร้างเมื่อ {admin.createdAt}{admin.lastLogin ? ` • เข้าใช้ล่าสุด: ${admin.lastLogin}` : ''}</p>
                                    </div>
                                </div>
                                <div className="flex gap-2 shrink-0">
                                    <button onClick={() => openEditModal(admin)} className="p-2 hover:bg-slate-100 rounded-lg text-slate-400 hover:text-slate-700 transition-colors" title="แก้ไข">
                                        <Pencil size={16} />
                                    </button>
                                    <button onClick={() => { setPasswordForm({ newPassword: '', confirmPassword: '' }); setShowPasswordModal(admin); }} className="p-2 hover:bg-amber-50 rounded-lg text-slate-400 hover:text-amber-600 transition-colors" title="เปลี่ยนรหัส">
                                        <Key size={16} />
                                    </button>
                                    <button onClick={() => handleDelete(admin)} className="p-2 hover:bg-red-50 rounded-lg text-slate-400 hover:text-red-500 transition-colors" title="ลบ" disabled={admin.id === currentAdmin.id}>
                                        <Trash2 size={16} />
                                    </button>
                                </div>
                            </Card>
                        ))}
                    </div>
                </>
            ) : (
                /* Activity Logs Tab */
                <Card className="p-0 overflow-hidden">
                    <div className="p-3 sm:p-4 bg-slate-50 border-b flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2">
                        <h3 className="font-bold flex items-center gap-2"><Clock size={18} /> ประวัติการใช้งาน (Activity Log)</h3>
                        <div className="relative w-full sm:w-48">
                            <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                            <input value={logSearch} onChange={e => setLogSearch(e.target.value)} placeholder="ค้นหา..." className="w-full pl-8 pr-3 py-1.5 text-xs border rounded-lg focus:outline-none focus:border-emerald-400" />
                        </div>
                    </div>
                    <div className="max-h-[600px] overflow-y-auto overflow-x-auto">
                        <table className="w-full text-sm text-left min-w-[500px]">
                            <thead className="bg-white sticky top-0 border-b">
                                <tr>
                                    <th className="p-3 sm:p-4 text-slate-500 font-medium">เวลา</th>
                                    <th className="p-3 sm:p-4 text-slate-500 font-medium">ผู้ดำเนินการ</th>
                                    <th className="p-3 sm:p-4 text-slate-500 font-medium">การดำเนินการ</th>
                                    <th className="p-3 sm:p-4 text-slate-500 font-medium">รายละเอียด</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y">
                                {filteredLogs.length === 0 ? (
                                    <tr><td colSpan={4} className="p-8 text-center text-slate-400">ไม่มีประวัติ</td></tr>
                                ) : (
                                    filteredLogs.map(log => (
                                        <tr key={log.id} className="hover:bg-slate-50">
                                            <td className="p-3 sm:p-4 whitespace-nowrap text-slate-500 text-xs">{log.timestamp}</td>
                                            <td className="p-3 sm:p-4 whitespace-nowrap">
                                                <span className="font-medium text-slate-700">{log.adminName}</span>
                                            </td>
                                            <td className="p-3 sm:p-4">
                                                <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${log.action === 'login' ? 'bg-emerald-100 text-emerald-700' :
                                                    log.action === 'logout' ? 'bg-slate-100 text-slate-700' :
                                                        log.action === 'create_admin' ? 'bg-blue-100 text-blue-700' :
                                                            log.action === 'delete_admin' ? 'bg-red-100 text-red-700' :
                                                                log.action === 'change_password' ? 'bg-amber-100 text-amber-700' :
                                                                    'bg-purple-100 text-purple-700'
                                                    }`}>
                                                    {log.action === 'login' ? 'เข้าสู่ระบบ' :
                                                        log.action === 'logout' ? 'ออกจากระบบ' :
                                                            log.action === 'create_admin' ? 'สร้างแอดมิน' :
                                                                log.action === 'delete_admin' ? 'ลบแอดมิน' :
                                                                    log.action === 'change_password' ? 'เปลี่ยนรหัส' :
                                                                        log.action === 'edit_admin' ? 'แก้ไขข้อมูล' : log.action}
                                                </span>
                                            </td>
                                            <td className="p-3 sm:p-4 text-slate-600">{log.details}</td>
                                        </tr>
                                    ))
                                )}
                            </tbody>
                        </table>
                    </div>
                </Card>
            )}

            {/* Create Admin Modal */}
            {showCreateModal && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-[110] p-4">
                    <Card className="w-full max-w-md p-6 relative animate-slide-up">
                        <button onClick={() => setShowCreateModal(false)} className="absolute top-4 right-4 text-slate-400 hover:text-slate-600"><XCircle /></button>
                        <h3 className="text-lg font-bold mb-6 flex items-center gap-2"><UserPlus className="text-emerald-500" size={20} /> เพิ่มแอดมินใหม่</h3>
                        <div className="space-y-4">
                            <Input label="ชื่อที่แสดง (Display Name)" value={createForm.displayName} onChange={(e: any) => setCreateForm({ ...createForm, displayName: e.target.value })} placeholder="เช่น Admin สมชาย" />
                            <Input label="ชื่อผู้ใช้ (Username)" value={createForm.username} onChange={(e: any) => setCreateForm({ ...createForm, username: e.target.value })} placeholder="ตัวอักษรภาษาอังกฤษ" />
                            <Input label="รหัสผ่าน" type="password" value={createForm.password} onChange={(e: any) => setCreateForm({ ...createForm, password: e.target.value })} />
                            <Input label="ยืนยันรหัสผ่าน" type="password" value={createForm.confirmPassword} onChange={(e: any) => setCreateForm({ ...createForm, confirmPassword: e.target.value })} />
                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">บทบาท (Role)</label>
                                <div className="flex gap-3">
                                    <button onClick={() => setCreateForm({ ...createForm, role: 'Admin' })} className={`flex-1 px-4 py-2.5 rounded-lg border text-sm font-medium transition-all ${createForm.role === 'Admin' ? 'bg-blue-50 border-blue-300 text-blue-700' : 'bg-white'}`}>Admin</button>
                                    <button onClick={() => setCreateForm({ ...createForm, role: 'SuperAdmin' })} className={`flex-1 px-4 py-2.5 rounded-lg border text-sm font-medium transition-all ${createForm.role === 'SuperAdmin' ? 'bg-purple-50 border-purple-300 text-purple-700' : 'bg-white'}`}>SuperAdmin</button>
                                </div>
                            </div>
                            <Button onClick={handleCreate} className="w-full mt-2">สร้างแอดมิน</Button>
                        </div>
                    </Card>
                </div>
            )}

            {/* Edit Admin Modal */}
            {showEditModal && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-[110] p-4">
                    <Card className="w-full max-w-md p-6 relative animate-slide-up">
                        <button onClick={() => setShowEditModal(null)} className="absolute top-4 right-4 text-slate-400 hover:text-slate-600"><XCircle /></button>
                        <h3 className="text-lg font-bold mb-6 flex items-center gap-2"><Pencil className="text-blue-500" size={20} /> แก้ไขข้อมูล: {showEditModal.username}</h3>
                        <div className="space-y-4">
                            <Input label="ชื่อที่แสดง" value={editForm.displayName} onChange={(e: any) => setEditForm({ ...editForm, displayName: e.target.value })} />
                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">บทบาท (Role)</label>
                                <div className="flex gap-3">
                                    <button onClick={() => setEditForm({ ...editForm, role: 'Admin' })} className={`flex-1 px-4 py-2.5 rounded-lg border text-sm font-medium transition-all ${editForm.role === 'Admin' ? 'bg-blue-50 border-blue-300 text-blue-700' : 'bg-white'}`}>Admin</button>
                                    <button onClick={() => setEditForm({ ...editForm, role: 'SuperAdmin' })} className={`flex-1 px-4 py-2.5 rounded-lg border text-sm font-medium transition-all ${editForm.role === 'SuperAdmin' ? 'bg-purple-50 border-purple-300 text-purple-700' : 'bg-white'}`}>SuperAdmin</button>
                                </div>
                            </div>
                            <Button onClick={handleEdit} className="w-full mt-2">บันทึก</Button>
                        </div>
                    </Card>
                </div>
            )}

            {/* Change Password Modal */}
            {showPasswordModal && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-[110] p-4">
                    <Card className="w-full max-w-md p-6 relative animate-slide-up">
                        <button onClick={() => setShowPasswordModal(null)} className="absolute top-4 right-4 text-slate-400 hover:text-slate-600"><XCircle /></button>
                        <h3 className="text-lg font-bold mb-6 flex items-center gap-2"><Key className="text-amber-500" size={20} /> เปลี่ยนรหัสผ่าน: {showPasswordModal.displayName}</h3>
                        <div className="space-y-4">
                            <Input label="รหัสผ่านใหม่" type="password" value={passwordForm.newPassword} onChange={(e: any) => setPasswordForm({ ...passwordForm, newPassword: e.target.value })} />
                            <Input label="ยืนยันรหัสผ่านใหม่" type="password" value={passwordForm.confirmPassword} onChange={(e: any) => setPasswordForm({ ...passwordForm, confirmPassword: e.target.value })} />
                            <Button onClick={handleChangePassword} className="w-full mt-2">เปลี่ยนรหัสผ่าน</Button>
                        </div>
                    </Card>
                </div>
            )}
        </div>
    );
};

export default AdminModule;
