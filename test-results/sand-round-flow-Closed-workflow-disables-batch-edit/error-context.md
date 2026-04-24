# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: sand-round-flow.spec.ts >> Closed workflow disables batch edit
- Location: e2e\sand-round-flow.spec.ts:19:1

# Error details

```
Error: expect(locator).toBeDisabled() failed

Locator: locator('input[value="BATCH-SEED-001"]').first()
Expected: disabled
Timeout: 5000ms
Error: element(s) not found

Call log:
  - Expect "toBeDisabled" with timeout 5000ms
  - waiting for locator('input[value="BATCH-SEED-001"]').first()

```

# Page snapshot

```yaml
- generic [ref=e3]:
  - heading "E2E Harness" [level=1] [ref=e4]
  - generic [ref=e5]:
    - button "Add Transaction" [ref=e6] [cursor=pointer]
    - button "Seed Matching Draft" [ref=e7] [cursor=pointer]
    - button "Seed Conflict Draft" [ref=e8] [cursor=pointer]
    - button "Clear All Drafts" [ref=e9] [cursor=pointer]
  - generic [ref=e10]:
    - generic [ref=e11]:
      - generic [ref=e12]:
        - paragraph [ref=e14]: ระบบช่วยบันทึกข้อมูลแบบทีละขั้นตอน
        - generic [ref=e15]:
          - button "บันทึก" [ref=e16] [cursor=pointer]:
            - img [ref=e17]
            - text: บันทึก
          - button "รายงาน" [ref=e20] [cursor=pointer]:
            - img [ref=e21]
            - text: รายงาน
      - generic [ref=e24]:
        - button "วันที่ทำงาน" [ref=e25] [cursor=pointer]:
          - img [ref=e26]
          - generic [ref=e28]: วันที่ทำงาน
        - button "ค่าแรง" [ref=e29] [cursor=pointer]:
          - img [ref=e30]
          - generic [ref=e35]: ค่าแรง
        - button "การใช้รถ" [ref=e36] [cursor=pointer]:
          - img [ref=e37]
          - generic [ref=e42]: การใช้รถ
        - button "เที่ยวรถ" [ref=e43] [cursor=pointer]:
          - img [ref=e44]
          - generic [ref=e49]: เที่ยวรถ
        - button "ล้างทราย" [ref=e50] [cursor=pointer]:
          - img [ref=e51]
          - generic [ref=e54]: ล้างทราย
        - button "น้ำมัน" [ref=e55] [cursor=pointer]:
          - img [ref=e56]
          - generic [ref=e59]: น้ำมัน
        - button "รายรับ" [ref=e60] [cursor=pointer]:
          - img [ref=e61]
          - generic [ref=e65]: รายรับ
        - button "เหตุการณ์" [ref=e66] [cursor=pointer]:
          - img [ref=e67]
          - generic [ref=e69]: เหตุการณ์
        - button "ตรวจสอบ" [ref=e70] [cursor=pointer]:
          - img [ref=e71]
          - generic [ref=e74]: ตรวจสอบ
    - generic [ref=e75]:
      - generic [ref=e78]:
        - status [ref=e80]: บันทึกล่าสุด 15:39
        - generic [ref=e81]:
          - generic [ref=e82]:
            - heading "บันทึกการล้างทราย" [level=3] [ref=e83]:
              - img [ref=e84]
              - text: บันทึกการล้างทราย
            - generic [ref=e87]: 22 เม.ย. 69
          - generic [ref=e88]:
            - generic [ref=e89]:
              - paragraph [ref=e90]: 🏭 เครื่องร่อน 1 (เก่า)
              - generic [ref=e91]:
                - generic [ref=e92]:
                  - generic [ref=e93]: ☀️ เช้า (คิว)
                  - generic [ref=e94]:
                    - spinbutton [ref=e95]
                    - button "เลือกจากรายการ" [ref=e96] [cursor=pointer]:
                      - img [ref=e97]
                - generic [ref=e99]:
                  - generic [ref=e100]: 🌙 บ่าย (คิว)
                  - generic [ref=e101]:
                    - spinbutton [ref=e102]
                    - button "เลือกจากรายการ" [ref=e103] [cursor=pointer]:
                      - img [ref=e104]
                - generic [ref=e106]:
                  - generic [ref=e107]: รวม
                  - generic [ref=e108]: "0"
                  - generic [ref=e109]: คิว
              - generic [ref=e110]:
                - generic [ref=e111]: 👷 พนักงานที่ล้าง
                - generic [ref=e113]: ยังไม่มีข้อมูล (กรุณาลากพนักงานใส่กล่อง "ล้างทราย เครื่องร่อน 1" ในขั้นค่าแรง)
            - generic [ref=e114]:
              - paragraph [ref=e115]: 🏭 เครื่องร่อน 2 (ใหม่)
              - generic [ref=e116]:
                - generic [ref=e117]:
                  - generic [ref=e118]: ☀️ เช้า (คิว)
                  - generic [ref=e119]:
                    - spinbutton [ref=e120]
                    - button "เลือกจากรายการ" [ref=e121] [cursor=pointer]:
                      - img [ref=e122]
                - generic [ref=e124]:
                  - generic [ref=e125]: 🌙 บ่าย (คิว)
                  - generic [ref=e126]:
                    - spinbutton [ref=e127]
                    - button "เลือกจากรายการ" [ref=e128] [cursor=pointer]:
                      - img [ref=e129]
                - generic [ref=e131]:
                  - generic [ref=e132]: รวม
                  - generic [ref=e133]: "0"
                  - generic [ref=e134]: คิว
              - generic [ref=e135]:
                - generic [ref=e136]: 👷 พนักงานที่ล้าง
                - generic [ref=e138]: ยังไม่มีข้อมูล (กรุณาลากพนักงานใส่กล่อง "ล้างทราย เครื่องร่อน 2" ในขั้นค่าแรง)
            - generic [ref=e139]:
              - paragraph [ref=e141]:
                - generic [ref=e142]: 🕐
                - text: เวลาเริ่มงาน / หยุดล้าง
              - generic [ref=e143]:
                - generic [ref=e144]:
                  - generic [ref=e145]: ☀️ ช่วงเช้า เริ่มงาน (น.)
                  - textbox [ref=e146]
                - generic [ref=e147]:
                  - generic [ref=e148]: 🌤️ ช่วงบ่าย เริ่มงาน (น.)
                  - textbox [ref=e149]
                - generic [ref=e150]:
                  - generic [ref=e151]: 🌙 เย็น หยุดล้าง (กี่โมง)
                  - textbox [ref=e152]
            - generic [ref=e153]:
              - generic [ref=e154]:
                - generic [ref=e155]:
                  - generic [ref=e156]:
                    - generic [ref=e157]: ➕
                    - text: จำนวนถังที่ได้วันนี้
                  - generic [ref=e158]:
                    - generic [ref=e159]:
                      - spinbutton [ref=e160]
                      - button "เลือกจากรายการ" [ref=e161] [cursor=pointer]:
                        - img [ref=e162]
                    - generic [ref=e164]: ถัง
                - generic [ref=e165]:
                  - generic [ref=e166]:
                    - generic [ref=e167]: ➖
                    - text: จำนวนทรายที่ล้างที่บ้านวันนี้
                  - generic [ref=e168]:
                    - generic [ref=e169]:
                      - spinbutton [ref=e170]
                      - button "เลือกจากรายการ" [ref=e171] [cursor=pointer]:
                        - img [ref=e172]
                    - generic [ref=e174]: ถัง
              - generic [ref=e175]:
                - generic [ref=e176]:
                  - paragraph [ref=e177]: จำนวนถังที่ได้วันนี้
                  - paragraph [ref=e178]: "0"
                - generic [ref=e179]:
                  - paragraph [ref=e180]: ล้างที่บ้านวันนี้
                  - paragraph [ref=e181]: "0"
                - generic [ref=e182]:
                  - paragraph [ref=e183]: จำนวนถังคงเหลือ
                  - paragraph [ref=e184]: "0"
              - generic [ref=e185]:
                - paragraph [ref=e186]: Lot/Batch ต้นทาง
                - generic [ref=e187]:
                  - generic [ref=e188]:
                    - text: รหัสล็อตทรายวันนี้
                    - textbox "รหัสล็อตทรายวันนี้" [ref=e189]: BATCH-20260422
                  - generic [ref=e190]:
                    - text: ล้างที่บ้านจากล็อต
                    - combobox "ล้างที่บ้านจากล็อต" [ref=e191]:
                      - option "-- เลือกล้อต --" [selected]
                  - generic [ref=e192]:
                    - text: จำนวนถังจากล็อตที่เลือก
                    - generic [ref=e193]:
                      - spinbutton "จำนวนถังจากล็อตที่เลือก เพิ่ม" [ref=e194]
                      - button "เพิ่ม" [ref=e195] [cursor=pointer]
                - paragraph [ref=e197]: ยังไม่ได้เลือกล็อตสำหรับล้างที่บ้าน
          - generic [ref=e198]:
            - button "บันทึกข้อมูลล้างทราย (0 คิว)" [ref=e199] [cursor=pointer]:
              - img [ref=e200]
              - text: บันทึกข้อมูลล้างทราย (0 คิว)
            - generic [ref=e203]:
              - button "ย้อนกลับ" [ref=e204] [cursor=pointer]
              - button "ถัดไป" [ref=e205] [cursor=pointer]:
                - text: ถัดไป
                - img [ref=e206]
      - generic [ref=e208]:
        - generic [ref=e209]:
          - generic [ref=e210]:
            - generic [ref=e211]:
              - paragraph [ref=e212]: สรุปวันนี้
              - paragraph [ref=e213]: 22 เม.ย. 2569
            - button "ย่อ" [ref=e214] [cursor=pointer]
          - generic [ref=e216]:
            - generic [ref=e217]:
              - img [ref=e219]
              - generic [ref=e224]:
                - paragraph [ref=e225]: คนงาน
                - paragraph [ref=e226]:
                  - generic "0 คน" [ref=e227]: "0"
                  - generic [ref=e228]: คน
            - generic [ref=e229]:
              - img [ref=e231]
              - generic [ref=e234]:
                - paragraph [ref=e235]: ทรายล้าง
                - paragraph [ref=e236]:
                  - generic "0 คิว" [ref=e237]: "0"
                  - generic [ref=e238]: คิว
            - generic [ref=e239]:
              - img [ref=e241]
              - generic [ref=e246]:
                - paragraph [ref=e247]: รถ / รายวัน
                - paragraph [ref=e248]:
                  - generic "0 รายการ" [ref=e249]: "0"
                  - generic [ref=e250]: รายการ
            - generic [ref=e251]:
              - img [ref=e253]
              - generic [ref=e256]:
                - paragraph [ref=e257]: น้ำมัน
                - paragraph [ref=e258]:
                  - generic "฿0 บาท" [ref=e259]: ฿0
                  - generic [ref=e260]: บาท
        - generic [ref=e262]:
          - generic [ref=e263]:
            - heading "รายการบันทึกวันนี้ (22 เม.ย. 2569)" [level=3] [ref=e265]:
              - generic [ref=e266]:
                - img [ref=e267]
                - generic [ref=e270]: รายการบันทึกวันนี้
              - generic [ref=e271]: (22 เม.ย. 2569)
            - generic [ref=e272]: 0 รายการ
          - generic [ref=e274]:
            - img [ref=e275]
            - paragraph [ref=e278]: ยังไม่มีรายการบันทึก
          - generic [ref=e279]:
            - generic [ref=e280]:
              - generic [ref=e281]: รวมค่าใช้จ่ายวันนี้
              - text: ค่าแรง, รถ, น้ำมัน ฯลฯ
            - generic [ref=e282]: ฿0
  - generic [ref=e283]:
    - heading "Data Verification Harness" [level=2] [ref=e284]
    - generic [ref=e285]:
      - generic [ref=e286]:
        - generic [ref=e287]:
          - heading "ระบบตรวจสอบข้อมูล (Daily Wizard)" [level=3] [ref=e288]:
            - img [ref=e289]
            - text: ระบบตรวจสอบข้อมูล (Daily Wizard)
          - paragraph [ref=e293]: ตรวจว่าวันไหนยังไม่มีบันทึกงานประจำวัน และรายการที่น่าสงสัยว่าซ้ำกัน
        - generic [ref=e294]:
          - button "Export CSV" [ref=e295] [cursor=pointer]:
            - img [ref=e296]
            - text: Export CSV
          - button "พิมพ์/PDF" [ref=e300] [cursor=pointer]:
            - img [ref=e301]
            - text: พิมพ์/PDF
      - generic [ref=e306]:
        - heading "สรุปภาพรวมในช่วงที่เลือก" [level=4] [ref=e307]
        - generic [ref=e308]:
          - generic [ref=e309]:
            - paragraph [ref=e310]: วันในช่วง
            - paragraph [ref=e311]: "45"
          - generic [ref=e312]:
            - paragraph [ref=e313]: ไม่มีบันทึกเลย
            - paragraph [ref=e314]: "44"
          - generic [ref=e315]:
            - paragraph [ref=e316]: กลุ่มซ้ำทั้งหมด
            - paragraph [ref=e317]: "0"
          - generic [ref=e318]:
            - paragraph [ref=e319]: วันที่ครบ 7 ขั้น
            - paragraph [ref=e320]: "0"
          - generic [ref=e321]:
            - paragraph [ref=e322]: Data Quality Score
            - paragraph [ref=e323]: "0"
            - paragraph [ref=e324]: 100 - (วันว่าง*4) - (ซ้ำ*2)
        - generic [ref=e325]:
          - generic [ref=e326]: "น้ำหนัก Score:"
          - generic [ref=e327]:
            - text: วันว่าง
            - spinbutton "วันว่าง" [ref=e328]: "4"
          - generic [ref=e329]:
            - text: ข้อมูลซ้ำ
            - spinbutton "ข้อมูลซ้ำ" [ref=e330]: "2"
        - generic [ref=e331]:
          - generic [ref=e332]:
            - text: Threshold รายรับเป็น 0
            - spinbutton "Threshold รายรับเป็น 0" [ref=e333]: "0"
          - generic [ref=e334]:
            - text: Threshold ค่าแรงสูง
            - spinbutton "Threshold ค่าแรงสูง" [ref=e335]: "25000"
          - generic [ref=e336]:
            - text: Threshold น้ำมันสูง (ลิตร)
            - spinbutton "Threshold น้ำมันสูง (ลิตร)" [ref=e337]: "400"
      - generic [ref=e339]:
        - generic [ref=e340]:
          - img [ref=e341]
          - generic [ref=e345]:
            - heading "ระบบตรวจสอบรอบล้างทราย (Flowchart)" [level=4] [ref=e346]
            - paragraph [ref=e347]: "ตัวอย่างรอบงาน: ขนทราย 800 คิว → ล้าง 2 วัน → ได้ 52 ถัง → ล้างที่บ้านครบ 52 ถัง = สรุปรอบ"
        - generic [ref=e348]:
          - generic [ref=e349]:
            - text: เป้าขนทราย (คิว)
            - spinbutton "เป้าขนทราย (คิว)" [ref=e350]: "800"
          - generic [ref=e351]:
            - text: เป้าจำนวนวันล้าง
            - spinbutton "เป้าจำนวนวันล้าง" [ref=e352]: "2"
          - generic [ref=e353]:
            - text: เป้าจำนวนถัง
            - spinbutton "เป้าจำนวนถัง" [ref=e354]: "52"
        - generic [ref=e356]:
          - text: ขั้นต่ำก่อนตัดรอบ (วัน)
          - spinbutton "ขั้นต่ำก่อนตัดรอบ (วัน) รองรับเคสล้าง 2-3 วัน แล้วถังเป็น 0 ค่อยตัดรอบ" [ref=e357]: "2"
          - generic [ref=e358]: รองรับเคสล้าง 2-3 วัน แล้วถังเป็น 0 ค่อยตัดรอบ
        - generic [ref=e359]:
          - generic [ref=e360]:
            - generic [ref=e361]: ขนทราย 800 / 800 คิว
            - generic [ref=e362]: →
            - generic [ref=e363]: ล้าง 0 / 2 วัน (0 คิว)
            - generic [ref=e364]: →
            - generic [ref=e365]: ได้ 52 / 52 ถัง
            - generic [ref=e366]: →
            - generic [ref=e367]: ล้างที่บ้าน 52 ถัง
          - generic [ref=e368]:
            - img [ref=e369]
            - text: "สรุปรอบนี้: เสร็จครบตาม Flowchart แล้ว"
        - generic [ref=e372]:
          - heading "Flowchart รอบปัจจุบัน" [level=5] [ref=e373]
          - generic [ref=e374]:
            - button "1) ขนทรายเข้า 800 / 800 คิว" [ref=e375] [cursor=pointer]:
              - paragraph [ref=e376]:
                - img [ref=e377]
                - text: 1) ขนทรายเข้า
              - paragraph [ref=e379]: 800 / 800 คิว
            - generic [ref=e382]: →
            - button "2) ล้างทราย 0 / 2 วัน 0 คิว" [ref=e383] [cursor=pointer]:
              - paragraph [ref=e384]: 2) ล้างทราย
              - paragraph [ref=e385]: 0 / 2 วัน
              - paragraph [ref=e386]: 0 คิว
            - generic [ref=e388]: →
            - button "3) ได้ถัง 52 / 52 ถัง" [ref=e389] [cursor=pointer]:
              - paragraph [ref=e390]: 3) ได้ถัง
              - paragraph [ref=e391]: 52 / 52 ถัง
          - generic [ref=e394]:
            - button "4) ล้างที่บ้าน 52 ถัง" [ref=e395] [cursor=pointer]:
              - paragraph [ref=e396]: 4) ล้างที่บ้าน
              - paragraph [ref=e397]: 52 ถัง
            - generic [ref=e398]:
              - paragraph [ref=e399]: คงเหลือ
              - paragraph [ref=e400]: 0 ถัง
            - generic [ref=e401]:
              - paragraph [ref=e402]: ปิดรอบแล้ว
              - paragraph [ref=e403]: รอบที่ 1
        - generic [ref=e404]:
          - heading "สรุปเป็นรอบๆ (คลิกเพื่อดูรายละเอียด)" [level=5] [ref=e405]
          - generic [ref=e406]:
            - paragraph [ref=e407]: Notification Inbox (ยังไม่รับทราบ) 0 รายการ
            - paragraph [ref=e408]: ไม่มีแจ้งเตือนคงค้าง
          - generic [ref=e409]:
            - generic [ref=e410]:
              - paragraph [ref=e411]: จำนวนรอบ
              - paragraph [ref=e412]: "1"
            - generic [ref=e413]:
              - paragraph [ref=e414]: รอบปิดแล้ว
              - paragraph [ref=e415]: "1"
            - generic [ref=e416]:
              - paragraph [ref=e417]: เฉลี่ยวัน/รอบ
              - paragraph [ref=e418]: "0.0"
            - generic [ref=e419]:
              - paragraph [ref=e420]: Yield เฉลี่ย (ถัง/คิว)
              - paragraph [ref=e421]: "0.000"
          - list [ref=e422]:
            - listitem [ref=e423] [cursor=pointer]:
              - generic [ref=e424]: รอบที่ 1 · 20/04/2569 - 20/04/2569 · ปิดรอบแล้ว
              - paragraph [ref=e425]: ขน 800 คิว | ล้าง 0 วัน (0 คิว) | ได้ 52 ถัง | ล้างที่บ้าน 52 ถัง
              - paragraph [ref=e426]: "คำนวณรายวัน: 20/04/2569 ล้าง 0 คิว ได้ 52 ถัง ล้างบ้าน 52 ถัง"
        - generic [ref=e427]:
          - generic [ref=e428]:
            - button "Export รอบนี้ CSV" [ref=e429] [cursor=pointer]:
              - img [ref=e430]
              - text: Export รอบนี้ CSV
            - button "พิมพ์/Export PDF รอบนี้" [ref=e434] [cursor=pointer]:
              - img [ref=e435]
              - text: พิมพ์/Export PDF รอบนี้
            - generic [ref=e439]:
              - text: แจ้งเตือนค้างเกิน
              - spinbutton "แจ้งเตือนค้างเกิน วัน" [ref=e440]: "1"
              - text: วัน
          - heading "รายละเอียดรอบที่ 1 แบบละเอียด · ปิดรอบด้วยสิทธิ์ผู้ดูแล" [level=5] [ref=e441]
          - generic [ref=e442]:
            - generic [ref=e443]: "Workflow:"
            - combobox [ref=e444]:
              - option "Open"
              - option "Reviewing"
              - option "Closed" [selected]
              - option "Reopened"
            - textbox "เหตุผล (บังคับเมื่อ Closed/Reopened)" [active] [ref=e445]: override test close
            - generic [ref=e446]: "เหตุผล: override test close"
          - generic [ref=e447]:
            - generic [ref=e448]:
              - paragraph [ref=e449]: ช่วงวันที่
              - paragraph [ref=e450]: 20/04/2569 - 20/04/2569
            - generic [ref=e451]:
              - paragraph [ref=e452]: ขนทรายรวม
              - paragraph [ref=e453]: 800 คิว
            - generic [ref=e454]:
              - paragraph [ref=e455]: ล้างทรายรวม
              - paragraph [ref=e456]: 0 คิว (0 วัน)
            - generic [ref=e457]:
              - paragraph [ref=e458]: ได้ถังรวม
              - paragraph [ref=e459]: 52 ถัง
            - generic [ref=e460]:
              - paragraph [ref=e461]: ล้างที่บ้านรวม
              - paragraph [ref=e462]: 52 ถัง
          - generic [ref=e463]:
            - generic [ref=e464]:
              - generic [ref=e465]: วันที่
              - generic [ref=e466]: ขนทราย
              - generic [ref=e467]: ล้างทราย
              - generic [ref=e468]: ได้ถัง
              - generic [ref=e469]: ล้างที่บ้าน
              - generic [ref=e470]: คงเหลือสะสม
            - generic [ref=e472]:
              - generic [ref=e473]: 20/04/2569
              - generic [ref=e474]: "800"
              - generic [ref=e475]: "0"
              - generic [ref=e476]: "52"
              - generic [ref=e477]: "52"
              - generic [ref=e478]: "0"
          - generic [ref=e479]:
            - generic [ref=e480]: Timeline มุมมองเดียวจบ (ขน → ล้าง → ได้ถัง → ล้างที่บ้าน)
            - generic [ref=e482]:
              - paragraph [ref=e484]: 20/04/2569
              - paragraph [ref=e485]: ขนทราย 800 คิว | ได้ 52 ถัง | ล้างที่บ้าน 52 ถัง
          - generic [ref=e486]:
            - generic [ref=e487]: "ติดตามย้อนกลับ Lot/Batch ID: ถังล้างที่บ้านมาจากวันล้างไหน และขนมาเมื่อไหร่"
            - generic [ref=e488]:
              - generic [ref=e489]: "Merge lot:"
              - textbox "from batch" [ref=e490]
              - generic [ref=e491]: →
              - textbox "to batch" [ref=e492]
              - button "merge" [disabled] [ref=e493]
            - generic [ref=e495]:
              - generic [ref=e496]:
                - paragraph [ref=e497]: ล้างที่บ้าน
                - paragraph [ref=e498]: 20/04/2569
              - generic [ref=e499]:
                - paragraph [ref=e500]: ทรายจากล้าง
                - paragraph [ref=e501]: 20/04/2569
              - generic [ref=e502]:
                - paragraph [ref=e503]: ขนเข้า (อ้างอิง)
                - paragraph [ref=e504]: 20/04/2569
              - generic [ref=e505]:
                - paragraph [ref=e506]: Batch ID
                - generic [ref=e507]:
                  - textbox [disabled] [ref=e508]: BATCH-20260420
                  - generic [ref=e509]:
                    - button "save" [disabled] [ref=e510]
                    - button "delete" [disabled] [ref=e511]
              - generic [ref=e512]:
                - paragraph [ref=e513]: จำนวนถัง
                - paragraph [ref=e514]: "52"
          - paragraph [ref=e515]: ล็อตถูกล็อกแล้วเพราะสถานะรอบเป็น Closed (แก้ไขได้เมื่อเปลี่ยนเป็น Reopened)
          - generic [ref=e516]:
            - heading "Audit Trail รอบล้างทราย" [level=6] [ref=e517]
            - paragraph [ref=e519]: 24/4/2569 15:39:24 · Admin · manual_close_round · workflow=Closed (override test close)
      - generic [ref=e521]:
        - heading "Dashboard mini trend (3 เดือนล่าสุด)" [level=4] [ref=e522]
        - generic [ref=e523]:
          - generic [ref=e524]:
            - generic [ref=e525]:
              - generic [ref=e526]: ม.ค. 69
              - generic [ref=e527]: Score 0
            - generic [ref=e529]: วันว่าง 31 | กลุ่มซ้ำ 0 | เคส 0
          - generic [ref=e530]:
            - generic [ref=e531]:
              - generic [ref=e532]: ก.พ. 69
              - generic [ref=e533]: Score 0
            - generic [ref=e535]: วันว่าง 28 | กลุ่มซ้ำ 0 | เคส 0
          - generic [ref=e536]:
            - generic [ref=e537]:
              - generic [ref=e538]: มี.ค. 69
              - generic [ref=e539]: Score 0
            - generic [ref=e541]: วันว่าง 31 | กลุ่มซ้ำ 0 | เคส 0
      - generic [ref=e543]:
        - generic [ref=e544]:
          - img [ref=e545]
          - text: ช่วงวันที่ตรวจสอบ
        - generic [ref=e547]:
          - generic [ref=e548]:
            - generic [ref=e549]: ตั้งแต่
            - textbox "ตั้งแต่" [ref=e550]: 2026-03-11
          - generic [ref=e551]:
            - generic [ref=e552]: ถึง
            - textbox "ถึง" [ref=e553]: 2026-04-24
          - generic [ref=e554] [cursor=pointer]:
            - checkbox "ไม่นับวันอาทิตย์" [ref=e555]
            - generic [ref=e556]: ไม่นับวันอาทิตย์
          - generic [ref=e557] [cursor=pointer]:
            - checkbox "ซ่อนวันหยุดนักขัตฤกษ์" [ref=e558]
            - generic [ref=e559]: ซ่อนวันหยุดนักขัตฤกษ์
        - generic [ref=e560]:
          - generic [ref=e561]: "ตัวกรองความผิดปกติ:"
          - button "ทั้งหมด" [ref=e562] [cursor=pointer]
          - button "ดูเฉพาะวันไม่มีบันทึก" [ref=e563] [cursor=pointer]
          - button "ดูเฉพาะวันซ้ำ" [ref=e564] [cursor=pointer]
      - generic [ref=e567]:
        - generic [ref=e568]:
          - img [ref=e569]
          - generic [ref=e571]:
            - heading "ปฏิทินตรวจสอบ (คลิกวันที่เพื่อไป Daily Wizard)" [level=4] [ref=e572]
            - paragraph [ref=e573]: แดง = ไม่มีบันทึก, ส้ม = ซ้ำแบบตรงกัน, เหลือง = ซ้ำใกล้เคียง, เขียว = ปกติ
        - generic [ref=e574]:
          - generic [ref=e575]: อา.
          - generic [ref=e576]: จ.
          - generic [ref=e577]: อ.
          - generic [ref=e578]: พ.
          - generic [ref=e579]: พฤ.
          - generic [ref=e580]: ศ.
          - generic [ref=e581]: ส.
          - generic [ref=e582]: "1"
          - generic [ref=e583]: "2"
          - generic [ref=e584]: "3"
          - generic [ref=e585]: "4"
          - generic [ref=e586]: "5"
          - generic [ref=e587]: "6"
          - generic [ref=e588]: "7"
          - generic [ref=e589]: "8"
          - generic [ref=e590]: "9"
          - generic [ref=e591]: "10"
          - button "11" [ref=e592] [cursor=pointer]
          - button "12" [ref=e593] [cursor=pointer]
          - button "13" [ref=e594] [cursor=pointer]
          - button "14" [ref=e595] [cursor=pointer]
          - button "15" [ref=e596] [cursor=pointer]
          - button "16" [ref=e597] [cursor=pointer]
          - button "17" [ref=e598] [cursor=pointer]
          - button "18" [ref=e599] [cursor=pointer]
          - button "19" [ref=e600] [cursor=pointer]
          - button "20" [ref=e601] [cursor=pointer]
          - button "21" [ref=e602] [cursor=pointer]
          - button "22" [ref=e603] [cursor=pointer]
          - button "23" [ref=e604] [cursor=pointer]
          - button "24" [ref=e605] [cursor=pointer]
          - button "25" [ref=e606] [cursor=pointer]
          - button "26" [ref=e607] [cursor=pointer]
          - button "27" [ref=e608] [cursor=pointer]
          - button "28" [ref=e609] [cursor=pointer]
          - button "29" [ref=e610] [cursor=pointer]
          - button "30" [ref=e611] [cursor=pointer]
          - button "31" [ref=e612] [cursor=pointer]
        - paragraph [ref=e617]: รวมวันไม่มีบันทึก 44 วัน | ซ้ำแบบตรงกัน 0 วัน | ซ้ำใกล้เคียง 0 วัน
      - generic [ref=e619]:
        - heading "กฎตรวจความสมเหตุสมผล (Rule Engine)" [level=4] [ref=e620]
        - paragraph [ref=e621]: "ตัวอย่างกฎ: รายรับเป็น 0, ค่าแรงสูงผิดปกติ, น้ำมันมากแต่ไม่มีเที่ยวรถ (ปรับ threshold ได้จากการ์ดสรุป)"
        - paragraph [ref=e622]: ไม่พบความผิดปกติจากกฎในช่วงที่เลือก
      - generic [ref=e624]:
        - heading "รายการที่น่าสงสัยว่าซ้ำกัน" [level=4] [ref=e625]
        - paragraph [ref=e626]: ตรวจทั้งแบบตรงกันทุกช่อง และแบบใกล้เคียงผิดปกติ (จำนวนเงิน/รายละเอียด/เวลา)
        - paragraph [ref=e627]: ไม่พบกลุ่มข้อมูลซ้ำในช่วงที่เลือก
      - generic [ref=e629]:
        - heading "แจ้งเตือน / สงสัยข้อมูลผิดพลาด" [level=4] [ref=e630]
        - paragraph [ref=e631]: สร้างเคสและติดตามสถานะได้ (ใหม่ / กำลังตรวจ / แก้แล้ว / ปิดเคส)
        - generic [ref=e633]:
          - generic [ref=e634]: วันที่อ้างอิง
          - textbox "วันที่อ้างอิง" [ref=e635]: 2026-04-24
        - textbox "เช่น วันนี้กรอกเที่ยวรถซ้ำ 2 ครั้ง / สงสัยรายรับวันที่ผิด..." [ref=e636]
        - button "บันทึกการแจ้งเตือน" [disabled] [ref=e637]
        - generic [ref=e638]:
          - text: หมายเหตุเวลาปรับสถานะเคส (ใช้ร่วมกับทุกแถว)
          - textbox "เช่น ตรวจข้อมูลย้อนหลังแล้วตรงกัน / แจ้งทีมแก้ไขแล้ว" [ref=e639]
      - generic [ref=e641]:
        - heading "Audit Trail ของเคสตรวจสอบ" [level=4] [ref=e642]
        - paragraph [ref=e643]: บันทึกว่าใครเปลี่ยนสถานะจากอะไรไปอะไร เมื่อไร และหมายเหตุ
        - paragraph [ref=e644]: ยังไม่มีประวัติการเปลี่ยนสถานะ
```

