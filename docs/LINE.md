# LINE — แจ้งเตือน GoldenMole

ใช้ [LINE Messaging API](https://developers.line.biz/en/docs/messaging-api/) ส่งข้อความหลังบันทึกสำเร็จแบบออนไลน์ (เว็บ + แอปมือถือ)

เมนูที่แจ้งผ่าน Edge `notify-advance-line` (ผู้รับจาก `LINE_ADVANCE_NOTIFY_USER_IDS` / LINE User ID พนักงานตามเมนู):

| เมนู | ข้อความ |
|------|---------|
| เบิกเงิน | รายการเบิกเงิน |
| ลางาน | บันทึกลางาน |
| บำรุงรักษา | แจ้งซ่อม / บันทึกบำรุงรักษา |
| เช็คชื่อ | เช็คชื่อ · ท่าทราย / คนขับรถ |
| รถดรัม / จำนวนเที่ยว | สรุปรถและเที่ยว |

## สิ่งที่ต้องมี

1. **LINE Official Account** เปิดใช้ Messaging API ใน [LINE Developers Console](https://developers.line.biz/)
2. **Channel access token (long-lived)** — เก็บเป็น Edge secret **`LINE_CHANNEL_ACCESS_TOKEN`** (อย่าใส่ในโค้ดฝั่ง client)
3. **ผู้รับอย่างน้อยหนึ่งอย่าง**
   - **User ID** (`U` + 32 hex) — เพิ่มเพื่อน OA ก่อน
   - **Group ID** (`C` + 32 hex) — เชิญบอทเข้ากลุ่ม (แนะนำสำหรับทีม)
   - **Room ID** (`R` + 32 hex) — ห้องแชทหลายคน

## แจ้งเตือนในกลุ่ม LINE (แนะนำ)

### 1) เปิดให้บอทเข้ากลุ่มได้

1. เปิด [LINE Developers](https://developers.line.biz/) → Channel ของ OA
2. แท็บ **Messaging API**
3. เปิด **Allow bot to join group chats** (อนุญาตให้บอทเข้าร่วมแชทกลุ่ม)
4. (แนะนำ) ปิด **Auto-reply messages** / **Greeting messages** ถ้าไม่ต้องการบอทตอบทักทายรบกวนในกลุ่ม

### 2) เชิญบอทเข้ากลุ่ม

1. ในแอป LINE สร้างกลุ่ม (หรือใช้กลุ่มเดิม)
2. เพิ่มสมาชิก → ค้นหาบัญชีทางการ (OA) ของ GoldenMole → เชิญเข้ากลุ่ม
3. ยืนยันว่าบอทอยู่ในสมาชิกกลุ่มแล้ว

### 3) หา Group ID (`C…`)

Group ID **ไม่โชว์ในแอป LINE** — ได้จาก Webhook เมื่อมีอีเวนต์ในกลุ่ม

#### ลิงก์ Webhook เอามาจากไหน?

**ไม่ได้มาจาก LINE** — LINE ให้คุณกรอก URL ของเซิร์ฟเวอร์คุณเอง  
สำหรับโปรเจกต์ GoldenMole ใช้ Edge Function นี้:

```text
https://cocvespahjymyrvmqzcs.supabase.co/functions/v1/line-webhook
```

(รูปแบบทั่วไป: `https://<PROJECT_REF>.supabase.co/functions/v1/line-webhook`)

#### วิธีตั้งใน LINE Developers

1. เปิด [LINE Developers](https://developers.line.biz/) → Channel ของ OA → แท็บ **Messaging API**
2. ช่อง **Webhook URL** → วางลิงก์ด้านบน → **Update**
3. เปิด **Use webhook** = On
4. กด **Verify** ให้ขึ้น Success
5. (แนะนำ) ตั้ง secret `LINE_CHANNEL_SECRET` บน Supabase ให้ตรงกับ Channel secret ในแท็บ Basic

#### อ่าน Group ID หลังเชิญบอทเข้ากลุ่ม

1. เชิญ OA เข้ากลุ่ม แล้วให้ใครสักคน**พิมพ์ข้อความในกลุ่ม 1 ครั้ง**
2. เปิดลิงก์นี้ในเบราว์เซอร์ (GET):

```text
https://cocvespahjymyrvmqzcs.supabase.co/functions/v1/line-webhook
```

3. จะเห็น `groups[].id` ขึ้นต้นด้วย **`C`** — คัดลอกไปใส่ `LINE_ADVANCE_NOTIFY_USER_IDS`

ใน payload ดิบของ LINE จะมีประมาณนี้:

```json
{
  "events": [
    {
      "type": "message",
      "source": {
        "type": "group",
        "groupId": "Cxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
      }
    }
  ]
}
```

อีเวนต์ `join` / `memberJoined` ก็มี `groupId` เช่นกัน

Deploy webhook (ครั้งแรกหรือเมื่อแก้โค้ด):

```bash
npx supabase functions deploy line-webhook --project-ref cocvespahjymyrvmqzcs
npx supabase secrets set LINE_CHANNEL_SECRET=your_channel_secret
```

### 4) ใส่ Group ID ในระบบ

ใน `mobile-flutter/.env` (และเว็บ `.env` ถ้าใช้):

```env
# คนเดียว (U…) และ/หรือ กลุ่ม (C…) คั่นด้วย comma ได้
LINE_ADVANCE_NOTIFY_USER_IDS=Cxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

หรือรวมทั้งคนและกลุ่ม:

```env
LINE_ADVANCE_NOTIFY_USER_IDS=Uaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,Cbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
```

เว็บใช้ชื่อเดิม:

```env
VITE_LINE_ADVANCE_NOTIFY_USER_IDS=Cxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

จากนั้น:

- **มือถือ**: ต้อง build/ติดตั้งแอปใหม่ (ค่าอยู่ใน asset `.env`)
- **Edge**: deploy ฟังก์ชัน `notify-advance-line` รุ่นที่รองรับ Group ID แล้ว

```bash
npx supabase functions deploy notify-advance-line
```

### 5) ทดสอบส่งเข้ากลุ่ม

หลังใส่ Group ID แล้ว ให้บันทึกเมนูใดเมนูหนึ่ง หรือเรียกทดสอบ Edge ด้วย `to: ["C…"]` — ข้อความควรโผล่ในกลุ่ม

ถ้าได้ **403**: บอทยังไม่อยู่ในกลุ่ม หรือถูกเตะออก — เชิญเข้ากลุ่มใหม่  
ถ้าได้ **400**: Group ID ผิด หรือยังไม่ได้เปิด Allow bot to join group chats

---

## ในแอป GoldenMole

| ที่มา | รายละเอียด |
|--------|------------|
| **พนักงานในรายการเบิกเงิน/ลา** | ฟิลด์ **LINE User ID** ในโปรไฟล์ (`line_user_id`) — เฉพาะ `U…` |
| **ผู้ดูแล / กลุ่ม** | env **`VITE_LINE_ADVANCE_NOTIFY_USER_IDS`** (เว็บ) / **`LINE_ADVANCE_NOTIFY_USER_IDS`** (มือถือ) — `U…` / `C…` / `R…` คั่นด้วย comma |

## Supabase Edge Function `notify-advance-line`

- รับ `{ text, to: string[] }`
- **User (`U…`)**: `multicast` (fallback เป็น `push`)
- **Group (`C…`) / Room (`R…`)**: `push` ทีละ chat
- กรองเฉพาะ ID รูปแบบ `U|C|R` + hex 32 ตัว

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

## แก้ error 400 / 403

- **User**: มักเกิดจากยังไม่ได้เพิ่มเพื่อน OA หรือ User ID ไม่ตรง
- **Group**: บอทไม่อยู่ในกลุ่ม / ยังไม่เปิด Allow bot to join group chats / Group ID ผิด
- หน้า **ทดสอบ LINE** จะแสดงข้อความจาก LINE (`LINE: ...`) ถ้ามี ช่วยไล่สาเหตุได้เร็ว
