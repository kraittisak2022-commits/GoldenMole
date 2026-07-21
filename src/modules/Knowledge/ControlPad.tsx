import { useCallback, useEffect, useRef } from 'react';
import {
  ArrowDown,
  ArrowLeft,
  ArrowRight,
  ArrowUp,
  AlertTriangle,
  Shovel,
  Trash2,
} from 'lucide-react';
import {
  SOIL_LAYERS,
  type ControlAction,
  type ControlState,
  type DigStats,
  EMPTY_CONTROLS,
} from './soilLayers';

interface ControlPadProps {
  digStats: DigStats;
  onControlsChange: (controls: ControlState) => void;
}

function HoldButton({
  label,
  action,
  onHold,
  className = '',
  children,
}: {
  label: string;
  action: ControlAction;
  onHold: (action: ControlAction, pressed: boolean) => void;
  className?: string;
  children?: React.ReactNode;
}) {
  const set = useCallback(
    (pressed: boolean) => onHold(action, pressed),
    [action, onHold],
  );

  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      className={`select-none touch-none rounded-xl border border-white/20 bg-slate-800/80 text-white shadow-lg active:bg-amber-600/80 active:scale-95 transition-transform ${className}`}
      onPointerDown={(e) => {
        e.preventDefault();
        (e.currentTarget as HTMLButtonElement).setPointerCapture(e.pointerId);
        set(true);
      }}
      onPointerUp={() => set(false)}
      onPointerCancel={() => set(false)}
      onPointerLeave={(e) => {
        if (e.buttons === 0) set(false);
      }}
      onContextMenu={(e) => e.preventDefault()}
    >
      {children ?? label}
    </button>
  );
}

