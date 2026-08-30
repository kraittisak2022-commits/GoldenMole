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

## ขั้นที่ 4 — TestFlight Test Information (ครั้งเดียว ก่อนส่ง external / beta review)

เปิด: [TestFlight → Test Information](https://appstoreconnect.apple.com/apps/6806747374/testflight/test-info)

กรอกให้ครบ:

| ช่อง | ตัวอย่าง |
|------|----------|
| **Feedback Email** | อีเมลรับฟีดแบ็กจากเทสเตอร์ |
| **First Name** | ชื่อผู้ติดต่อ Beta Review |
| **Last Name** | นามสกุล |
| **Phone Number** | เบอร์ติดต่อ (มีรหัสประเทศ) |
| **Email** | อีเมลผู้ติดต่อ |

หลังกรอกแล้ว ถ้าต้องการให้ Codemagic ส่งเข้า beta review อัตโนมัติ ให้ตั้งใน `codemagic.yaml`:

```yaml
submit_to_testflight: true
```

ตอนนี้ค่าเริ่มต้นเป็น `false` = **อัปโหลด IPA สำเร็จแล้วจบ** (ใช้ Internal Testing ได้โดยไม่ต้อง beta review)

## ขั้นที่ 5 — Start build

1. Push / ใช้ `main` ล่าสุด
2. Codemagic → แอป **GoldenMole** → **Start new build**
3. เลือก workflow **GoldenMole for User iOS**
4. หลัง build สำเร็จ → App Store Connect → **TestFlight** → Internal Testing → เพิ่มเทสเตอร์

Apple ID แอป User: **`6806747374`** · Bundle: `com.goldenmole.app`

---

## Troubleshooting

| Error | แก้ |
|-------|-----|
| Complete test information / Feedback Email | กรอกขั้นที่ 4 แล้วค่อย `submit_to_testflight: true` หรือใช้ Internal Testing |
| Cannot determine Apple ID from Bundle ID | สร้างแอป ASC ด้วย Bundle `com.goldenmole.app` |
| Bundle ID เป็น AltStore / อื่น | แก้หรือสร้างแอปใหม่ให้เป็น `com.goldenmole.app` |
| unknown variable group `goldenmole_user` | ใช้ group `goldenmole_dashboard` แล้ว |
| 409 Distribution certificate | ใช้ PEM เดิมใน `goldenmole_dashboard` |
| Missing SUPABASE_* | ตรวจ group `goldenmole_dashboard` |

---

## ไฟล์ที่เกี่ยวข้อง

- `mobile-flutter/ios/` — Xcode / Flutter iOS project
- `codemagic.yaml` — workflow `goldenmole-user-ios`
- `docs/codemagic-setup.md` — Dashboard iOS
