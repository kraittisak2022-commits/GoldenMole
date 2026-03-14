# GoldenMole

ระบบจัดการโครงการก่อสร้าง (Construction Management) สร้างด้วย React, TypeScript, และ Vite

## ฟีเจอร์หลัก

- 📊 Dashboard ภาพรวมและวิเคราะห์ข้อมูล
- 👥 จัดการพนักงานและค่าแรง
- 🚗 บันทึกการใช้รถ น้ำมัน ซ่อมบำรุง
- 💰 รายรับ-รายจ่าย โครงการที่ดิน
- 📅 บันทึกงานประจำวัน
- 🔐 ระบบแอดมิน (Login, SuperAdmin/Admin)

## การติดตั้ง

```bash
npm install
```

## การตั้งค่า

1. คัดลอก `.env.example` เป็น `.env`
2. กรอกค่า Supabase:

```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your_anon_key_here
```

3. สร้างตารางใน Supabase ตาม schema ที่ใช้ในโปรเจกต์ (employees, transactions, land_projects, app_settings, admin_users, admin_logs)

## รันพัฒนา

```bash
npm run dev
```

## Build สำหรับ Production

```bash
npm run build
```

## คำเตือนความปลอดภัย

⚠️ **ก่อนใช้งานจริง:**

1. **เปลี่ยนรหัสผ่านแอดมินเริ่มต้น** — บัญชี admin/1234 ต้องเปลี่ยนทันทีที่ deploy
2. **เปิด Row Level Security (RLS)** ใน Supabase Dashboard สำหรับทุกตาราง
3. **เก็บ Service Role Key เป็นความลับ** — ใช้เฉพาะฝั่ง backend เท่านั้น ห้ามใส่ใน frontend
4. เมนู **จัดการแอดมิน** แสดงเฉพาะบัญชีที่มีบทบาท **SuperAdmin**
