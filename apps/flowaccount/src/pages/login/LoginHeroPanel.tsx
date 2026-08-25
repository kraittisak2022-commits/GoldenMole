import {
  BookOpen,
  LayoutDashboard,
  Truck,
  Wallet,
} from 'lucide-react';

const chips = [
  { label: 'แดชบอร์ด', icon: LayoutDashboard, delay: '0ms', float: 'animate-login-float' },
  { label: 'รายรับ-จ่าย', icon: BookOpen, delay: '120ms', float: 'animate-login-float-slow' },
  { label: 'เงินเดือน', icon: Wallet, delay: '240ms', float: 'animate-login-float' },
  { label: 'ต้นทุนรถ', icon: Truck, delay: '360ms', float: 'animate-login-float-slow' },
] as const;

const sampleRows = [
  { label: 'รายรับเดือนนี้', value: '฿ 428,500', tone: 'text-emerald-700' },
  { label: 'รายจ่ายเดือนนี้', value: '฿ 312,180', tone: 'text-ink' },
  { label: 'คงเหลือสุทธิ', value: '฿ 116,320', tone: 'text-accent' },
] as const;

export default function LoginHeroPanel() {
  return (
    <div className="relative flex h-full flex-col justify-between overflow-hidden px-4 py-6 md:px-8 md:py-10 lg:px-12 lg:py-14">
      <div>
        <div className="animate-login-enter" style={{ animationDelay: '40ms' }}>
          <div className="inline-flex h-10 w-10 items-center justify-center rounded-DEFAULT bg-accent text-accent-foreground shadow-sm md:h-14 md:w-14">
            <Wallet className="h-[18px] w-[18px] md:h-6 md:w-6" aria-hidden />
          </div>
        </div>

        <p
          className="mt-5 text-xs font-medium uppercase tracking-[0.2em] text-muted animate-login-enter"
          style={{ animationDelay: '100ms' }}
        >
          GoldenMole
        </p>
        <h1
          className="mt-2 text-2xl font-semibold tracking-tight text-ink animate-login-enter md:text-4xl lg:text-5xl"
          style={{ animationDelay: '160ms' }}
        >
          FlowAccount
        </h1>
        <p
          className="mt-3 max-w-sm text-sm text-muted animate-login-enter md:text-base"
          style={{ animationDelay: '220ms' }}
        >
          ระบบงานบัญชี — เข้าสู่ระบบด้วยบัญชี SuperAdmin
        </p>

        <div
          className="mt-8 hidden max-w-sm gap-2 animate-login-enter md:grid"
          style={{ animationDelay: '280ms' }}
        >
          {sampleRows.map((row) => (
            <div
              key={row.label}
              className="flex items-center justify-between rounded-DEFAULT border border-border/70 bg-surface/70 px-3.5 py-2.5 backdrop-blur-sm"
            >
              <span className="text-xs text-muted">{row.label}</span>
              <span className={`text-sm font-medium tabular-nums ${row.tone}`}>{row.value}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-5 flex flex-wrap gap-2 md:mt-10">
        {chips.map((chip) => {
          const Icon = chip.icon;
          return (
            <div
              key={chip.label}
              className="animate-login-enter"
              style={{ animationDelay: chip.delay }}
            >
              <span
                className={[
                  'inline-flex items-center gap-1.5 rounded-full border border-border/80 bg-surface/80 px-3 py-1.5 text-xs font-medium text-ink shadow-sm backdrop-blur-sm',
                  chip.float,
                ].join(' ')}
              >
                <Icon size={13} className="text-accent" aria-hidden />
                {chip.label}
              </span>
            </div>
          );
        })}
        <div className="animate-login-enter" style={{ animationDelay: '480ms' }}>
          <span
            className="inline-flex h-8 w-8 items-center justify-center rounded-full border border-gold/40 bg-gold/15 text-sm font-semibold text-amber-800 animate-login-float"
            aria-hidden
          >
            ฿
          </span>
        </div>
      </div>
    </div>
  );
}
