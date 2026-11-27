# FlowAccount LandClerk — Design Spec

**Date:** 2026-11-27  
**App:** `apps/flowaccount`  
**Status:** Approved in conversation (approach A)

## Goal

ให้มีบัญชีผู้ใช้แยกสำหรับงานซื้อขายที่ดิน ที่ล็อกอิน FlowAccount ได้ แต่เห็นและใช้ได้เฉพาะโมดูลที่ดิน และส่งรายการเข้าคิวรอ SuperAdmin อนุมัติเท่านั้น

## Non-goals

- ลิงก์สาธารณะแบบไม่ล็อกอิน (`/land-submit/:token`) — ไม่ทำในรอบนี้
- แยก deploy เป็นแอปใหม่ (เช่น `land.goldenmole.pro`)
- Sync กับ Google Sheets / import ต.ค. 2569 — คนละงาน
- รวม `land_projects` (เว็บหลัก) เข้า UI ที่ดินในรอบนี้เกินที่มีอยู่แล้ว

## Decisions

| Topic | Choice |
|-------|--------|
| Architecture | สิทธิ์ใน FlowAccount เดิม (approach A) |
| Persona | `LandClerk` — login ได้ เห็นเฉพาะ `/land` |
| Clerk capability | สร้างรายการอย่างเดียว → คิวรอตรวจ |
| Admin capability | อนุมัติ / ปฏิเสธ / CRUD เต็ม |
| User provisioning | SuperAdmin สร้างใน FlowAccount (หน้าข้อมูลหลัก) |

## Auth & access

### Role

- เพิ่ม `LandClerk` ใน `AdminRole` (`session.ts` และจุดที่ union role ใช้ร่วมกันใน FlowAccount)
- Login ผ่าน `admin_users` เหมือนเดิม
- `canAccessSite(..., 'flowaccount')`:
  - `SuperAdmin` (ค่าเริ่มต้นเดิม)
  - หรือ `allowed_apps` รวม `'flowaccount'`
  - และ **`LandClerk` เข้าได้โดยค่าเริ่มต้น** (แม้ไม่มี `allowed_apps`)

### Session

- `FlowAccountSession.role` รองรับ `'LandClerk'`
- ไม่ต้องเพิ่มฟิลด์ session อื่นในรอบนี้

### Route & nav guards

- หลัง login สำเร็จ:
  - `LandClerk` → navigate ไป `/land` (ไม่ไป dashboard)
  - อื่นๆ → พฤติกรรมเดิม (`from` หรือ `/`)
- `RequireAuth` / wrapper ใหม่: ถ้า `role === 'LandClerk'` และ path ไม่ใช่ `/land` (และไม่ใช่ login) → redirect `/land`
- `AppShell`: แสดงเฉพาะเมนูซื้อขายที่ดิน (+ ปุ่มออกจากระบบ / ชื่อผู้ใช้) สำหรับ `LandClerk`

## Land deal workflow

### Status

เพิ่มสถานะ:

- `pending_review` — รอ SuperAdmin ตรวจ (สถานะเริ่มต้นเมื่อ `LandClerk` สร้าง)

สถานะเดิมคงไว้: `negotiating` | `deposited` | `transferred` | `cancelled`

### Clerk create

- ใช้ฟอร์มสร้างดีลที่มีอยู่ (`LandDealFormModal`) ในโหมดจำกัด:
  - บังคับ `status = pending_review` (ไม่ให้เลือกสถานะอื่น)
  - เซ็ต `createdBy` = session user id
- ไม่มีปุ่มแก้ไข / ลบ / เปลี่ยนสถานะ
- รายการที่เห็น: เฉพาะที่ `createdBy === self` (ทุกสถานะของรายการตัวเอง รวมหลังถูกอนุมัติแล้ว เพื่อติดตาม)

### SuperAdmin review

บน `/land` เมื่อแถวเป็น `pending_review`:

