import { useMemo, useState, type ReactNode } from 'react';
import { AlertTriangle, Crosshair, Link2, MapPin, Pencil, Phone, Store, Truck } from 'lucide-react';
import { suggestDeliveryFee } from '../../calc/deliveryFee';
import { truckFits, type Load } from '../../calc/trips';
import DeliveryMap, { type LatLng } from '../../components/map/DeliveryMap';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Chip from '../../components/ui/Chip';
import Field from '../../components/ui/Field';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import Textarea from '../../components/ui/Textarea';
import { zoneDriverFee } from '../../lib/driverPay';
import { distanceToMainRoad, findTambon } from '../../lib/geo';
import { formatMoney, formatNumber, formatPhone } from '../../lib/format';
import { parseLatLng } from '../../lib/latlng';
import {
  ROUTE_GROUP_LABEL,
  type AppSettings,
  type Customer,
  type Driver,
  type RouteGroup,
  type TruckSize,
  type Zone,
} from '../../types';
import StepTitle from './StepTitle';
import type { WizardState } from './wizardState';

interface Props {
  state: WizardState;
  patch: (p: Partial<WizardState>) => void;
  customer: Customer | null;
  zones: Zone[];
  drivers: Driver[];
  settings: AppSettings;
  loadLines: LoadLine[];
  onEditProducts: () => void;
}

export interface LoadLine extends Load {
  id: string;
  name: string;
}

type GroupFilter = 'all' | RouteGroup;

