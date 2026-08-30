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
| Env group | **`goldenmole_dashboard`** (ใช้ group เดียวกับ Dashboard) |

---

## ขั้นที่ 1 — Apple Developer: สร้าง App ID

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list) → **+**
2. **App IDs** → App
3. Description: `GoldenMole for User`
4. Bundle ID: **Explicit** → `com.goldenmole.app`
5. Register

## ขั้นที่ 2 — App Store Connect: สร้างแอป

1. [App Store Connect](https://appstoreconnect.apple.com/) → **My Apps** → **+**
2. Bundle ID: `com.goldenmole.app`
3. ชื่อ: `GoldenMole for User`
4. จด **Apple ID** ตัวเลขของแอป (App Information → Apple ID)

## ขั้นที่ 3 — Env group (ใช้ของเดิม)

ไม่ต้องสร้าง group ใหม่ — workflow User อ้าง **`goldenmole_dashboard`** อยู่แล้ว

ตัวแปรที่มีอยู่ใช้ร่วมได้:

| Variable | ใช้กับ |
|----------|--------|
| `SUPABASE_URL` | Dashboard + User |
| `SUPABASE_ANON_KEY` | Dashboard + User |
| `CERTIFICATE_PRIVATE_KEY` | Dashboard + User (cert ชุดเดียวกัน) |

เพิ่มใน group เดิม (แนะนำ):

| Variable | Secure | หมายเหตุ |
|----------|--------|----------|
| `USER_APP_STORE_APPLE_ID` | ไม่บังคับ | ตัวเลขจากขั้น 2 — ใช้เพิ่ม build number ของแอป User |

> อย่าใส่ Apple ID ของ Dashboard ลงตัวแปรนี้

## ขั้นที่ 4 — Start build

1. Push branch ที่มี `codemagic.yaml` อัปเดตแล้ว
2. Codemagic → แอป **GoldenMole** (ตัวเดิม) → **Start new build**
3. เลือก workflow **GoldenMole for User iOS**
4. รอ IPA + TestFlight (~15–30 นาที)

---

## Troubleshooting

| Error | แก้ |
|-------|-----|
| unknown variable group `goldenmole_user` | อัปเดต yaml ให้ใช้ `goldenmole_dashboard` แล้ว (pull main ล่าสุด) |
| Bundle ID not found | สร้าง App ID `com.goldenmole.app` บน Apple Developer |
| 409 Distribution certificate | ใช้ PEM เดิมใน `goldenmole_dashboard` — อย่า genrsa ใหม่ |
| Missing SUPABASE_* | ตรวจ group `goldenmole_dashboard` |

---

## ไฟล์ที่เกี่ยวข้อง

- `mobile-flutter/ios/` — Xcode / Flutter iOS project
- `codemagic.yaml` — workflow `goldenmole-user-ios`
- `docs/codemagic-setup.md` — Dashboard iOS
