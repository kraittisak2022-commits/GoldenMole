import { hasSupabaseConfig, supabase } from '../lib/supabase';
import { verifyStoredPassword } from './passwordAuth';
import type { AdminRole, FlowAccountSession } from './session';

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
): Promise<FlowAccountSession> {
  const u = username.trim();
  const p = password;
  if (!u || !p) {
    throw new SignInError('empty_fields', 'กรุณากรอกชื่อผู้ใช้และรหัสผ่าน');
  }
  if (!hasSupabaseConfig) {
    throw new SignInError(
      'missing_config',
      'ยังไม่ได้ตั้งค่าการเชื่อมต่อฐานข้อมูล (ขาด VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY) — ถ้าใช้ localhost ให้สร้างไฟล์ apps/flowaccount/.env แล้วรีสตาร์ท npm run dev; ถ้าอยู่บน Vercel ให้ใส่ env ในโปรเจกต์ goldenmole-flowaccount แล้ว Redeploy',
    );
  }

  const normalized = normalizeUsername(u);
  const { data, error } = await supabase
    .from('admin_users')
    .select('id, username, password, display_name, role')
    .ilike('username', normalized)
    .maybeSingle();

  if (error) {
    throw new SignInError('network', `เชื่อมต่อฐานข้อมูลไม่ได้ (${error.message})`);
  }

  const row = data as AdminUserRow | null;
  if (!row || normalizeUsername(row.username) !== normalized) {
    // Prefer generic message to avoid username enumeration in UI; tests check codes.
    throw new SignInError('user_not_found', 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
  }

  const ok = await verifyStoredPassword(row.password, p);
  if (!ok) {
    throw new SignInError('bad_password', 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
  }

  if (row.role !== 'SuperAdmin') {
    throw new SignInError('forbidden_role', 'บัญชีนี้ไม่มีสิทธิ์เข้าใช้ FlowAccount');
  }

  return {
    id: row.id,
    username: row.username,
    displayName: row.display_name,
    role: row.role,
    loginAt: new Date().toISOString(),
  };
}
