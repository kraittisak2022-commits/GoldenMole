import { BookOpen, ExternalLink, Layers } from 'lucide-react';
import MiningSimulation3D from './MiningSimulation3D';
import { SOIL_LAYERS } from './soilLayers';

const STEPS = [
  {
    title: '1. เปิดชั้นหน้าดิน',
    body: 'ใช้บุ้งกี๋ตักชั้นดินผิวหน้า (สีน้ำตาลเข้ม) ออกก่อน กองแยกไว้ข้างบ่อ อย่าผสมกับทรายหรือแร่',
  },
  {
    title: '2. กองแยกชั้นทรายแดง',
    body: 'ขุดต่อลงไปจนเจอชั้นทรายสีแดงอิฐ ตักออกและกองแยกต่างหาก — ทรายแดงไม่ใช่เป้าหมายการผลิต',
  },
  {
    title: '3. ตักชั้นแร่กะสะ',
    body: 'เมื่อเห็นชั้นกรวด/แร่สีเทาเข้ม (ชั้นกะสะ) นั่นคือชั้นเป้าหมาย ตักขึ้นไปแต่ง/แยกแร่ตามขั้นตอนหน้างาน',
  },
  {
    title: '4. หยุดเมื่อถึงชั้นดินดาล',
    body: 'ชั้นดินดาลแข็งสีเทาอมฟ้าขุดยากและไม่มีแร่ — เมื่อถึงชั้นนี้ให้หยุดขุดลึกต่อ เพื่อไม่เสียเวลาและไม่ทำลายเครื่องมือ',
  },
];

export default function KnowledgePage() {
  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-100 to-stone-200 text-slate-900">
      <header className="sticky top-0 z-20 border-b border-slate-200/80 bg-white/90 backdrop-blur">
        <div className="mx-auto max-w-5xl px-4 py-3 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <div className="rounded-xl bg-amber-500/15 p-2 text-amber-700">
              <BookOpen size={22} />
            </div>
            <div>
              <h1 className="text-base sm:text-lg font-bold leading-tight">
                ความรู้การขุดแร่ชั้นกะสะ
              </h1>
              <p className="text-xs text-slate-500">แบบจำลอง 3D สำหรับผู้ขับรถขุด · ไม่ต้องเข้าสู่ระบบ</p>
            </div>
          </div>
          <a
            href="/"
            className="inline-flex items-center gap-1.5 text-sm font-medium text-slate-600 hover:text-amber-700 transition-colors"
          >
            <ExternalLink size={16} />
            กลับสู่แอพหลัก
          </a>
        </div>
      </header>

      <main className="mx-auto max-w-5xl px-4 py-6 space-y-8">
        {/* Intro */}
        <section className="rounded-2xl bg-white border border-slate-200 shadow-sm p-4 sm:p-6">
          <div className="flex items-start gap-3">
            <Layers className="shrink-0 text-amber-600 mt-0.5" size={22} />
            <div>
              <h2 className="text-lg font-bold">แผนภูมิชั้นดินเพื่อการขุดเจาะ</h2>
              <p className="mt-1 text-sm text-slate-600 leading-relaxed">
                ใช้แบบจำลองด้านล่างบังคับรถขุด ขุดทีละชั้นตามลำดับจริงหน้างาน
                สังเกตสีดินใต้บุ้งกี๋และตัวนับแร่กะสะ เพื่อเข้าใจว่าชั้นไหนต้องเปิดออก ชั้นไหนคือเป้าหมาย
                และเมื่อใดควรหยุด
              </p>
            </div>
          </div>
        </section>

        {/* 3D Simulation */}
        <section>
          <h2 className="text-base font-bold mb-2 px-1">แบบจำลอง 3D แบบโต้ตอบ</h2>
          <MiningSimulation3D />
          <p className="mt-2 text-xs text-slate-500 px-1">
            เคล็ดลับ: ใช้ปุ่มบนจอหรือคีย์บอร์ด (WASD เคลื่อนที่ · Q/E บูม · R/F แขน · Space ขุด · X เท) ·
            ลากเมาส์/สองนิ้วเพื่อหมุนกล้อง
          </p>
        </section>

        {/* Reference image */}
        <section className="rounded-2xl bg-white border border-slate-200 shadow-sm overflow-hidden">
          <div className="px-4 sm:px-6 py-3 border-b border-slate-100">
            <h2 className="font-bold">ภาพอ้างอิงชั้นดิน</h2>
          </div>
          <figure className="p-3 sm:p-4">
            <img
              src="/knowledge/soil-layers.png"
              alt="แผนภูมิชั้นดินเพื่อการขุดเจาะ — หน้าดิน ทรายแดง ชั้นแร่กะสะ ดินดาล"
              className="w-full rounded-xl border border-slate-200 object-contain max-h-[480px] bg-slate-50"
            />
            <figcaption className="mt-2 text-xs text-slate-500 text-center">
              จากบนลงล่าง: ชั้นหน้าดิน → ชั้นทรายแดง → ชั้นแร่ (กะสะ) → ชั้นดินดาล
            </figcaption>
          </figure>
        </section>

        {/* Layer cards */}
        <section>
          <h2 className="text-base font-bold mb-3 px-1">รายละเอียดแต่ละชั้นดิน</h2>
          <div className="grid sm:grid-cols-2 gap-3">
            {SOIL_LAYERS.map((layer) => (
              <article
                key={layer.id}
                className="rounded-2xl bg-white border border-slate-200 shadow-sm p-4 flex gap-3"
              >
                <span
                  className="shrink-0 w-3 rounded-full self-stretch min-h-[3rem]"
                  style={{ backgroundColor: layer.color }}
                  aria-hidden
                />
                <div>
                  <h3 className="font-bold text-slate-900">{layer.nameTh}</h3>
                  <p className="text-xs text-slate-500">
                    {layer.nameEn} · ความลึก {layer.depthFrom}–{layer.depthTo === 20 ? '5+' : layer.depthTo} ม.
                    {!layer.diggable && (
                      <span className="ml-1 text-rose-600 font-semibold">· หยุดขุด</span>
                    )}
                    {layer.id === 'ore' && (
                      <span className="ml-1 text-amber-600 font-semibold">· เป้าหมาย</span>
                    )}
                  </p>
                  <p className="mt-1.5 text-sm text-slate-600 leading-relaxed">{layer.description}</p>
                </div>
              </article>
            ))}
          </div>
        </section>

        {/* Process steps */}
        <section className="rounded-2xl bg-white border border-slate-200 shadow-sm p-4 sm:p-6">
          <h2 className="text-lg font-bold mb-4">ขั้นตอนการขุดที่ควรจำ</h2>
          <ol className="space-y-4">
            {STEPS.map((step) => (
              <li key={step.title} className="flex gap-3">
                <span className="shrink-0 mt-0.5 flex h-7 w-7 items-center justify-center rounded-full bg-amber-100 text-amber-800 text-xs font-bold">
                  {step.title.charAt(0)}
                </span>
                <div>
                  <h3 className="font-semibold">{step.title}</h3>
                  <p className="text-sm text-slate-600 mt-0.5 leading-relaxed">{step.body}</p>
                </div>
              </li>
            ))}
          </ol>
        </section>

        <footer className="text-center text-xs text-slate-400 pb-8">
          ลิงค์สาธารณะ: เพิ่ม <code className="bg-slate-200/80 px-1 rounded">?knowledge=1</code> ท้าย URL ของเว็บแอพ
        </footer>
      </main>
    </div>
  );
}