export default function ControlPad({ digStats, onControlsChange }: ControlPadProps) {
  const controlsRef = useRef<ControlState>({ ...EMPTY_CONTROLS });

  const publish = useCallback(() => {
    onControlsChange({ ...controlsRef.current });
  }, [onControlsChange]);

  const setHold = useCallback(
    (action: ControlAction, pressed: boolean) => {
      if (controlsRef.current[action] === pressed) return;
      controlsRef.current = { ...controlsRef.current, [action]: pressed };
      publish();
    },
    [publish],
  );

  useEffect(() => {
    const keyMap: Record<string, ControlAction> = {
      KeyW: 'forward',
      ArrowUp: 'forward',
      KeyS: 'back',
      ArrowDown: 'back',
      KeyA: 'turnLeft',
      ArrowLeft: 'turnLeft',
      KeyD: 'turnRight',
      ArrowRight: 'turnRight',
      KeyQ: 'boomUp',
      KeyE: 'boomDown',
      KeyR: 'armOut',
      KeyF: 'armIn',
      KeyT: 'bucketCurl',
      KeyG: 'bucketDump',
      Space: 'dig',
      KeyX: 'dump',
    };

    const onKeyDown = (e: KeyboardEvent) => {
      const action = keyMap[e.code];
      if (!action) return;
      e.preventDefault();
      setHold(action, true);
    };
    const onKeyUp = (e: KeyboardEvent) => {
      const action = keyMap[e.code];
      if (!action) return;
      e.preventDefault();
      setHold(action, false);
    };

    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    return () => {
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('keyup', onKeyUp);
    };
  }, [setHold]);

  const layerLabel =
    digStats.currentLayer == null
      ? '—'
      : SOIL_LAYERS.find((l) => l.id === digStats.currentLayer)?.nameTh ?? '—';

  const fillPct = Math.min(
    100,
    Math.round((digStats.bucketFill / digStats.bucketCapacity) * 100),
  );

  return (
    <div className="pointer-events-none absolute inset-0 flex flex-col justify-between p-2 sm:p-3">
      {/* HUD top */}
      <div className="pointer-events-auto flex flex-wrap gap-2 items-start justify-between">
        <div className="rounded-xl bg-slate-900/85 backdrop-blur text-white px-3 py-2 text-sm shadow-lg max-w-xs">
          <div className="font-semibold text-amber-300">สถานะการขุด</div>
          <div className="mt-1 space-y-0.5 text-xs sm:text-sm">
            <div>
              ชั้นใต้บุ้งกี๋:{' '}
              <span className="font-medium text-emerald-300">{layerLabel}</span>
            </div>
            <div>
              ความลึก:{' '}
              <span className="font-mono">{digStats.currentDepth.toFixed(1)} ม.</span>
            </div>
            <div className="flex items-center gap-2">
              <span>บุ้งกี๋:</span>
              <div className="h-2 flex-1 min-w-[4rem] rounded bg-slate-700 overflow-hidden">
                <div
                  className="h-full bg-amber-500 transition-all"
                  style={{ width: `${fillPct}%` }}
                />
              </div>
              <span className="font-mono text-xs">{fillPct}%</span>
            </div>
            <div className="pt-1 border-t border-white/10 grid grid-cols-2 gap-x-3 gap-y-0.5">
              <span>หน้าดิน: {digStats.topsoil.toFixed(1)}</span>
              <span>ทรายแดง: {digStats.redSand.toFixed(1)}</span>
              <span className="text-amber-300 font-semibold">
                แร่กะสะ: {digStats.ore.toFixed(1)}
              </span>
              <span>ดินดาล: {digStats.hardpan.toFixed(1)}</span>
            </div>
          </div>
          {digStats.hardpanWarning && (
            <div className="mt-2 flex items-center gap-1.5 text-rose-300 text-xs font-semibold animate-pulse">
              <AlertTriangle size={14} />
              ถึงชั้นดินดาลแล้ว — หยุดขุด
            </div>
          )}
        </div>

        <div className="rounded-xl bg-slate-900/85 backdrop-blur text-white px-3 py-2 text-xs shadow-lg hidden sm:block">
          <div className="font-semibold mb-1 text-amber-300">สีชั้นดิน</div>
          <ul className="space-y-1">
            {SOIL_LAYERS.map((l) => (
              <li key={l.id} className="flex items-center gap-2">
                <span
                  className="inline-block w-3 h-3 rounded-sm border border-white/30"
                  style={{ backgroundColor: l.color }}
                />
                {l.nameTh}
              </li>
            ))}
          </ul>
        </div>
      </div>

      {/* Controls bottom */}
      <div className="pointer-events-auto flex flex-wrap items-end justify-between gap-3">
        {/* Drive pad */}
        <div className="flex flex-col items-center gap-1">
          <span className="text-[10px] text-white/70 bg-slate-900/60 px-2 py-0.5 rounded">
            เคลื่อนที่ (WASD)
          </span>
          <HoldButton
            label="เดินหน้า"
            action="forward"
            onHold={setHold}
            className="w-12 h-12 flex items-center justify-center"
          >
            <ArrowUp size={22} />
          </HoldButton>
          <div className="flex gap-1">
            <HoldButton
              label="เลี้ยวซ้าย"
              action="turnLeft"
              onHold={setHold}
              className="w-12 h-12 flex items-center justify-center"
            >
              <ArrowLeft size={22} />
            </HoldButton>
            <HoldButton
              label="ถอยหลัง"
              action="back"
              onHold={setHold}
              className="w-12 h-12 flex items-center justify-center"
            >
              <ArrowDown size={22} />
            </HoldButton>
            <HoldButton
              label="เลี้ยวขวา"
              action="turnRight"
              onHold={setHold}
              className="w-12 h-12 flex items-center justify-center"
            >
              <ArrowRight size={22} />
            </HoldButton>
          </div>
        </div>

        {/* Dig / Dump */}
        <div className="flex flex-col gap-2 items-center">
          <HoldButton
            label="ขุด (Space)"
            action="dig"
            onHold={setHold}
            className="px-4 h-14 min-w-[5.5rem] flex items-center justify-center gap-2 font-bold bg-amber-700/90"
          >
            <Shovel size={20} />
            ขุด
          </HoldButton>
          <HoldButton
            label="เท (X)"
            action="dump"
            onHold={setHold}
            className="px-4 h-12 min-w-[5.5rem] flex items-center justify-center gap-2 font-semibold bg-emerald-700/90"
          >
            <Trash2 size={18} />
            เท
          </HoldButton>
        </div>

        {/* Arm controls */}
        <div className="flex flex-col gap-1 items-end">
          <span className="text-[10px] text-white/70 bg-slate-900/60 px-2 py-0.5 rounded">
            แขน (Q/E R/F T/G)
          </span>
          <div className="grid grid-cols-3 gap-1">
            <HoldButton
              label="บูมขึ้น"
              action="boomUp"
              onHold={setHold}
              className="w-11 h-10 text-xs font-medium"
            >
              บูม↑
            </HoldButton>
            <HoldButton
              label="แขนยื่น"
              action="armOut"
              onHold={setHold}
              className="w-11 h-10 text-xs font-medium"
            >
              แขน→
            </HoldButton>
            <HoldButton
              label="ม้วนบุ้งกี๋"
              action="bucketCurl"
              onHold={setHold}
              className="w-11 h-10 text-xs font-medium"
            >
              บุ้ง↻
            </HoldButton>
            <HoldButton
              label="บูมลง"
              action="boomDown"
              onHold={setHold}
              className="w-11 h-10 text-xs font-medium"
            >
              บูม↓
            </HoldButton>
            <HoldButton
              label="แขนหุบ"
              action="armIn"
              onHold={setHold}
              className="w-11 h-10 text-xs font-medium"
            >
              แขน←
            </HoldButton>
            <HoldButton
              label="เทบุ้งกี๋"
              action="bucketDump"
              onHold={setHold}
              className="w-11 h-10 text-xs font-medium"
            >
              บุ้ง↺
            </HoldButton>
          </div>
        </div>
      </div>
    </div>
  );
}
