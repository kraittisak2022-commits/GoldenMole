import type { ClientErrorCode } from './api';
import { errorCode } from './api';

const MESSAGES: Record<ClientErrorCode | 'upload_expired' | 'upload_failed', string> = {
  bad_request: 'ข้อมูลไม่ถูกต้อง',
  unauthorized: 'กรุณาเข้าสู่ระบบใหม่',
  forbidden: 'บัญชีนี้ไม่มีสิทธิ์ใช้งานระบบอัลบั้มรูป',
  not_found: 'ไม่พบอัลบั้มนี้ หรือลิงก์ถูกเปลี่ยนแล้ว',
  bad_credentials: 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง',
  drive_not_connected: 'ยังไม่ได้เชื่อมต่อ Google Drive ให้ผู้ดูแลระบบเชื่อมต่อในหน้าตั้งค่า',
  drive_error: 'Google Drive ตอบกลับผิดพลาด ลองใหม่อีกครั้ง',
  upload_disabled: 'อัลบั้มนี้ปิดการเพิ่มรูปผ่านลิงก์แล้ว',
  bad_type: 'รองรับเฉพาะไฟล์รูปภาพและวิดีโอ',
  too_large: 'ไฟล์ใหญ่เกินไป (รูปไม่เกิน 50 MB วิดีโอไม่เกิน 2 GB)',
  empty_file: 'ไฟล์ว่างเปล่า',
  rate_limited: 'อัปโหลดถี่เกินไป ลองใหม่ภายหลัง',
  wrong_folder: 'ไฟล์ไม่ได้อยู่ในโฟลเดอร์ของอัลบั้มนี้',
  not_configured: 'ระบบยังตั้งค่าไม่ครบ (ตัวแปรบนเซิร์ฟเวอร์)',
  pin_required: 'ใส่ PIN เพื่อดูอัลบั้มนี้',
  bad_pin: 'PIN ไม่ถูกต้อง',
  too_many_attempts: 'ลองผิดหลายครั้งเกินไป ระบบล็อกไว้ชั่วคราว รอ 15 นาทีแล้วลองใหม่',
  server_error: 'เกิดข้อผิดพลาด ลองใหม่อีกครั้ง',
  network: 'เชื่อมต่ออินเทอร์เน็ตไม่ได้',
  upload_expired: 'ลิงก์อัปโหลดหมดอายุ กดลองใหม่',
  upload_failed: 'อัปโหลดไม่สำเร็จ',
};

export function messageFor(code: keyof typeof MESSAGES): string {
  return MESSAGES[code] ?? MESSAGES.server_error;
}

export function errorMessage(err: unknown): string {
  return messageFor(errorCode(err));
}
