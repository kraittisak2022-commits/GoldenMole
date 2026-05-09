# LINE — แจ้งเตือนการเบิกเงิน (GoldenMole)

ใช้ [LINE Messaging API](https://developers.line.biz/en/docs/messaging-api/) ส่งข้อความหลังบันทึก **Labor → Advance (เบิกเงิน)** สำเร็จแบบออนไลน์ (เว็บ + แอปมือถือ)

## สิ่งที่ต้องมี

1. **LINE Official Account** เปิดใช้ Messaging API ใน [LINE Developers Console](https://developers.line.biz/)
2. **Channel access token (long-lived)** — เก็บเป็น Edge secret **`LINE_CHANNEL_ACCESS_TOKEN`** (อย่าใส่ในโค้ดฝั่ง client)
3. **LINE userId** ของผู้รับ — ผู้ใช้ต้อง **เพิ่มเพื่อน OA** ก่อน แล้วได้ `userId` (ขึ้นต้นด้วย `U` + 32 ตัว hex) จาก Webhook หรือ LINE Login

## ในแอป GoldenMole

| ที่มา | รายละเอียด |
|--------|------------|
| **พนักงานในรายการเบิกเงิน** | ฟิลด์ **LINE User ID** ในโปรไฟล์พนักงาน (`line_user_id` ในฐานข้อมูล) |
| **เพิ่มเติม** | ตัวแปร env: **`VITE_LINE_ADVANCE_NOTIFY_USER_IDS`** (เว็บ) / **`LINE_ADVANCE_NOTIFY_USER_IDS`** (มือถือ) — หลายค่าคั่นด้วย comma |

## Supabase Edge Function `notify-advance-line`

- รับ `{ text, to: string[] }` แล้วเรียก `POST https://api.line.me/v2/bot/message/multicast` แบ่งชุดละ 150 คน
- กรองเฉพาะ `userId` รูปแบบ `U` + 32 hex

### การยืนยันตัวตน (เลือกอย่างใดอย่างหนึ่ง)

1. **แนะนำ — Shared secret (ไม่ต้องเปิด Anonymous)**  
   - ตั้ง secret บนโปรเจกต์: `NOTIFY_ADVANCE_INVOKER_SECRET` (สตริงยาวสุ่ม อย่า commit ลง git)  
   - เว็บ: ใน `.env` ใส่ `VITE_NOTIFY_ADVANCE_INVOKER_SECRET` ให้**ตรงค่าเดียวกัน**  
   - มือถือ: ใน `mobile-flutter/.env` ใส่ `NOTIFY_ADVANCE_INVOKER_SECRET` ให้**ตรงค่าเดียวกัน**  
   - ฟังก์ชันใช้ `verify_jwt = false` ใน `supabase/config.toml` และตรวจ header `x-cm-notify-advance-secret` บน Edge

2. **ทางเลือก — Anonymous sign-in**  
   - Dashboard → Authentication → Providers → **Anonymous** → Enable  
   - แอปจะสร้าง JWT แบบ anonymous ก่อนเรียกฟังก์ชัน (เมื่อไม่ได้ตั้งค่า secret ตามข้อ 1)

### Deploy & secrets

จากรากโปรเจกต์:

```bash
npx supabase functions deploy notify-advance-line
npx supabase secrets set LINE_CHANNEL_ACCESS_TOKEN=your_channel_access_token
npx supabase secrets set NOTIFY_ADVANCE_INVOKER_SECRET=your_long_random_secret
```

### Migration คอลัมน์พนักงาน

รัน migration ใน repo (`supabase/migrations/..._add_employees_line_user_id.sql`) บนโปรเจกต์ของคุณ (Dashboard → SQL หรือ `supabase db push`)

### Channel access token vs Channel secret

- ต้องใช้ **Channel access token** (แท็บ Messaging API → Issue / long-lived) ใน secret `LINE_CHANNEL_ACCESS_TOKEN`
- **Channel secret** (แท็บ Basic — มักเป็น hex 32 ตัว) ใช้ยืนยัน webhook ไม่ใช่ส่งข้อความ — ถ้าใส่ผิด ฟังก์ชันจะตอบ `token_looks_like_channel_secret` พร้อมข้อความภาษาไทย
- ข้อความยาวสูงสุดตามที่ LINE นับเป็น **UTF-16** ไม่เกิน 5000 code units (ฟังก์ชันจะตัดให้อัตโนมัติ)

## แก้ error 400

- **LINE HTTP 400** มักเกิดจากผู้รับ **ยังไม่ได้เพิ่มเพื่อน OA** หรือ User ID ไม่ตรงกับบัญชีที่เป็นเพื่อน — ลองข้อความสั้น ๆ แล้วส่งใหม่
- หน้า **ทดสอบ LINE** จะแสดงข้อความจาก LINE (`LINE: ...`) ถ้ามี ช่วยไล่สาเหตุได้เร็ว