- ปุ่ม **อนุมัติ** → ตั้งสถานะเป็น `negotiating` (ค่าเริ่มต้นหลังอนุมัติ; แก้รายละเอียดก่อน/หลังได้ตาม CRUD เดิม)
- ปุ่ม **ปฏิเสธ** → ตั้งสถานะเป็น `cancelled` (optional หมายเหตุใน `notes`)
- CRUD เดิมทั้งตารางยังใช้ได้

### Data layer

- อัปเดต `LandDealStatus` + labels ใน `types.ts`
- `saveLandDeal` / `updateLandDealStatus` รับ `pending_review`
- SQL: อัปเดต check constraint / enum ของ `fa_land_deals.status` ให้รวม `pending_review` (ไฟล์ใน `apps/flowaccount/sql/`)
- `listLandDeals` สำหรับ clerk: filter `created_by = session.id` (ฝั่ง client หลัง fetch หรือ query filter — เลือก query filter ถ้า RLS ยังเปิดกว้าง)

## User provisioning UI

ใน `MastersPage` (หรือส่วนย่อยที่ชัดเจน):

- SuperAdmin เท่านั้นเห็นแท็บ/การ์ด **ผู้ใช้ที่ดิน**
- สร้าง: username, รหัสผ่าน, display name → insert `admin_users` ด้วย
  - `role = 'LandClerk'`
  - `allowed_apps = ['flowaccount']` (ถ้าคอลัมน์มีอยู่)
- รายการผู้ใช้ `LandClerk` ที่มีอยู่ + ปิดการใช้งานถ้ามีฟิลด์รองรับ (ถ้ายังไม่มี `inactive` ใน `admin_users` ให้ทำแค่สร้าง + แสดงรายการในรอบนี้)
- **ไม่** ให้ `LandClerk` เห็นหรือจัดการผู้ใช้

รหัสผ่านเก็บด้วยรูปแบบ hash เดียวกับระบบเดิม (`passwordAuth`)

## Security notes

- Guard เป็นฝั่ง UI + session; RLS ของ `fa_*` ยังเปิดกว้างอยู่ — ยอมรับความเสี่ยงเดิมของแอป แต่ต้องไม่โชว์/ไม่เรียก API ลบแก้จาก UI ของ clerk
- ข้อความ login เมื่อ role ไม่มีสิทธิ์: คงข้อความกลาง ไม่ enumerate username
- ไม่เปิด public land form ในรอบนี้

## Testing

- Unit: `AdminRole` / `canAccessSite` รวม `LandClerk`
- Auth: login เป็น `LandClerk` ได้; role อื่นที่ไม่มีสิทธิ์ยังถูกบล็อกตามเดิม
- UI: `LandClerk` ไม่เห็นเมนู ledger/payroll/…; เข้า `/` แล้วถูกพาไป `/land`
- Land page: clerk สร้างได้เฉพาะ `pending_review`; ไม่มีปุ่มลบ/แก้สถานะ
- SuperAdmin: อนุมัติ/ปฏิเสธ `pending_review` ได้
- Masters: สร้าง LandClerk ได้ (mock supabase)

## Acceptance criteria

1. สร้างบัญชี LandClerk จาก FlowAccount (SuperAdmin) ได้  
2. LandClerk ล็อกอินแล้วเห็นเฉพาะโมดูลที่ดิน  
3. LandClerk ส่งดีลใหม่เข้าสถานะรอตรวจได้  
4. SuperAdmin อนุมัติหรือปฏิเสธคิวได้  
5. LandClerk แก้/ลบ/เปลี่ยนสถานะดีลไม่ได้จาก UI  
6. เทสที่เกี่ยวข้องผ่าน  

## Out of scope follow-ups

- Feature-level RBAC ทั่วไป (`allowed_modules`) สำหรับหลายโมดูล  
- RLS เข้มต่อ `created_by`  
- Public intake link  
- Merge UI กับ `land_projects` เพิ่มเติม  