export default function StepFulfillment({ state: s, patch, customer, zones, drivers, settings, loadLines, onEditProducts }: Props) {
  const [flyTarget, setFlyTarget] = useState<LatLng | null>(null);
  const [locating, setLocating] = useState(false);
  const [geoError, setGeoError] = useState('');
  const [coordText, setCoordText] = useState('');
  const [group, setGroup] = useState<GroupFilter>('all');

  const zone = zones.find((z) => z.id === s.zoneId);
  const driverFeePerTrip = zoneDriverFee(zone, s.truckSize);
  const largestPerTrip = Math.max(0, ...loadLines.map((l) => l.perTrip));

  const chooseFulfillment = (f: 'pickup' | 'delivery') => {
    const next: Partial<WizardState> = { fulfillment: f };
    if (f === 'delivery' && !s.deliveryAddress.trim() && customer?.address) next.deliveryAddress = customer.address;
    if (f === 'delivery' && !s.pin && customer?.lat != null && customer.lng != null) {
      Object.assign(next, pinPatch({ lat: customer.lat, lng: customer.lng }));
      setFlyTarget({ lat: customer.lat, lng: customer.lng });
    }
    patch(next);
  };

  const pinPatch = (p: LatLng): Partial<WizardState> => {
    const tambon = findTambon(p.lat, p.lng);
    const road = distanceToMainRoad(p.lat, p.lng);
    const next: Partial<WizardState> = {
      pin: { lat: Number(p.lat.toFixed(6)), lng: Number(p.lng.toFixed(6)) },
      outsideDistrict: !tambon,
      roadDistanceKm: road?.km ?? null,
      roadLabel: road?.roadLabel ?? '',
    };
    const matched = tambon ? zones.find((z) => z.name === tambon.name) : undefined;
    let feeZone = zone;
    if (matched && s.tambonMethod !== 'manual') {
      next.zoneId = matched.id;
      next.tambonMethod = tambon!.method;
      feeZone = matched;
    }
    if (!s.feeTouched && feeZone) next.feePerTrip = suggestDeliveryFee(feeZone, road?.km, settings.delivery);
    return next;
  };

  const onPin = (p: LatLng) => {
    setGeoError('');
    patch(pinPatch(p));
  };

  const locate = () => {
    if (!navigator.geolocation) return setGeoError('อุปกรณ์นี้ไม่รองรับ GPS');
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const p = { lat: pos.coords.latitude, lng: pos.coords.longitude };
        onPin(p);
        setFlyTarget(p);
        setLocating(false);
      },
      () => {
        setGeoError('ระบุตำแหน่งไม่ได้ ลองแตะบนแผนที่แทน');
        setLocating(false);
      },
      { enableHighAccuracy: true, timeout: 10000 },
    );
  };

  const applyCoordText = () => {
    const p = parseLatLng(coordText);
    if (!p) {
      setGeoError('อ่านพิกัดไม่ได้ วางพิกัดแบบ 19.15, 99.62 หรือลิงก์ Google Maps แบบเต็ม (ลิงก์ย่อ maps.app.goo.gl ใช้ไม่ได้)');
      return;
    }
    onPin(p);
    setFlyTarget(p);
    setCoordText('');
  };

  const chooseZone = (id: string) => {
    const z = zones.find((x) => x.id === id);
    const next: Partial<WizardState> = { zoneId: id || null, tambonMethod: id ? 'manual' : null };
    if (z && !s.feeTouched) next.feePerTrip = suggestDeliveryFee(z, s.roadDistanceKm, settings.delivery);
    patch(next);
  };

  const resetFee = () => {
    if (zone) patch({ feePerTrip: suggestDeliveryFee(zone, s.roadDistanceKm, settings.delivery), feeTouched: false });
  };

  const noDriver: Partial<WizardState> = { driverId: null, driverTruckSize: null, driverConfirmed: false };

  const setTruck = (size: TruckSize) => {
    const keepDriver = s.driverTruckSize === size;
    patch({ truckSize: size, truckTouched: true, ...(keepDriver ? {} : noDriver) });
  };

  const chooseDriver = (d: Driver) => {
    if (s.driverId === d.id) return patch(noDriver);
    patch({ driverId: d.id, driverTruckSize: d.truckSize, driverConfirmed: false, truckSize: d.truckSize, truckTouched: true });
  };

  const activeDrivers = useMemo(() => {
    const list = drivers.filter((d) => d.active && (group === 'all' || d.routeGroup === group));
    return [...list].sort(
      (a, b) => Number(b.truckSize === s.truckSize) - Number(a.truckSize === s.truckSize) || a.sortOrder - b.sortOrder,
    );
  }, [drivers, group, s.truckSize]);

  const groupCounts = useMemo(() => {
    const counts: Record<string, number> = { all: 0 };
    for (const d of drivers) {
      if (!d.active) continue;
      counts.all += 1;
      counts[d.routeGroup] = (counts[d.routeGroup] || 0) + 1;
    }
    return counts;
  }, [drivers]);

  const deliveryTotal = s.feePerTrip * s.trips + s.remoteSurcharge;
  const selectedDriver = drivers.find((d) => d.id === s.driverId);

  return (
    <div className="step-enter flex flex-col gap-5">
      <StepTitle title="การรับสินค้า" subtitle="ลูกค้ามารับเองที่ท่าทราย หรือให้รถไปส่ง" />

      <div className="grid grid-cols-2 gap-3" role="radiogroup" aria-label="การรับสินค้า" data-tour="wiz-fulfillment">
        <ChoiceCard
          active={s.fulfillment === 'pickup'}
          onClick={() => chooseFulfillment('pickup')}
          icon={<Store size={26} aria-hidden />}
          title="มารับเอง"
          hint="ไม่มีค่าส่ง"
        />
        <ChoiceCard
          active={s.fulfillment === 'delivery'}
          onClick={() => chooseFulfillment('delivery')}
          icon={<Truck size={26} aria-hidden />}
          title="จัดส่ง"
          hint="ในเขต อ.วังเหนือ"
        />
      </div>

      {s.fulfillment === 'delivery' ? (
        <>
          <section className="flex flex-col gap-3">
            <div className="flex items-center justify-between gap-2">
              <h3 className="font-medium">ปักหมุดหน้างาน</h3>
              <Button variant="secondary" onClick={locate} disabled={locating}>
                <Crosshair size={16} aria-hidden /> {locating ? 'กำลังหา…' : 'ตำแหน่งปัจจุบัน'}
              </Button>
            </div>
            <p className="text-sm text-muted">แตะบนแผนที่หรือลากหมุด เส้นสีส้มคือถนนสายหลัก</p>
            <DeliveryMap value={s.pin} onChange={onPin} flyTarget={flyTarget} height={300} />
            <div className="flex gap-2">
              <div className="relative flex-1">
                <Link2 size={16} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" aria-hidden />
                <Input
                  aria-label="วางพิกัดหรือลิงก์ Google Maps"
                  placeholder="วางพิกัด / ลิงก์ Google Maps"
                  value={coordText}
                  onChange={(e) => setCoordText(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault();
                      applyCoordText();
                    }
                  }}
                  className="pl-9"
                />
              </div>
              <Button variant="secondary" onClick={applyCoordText} disabled={!coordText.trim()}>
                ใช้พิกัด
              </Button>
            </div>
            {geoError ? <p className="text-sm text-destructive">{geoError}</p> : null}

            {s.pin ? (
              <div className="grid grid-cols-2 gap-2 text-sm">
                <InfoTile label="ตำบล (จากหมุด)" value={zone?.name ?? '—'} hint={tambonHint(s.tambonMethod)} />
                <InfoTile
                  label="ห่างถนนใหญ่"
                  value={s.roadDistanceKm != null ? `${formatNumber(s.roadDistanceKm)} กม.` : '—'}
                  hint={s.roadLabel || undefined}
                />
              </div>
            ) : null}
            {s.pin && s.outsideDistrict ? (
              <div className="flex items-start gap-2 rounded bg-warning-soft px-3 py-2.5 text-sm text-warning">
                <AlertTriangle size={16} className="mt-0.5 shrink-0" aria-hidden />
                หมุดอยู่นอกเขต อ.วังเหนือ เลือกตำบลที่ใกล้ที่สุดเอง และใส่ค่าส่งเพิ่มตามความเหมาะสม
              </div>
            ) : null}
          </section>

          <section className="flex flex-col gap-4 rounded border border-border bg-surface p-4">
            <Field id="f-zone" label="ตำบลที่จัดส่ง *" hint={zone ? `ค่าส่ง ${formatNumber(zone.feeMin)}-${formatNumber(zone.feeMax)} บาท/เที่ยว` : undefined}>
              <Select id="f-zone" value={s.zoneId ?? ''} onChange={(e) => chooseZone(e.target.value)}>
                <option value="">— เลือกตำบล —</option>
                {zones.map((z) => (
                  <option key={z.id} value={z.id}>
                    {z.name} ({formatNumber(z.feeMin)}-{formatNumber(z.feeMax)})
                  </option>
                ))}
              </Select>
            </Field>

            <Field id="f-address" label="ที่อยู่จัดส่ง / จุดสังเกต">
              <Textarea
                id="f-address"
                rows={2}
                value={s.deliveryAddress}
                onChange={(e) => patch({ deliveryAddress: e.target.value })}
                placeholder="บ้านเลขที่ หมู่บ้าน จุดสังเกต"
              />
            </Field>

            <div>
              <p className="mb-2 text-sm font-medium">ขนาดรถ</p>
              <div className="grid grid-cols-2 gap-2" role="radiogroup" aria-label="ขนาดรถ">
                {([3, 5] as TruckSize[]).map((size) => (
                  <button
                    key={size}
                    type="button"
                    role="radio"
                    aria-checked={s.truckSize === size}
                    disabled={!truckFits(size, loadLines)}
                    onClick={() => setTruck(size)}
                    className={[
                      'min-h-11 rounded border px-3 text-sm font-medium transition-colors cursor-pointer disabled:cursor-not-allowed disabled:opacity-40',
                      s.truckSize === size ? 'border-primary bg-primary text-primary-foreground' : 'border-border hover:bg-subtle',
                    ].join(' ')}
                  >
                    รถ {size} คิว
                  </button>
                ))}
              </div>
              {!truckFits(3, loadLines) ? (
                <p className="mt-1.5 text-xs text-muted">สินค้าเที่ยวละ {formatNumber(largestPerTrip)} คิว ต้องใช้รถ 5 คิว</p>
              ) : null}
            </div>

            <div className="rounded bg-subtle px-3 py-2.5">
              <div className="flex items-center justify-between gap-3">
                <p className="text-sm font-medium">
                  จำนวนเที่ยว <span className="text-base font-semibold tabular-nums">{s.trips}</span> เที่ยว
                </p>
                <button
                  type="button"
                  onClick={onEditProducts}
                  className="inline-flex min-h-11 items-center gap-1.5 rounded px-2 text-sm font-medium text-primary hover:bg-surface cursor-pointer"
                >
                  <Pencil size={14} aria-hidden /> แก้ที่สินค้า
                </button>
              </div>
              <ul className="flex flex-col gap-0.5 text-sm text-muted">
                {loadLines.map((l) => (
                  <li key={l.id} className="flex justify-between gap-3">
                    <span className="truncate">{l.name}</span>
                    <span className="shrink-0 tabular-nums">
                      {formatNumber(l.perTrip)} คิว × {l.trips} เที่ยว
                    </span>
                  </li>
                ))}
              </ul>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <Field
                id="f-fee"
                label="ค่าส่ง / เที่ยว"
                hint={s.feeTouched && zone ? undefined : 'คำนวณจากระยะถึงถนนใหญ่'}
              >
                <Input
                  id="f-fee"
                  type="number"
                  inputMode="numeric"
                  min={0}
                  step={50}
                  value={s.feePerTrip || ''}
                  placeholder="0"
                  onChange={(e) => patch({ feePerTrip: Math.max(0, Number(e.target.value) || 0), feeTouched: true })}
                />
              </Field>
              <Field id="f-remote" label="ที่กันดาร (บวกเพิ่ม)">
                <Input
                  id="f-remote"
                  type="number"
                  inputMode="numeric"
                  min={0}
                  step={50}
                  value={s.remoteSurcharge || ''}
                  placeholder="0"
                  onChange={(e) => patch({ remoteSurcharge: Math.max(0, Number(e.target.value) || 0) })}
                />
              </Field>
            </div>
            {s.feeTouched && zone ? (
              <button type="button" onClick={resetFee} className="-mt-2 self-start text-sm text-primary underline cursor-pointer">
                ใช้ค่าส่งที่ระบบแนะนำ ({formatNumber(suggestDeliveryFee(zone, s.roadDistanceKm, settings.delivery))})
              </button>
            ) : null}

            <div className="flex items-center justify-between rounded bg-subtle px-3 py-2.5 text-sm">
              <span className="text-muted">
                {formatNumber(s.feePerTrip)} × {s.trips} เที่ยว{s.remoteSurcharge ? ` + ${formatNumber(s.remoteSurcharge)}` : ''}
              </span>
              <span className="font-semibold tabular-nums">ค่าส่ง {formatMoney(deliveryTotal)}</span>
            </div>
          </section>

          <section className="flex flex-col gap-3">
            <div>
              <h3 className="font-medium">คนขับ (ไม่บังคับ)</h3>
              <p className="text-sm text-muted">โทรเช็คคิวก่อน แล้วเลือกคนขับ ระบุภายหลังในหน้าออเดอร์ได้</p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Chip active={group === 'all'} onClick={() => setGroup('all')} count={groupCounts.all}>
                ทั้งหมด
              </Chip>
              {(Object.keys(ROUTE_GROUP_LABEL) as RouteGroup[]).map((g) => (
                <Chip key={g} active={group === g} onClick={() => setGroup(g)} count={groupCounts[g] || 0}>
                  {ROUTE_GROUP_LABEL[g]}
                </Chip>
              ))}
            </div>
            <ul className="flex flex-col divide-y divide-border overflow-hidden rounded border border-border bg-surface">
              {activeDrivers.map((d) => {
                const selected = s.driverId === d.id;
                const fits = truckFits(d.truckSize, loadLines);
                return (
                  <li key={d.id} className={selected ? 'bg-primary-soft/60' : ''}>
                    <div className="flex items-center gap-3 px-3 py-2.5">
                      <button
                        type="button"
                        onClick={() => chooseDriver(d)}
                        aria-pressed={selected}
                        disabled={!fits}
                        className="flex min-h-11 flex-1 items-center gap-3 text-left cursor-pointer disabled:cursor-not-allowed disabled:opacity-50"
                      >
                        <span
                          className={[
                            'flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2',
                            selected ? 'border-primary' : 'border-border',
                          ].join(' ')}
                          aria-hidden
                        >
                          {selected ? <span className="h-2.5 w-2.5 rounded-full bg-primary" /> : null}
                        </span>
                        <span className="min-w-0">
                          <span className="block font-medium">{d.name}</span>
                          <span className="block truncate text-xs text-muted">
                            {fits
                              ? [d.village, ROUTE_GROUP_LABEL[d.routeGroup]].filter(Boolean).join(' · ')
                              : `รถเล็กเกิน (สินค้าเที่ยวละ ${formatNumber(largestPerTrip)} คิว)`}
                          </span>
                        </span>
                      </button>
                      <Badge tone={d.truckSize === s.truckSize ? 'info' : 'neutral'}>
                        {d.truckSize} คิว{d.truckCount > 1 ? ` ×${d.truckCount}` : ''}
                      </Badge>
                      {d.contacts[0] ? (
                        <a
                          href={`tel:${d.contacts[0].phone}`}
                          aria-label={`โทรหา ${d.name} ${formatPhone(d.contacts[0].phone)}`}
                          className="inline-flex min-h-11 min-w-11 items-center justify-center rounded text-primary hover:bg-subtle"
                        >
                          <Phone size={18} aria-hidden />
                        </a>
                      ) : null}
                    </div>
                  </li>
                );
              })}
            </ul>
            {selectedDriver ? (
              <label className="flex min-h-11 cursor-pointer items-start gap-3 rounded border border-border bg-surface p-3 text-sm">
                <input
                  type="checkbox"
                  className="mt-0.5 h-5 w-5 shrink-0 accent-[var(--color-primary)]"
                  checked={s.driverConfirmed}
                  onChange={(e) => patch({ driverConfirmed: e.target.checked })}
                />
                <span>
                  ยืนยันว่ารถ <b>{selectedDriver.name}</b> เข้าหน้างานได้และมีคิวว่าง
                  {zone && driverFeePerTrip ? (
                    <span className="block text-muted">
                      ค่ารถคนขับ ต.{zone.name} รถ {s.truckSize} คิว {formatNumber(driverFeePerTrip)} × {s.trips} ={' '}
                      {formatMoney(driverFeePerTrip * s.trips)} บาท
                    </span>
                  ) : null}
                </span>
              </label>
            ) : null}
          </section>
        </>
      ) : null}

      {s.fulfillment === 'pickup' ? (
        <div className="flex items-start gap-3 rounded border border-border bg-surface p-4 text-sm text-muted">
          <MapPin size={18} className="mt-0.5 shrink-0 text-primary" aria-hidden />
          ลูกค้ามารับที่ท่าทราย ไม่มีค่าส่ง ระบบจะบันทึกสถานะการส่งเป็น "มารับเอง"
        </div>
      ) : null}
    </div>
  );
}

function tambonHint(method: WizardState['tambonMethod']): string | undefined {
  if (method === 'nearest') return 'ประมาณจากตำบลที่ใกล้ที่สุด';
  if (method === 'manual') return 'เลือกเอง';
  return undefined;
}

function ChoiceCard({
  active,
  onClick,
  icon,
  title,
  hint,
}: {
  active: boolean;
  onClick: () => void;
  icon: ReactNode;
  title: string;
  hint: string;
}) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={active}
      onClick={onClick}
      className={[
        'flex min-h-28 flex-col items-center justify-center gap-2 rounded border-2 p-4 text-center transition-colors cursor-pointer',
        active ? 'border-primary bg-primary-soft/50 text-primary' : 'border-border bg-surface hover:bg-subtle',
      ].join(' ')}
    >
      {icon}
      <span className="text-base font-semibold">{title}</span>
      <span className="text-xs text-muted">{hint}</span>
    </button>
  );
}

function InfoTile({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="rounded border border-border bg-surface px-3 py-2">
      <p className="text-xs text-muted">{label}</p>
      <p className="font-semibold">{value}</p>
      {hint ? <p className="truncate text-xs text-muted">{hint}</p> : null}
    </div>
  );
}
