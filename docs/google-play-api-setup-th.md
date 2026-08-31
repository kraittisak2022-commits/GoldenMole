# ตั้งค่า Google Play API (GoldenMole for User)

คู่มือครั้งเดียวสำหรับให้ Fastlane อัปโหลด AAB ไป **การทดสอบแบบปิด** ได้อัตโนมัติ

แอป: **GoldenMole for User** · `com.goldenmole.app`

---

## ภาพรวม (3 ส่วน)

```
Play Console (เว็บ)     →  สร้าง Service Account + ให้สิทธิ์
Google Cloud (เว็บ)    →  ดาวน์โหลด JSON key
เครื่องคุณ (local)    →  เก็บ JSON + สร้าง .env.play + ทดสอบ
```

---

## ขั้นที่ 1 — เปิด API access ใน Play Console

1. เปิด [Google Play Console](https://play.google.com/console)
2. เลือกแอป **GoldenMole for User**
3. ไป **การตั้งค่า (Setup)** → **การเข้าถึง API (API access)**
4. ถ้ายังไม่ได้เชื่อม Google Cloud:
   - กด **เชื่อมโยง (Link)** หรือ **สร้างโปรเจกต์ใหม่**
   - รอสักครู่จนสถานะเป็น **เชื่อมแล้ว**

---

## ขั้นที่ 2 — สร้าง Service Account

### 2a) จากหน้า API access ใน Play Console

1. ในส่วน **Service accounts** กด **Create new service account**
2. จะเปิด Google Cloud Console — กด **Create service account**
3. ตั้งชื่อ เช่น `goldenmole-play-upload`
4. กด **Create and continue** → **Done** (ไม่ต้องใส่ role ใน Cloud ก็ได้ — สิทธิ์จริงมาจาก Play Console)

### 2b) กลับมา Play Console → Grant access

1. กลับหน้า **API access** → กด **Refresh** / **Grant access** ที่ service account ที่สร้าง
2. แท็บ **Account permissions**:
   - เปิด **View app information** (ดูข้อมูลแอป)
   - เปิด **Manage testing track releases** หรือ **Release to testing tracks**
   - หรือเลือก preset **Release manager** (แนะนำ)
3. แท็บ **App permissions**:
   - เลือกแอป **GoldenMole for User** (`com.goldenmole.app`)
4. กด **Invite user** / **Apply** / **Save**

> ถ้าให้สิทธิ์ไม่ครบ จะเจอ error `403` ตอนอัปโหลด

---

## ขั้นที่ 3 — ดาวน์โหลด JSON key

1. เปิด [Google Cloud Console → IAM → Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
2. เลือก service account ที่สร้าง (เช่น `goldenmole-play-upload@...`)
3. แท็บ **Keys** → **Add key** → **Create new key** → **JSON**
4. ไฟล์จะดาวน์โหลด เช่น `goldenmole-play-xxxxx.json`

### เก็บไฟล์อย่างปลอดภัย (นอก git)

```powershell
New-Item -ItemType Directory -Force -Path C:\secrets
Move-Item "$env:USERPROFILE\Downloads\goldenmole-play-*.json" C:\secrets\goldenmole-play-api.json
```

**ห้าม** commit ไฟล์ JSON นี้เข้า GitHub

---

## ขั้นที่ 4 — หา track การทดสอบแบบปิด

1. Play Console → **Testing** → **Closed testing**
2. ดู track ที่ใช้ (มักมี track เริ่มต้นชื่อ **Alpha**)
3. ดู slug จาก URL หรือชื่อ track:
   - track เริ่มต้นมักใช้ slug **`alpha`**
   - track ที่สร้างเองใช้ slug ตามที่ Console กำหนด

ตั้งใน `.env.play`:

```env
PLAY_STORE_TRACK=alpha
```

---

## ขั้นที่ 5 — สร้าง `.env.play` บนเครื่อง

รันสคริปต์ช่วย (ใน `mobile-flutter`):

```powershell
cd c:\construction-management-app\mobile-flutter
.\scripts\setup-play-api.ps1 -JsonKeyPath "C:\secrets\goldenmole-play-api.json"
```

หรือทำมือ:

```powershell
copy .env.play.example .env.play
# แก้ไฟล์ .env.play
```

ตัวอย่าง `.env.play`:

```env
PLAY_STORE_JSON_KEY_PATH=C:/secrets/goldenmole-play-api.json
PLAY_STORE_TRACK=alpha
SUPABASE_URL=https://cocvespahjymyrvmqzcs.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...   # จาก Supabase → Settings → API → service_role
```

หา **service_role key**: [Supabase Dashboard](https://supabase.com/dashboard/project/cocvespahjymyrvmqzcs/settings/api) → **Project API keys** → `service_role` (secret)

---

## ขั้นที่ 6 — ทดสอบว่า API ใช้ได้

```powershell
cd c:\construction-management-app\mobile-flutter
.\scripts\verify-play-api.ps1
```

ถ้าผ่าน จะเห็นข้อความประมาณ:

```
Play API OK — track 'alpha' ...
```

---

## Checklist สรุป

- [ ] Play Console → API access เชื่อม Google Cloud แล้ว
- [ ] สร้าง Service Account แล้ว
- [ ] ให้สิทธิ์ Release manager กับแอป `com.goldenmole.app`
- [ ] ดาวน์โหลด JSON key เก็บที่ `C:\secrets\...`
- [ ] สร้าง `mobile-flutter/.env.play`
- [ ] รัน `verify-play-api.ps1` ผ่าน
- [ ] มี `android/key.properties` + keystore สำหรับ sign AAB (มีแล้วบนเครื่อง)

---

## ปัญหาที่พบบ่อย

| อาการ | วิธีแก้ |
|--------|--------|
| `403 The caller does not have permission` | กลับ Play Console ให้สิทธิ์ service account ใหม่ (Release manager + เลือกแอป) |
| `404 Package not found` | ตรวจ package `com.goldenmole.app` และว่าแอปสร้างใน Console แล้ว |
| `Invalid grant` / JSON error | ดาวน์โหลด key ใหม่ หรือ path ใน `.env.play` ผิด |
| `Track not found` | เปลี่ยน `PLAY_STORE_TRACK` ให้ตรง slug ใน Closed testing |
| ยังไม่เคยอัปโหลดรุ่นแรก | อาจต้องอัปโหลด AAB ครั้งแรกมือ 1 ครั้งใน Closed testing ก่อน API ใช้ได้เต็มที่ |

---

## ขั้นถัดไป

เมื่อ verify ผ่านแล้ว ปล่อยรุ่น closed test:

```powershell
.\scripts\release-android-closed.ps1 `
  -ReleaseName "1.0.3 — คำอธิบาย" `
  -ReleaseNotes "• รายการเปลี่ยนแปลง"
```

ดู workflow เต็ม: [android-play-fastlane-setup.md](./android-play-fastlane-setup.md)