# Test source

```ts
  1  | import { expect, test } from '@playwright/test';
  2  | 
  3  | test('assign washHome + batch allocation saves successfully', async ({ page }) => {
  4  |     await page.goto('/?e2e=harness');
  5  |     await expect(page.getByText('บันทึกการล้างทราย')).toBeVisible();
  6  |     await page.getByLabel('จำนวนถังที่ได้วันนี้').locator('input').fill('10');
  7  |     await page.getByLabel('รหัสล็อตทรายวันนี้').fill('BATCH-E2E-001');
  8  |     await page.getByRole('button', { name: 'บันทึกข้อมูลล้างทราย' }).click();
  9  |     await expect(page.getByText('บันทึกการล้างทราย')).toBeVisible();
  10 | });
  11 | 
  12 | test('without washHome assignment but home drums > 0 is blocked', async ({ page }) => {
  13 |     await page.goto('/?e2e=harness');
  14 |     await page.getByLabel('จำนวนทรายที่ล้างที่บ้านวันนี้').locator('input').fill('5');
  15 |     await page.getByRole('button', { name: 'บันทึกข้อมูลล้างทราย' }).click();
  16 |     await expect(page.getByText(/ยังไม่ได้ assign งาน washHome|มีการล้างที่บ้าน/)).toBeVisible();
  17 | });
  18 | 
  19 | test('Closed workflow disables batch edit', async ({ page }) => {
  20 |     await page.goto('/?e2e=harness');
  21 |     const reason = page.getByPlaceholder('เหตุผล (บังคับเมื่อ Closed/Reopened)').first();
  22 |     const workflow = reason.locator('xpath=preceding-sibling::select[1]');
  23 |     await reason.fill('override test close');
  24 |     await workflow.selectOption('Closed');
  25 |     const batchInput = page.locator('input[value=\"BATCH-SEED-001\"]').first();
> 26 |     await expect(batchInput).toBeDisabled();
     |                              ^ Error: expect(locator).toBeDisabled() failed
  27 | });
  28 | 
  29 | test('Reopened workflow enables batch edit', async ({ page }) => {
  30 |     await page.goto('/?e2e=harness');
  31 |     const reason = page.getByPlaceholder('เหตุผล (บังคับเมื่อ Closed/Reopened)').first();
  32 |     const workflow = reason.locator('xpath=preceding-sibling::select[1]');
  33 |     await reason.fill('override test reopen');
  34 |     await workflow.selectOption('Reopened');
  35 |     const editable = page.locator('input[value=\"BATCH-SEED-001\"]').first();
  36 |     await expect(editable).toBeEnabled();
  37 | });
  38 | 
  39 | 
```