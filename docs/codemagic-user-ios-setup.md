# Codemagic setup — GoldenMole for User iOS (Flutter)

คู่มือ build แอปผู้ใช้ (`mobile-flutter`) ขึ้น TestFlight จาก Windows ผ่าน [codemagic.io](https://codemagic.io/)  
แยกจากแอป Dashboard (`com.goldenmole.dashboard`) — ดู `docs/codemagic-setup.md`

## สิ่งที่ตั้งใน repo แล้ว

| รายการ | ค่า |
|--------|-----|
| โฟลเดอร์ | `mobile-flutter/ios/` |
| Bundle ID | `com.goldenmole.app` |
| Display name | GoldenMole for User |
| Workflow | `goldenmole-user-ios` |
| Preview | `goldenmole-user-ios-preview` |
| Integration | `codemagic` (ร่วมกับ Dashboard) |
| Env group | `goldenmole_user` |

---

## ขั้นที่ 1 — Apple Developer: สร้าง App ID

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list) → **+**
2. **App IDs** → App
3. Description: `GoldenMole for User`
4. Bundle ID: **Explicit** → `com.goldenmole.app`
5. Capabilities: เปิดอย่างน้อย **Associated Domains** ไม่จำเป็นตอนนี้ — ค่าเริ่มต้นพอ
6. Register

## ขั้นที่ 2 — App Store Connect: สร้างแอป

1. [App Store Connect](https://appstoreconnect.apple.com/) → **My Apps** → **+**
2. Bundle ID: `com.goldenmole.app`
3. ชื่อ: `GoldenMole for User`
4. จด **Apple ID** ตัวเลขของแอป (App Information → Apple ID) → ใส่เป็น `APP_STORE_APPLE_ID` ใน Codemagic

## ขั้นที่ 3 — Codemagic env group `goldenmole_user`

Team / แอป → **Environment variables** → group **`goldenmole_user`**:

| Variable | Secure | หมายเหตุ |
|----------|--------|----------|
| `SUPABASE_URL` | ใช่ | เดียวกับแอป Android / `.env` |
| `SUPABASE_ANON_KEY` | ใช่ | เดียวกับแอป Android |
| `CERTIFICATE_PRIVATE_KEY` | ใช่ | **ใช้ PEM เดียวกับ Dashboard ได้** (Distribution cert ชุดเดียวกัน) |
| `APP_STORE_APPLE_ID` | ไม่บังคับ secure | ตัวเลขจากขั้น 2 — ใช้เพิ่ม build number + TestFlight |
| `LINE_ADVANCE_NOTIFY_USER_IDS` | ใช่ (ถ้ามี) | optional |
| `NOTIFY_ADVANCE_INVOKER_SECRET` | ใช่ (ถ้ามี) | optional |

Integration `codemagic` (ASC API key) ตั้งไว้แล้วถ้าเคย build Dashboard — ไม่ต้องสร้างใหม่

> Apple จำกัด Distribution cert ≈ 3 ใบ — **อย่ารัน `openssl genrsa` ใหม่** ถ้า Dashboard ใช้อยู่แล้ว ให้ copy `CERTIFICATE_PRIVATE_KEY` จาก group `goldenmole_dashboard` มาใส่ `goldenmole_user`

## ขั้นที่ 4 — Start build

1. Push branch ที่มี `mobile-flutter/ios/` + `codemagic.yaml` อัปเดตแล้ว
2. Codemagic → แอป GoldenMole → **Start new build**
3. เลือก workflow **GoldenMole for User iOS**
4. รอ IPA + TestFlight (~15–30 นาที)

Preview ในเบราว์เซอร์: workflow **GoldenMole for User iOS (Simulator Preview)**

---

## Troubleshooting

| Error | แก้ |
|-------|-----|
| Bundle ID not found | สร้าง App ID `com.goldenmole.app` บน Apple Developer |
| 409 Distribution certificate | ลบ Distribution cert เก่าที่ไม่ใช้ / ใช้ PEM เดิมของ Dashboard |
| Missing SUPABASE_* | ใส่ใน group `goldenmole_user` และผูก group กับ workflow |
| TestFlight submit fail | ตรวจว่าสร้างแอปใน ASC แล้ว และ `APP_STORE_APPLE_ID` ถูกต้อง |
| Integration `codemagic` not found | ดูขั้น API key ใน `docs/codemagic-setup.md` |

---

## ไฟล์ที่เกี่ยวข้อง

- `mobile-flutter/ios/` — Xcode / Flutter iOS project
- `codemagic.yaml` — workflow `goldenmole-user-ios`
- `docs/codemagic-setup.md` — Dashboard iOS (อ้างอิง signing / API key)
