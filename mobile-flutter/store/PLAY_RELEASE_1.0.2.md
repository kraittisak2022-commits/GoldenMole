# GoldenMole for User — Play Store release 1.0.2 (3)

## ไฟล์อัปโหลด

| รายการ | ค่า |
|--------|-----|
| App Bundle | `mobile-flutter/build/app/outputs/bundle/release/app-release.aab` |
| Application ID | `com.goldenmole.app` |
| ชื่อแอพ | GoldenMole for User |
| versionName | **1.0.2** |
| versionCode | **3** |
| minSdk | 24 (Android 7.0+) |
| targetSdk | 36 |
| Signing | `android/upload-keystore.jks` (alias `upload`) |

Privacy policy: https://goldenmole.pro/privacy-policy-android.html

## ข้อความเวอร์ชันสำหรับ Play Console (ไทย)

**ชื่อรุ่น** (≤ 50 ตัวอักษร):

```
1.0.2 — UX มือถือ + โหมดมืด + แบรนด์ใหม่
```

**บันทึกประจำรุ่น** (What's new):

```
• ปรับ UX เมนูบันทึกประจำวันและหลายเมนูให้เหมาะกับมือถือแนวตั้ง
• เพิ่มโหมดมืด (สลับได้จากหน้าบันทึกประจำวัน)
• อัปเดตไอคอนแอป / โลโก้ / หน้าโหลดเปิดแอป และปรับหน้าเข้าสู่ระบบให้เป็นสไตล์มือถือ
• แก้ปัญหาเด้งตอนเปิดแอปที่เกี่ยวกับฟอนต์
• เอา popup สอนใช้งานหน้าบันทึกและนับจำนวนออก
```

## Soft update บนเซิร์ฟเวอร์

หลังอัปโหลดและเผยแพร่บน Play แล้ว ตั้งใน `app_settings.app_defaults`:

```json
{
  "androidLatestVersionCode": 3,
  "androidLatestVersionName": "1.0.2"
}
```

## Checklist ก่อนส่ง Play

- [ ] อัปโหลด `app-release.aab` เป็น production / internal testing
- [ ] ใส่บันทึกประจำรุ่นด้านบน
- [ ] ตรวจ Privacy Policy URL
- [ ] ตั้ง `androidLatestVersionCode` / `androidLatestVersionName` ใน Supabase หลังเผยแพร่
