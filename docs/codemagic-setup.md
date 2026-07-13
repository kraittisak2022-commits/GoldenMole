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
| `CERTIFICATE_PRIVATE_KEY` | ใช่ | ดูขั้นที่ 3.5 — ครั้งเดียว แล้ว build สร้าง cert+profile อัตโนมัติ |

---

## ขั้นที่ 3.5 — ตั้งค่าครั้งเดียว (สร้าง cert+profile อัตโนมัติ)

### 1. ลบ Distribution cert เก่าบน Apple
[Apple → Certificates](https://developer.apple.com/account/resources/certificates/list) → ลบ **Apple Distribution** ทั้งหมด

### 2. สร้าง private key (Git Bash)
```bash
openssl genrsa 2048
```

### 3. ใส่ใน Codemagic
group `goldenmole_dashboard` → **`CERTIFICATE_PRIVATE_KEY`** (Secure)

วางแบบนี้ (ต้องมีบรรทัด BEGIN/END):
```
-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----
```
อย่าใส่เครื่องหมาย `"` หน้า-หลัง

ตรวจว่า group `goldenmole_dashboard` ถูกเลือกใน workflow ของแอป (Application settings → Environment variables)

### 4. Start new build
yaml เรียก `fetch-signing-files --create` สร้าง **Distribution certificate + App Store profile** อัตโนมัติ — **ไม่ต้อง** สร้างใน Apple/Codemagic UI ด้วยมือ

### 5. หลัง build สำเร็จ
**อย่าลบ** `CERTIFICATE_PRIVATE_KEY`

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
| `CERTIFICATE_PRIVATE_KEY is missing` | เพิ่มใน group `goldenmole_dashboard` + ผูก group กับ workflow |
| `CERTIFICATE_PRIVATE_KEY is invalid` | `openssl genrsa 2048` ใหม่ วาง PEM ทั้งก้อน ไม่มี quotes |
| Cannot save certificate without private key | ใส่ `CERTIFICATE_PRIVATE_KEY` ให้ถูกต้อง (ดูขั้น 3.5) |
| 409 Distribution certificate | ลบ Distribution cert **ทั้งหมด** บน Apple แล้ว build ใหม่ |
| SUPABASE_URL fatalError | ตรวจ group `goldenmole_dashboard` ใน Codemagic |

---

## ไฟล์ที่เกี่ยวข้อง

- `codemagic.yaml` — workflow หลัก
- `codemagic.secrets.yaml` — ค่า Supabase local (gitignored)
- `scripts/sync-codemagic-env.ps1` — อัปโหลด env ไป Codemagic
