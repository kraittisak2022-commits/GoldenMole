# SMSOK + เบิกเงิน (GoldenMole)

อ้างอิง API ส่ง SMS: [SMSOK API — POST /s](https://developer.smsok.co/#tag/sms/POST/s)  
Base URL ฝั่งผู้ให้บริการ: `https://api.smsok.co`

## สิ่งที่โปรเจกต์นี้ทำ

1. **Supabase Edge Function `send-advance-sms`** — รับ `{ text, destinations[] }` จากแอป (หลังล็อกอิน), เรียก `POST https://api.smsok.co/s` ด้วย **HTTP Basic** จาก secrets  
2. **Supabase Edge Function `smsok-dlr-webhook`** — รับ callback สถานะการส่ง (DLR) ถ้าตั้ง `callback_url` ตอนส่ง SMS  
3. **เว็บ + มือถือ** — หลังบันทึกรายการ **เบิกเงิน** (Labor / Advance) สำเร็จแบบออนไลน์ จะ `invoke` ฟังก์ชันข้อ 1 (ไม่บล็อก UX ถ้า SMS ล้ม)

### เช็กลิสต์ให้ SMS ออกจริง

1. ตั้ง **Supabase secrets** + **deploy** ฟังก์ชัน `send-advance-sms` (ดูด้านล่าง)  
2. ใส่ **เบอร์ในโปรไฟล์พนักงาน** (`phone`) หรือตั้ง **`VITE_SMS_ADVANCE_NOTIFY_EXTRA` / `SMS_ADVANCE_NOTIFY_EXTRA`** ใน `.env`  
3. บันทึกรายการ **Labor → Advance** แบบออนไลน์ — ระบบจะรวมเบอร์แล้วส่งให้ Edge แปลงเป็น JSON แบบ SMSOK (`destinations`) ให้เอง

รายละเอียดว่าเบอร์มาจากไหน → ดูหัวข้อ **เบอร์ปลายทางส่ง SMS ระบุยังไง** ด้านล่าง

## Webhook URL (ให้ตั้งใน SMSOK / หรือส่งผ่าน API)

| จุดประสงค์ | URL |
|-----------|-----|
| **DLR / สถานะ (โดเมนโปรดักชัน)** | `https://goldenmole.pro/sms/callback` — Serverless ที่ `api/sms/callback.ts` + rewrite ใน `vercel.json` |
| **DLR / สถานะ (Supabase Edge)** | `https://<project-ref>.supabase.co/functions/v1/smsok-dlr-webhook` |

### Webhook ใช้ GET หรือ POST?

- **แนะนำให้เลือก `POST`** ในฟอร์ม SMSOK (และให้ตรงกับ `callback_method: POST` ตาม [เอกสาร SMSOK](https://developer.smsok.co/#tag/sms/POST/s)) — สถานะการส่งมักส่งเป็น **JSON ใน body** ซึ่งเหมาะกับ POST  
- ฟังก์ชัน **`smsok-dlr-webhook`** รองรับทั้ง **POST** (body JSON หรือ text) และ **GET** (อ่านพารามิเตอร์จาก query string แล้ว log) — ถ้าฝั่ง SMSOK ตั้งเป็น GET อย่างเดียวก็ยังเรียก URL นี้ได้ แต่โครงข้อมูลจะอยู่บน query แทน body

ตั้งค่าใน Supabase (แนะนำ):

- Secret **`SMSOK_CALLBACK_URL`** = URL รับ DLR ที่ต้องการ เช่น **`https://goldenmole.pro/sms/callback`** หรือ URL ของ Edge `smsok-dlr-webhook`  
  Edge `send-advance-sms` จะส่งไปที่ SMSOK เป็น `callback_url` + `callback_method: POST` อัตโนมัติ

หรือจะไม่ใช้ callback ก็ได้ — ลบ secret `SMSOK_CALLBACK_URL` ออก แล้วฟังก์ชันจะไม่ส่ง `callback_url` ไปที่ SMSOK

### ความปลอดภัยเสริม (ทางเลือก)

- Secret **`SMSOK_WEBHOOK_SECRET`** — ถ้าตั้งแล้ว ฟังก์ชัน `smsok-dlr-webhook` จะต้องได้รับ header **`x-smsok-webhook-secret`** ตรงกับค่าที่ตั้ง (ใช้เมื่อคุณมี reverse proxy หรือต้องการกันเรียกปลอม)  
- **หมายเหตุ:** เอกสารสาธารณะของ SMSOK ที่ดึงมาในรอบนี้ **ไม่ระบุรายการ IP ต้นทางของ callback** — ถ้า SMSOK มีเมนู “IP Whitelist” สำหรับ URL ปลายทางหรือสำหรับผู้เรียก API ให้ใช้ตามคู่มือล่าสุดจาก SMSOK หรือสอบถามผู้ให้บริการโดยตรง

## IP Whitelist (สรุปสำหรับทีมโครงสร้าง)

- **ถ้า SMSOK ให้ whitelist IP ของ “เซิร์ฟเวอร์ที่เรียก API ส่ง SMS”**  
  คำขอออกจาก **Supabase Edge (region ของโปรเจกต์)** — IP อาจไม่คงที่ระหว่างผู้ให้บริการ ควรยืนยันกับ [Supabase](https://supabase.com/docs) / แดชบอร์ดโปรเจกต์ หรือขอรายการจาก SMSOK ว่ารองรับแบบไดนามิกหรือไม่  

- **ถ้าโครงสร้างของคุณ whitelist “เฉพาะ IP ที่ยิงเข้า Webhook ของเรา”**  
  ต้องใช้รายการ IP **ฝั่ง SMSOK ที่มายิง `smsok-dlr-webhook`** — รายการนี้ไม่ได้อยู่ใน snippet เอกสาร API ด้านบน ต้องได้จาก SMSOK โดยตรง  

แนวทางทั่วไป: เปิด endpoint เป็น **HTTPS เท่านั้น** + ใช้ **`SMSOK_WEBHOOK_SECRET`** + จำกัดขนาด body / log เพื่อตรวจสอบย้อนหลัง

## Secrets ที่ต้องตั้งใน Supabase (Edge)

| Secret | ความหมาย |
|--------|-----------|
| `SMSOK_API_USER` | ชื่อผู้ใช้ API สำหรับ **HTTP Basic** ตาม [SMSOK](https://developer.smsok.co/#tag/sms/POST/s) (มักเป็นอีเมลบัญชี — **ไม่ใช่** API Key ยาวๆ ยกเว้น SMSOK ระบุให้ใช้แบบอื่น) |
| `SMSOK_API_PASSWORD` | รหัสผ่าน API (Basic) |
| `SMSOK_SENDER_ID` | Sender ID ที่ลงทะเบียนกับ SMSOK แล้ว (case-sensitive) |
| `SMSOK_CALLBACK_URL` | (ทางเลือก) เช่น `https://goldenmole.pro/sms/callback` |
| `SMSOK_WEBHOOK_SECRET` | (ทางเลือก) ถ้าตั้ง ให้ SMSOK ส่ง header `x-smsok-webhook-secret` ตรงกับค่านี้ (ตั้งคู่กับ Vercel ได้) |

ค่า `SUPABASE_URL` และ `SUPABASE_ANON_KEY` มีให้ใน runtime ของ Edge อยู่แล้ว

## Vercel (`goldenmole.pro`) — `/sms/callback`

- โค้ด: `api/sms/callback.ts`  
- Rewrite: `vercel.json` แมป **`/sms/callback` → `/api/sms/callback`**  
- ตั้ง env บน Vercel: **`SMSOK_WEBHOOK_SECRET`** (แนะนำ) — ถ้ามีค่า ระบบจะต้องได้รับ header **`x-smsok-webhook-secret`** ตรงกันทุกครั้งที่ SMSOK ยิงเข้ามา  
- ดู log ได้ที่ Vercel → Functions → `api/sms/callback`

> **ความปลอดภัย:** อย่า commit รหัสผ่าน / API Secret ลง Git ตั้งเฉพาะใน Vercel และ Supabase secrets หากเคยแชร์รหัสในที่สาธารณะ ควร **เปลี่ยนรหัสและหมุน API Key** ที่ SMSOK

## Deploy

รันจาก **รากโปรเจกต์** (`construction-management-app` — โฟลเดอร์ที่มี `supabase/config.toml`)  
ถ้าเทอร์มินัลอยู่ที่ `...\construction-management-app\supabase` อยู่แล้ว **อย่า** `cd supabase` ซ้ำ (จะหา path `supabase\supabase` ไม่เจอ)

```bash
npx supabase login
npx supabase functions deploy send-advance-sms
npx supabase functions deploy smsok-dlr-webhook
npx supabase secrets set SMSOK_API_USER=... SMSOK_API_PASSWORD=... SMSOK_SENDER_ID=...
# ทางเลือก:
npx supabase secrets set SMSOK_CALLBACK_URL=https://goldenmole.pro/sms/callback
# หรือ URL ของ Edge smsok-dlr-webhook
```

ถ้าติดตั้ง CLI แบบ global แล้ว ใช้คำสั่ง `supabase` แทน `npx supabase` ได้

### ตั้ง Edge secrets (ถ้าไม่อยากใช้ CLI)

ใน [Supabase Dashboard](https://supabase.com/dashboard) → โปรเจกต์ของคุณ → **Project Settings** → **Edge Functions** → **Secrets**  
เพิ่มชื่อตามตาราง **Secrets ที่ต้องตั้งใน Supabase (Edge)** ด้านบน (อย่างน้อย `SMSOK_API_USER`, `SMSOK_API_PASSWORD`, `SMSOK_SENDER_ID`)

ถ้าไม่ตั้ง SMSOK ฟังก์ชันจะตอบ `503` พร้อมข้อความว่า credentials ยังไม่ครบ

## ทดสอบส่ง SMS (สคริปต์)

จากรากโปรเจกต์ ตั้งค่าชั่วคราวใน `.env` (อย่า commit):

- `SMS_TEST_EMAIL`, `SMS_TEST_PASSWORD` — บัญชี Supabase Auth ที่ล็อกอินได้
- `SMS_TEST_DEST` — เบอร์ทดสอบ (คั่นด้วย comma ได้)

แล้วรัน:

```bash
npm run test:sms
```

สคริปต์จะ `signInWithPassword` แล้ว `invoke('send-advance-sms')` เหมือนแอป ต้อง deploy ฟังก์ชัน + ตั้ง secrets SMSOK บนโปรเจกต์นั้นแล้ว ถึงจะส่งถึง SMSOK ได้จริง

## เบอร์ปลายทางส่ง SMS ระบุยังไง

ระบบ GoldenMole **ไม่ให้คุณพิมพ์เบอร์ในโค้ดที่เรียก SMSOK โดยตรง** แต่รวบรวมเบอร์แล้วส่งเป็น `destinations` ไปที่ Edge `send-advance-sms` — ฝั่ง Edge จะแปลงเป็นรูปแบบ SMSOK คือ `destinations: [{ "destination": "0996512409" }, ...]` (เบอร์ไทยหลัง normalize เป็น `0xxxxxxxxx`)

| แหล่งที่มา | รายละเอียด |
|------------|------------|
| **พนักงานในรายการเบิกเงิน** | หลังบันทึก **Labor → Advance (เบิกเงิน)** สำเร็จ ระบบดึงฟิลด์ **เบอร์โทร (`phone`)** ของพนักงานทุกคนที่เลือกในรายการนั้น มาเป็นปลายทาง (ซ้ำจะถูกรวมเป็นคนละเบอร์) |
| **เบอร์เสริม (ทางเลือก)** | ตั้งใน `.env` ตามตารางด้านล่าง — ใช้เมื่ออยากแจ้งหัวหน้างาน / เลขา โดยไม่ต้องใส่เป็นพนักงานในรายการ |

รูปแบบเบอร์: ใส่ `0812345678`, `+66812345678` หรือ `66812345678` ได้ — โค้ดจะ normalize เป็นเลขไทย 10 หลักขึ้นต้นด้วย `0` ก่อนส่ง

**ขีดจำกัด:** ฟังก์ชัน `send-advance-sms` ส่งได้สูงสุด **25** เบอร์ต่อครั้ง (หลังตัดซ้ำแล้ว; ถ้าเกินจะเอาเฉพาะ 25 เบอร์แรกตามลำดับที่ส่งมา)

**ไม่เรียก `https://api.smsok.co/s` จากเบราว์เซอร์หรือแอปมือถือโดยตรง** (จะเปิดรหัส API และโดเมน CORS) — แอปเรียก `supabase.functions.invoke('send-advance-sms', { body: { text, destinations } })` แล้วให้ Edge ใส่ **HTTP Basic** (username:password แปลง Base64) เรียก SMSOK แทน ตัวอย่างในเอกสาร SMSOK ที่ใช้ `Authorization: 'Basic username:password'` เป็นแนวคิดเท่านั้น ของจริงต้องเป็น `Basic <base64(user:pass)>`

## ตัวแปรแอป (เบอร์แจ้งเตือมเพิ่ม)

- **เว็บ (Vite):** `.env` — `VITE_SMS_ADVANCE_NOTIFY_EXTRA` = เบอร์เพิ่ม (คั่นด้วย comma) นอกเหนือจากเบอร์ใน employee
- **มือถือ:** `.env` — `SMS_ADVANCE_NOTIFY_EXTRA` (รูปแบบเดียวกัน)

ถ้าไม่มีเบอร์ใน employee และไม่ตั้ง extra ระบบจะไม่ส่ง SMS (ไม่ error)

### แอนดรอยด์ — ดู log เมื่อไม่มี SMS

ฟังก์ชัน `notifyAdvanceSmsAfterSave` จะเขียน log แท็ก **`GoldenMole.advance_sms`** (ดูใน Android Studio / `adb logcat` หรือ DevTools) เช่น

- `skip: no valid phone` → ต้องใส่เบอร์ในโปรไฟล์พนักงาน หรือ `SMS_ADVANCE_NOTIFY_EXTRA` ใน `mobile-flutter/.env`
- `invoke failed status=503` → ยังไม่ตั้ง secrets SMSOK บน Supabase Edge
- `invoke failed status=401` → เซสชันล็อกอินหมดอายุ ให้ล็อกอินใหม่
