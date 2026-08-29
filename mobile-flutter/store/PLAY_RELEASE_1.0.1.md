# GoldenMole for User — Play Store release 1.0.1 (2)

## ไฟล์อัปโหลด

| รายการ | ค่า |
|--------|-----|
| App Bundle | `mobile-flutter/build/app/outputs/bundle/release/app-release.aab` |
| Application ID | `com.goldenmole.app` |
| ชื่อแอพ | GoldenMole for User |
| versionName | **1.0.1** |
| versionCode | **2** |
| minSdk | 24 (Android 7.0+) |
| targetSdk | 36 |
| Signing | `android/upload-keystore.jks` (alias `upload`) |

Privacy policy: https://goldenmole.pro/privacy-policy-android.html

## ข้อความเวอร์ชันสำหรับ Play Console (ไทย)

**ชื่อรุ่น** (≤ 50 ตัวอักษร):

```
1.0.1 — บันทึกงาน + แจ้งอัปเดต
```

**บันทึกประจำรุ่น** (What\'s new):

```
• ปรับปรุงเมนูบันทึกการทำงาน: รวมกล่องงานทั่วไป และรายละเอียดงานเพิ่มได้หลายรายการในกล่องเดียวกัน
• แจ้งเตือนเมื่อมีเวอร์ชันใหม่บน Play Store (อัปเดตได้โดยไม่บังคับ)
• ปรับปรุงป้ายชื่อประเภทงานให้อ่านง่าย ไม่โชว์รหัสระบบ
• แก้จุดบกพร่องเล็กน้อยและปรับเสถียรภาพ
```

## Soft update บนเซิร์ฟเวอร์

หลังอัปโหลดและเผยแพร่บน Play แล้ว ตั้งใน `app_settings.app_defaults`:

```json
{
  "androidLatestVersionCode": 2,
  "androidLatestVersionName": "1.0.1"
}
```

## Checklist ก่อนส่ง Play

- [ ] อัปโหลด `app-release.aab` เป็น production / internal testing
- [ ] ใส่บันทึกประจำรุ่นด้านบน
- [ ] ตรวจ Privacy Policy URL
- [ ] ตั้ง `androidLatestVersionCode` / `androidLatestVersionName` ใน Supabase หลังเผยแพร่
