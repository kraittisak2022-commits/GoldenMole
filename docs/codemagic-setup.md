# Codemagic setup — Goldenmole Dashboard iOS

คู่มือตั้งค่า build iOS บน Codemagic จาก Windows (ไม่ต้องมี Mac)

## สิ่งที่ตั้งค่าใน repo แล้ว

| รายการ | ค่า |
|--------|-----|
| Bundle ID | `com.goldenmole.dashboard` |
| App Store Apple ID | `6790311737` |
| Workflow | `goldenmole-dashboard-ios` |
| Integration name | `codemagic` |
| Env group | `goldenmole_dashboard` |
| Build notify email | `kraittisak2022@gmail.com` |

---

## ขั้นที่ 1 — เชื่อม GitHub กับ Codemagic

1. เปิด [codemagic.io](https://codemagic.io/) → login
2. **Applications** → **Add application**
3. เลือก **GitHub** → repo `kraittisak2022-commits/GoldenMole`
4. เลือก **codemagic.yaml** เป็น config file
5. **Check for configuration file** ควรเห็น workflow `Goldenmole Dashboard iOS`

---

## ขั้นที่ 2 — App Store Connect API key (แก้ error "integration codemagic does not exist")

ชื่อใน `codemagic.yaml` ต้อง **ตรงกันทุกตัวอักษร** กับชื่อที่ตั้งใน Codemagic UI:

```yaml
integrations:
  app_store_connect: codemagic   # ← ชื่อนี้ต้องมีใน Codemagic
```

### สร้างที่ Apple (ถ้ายังไม่มี)

1. [App Store Connect](https://appstoreconnect.apple.com/) → **Users and Access** → **Integrations**
2. **App Store Connect API** → **+** Generate
3. Name: `Codemagic` · Access: **App Manager**
4. ดาวน์โหลด `.p8` (ครั้งเดียว) · จด **Issuer ID** และ **Key ID**

### ใส่ใน Codemagic (ขั้นที่ขาด — ทำก่อน build)

1. เปิด [codemagic.io](https://codemagic.io/) → **Teams** (มุมซ้ายล่าง)
2. **Team settings** (ไอคอนฟันเฟืองทีม)
3. **Team integrations** → **Developer Portal** → **Manage keys**
4. กด **Add key**
5. กรอก:
   - **App Store Connect API key name**: พิมพ์ **`codemagic`** ตรงๆ (ไม่มีช่องว่าง ตัวพิมพ์เล็ก)
   - **Issuer ID**: จาก App Store Connect → Users and Access → Integrations
   - **Key ID**: จากตาราง API keys
   - **ไฟล์ .p8**: อัปโหลด `AuthKey_XXXXXX.p8`
6. กด **Save**
7. กลับไปแอป → **Start new build** อีกครั้ง

> ถ้าตั้งชื่ออื่น (เช่น `GoldenMole`) ต้องแก้ `codemagic.yaml` บรรทัด `app_store_connect:` ให้ตรงชื่อนั้น

### ตรวจว่าสร้างสำเร็จ

- Team settings → Developer Portal → ต้องเห็น key ชื่อ `codemagic` ในรายการ
- ถ้ายัง error อยู่ → reload หน้า Codemagic แล้ว build ใหม่

---

## ขั้นที่ 3 — ตัวแปร environment (บังคับ)

**Team settings** → **Environment variables** → group **`goldenmole_dashboard`**:

| Variable | Secure | ค่า |
|----------|--------|-----|
| `SUPABASE_URL` | ใช่ | `https://cocvespahjymyrvmqzcs.supabase.co` |
| `SUPABASE_ANON_KEY` | ใช่ | ดูใน `codemagic.secrets.yaml` (ไฟล์ local ไม่ commit) |

> **ไม่ต้อง**ใส่ `CERTIFICATE_PRIVATE_KEY` ถ้าสร้าง cert + profile ใน Codemagic UI แล้ว (ดูขั้นที่ 3.5)

---

## ขั้นที่ 3.5 — Code signing ใน Codemagic UI (แนะนำ)

### 1. สร้าง Distribution certificate
**Code signing identities** → **iOS certificates** → **Generate certificate**

| ช่อง | ค่า |
|------|-----|
| Reference name | `goldenmole_appstore` |
| Certificate type | **Apple Distribution** (ต้องเป็น **production** ในรายการ) |
| API key | `codemagic` |

**สำคัญ:** Reference name ต้องตรงกับที่เห็นใน Codemagic — ตอนนี้ใช้ `goldenmole_appstore` (cert แบบ production) + `goldenmole_appstore` (profile)

### 2. ดึง App Store provisioning profile
**iOS provisioning profiles** → **Fetch profiles** → ติ๊ก **Goldenmole Dashboard** (`com.goldenmole.dashboard`) → **Download selected** → Reference name: `goldenmole_appstore`

### 3. ตรวจก่อน build
- ใน **Available provisioning profiles** คอลัมน์ **Certificate** ต้องมี **เครื่องหมายถูกสีเขียว**
- Reference name ต้องตรง yaml: cert + profile = `goldenmole_appstore` (ชื่อเดียวกันได้ คนละแท็บ)
- Profile ยังไม่หมดอายุ

ถ้า Certificate ไม่มีเครื่องหมายถูก → ใช้ cert แบบ **production** ชื่อ `goldenmole_appstore` ไม่ใช่ `goldenmole_dist` (development)

### ทางเลือก: ใช้ openssl + env (ไม่แนะนำถ้าทำ UI แล้ว)

ลบ Distribution cert เก่าบน Apple → `openssl genrsa 2048` → ใส่ `CERTIFICATE_PRIVATE_KEY` ใน env group แล้วใช้ yaml แบบ `fetch-signing-files --create`

---

### วิธี B: Sync ด้วย API (รวม Supabase + signing key)

```powershell
$env:CODEMAGIC_API_TOKEN = "your-codemagic-api-token"
$env:CODEMAGIC_TEAM_ID = "your-team-id"
.\scripts\sync-codemagic-env.ps1
```

API token: Codemagic → **User settings** → **Integrations** → **Codemagic API**

---

## ขั้นที่ 4 — รัน build

1. Push branch ที่มี `codemagic.yaml` อัปเดตแล้ว
2. Codemagic → แอป → **Start new build** → workflow **Goldenmole Dashboard iOS**
3. รอ build + อัปโหลด TestFlight (~15–30 นาที)

---

## หลัง build สำเร็จ

1. App Store Connect → **TestFlight** → รอ processing
2. เพิ่ม internal tester (อีเมล Apple ID)
3. ติดตั้งแอปผ่าน TestFlight บน iPhone

---

## Troubleshooting

| Error | แก้ |
|-------|-----|
| Integration `codemagic` not found | Add key ใน Team settings → Developer Portal; ชื่อต้องตรง yaml |
| `CERTIFICATE_PRIVATE_KEY is missing` | ใช้ yaml ล่าสุด (`ios_signing`) + cert/profile ใน Code signing identities |
| No matching certificate for profile | อัปโหลด `.p12` หลัง Generate cert; ตรวจชื่อ reference ตรง yaml |
| No profiles for bundle id | Fetch App Store profile สำหรับ `com.goldenmole.dashboard` ใน Codemagic UI |
| 409 Distribution certificate | ลบ Distribution cert เก่าใน Apple Developer |
| SUPABASE_URL fatalError | ตรวจ group `goldenmole_dashboard` ใน Codemagic |

---

## ไฟล์ที่เกี่ยวข้อง

- `codemagic.yaml` — workflow หลัก
- `codemagic.secrets.yaml` — ค่า Supabase local (gitignored)
- `scripts/sync-codemagic-env.ps1` — อัปโหลด env ไป Codemagic
