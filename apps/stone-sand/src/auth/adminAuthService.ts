import { hasSupabaseConfig, supabase } from '../lib/supabase';
import { verifyStoredPassword } from './passwordAuth';
import { canAccessSite } from './siteAccess';
import type { AdminRole, StoneSandSession } from './session';

export type SignInErrorCode =
  | 'missing_config'
  | 'empty_fields'
  | 'user_not_found'
  | 'bad_password'
  | 'forbidden_role'
  | 'network';

export class SignInError extends Error {
  readonly code: SignInErrorCode;

  constructor(code: SignInErrorCode, message: string) {
    super(message);
    this.name = 'SignInError';
    this.code = code;
  }
}

interface AdminUserRow {
  id: string;
  username: string;
  password: string;
  display_name: string;
  role: AdminRole;
  allowed_apps: string[] | null;
}

const normalizeUsername = (raw: string) =>
  raw
    .normalize('NFKC')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();

export async function signInWithAdminUsers(
  username: string,
  password: string,
): Promise<StoneSandSession> {
  const u = username.trim();
  if (!u || !password) {
    throw new SignInError('empty_fields', 'กรุณากรอกชื่อผู้ใช้และรหัสผ่าน');
  }
  if (!hasSupabaseConfig) {
    throw new SignInError(
      'missing_config',
      'ยังไม่ได้ตั้งค่าการเชื่อมต่อฐานข้อมูล (ขาด VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY) — สร้างไฟล์ apps/stone-sand/.env แล้วรีสตาร์ท หรือใส่ env บน Vercel แล้ว Redeploy',
    );
  }

  const normalized = normalizeUsername(u);
  const { data, error } = await supabase
    .from('admin_users')
    .select('id, username, password, display_name, role, allowed_apps')
    .ilike('username', normalized)
    .maybeSingle();

  if (error) {
    throw new SignInError('network', `เชื่อมต่อฐานข้อมูลไม่ได้ (${error.message})`);
  }

  const row = data as AdminUserRow | null;
  if (!row || normalizeUsername(row.username) !== normalized) {
    throw new SignInError('user_not_found', 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
  }

  const ok = await verifyStoredPassword(row.password, password);
  if (!ok) {
    throw new SignInError('bad_password', 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
  }

  if (!canAccessSite(row, 'order')) {
    throw new SignInError('forbidden_role', 'บัญชีนี้ไม่มีสิทธิ์เข้าใช้ระบบออเดอร์');
  }

  return {
    id: row.id,
    username: row.username,
    displayName: row.display_name,
    role: row.role,
    loginAt: new Date().toISOString(),
  };
}

/** `allowed` is false only when the account is gone or lost access; a failed request keeps the session (role unknown). */
export async function checkSession(id: string): Promise<{ allowed: boolean; role?: AdminRole }> {
  if (!hasSupabaseConfig) return { allowed: true };
  const { data, error } = await supabase.from('admin_users').select('role, allowed_apps').eq('id', id).maybeSingle();
  if (error) return { allowed: true };
  const row = data as Pick<AdminUserRow, 'role' | 'allowed_apps'> | null;
  return row ? { allowed: canAccessSite(row, 'order'), role: row.role } : { allowed: false };
}
