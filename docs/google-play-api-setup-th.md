# ตั้งค่า Google Play API (GoldenMole for User)

คู่มือครั้งเดียวสำหรับให้ Fastlane อัปโหลด AAB ไป **การทดสอบแบบปิด** ได้อัตโนมัติ

แอป: **GoldenMole for User** · `com.goldenmole.app`

> **หมายเหตุ (UI ใหม่):** Google **ย้าย/ยกเลิกเมนู** `การตั้งค่า → การเข้าถึง API` แล้ว  
> ตอนนี้ให้สิทธิ์ API ผ่าน **ผู้ใช้และสิทธิ์ (Users and permissions)** แทน — เชิญอีเมล Service Account เข้า Play Console

---

## ภาพรวม (3 ส่วน)

```
Google Cloud (เว็บ)     →  สร้าง Service Account + เปิด API + ดาวน์โหลด JSON
Play Console (เว็บ)     →  เชิญ Service Account ใน Users and permissions
เครื่องคุณ (local)    →  เก็บ JSON + .env.play + ทดสอบ
```

---

## ขั้นที่ 1 — สร้าง Service Account ใน Google Cloud

1. เปิด [Google Cloud Console](https://console.cloud.google.com/)
2. เลือกโปรเจกต์ (สร้างใหม่ก็ได้ เช่น `goldenmole-play`)
3. **เปิด API** — ไปที่ [Google Play Android Developer API](https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com) แล้วกด **Enable**
4. ไป **IAM & Admin** → **Service Accounts** → **Create service account**
   - ชื่อ เช่น `goldenmole-play-upload`
   - กด **Create and continue** → **Done**  
   - **ไม่ต้อง**ใส่ role ใน Cloud ตอนนี้ (สิทธิ์จริงตั้งใน Play Console)
5. คัดลอก **อีเมล** ของ service account (ลงท้าย `@....iam.gserviceaccount.com`)

---

## ขั้นที่ 2 — ดาวน์โหลด JSON key

1. ในรายการ Service Accounts → เลือกตัวที่สร้าง
2. แท็บ **Keys** → **Add key** → **Create new key** → **JSON**
3. ไฟล์จะดาวน์โหลด เช่น `goldenmole-play-xxxxx.json`

เก็บนอก git:

```powershell
New-Item -ItemType Directory -Force -Path C:\secrets
Move-Item "$env:USERPROFILE\Downloads\*.json" C:\secrets\goldenmole-play-api.json
# (เลือกไฟล์ service account ที่ถูกต้อง)
```

**ห้าม** commit JSON นี้เข้า GitHub

---

## ขั้นที่ 3 — ให้สิทธิ์ใน Play Console (แทน API access)

### ไปที่เมนูไหน?

1. เปิด [Google Play Console](https://play.google.com/console)
2. **อย่าเข้าไปในแอปเดียว** — ไปที่ระดับ **บัญชีนักพัฒนา (Developer account)**  
   - คลิกโลโก้ Play Console / ชื่อบัญชีด้านบน หรือ
   - เมนูซ้าย **ผู้ใช้และสิทธิ์** / **Users and permissions**
3. URL มักเป็นแบบ: `https://play.google.com/console/u/0/developers/XXXXXXXX/users-and-permissions`

### เชิญ Service Account

1. กด **เชิญผู้ใช้ใหม่** / **Invite new users**
2. วาง **อีเมล service account** จากขั้นที่ 1 (ไม่ใช่อีเมล Gmail ของคุณ)
3. แท็บ **สิทธิ์ของแอป (App permissions)**:
   - กด **Add app** → เลือก **GoldenMole for User** → **Apply**
4. เปิดสิทธิ์อย่างน้อย:
   - **ดูข้อมูลแอป (View app information)** — อ่านอย่างเดียว
   - **จัดการการเผยแพร่ใน track การทดสอบ** / **Release to testing tracks**  
     หรือเลือก preset **Release manager** (แนะนำสำหรับอัปโหลด closed test)
5. กด **Invite user** / **Send invite** / **Save**

สถานะควรเป็น **Active** (service account ไม่ต้องกดรับ invite ใน Gmail)

> ถ้าให้สิทธิ์ไม่ครบ จะเจอ `403` ตอน Fastlane อัปโหลด

---

## ถ้าหาเมนูไม่เจอ

| ต้องการ | ไปที่ |
|--------|--------|
| เชิญ service account | **Users and permissions** (ระดับบัญชีนักพัฒนา ไม่ใช่ในแอปเดียว) |
| เปิด Play Developer API | [Google Cloud → androidpublisher API](https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com) |
| สร้าง / ดาวน์โหลด JSON | [Google Cloud → Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts) |
| Closed testing track | ในแอป → **Testing** → **Closed testing** |

**ไม่มีเมนู API access แล้ว** — เป็นปกติใน UI 2024+ ไม่ใช่บัญชีผิด

---

## ขั้นที่ 4 — track การทดสอบแบบปิด

1. Play Console → เลือกแอป **GoldenMole for User**
2. **Testing** → **Closed testing**
3. track เริ่มต้นมักใช้ slug **`alpha`**

ใน `.env.play`:

```env
PLAY_STORE_TRACK=alpha
```

---

## ขั้นที่ 5 — `.env.play` บนเครื่อง

```powershell
cd c:\construction-management-app\mobile-flutter
.\scripts\setup-play-api.ps1 -JsonKeyPath "C:\secrets\goldenmole-play-api.json"
```

ตัวอย่าง `.env.play`:

```env
PLAY_STORE_JSON_KEY_PATH=C:/secrets/goldenmole-play-api.json
PLAY_STORE_TRACK=alpha
SUPABASE_URL=https://cocvespahjymyrvmqzcs.supabase.co
SUPABASE_SERVICE_ROLE_KEY=...   # Supabase → Settings → API → service_role
```

[Supabase API keys](https://supabase.com/dashboard/project/cocvespahjymyrvmqzcs/settings/api)

---

## ขั้นที่ 6 — ทดสอบ

```powershell
cd c:\construction-management-app\mobile-flutter
.\scripts\verify-play-api.ps1
```

ผ่านแล้วจะเห็น: `Play API OK — track 'alpha' ...`

---

## Checklist สรุป

- [ ] Cloud: เปิด **Google Play Android Developer API**
- [ ] Cloud: สร้าง Service Account + ดาวน์โหลด JSON
- [ ] Play: **Users and permissions** → เชิญอีเมล service account
- [ ] Play: เลือกแอป `com.goldenmole.app` + สิทธิ์ Release / testing tracks
- [ ] Local: `.env.play` + JSON ที่ `C:\secrets\...`
- [ ] รัน `verify-play-api.ps1` ผ่าน

---

## ปัญหาที่พบบ่อย

| อาการ | วิธีแก้ |
|--------|--------|
| ไม่มีเมนู API access | ใช้ **Users and permissions** แทน (ดูด้านบน) |
| `403` permission denied | เชิญ service account ใหม่ + สิทธิ์ Release manager + เลือกแอป |
| `404 Package not found` | ตรวจ `com.goldenmole.app` ใน Console |
| API not enabled | Enable [androidpublisher API](https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com) ใน Cloud project เดียวกับ JSON key |

---

## ขั้นถัดไป

```powershell
.\scripts\release-android-closed.ps1 `
  -ReleaseName "1.0.3 — คำอธิบาย" `
  -ReleaseNotes "• รายการเปลี่ยนแปลง"
```

ดู workflow เต็ม: [android-play-fastlane-setup.md](./android-play-fastlane-setup.md)
