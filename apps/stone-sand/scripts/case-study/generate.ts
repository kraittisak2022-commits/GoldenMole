/**
 * Builds the A4 admin case-study worksheet and its answer key.
 * Run from apps/stone-sand: npx tsx scripts/case-study/generate.ts
 * Expected numbers come from the app's own pricing and driver-pay code with the rates below,
 * so update RATES_DATE and the tables when the products, tambons or drivers change.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { computeTotals } from '../../src/calc/pricing';
import { driverPayBreakdown } from '../../src/lib/driverPay';
import { ORDER_SOURCE_LABEL, PAYMENT_METHOD_LABEL, type DeliverySettings, type TruckSize } from '../../src/types';
import { CASES, type ProductId, type StudyCase, type ZoneId } from './cases';

const RATES_DATE = '9 ต.ค. 2569';

const PRODUCTS: Record<ProductId, { name: string; price: number }> = {
  'small-stone': { name: 'หินเล็กคละ เบอร์ 1-3', price: 560 },
  'big-stone': { name: 'หินคละใหญ่ เบอร์ 4-6', price: 560 },
  'fill-sand': { name: 'ทรายถม (ทรายขี้เป็ด)', price: 450 },
  'mortar-sand': { name: 'ทรายก่อ/เท', price: 560 },
};

const ZONES: Record<ZoneId, { name: string; feePerCubic: number; driverFee: number; driverFee3: number }> = {
  'thung-hua': { name: 'ทุ่งฮั้ว', feePerCubic: 0, driverFee: 400, driverFee3: 400 },
  'wang-kaeo': { name: 'วังแก้ว', feePerCubic: 0, driverFee: 500, driverFee3: 400 },
  'wang-nuea': { name: 'วังเหนือ', feePerCubic: 0, driverFee: 700, driverFee3: 500 },
  'wang-sai': { name: 'วังซ้าย', feePerCubic: 0, driverFee: 700, driverFee3: 500 },
  'wang-tai': { name: 'วังใต้', feePerCubic: 40, driverFee: 1000, driverFee3: 700 },
  'wang-sai-kham': { name: 'วังทรายคำ', feePerCubic: 40, driverFee: 1000, driverFee3: 700 },
  'wang-thong': { name: 'วังทอง', feePerCubic: 40, driverFee: 1300, driverFee3: 1000 },
  'rong-kho': { name: 'ร่องเคาะ', feePerCubic: 40, driverFee: 1300, driverFee3: 1000 },
};

const DRIVERS: Record<string, TruckSize> = {
  อ้ายโก: 5,
  โอ็ต: 5,
  เทวา: 5,
  หลวงพูน: 3,
  ลุงช่วย: 3,
  โอเว่น: 5,
  สมศักดิ์: 5,
  อินจัน: 3,
  แซม: 3,
  อ้ายเบล: 5,
  อาวชาติ: 5,
  พ่อเลี้ยงตุ๋ย: 5,
};

const DELIVERY: DeliverySettings = { nearKm: 1, driverPerKm5: 50, driverPerKm3: 30 };

const money = (n: number) => n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const num = (n: number) => n.toLocaleString('en-US', { maximumFractionDigits: 2 });
const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const pad = (n: number) => String(n).padStart(2, '0');

interface Expected {
  qty: number;
  trips: number;
  truck: TruckSize | null;
  subtotal: number;
  deliveryTotal: number;
  itemDiscount: number;
  deliveryDiscount: number;
  billDiscount: number;
  total: number;
  driverRate: number;
  driverPay: number;
  deliveryFee: number;
  goods: number;
  net: number;
  paid: boolean;
  receivable: number;
  stageNow: string;
  stageDelivered: string | null;
}

function expected(c: StudyCase): Expected {
  const items = c.items.map((it) => ({
    unitPrice: PRODUCTS[it.product].price,
    quantity: Math.round(it.perTrip * it.trips * 10) / 10,
    discountPerUnit: it.unitDiscount ?? 0,
  }));
  const trips = c.items.reduce((s, it) => s + it.trips, 0);
  const d = c.delivery;
  const zone = d ? ZONES[d.zone] : undefined;
  const truck = d ? DRIVERS[d.driver] : null;
  if (d && truck == null) throw new Error(`unknown driver ${d.driver}`);
  if (d && truck! < Math.max(...c.items.map((it) => it.perTrip))) throw new Error(`${c.title}: truck too small`);

  const t = computeTotals({
    items,
    feePerCubic: zone?.feePerCubic ?? 0,
    feePerTrip: 0,
    trips: d ? trips : 0,
    remoteSurcharge: d?.remote ?? 0,
    deliveryDiscount: d?.deliveryDiscount ?? 0,
    discountType: c.billDiscount?.type ?? 'baht',
    discountValue: c.billDiscount?.value ?? 0,
  });

  const pay = d
    ? driverPayBreakdown(
        {
          driverWage: 0,
          trips,
          truckSize: truck,
          roadDistanceKm: null,
          deliveryTotal: t.deliveryTotal,
          deliveryDiscount: t.deliveryDiscount,
        },
        zone,
        DELIVERY,
      )
    : null;
  const driverPay = pay?.amount ?? 0;
  const deliveryFee = Math.max(0, t.deliveryTotal - t.deliveryDiscount);

  const paid = c.payment === 'cash' || c.payment === 'transfer' ? c.paidNow ?? true : false;
  const moneyStage = paid ? null : c.payment === 'cod' && d ? 'รอรับเงินจากคนขับ' : c.payment === 'credit' ? 'รอวางบิล' : 'รอรับเงิน';
  const stageNow = d ? 'รอจัดส่ง' : moneyStage ?? 'ปิดงานแล้ว';
  const stageDelivered = d ? moneyStage ?? 'รอเคลียร์ค่ารถ' : null;

  return {
    qty: t.totalQuantity,
    trips,
    truck,
    subtotal: t.subtotal,
    deliveryTotal: t.deliveryTotal,
    itemDiscount: t.itemDiscount,
    deliveryDiscount: t.deliveryDiscount,
    billDiscount: t.billDiscount,
    total: t.total,
    driverRate: pay?.rate.perTrip ?? 0,
    driverPay,
    deliveryFee,
    goods: t.total - deliveryFee,
    net: t.total - driverPay,
    paid,
    receivable: paid ? 0 : t.total,
    stageNow,
    stageDelivered,
  };
}

const payLabel = (c: StudyCase) => {
  const base = PAYMENT_METHOD_LABEL[c.payment];
  if (c.payment === 'cash' || c.payment === 'transfer') return `${base} · ${c.paidNow ?? true ? 'ติ๊ก "ได้รับเงินแล้ว"' : 'ไม่ติ๊ก "ได้รับเงินแล้ว"'}`;
  return base;
};

const discountLabel = (c: StudyCase) =>
  c.billDiscount ? `${num(c.billDiscount.value)} ${c.billDiscount.type === 'percent' ? '%' : 'บาท'}` : '—';

function inputRows(c: StudyCase): [string, string][] {
  const d = c.delivery;
  const rows: [string, string][] = [
    ['1. ประเภท / วันที่', `ออเดอร์${ORDER_SOURCE_LABEL[c.source]} · วันที่ "วันนี้"`],
    [
      '2. สินค้า',
      c.items
        .map((it) => `${PRODUCTS[it.product].name} — ${num(it.perTrip)} คิว/เที่ยว × ${it.trips} เที่ยว`)
        .join('<br>'),
    ],
    [
      '3. ลูกค้า (เพิ่มใหม่)',
      `${esc(c.customer.name)}<br><span class="muted">โทร ${c.customer.phone.replace(/(\d{3})(\d{3})(\d{4})/, '$1-$2-$3')} · ที่อยู่ ${esc(c.customer.address)}</span>`,
    ],
  ];
  if (d) {
    rows.push([
      '4. การรับสินค้า',
      `<b>จัดส่ง</b> · ไม่ต้องปักหมุด พิมพ์ที่อยู่: ${esc(d.address)}<br>ตำบล: <b>${ZONES[d.zone].name}</b> (เลือกเอง) · คนขับ: <b>${d.driver}</b> (รถ ${DRIVERS[d.driver]} คิว)` +
        (d.remote ? `<br>ที่กันดาร (บวกเพิ่ม): <b>${num(d.remote)}</b> บาท` : ''),
    ]);
  } else {
    rows.push(['4. การรับสินค้า', '<b>มารับเอง</b>']);
  }
  const disc: string[] = [];
  c.items.forEach((it) => it.unitDiscount && disc.push(`ลดคิวละ ${num(it.unitDiscount)} บาท (${PRODUCTS[it.product].name})`));
  if (d?.deliveryDiscount) disc.push(`ลดค่าส่ง ${num(d.deliveryDiscount)} บาท`);
  if (c.billDiscount) disc.push(`ส่วนลดท้ายบิล ${discountLabel(c)}`);
  rows.push(['5. สรุป / ส่วนลด', disc.length ? disc.join('<br>') : 'ไม่มีส่วนลด']);
  rows.push(['6. วิธีชำระเงิน', payLabel(c) + (c.note ? `<br>หมายเหตุ: ${esc(c.note)}` : '')]);
  return rows;
}

const CHECK_FIELDS: { label: string; hint: string; delivery?: boolean }[] = [
  { label: 'เลขที่เอกสาร', hint: 'DO… / TS…' },
  { label: 'รวมคิว / จำนวนเที่ยว', hint: 'ขั้นสินค้า' },
  { label: 'ค่าสินค้า', hint: 'ก่อนส่วนลด' },
  { label: 'ค่าจัดส่ง', hint: 'ก่อนลดค่าส่ง', delivery: true },
  { label: 'ส่วนลดรวม', hint: 'ทุกส่วนลด' },
  { label: 'ยอดสุทธิ', hint: 'ตัวเลขสีน้ำเงิน' },
  { label: 'ค่ารถคนขับ', hint: 'ใต้ช่องยืนยันคนขับ', delivery: true },
  { label: 'คงเหลือเข้าร้าน', hint: 'เมนูสรุปบิล' },
  { label: 'ขั้นตอนในสรุปบิล', hint: 'ป้ายสถานะ' },
];

function casePage(c: StudyCase, i: number): string {
  const d = c.delivery;
  const fields = CHECK_FIELDS.filter((f) => !f.delivery || d);
  return `
<section class="page">
  <header class="head">
    <div>
      <p class="kicker">Case Study · ทดสอบการเปิดออเดอร์</p>
      <h1>เคสที่ ${pad(i + 1)} · ${esc(c.title)}</h1>
    </div>
    <div class="head-right">
      <span class="level level-${c.level}">${c.level}</span>
      <span class="count">${pad(i + 1)} / ${pad(CASES.length)}</span>
    </div>
  </header>
  <p class="tags">${c.topics.map((t) => `<span>${esc(t)}</span>`).join('')}</p>

  <div class="story"><b>โจทย์</b> ${esc(c.story)}</div>

  <h2>ข้อมูลที่ต้องกรอก (เมนู "สร้างออเดอร์")</h2>
  <table class="input">
    ${inputRows(c)
      .map(([k, v]) => `<tr><th>${k}</th><td>${v}</td></tr>`)
      .join('')}
  </table>

  ${
    c.tryFirst?.length
      ? `<div class="try"><b>ให้ลองทำระหว่างกรอก</b><ol>${c.tryFirst.map((t) => `<li>${esc(t)}</li>`).join('')}</ol>
         <p class="write">สิ่งที่ระบบแสดง: <span class="line"></span></p></div>`
      : ''
  }

  <h2>จดผลที่ระบบแสดง</h2>
  <table class="check">
    <thead><tr><th>รายการ</th><th>ระบบแสดง</th><th class="ok">ผู้ตรวจ ✓/✗</th></tr></thead>
    <tbody>
      ${fields
        .map((f) => `<tr><th>${f.label}<small>${f.hint}</small></th><td></td><td class="ok"></td></tr>`)
        .join('')}
    </tbody>
  </table>

  <div class="issue">
    <b>ปัญหา / ข้อสังเกตที่พบ</b>
    <span class="line"></span><span class="line"></span>
  </div>

  <footer class="sign">
    <span>ผู้กรอก ............................................</span>
    <span>วันที่/เวลา ......................................</span>
    <span>ผู้ตรวจ ............................................</span>
  </footer>
</section>`;
}

function coverPage(): string {
  return `
<section class="page cover">
  <p class="kicker">Golden Mole · ระบบสั่งหิน-ทราย</p>
  <h1 class="title">Case Study<br>ทดสอบการเปิดออเดอร์ 20 เคส</h1>
  <p class="lead">ชุดฝึกให้แอดมินลองกรอกออเดอร์จริงในระบบ แล้วจดตัวเลขที่ระบบแสดง เพื่อตรวจว่า<br>
  <b>(1) แอดมินกรอกข้อมูลถูกต้อง</b> และ <b>(2) ระบบคำนวณ/ทำงานถูกต้อง</b></p>

  <h2>วิธีทำ</h2>
  <ol class="steps">
    <li>เข้าเมนู <b>สร้างออเดอร์</b> แล้วกรอกตาม "ข้อมูลที่ต้องกรอก" ของแต่ละเคสทีละขั้น</li>
    <li>เพิ่มลูกค้าใหม่ตามชื่อในเคส (ทุกชื่อขึ้นต้นด้วย <b>"ทดสอบ"</b> เพื่อแยกจากลูกค้าจริง)</li>
    <li>เคสจัดส่ง: <b>ไม่ต้องปักหมุด</b> พิมพ์ที่อยู่ แล้วเลือกตำบลจากรายการเอง (ตัวเลขจะได้ตรงกับเฉลย)</li>
    <li>ระหว่างกรอก จดตัวเลขลงตาราง "จดผลที่ระบบแสดง" ส่วน "คงเหลือเข้าร้าน" และ "ขั้นตอน" ดูที่เมนู <b>สรุปบิล</b> หลังบันทึก</li>
    <li>ถ้าเคสมีกล่อง "ให้ลองทำระหว่างกรอก" ให้ทำตามและจดว่าระบบแสดงอะไร</li>
    <li>ส่งใบงานให้ผู้ตรวจเทียบกับ <b>เฉลย</b> (แยกเป็นอีกไฟล์)</li>
  </ol>

  <h2>ระดับความยาก</h2>
  <table class="levels">
    <tr><th><span class="level level-พื้นฐาน">พื้นฐาน</span></th><td>เคส 01–06 · มารับเอง / จัดส่งธรรมดา / วิธีจ่ายเงินแบบต่างๆ</td></tr>
    <tr><th><span class="level level-ปานกลาง">ปานกลาง</span></th><td>เคส 07–15 · ขนาดรถ หลายสินค้า คิวไม่เต็ม และส่วนลดทุกแบบ</td></tr>
    <tr><th><span class="level level-ท้าทาย">ท้าทาย</span></th><td>เคส 16–20 · ทดสอบขอบเขต การบังคับกรอก ที่กันดาร และบิลใหญ่</td></tr>
  </table>

  <div class="warn">
    <b>หลังทดสอบเสร็จ</b> ให้ <b>ยกเลิกออเดอร์</b> ของลูกค้า "ทดสอบ01–20" ทุกใบ และลบลูกค้าทดสอบออก
    เพื่อไม่ให้ปนกับยอดขายจริง (ออเดอร์ที่ยกเลิกจะไม่ถูกนับในสรุปบิล)
  </div>

  <footer class="sign cover-sign">
    <span>ชื่อผู้ทดสอบ ............................................</span>
    <span>วันที่ทดสอบ ............................................</span>
  </footer>
</section>`;
}

function answerCover(rows: { c: StudyCase; e: Expected }[]): string {
  const sum = (f: (e: Expected) => number) => rows.reduce((s, r) => s + f(r.e), 0);
  return `
<section class="page">
  <p class="kicker">เฉลยสำหรับผู้ตรวจ · ห้ามแจกให้ผู้ทดสอบ</p>
  <h1 class="title-sm">เฉลย Case Study 20 เคส</h1>
  <p class="lead">ตัวเลขทั้งหมดคำนวณด้วยสูตรเดียวกับในระบบ จากราคาและอัตราค่าส่ง ณ ${RATES_DATE}
  ถ้าแก้ราคาสินค้า อัตราตำบล หรือคนขับหลังวันนี้ ตัวเลขในเฉลยจะไม่ตรง ต้องสร้างเฉลยใหม่</p>

  <h2>ราคาสินค้า</h2>
  <table class="ref">
    <thead><tr><th>สินค้า</th><th class="r">บาท/คิว</th></tr></thead>
    <tbody>${Object.values(PRODUCTS).map((p) => `<tr><td>${p.name}</td><td class="r">${num(p.price)}</td></tr>`).join('')}</tbody>
  </table>

  <h2>อัตราตำบล</h2>
  <table class="ref">
    <thead><tr><th>ตำบล</th><th class="r">ค่าส่งลูกค้า บาท/คิว</th><th class="r">ค่ารถคนขับ รถ 5 คิว/เที่ยว</th><th class="r">ค่ารถคนขับ รถ 3 คิว/เที่ยว</th></tr></thead>
    <tbody>${Object.values(ZONES)
      .map((z) => `<tr><td>${z.name}</td><td class="r">${num(z.feePerCubic)}</td><td class="r">${num(z.driverFee)}</td><td class="r">${num(z.driverFee3)}</td></tr>`)
      .join('')}</tbody>
  </table>

  <h2>สูตรที่ใช้ตรวจ</h2>
  <ul class="formula">
    <li><b>ค่าจัดส่ง</b> = ค่าส่ง/คิว ของตำบล × คิวรวม + ที่กันดาร (ไม่ปักหมุด จึงไม่มีค่าเพิ่มตามระยะ)</li>
    <li><b>ยอดสุทธิ</b> = ค่าสินค้า + ค่าจัดส่ง − ลดคิวละ − ลดค่าส่ง (ไม่เกินค่าจัดส่ง) − ส่วนลดท้ายบิล (% คิดจากค่าสินค้าหลังลดคิวละ เท่านั้น)</li>
    <li><b>ค่ารถคนขับ</b> = อัตราตำบลตามขนาดรถของคนขับ × จำนวนเที่ยว (ไม่รวมที่กันดาร)</li>
    <li><b>คงเหลือเข้าร้าน</b> = ยอดสุทธิ − ค่ารถคนขับ</li>
  </ul>

  <h2>ยอดรวมทั้ง 20 เคส (ใช้เทียบหน้าสรุปบิล เมื่อกรองเฉพาะลูกค้าทดสอบ)</h2>
  <table class="ref">
    <tbody>
      <tr><td>ยอดบิลรวม</td><td class="r">${money(sum((e) => e.total))}</td></tr>
      <tr><td>ค่ารถคนขับรวม</td><td class="r">${money(sum((e) => e.driverPay))}</td></tr>
      <tr><td>คงเหลือเข้าร้านรวม</td><td class="r"><b>${money(sum((e) => e.net))}</b></td></tr>
      <tr><td>ค้างรับรวม (ทันทีหลังบันทึก)</td><td class="r">${money(sum((e) => e.receivable))}</td></tr>
    </tbody>
  </table>
</section>`;
}

function answerBlock(c: StudyCase, e: Expected, i: number): string {
  const d = c.delivery;
  const discount = e.itemDiscount + e.deliveryDiscount + e.billDiscount;
  const discParts = [
    e.itemDiscount ? `ลดคิวละ ${money(e.itemDiscount)}` : '',
    e.deliveryDiscount ? `ลดค่าส่ง ${money(e.deliveryDiscount)}` : '',
    e.billDiscount ? `ท้ายบิล ${money(e.billDiscount)}` : '',
  ].filter(Boolean);
  const rows: [string, string][] = [
    ['เลขที่เอกสาร', c.source === 'pit' ? 'ขึ้นต้น TS' : 'ขึ้นต้น DO'],
    ['รวมคิว / เที่ยว', `${num(e.qty)} คิว · ${e.trips} เที่ยว${e.truck ? ` · รถ ${e.truck} คิว` : ''}`],
    ['ค่าสินค้า', money(e.subtotal)],
    ...(d ? ([['ค่าจัดส่ง', money(e.deliveryTotal)]] as [string, string][]) : []),
    ['ส่วนลดรวม', discount ? `${money(discount)} <small>(${discParts.join(' + ')})</small>` : '0.00'],
    ['ยอดสุทธิ', `<b>${money(e.total)}</b>`],
    ...(d
      ? ([['ค่ารถคนขับ', `${money(e.driverPay)} <small>(${num(e.driverRate)} × ${e.trips} เที่ยว · ต.${ZONES[d.zone].name} รถ ${e.truck} คิว)</small>`]] as [string, string][])
      : []),
    ['คงเหลือเข้าร้าน', `<b class="pos">${money(e.net)}</b>${d ? ` <small>(กำไรค่าส่ง: ค่าส่งเก็บลูกค้า ${money(e.deliveryFee)} − ค่ารถ ${money(e.driverPay)} = ${money(e.deliveryFee - e.driverPay)})</small>` : ''}`],
    ['ค้างรับ', money(e.receivable)],
    ['ขั้นตอนในสรุปบิล', `<b>${e.stageNow}</b>${e.stageDelivered ? ` <small>→ หลังกด "ส่งแล้ว": ${e.stageDelivered}</small>` : ''}`],
  ];
  return `
<article class="ans">
  <h3>เคสที่ ${pad(i + 1)} · ${esc(c.title)} <span class="muted">· ${esc(c.customer.name)} · ${PAYMENT_METHOD_LABEL[c.payment]}</span></h3>
  <table class="ans-t">${rows.map(([k, v]) => `<tr><th>${k}</th><td>${v}</td></tr>`).join('')}</table>
  ${c.expectBehaviour?.length ? `<p class="behave"><b>ต้องเห็น:</b> ${c.expectBehaviour.map(esc).join(' · ')}</p>` : ''}
</article>`;
}

const CSS = `
@page { size: A4; margin: 10mm 13mm; }
* { box-sizing: border-box; }
body { margin: 0; font-family: 'Sarabun', 'Leelawadee UI', 'Leelawadee', Tahoma, sans-serif; font-size: 10.5pt; color: #1f2937; line-height: 1.45; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
.page { page-break-after: always; break-after: page; }
.page:last-child { page-break-after: auto; break-after: auto; }
h1 { font-size: 17pt; margin: 2px 0 0; line-height: 1.25; }
h2 { font-size: 11pt; margin: 9px 0 4px; color: #0f5132; border-left: 4px solid #198754; padding-left: 7px; }
h3 { font-size: 10.5pt; margin: 0 0 4px; }
small { display: block; font-size: 8pt; color: #6b7280; font-weight: 400; }
td small, h3 small { display: inline; }
.muted { color: #6b7280; font-weight: 400; }
.kicker { margin: 0; font-size: 8.5pt; letter-spacing: .04em; color: #198754; font-weight: 600; text-transform: uppercase; }
.head { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; border-bottom: 2px solid #111827; padding-bottom: 6px; }
.head-right { display: flex; flex-direction: column; align-items: flex-end; gap: 4px; }
.count { font-size: 9pt; color: #6b7280; font-variant-numeric: tabular-nums; }
.level { display: inline-block; border-radius: 999px; padding: 1px 10px; font-size: 8.5pt; font-weight: 700; }
.level-พื้นฐาน { background: #d1fae5; color: #065f46; }
.level-ปานกลาง { background: #fef3c7; color: #92400e; }
.level-ท้าทาย { background: #fee2e2; color: #991b1b; }
.tags { margin: 6px 0 0; display: flex; flex-wrap: wrap; gap: 4px; }
.tags span { background: #f3f4f6; border-radius: 4px; padding: 0 7px; font-size: 8.5pt; color: #374151; }
.story { margin-top: 8px; background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 6px; padding: 6px 11px; font-size: 10.5pt; }
.story b { color: #166534; margin-right: 4px; }
table { width: 100%; border-collapse: collapse; }
.input th, .input td, .check th, .check td, .ref th, .ref td, .ans-t th, .ans-t td { border: 1px solid #d1d5db; padding: 4px 8px; vertical-align: top; text-align: left; }
.input th { width: 30%; background: #f9fafb; font-weight: 600; }
.check thead th { background: #111827; color: #fff; font-size: 9pt; }
.check tbody th { width: 34%; background: #f9fafb; font-weight: 600; }
.check tbody th { padding-top: 2px; padding-bottom: 2px; line-height: 1.25; }
.check tbody td { height: 26px; }
.check .ok { width: 18%; text-align: center; }
.try { margin-top: 8px; border: 1.5px dashed #f59e0b; background: #fffbeb; border-radius: 6px; padding: 5px 11px; }
.try ol { margin: 3px 0 0; padding-left: 18px; }
.write { margin: 6px 0 0; display: flex; gap: 6px; align-items: flex-end; }
.line { display: block; flex: 1; border-bottom: 1px dotted #6b7280; height: 20px; }
.issue { margin-top: 8px; }
.issue .line { margin-top: 2px; }
.sign { margin-top: 10px; display: flex; justify-content: space-between; gap: 8px; font-size: 9pt; color: #374151; }
.cover .title { font-size: 26pt; margin: 6px 0 8px; }
.title-sm { font-size: 20pt; margin: 4px 0 6px; }
.lead { font-size: 11pt; color: #374151; }
.steps { padding-left: 20px; margin: 4px 0; }
.steps li { margin: 3px 0; }
.levels th { width: 22%; padding: 6px 8px; text-align: left; border: 1px solid #e5e7eb; }
.levels td { padding: 6px 8px; border: 1px solid #e5e7eb; }
.warn { margin-top: 16px; background: #fef2f2; border: 1px solid #fecaca; border-radius: 6px; padding: 9px 12px; color: #7f1d1d; }
.cover-sign { margin-top: 28px; }
.ref thead th { background: #f3f4f6; font-size: 9pt; }
.r { text-align: right !important; font-variant-numeric: tabular-nums; }
.formula { padding-left: 18px; margin: 4px 0; }
.formula li { margin: 3px 0; }
.ans { break-inside: avoid; page-break-inside: avoid; margin-bottom: 10px; }
.ans-t th { width: 26%; background: #f9fafb; font-weight: 600; font-size: 9.5pt; padding: 3px 8px; }
.ans-t td { font-variant-numeric: tabular-nums; padding: 3px 8px; }
.pos { color: #047857; }
.behave { margin: 4px 0 0; font-size: 9.5pt; background: #fffbeb; border-left: 3px solid #f59e0b; padding: 3px 8px; }
`;

const doc = (title: string, body: string) => `<!doctype html>
<html lang="th"><head><meta charset="utf-8"><title>${title}</title><style>${CSS}</style></head>
<body>${body}</body></html>`;

const rows = CASES.map((c) => ({ c, e: expected(c) }));
const outDir = join(dirname(fileURLToPath(import.meta.url)), '../../docs/case-study');
mkdirSync(outDir, { recursive: true });

writeFileSync(
  join(outDir, 'case-study-admin.html'),
  doc('Case Study ทดสอบการเปิดออเดอร์', coverPage() + CASES.map(casePage).join('')),
);

const answerPages: string[] = [];
for (let i = 0; i < rows.length; i += 3) {
  answerPages.push(`<section class="page">${rows.slice(i, i + 3).map((r, j) => answerBlock(r.c, r.e, i + j)).join('')}</section>`);
}
writeFileSync(join(outDir, 'case-study-answer-key.html'), doc('เฉลย Case Study', answerCover(rows) + answerPages.join('')));

for (const [i, { c, e }] of rows.entries()) {
  console.log(
    `${pad(i + 1)} ${c.title.padEnd(36)} total=${money(e.total).padStart(10)} driver=${money(e.driverPay).padStart(9)} net=${money(e.net).padStart(10)} ${e.stageNow}`,
  );
}
