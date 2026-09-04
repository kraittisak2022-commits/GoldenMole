/**
 * Shared fuel stock balance — mirrors src/utils/index.ts computeFuelStockBalances
 * (without sand-sieve lap estimate; SandSieve Fuel rows still count).
 */
export const FUEL_STOCK_CUTOVER_YMD = "2026-08-01";
export const FUEL_OPENING_RESERVE_DIESEL_LITERS = 100;
export const FUEL_RESERVE_ANCHOR_YMD = "2026-08-31";
export const FUEL_RESERVE_ANCHOR_LITERS = 100;
export const FUEL_TANK_CAPACITY_MAIN = 12000;
export const FUEL_TANK_CAPACITY_RESERVE = 1000;

const FUEL_WITHDRAW = "Withdraw";
const FUEL_TRANSFER = "Transfer";
const FUEL_SAND_SIEVE = "SandSieve";
const FUEL_VEHICLE_USAGE = "VehicleUsage";

export type FuelTx = {
  date?: string | null;
  category?: string | null;
  type?: string | null;
  sub_category?: string | null;
  quantity?: number | null;
  unit?: string | null;
  fuel_type?: string | null;
  fuel_tank?: string | null;
  fuel_movement?: string | null;
  vehicle_id?: string | null;
  vehicle_name?: string | null;
  work_type?: string | null;
};

type Bucket = { stockIn: number; withdraw: number };

export type FuelStockBalances = {
  mainDiesel: number;
  reserveDiesel: number;
  mainBenzine: number;
  reserveBenzine: number;
};

function normalizeDate(d?: string | null): string {
  if (!d) return "";
  return d.length >= 10 ? d.slice(0, 10) : d;
}

function fuelTxToLiters(t: FuelTx): number {
  const q = Number(t.quantity) || 0;
  if (!q) return 0;
  const u = String(t.unit || "L").toLowerCase();
  if (u === "gallon" || u === "แกลลอน") return q * 3.785411784;
  return q;
}

function hasVehicle(t: FuelTx): boolean {
  return !!(String(t.vehicle_id ?? "").trim() || String(t.vehicle_name ?? "").trim());
}

function inferFuelMovement(t: FuelTx): "stock_in" | "stock_out" {
  const mov = String(t.fuel_movement ?? "").trim().toLowerCase();
  if (mov === "stock_in" || mov === "stock_out") return mov;
  return hasVehicle(t) ? "stock_out" : "stock_in";
}

function normalizeFuelTank(raw?: string | null): "main" | "reserve" {
  const v = String(raw ?? "").trim().toLowerCase();
  if (v === "reserve" || v === "สำรอง") return "reserve";
  return "main";
}

function fuelUsageTankOf(t: FuelTx): "main" | "reserve" {
  const raw = String(t.fuel_tank ?? "").trim();
  if (raw) return normalizeFuelTank(raw);
  const sub = String(t.sub_category ?? "").trim();
  if (sub === FUEL_VEHICLE_USAGE) return "reserve";
  return "main";
}

export function effectiveFuelOpeningReserveDiesel(configured: number): number {
  return configured > 0 ? configured : FUEL_OPENING_RESERVE_DIESEL_LITERS;
}

function fuelReserveAnchorIsActive(asOfYmd?: string): boolean {
  return (
    FUEL_RESERVE_ANCHOR_YMD.length > 0 &&
    asOfYmd != null &&
    asOfYmd >= FUEL_RESERVE_ANCHOR_YMD
  );
}

function applyFuelReserveDieselAnchor(
  buckets: Map<string, Bucket>,
  openingReserveDiesel: number,
  asOfYmd?: string,
): number {
  const byDay = new Map<string, number>();
  for (const [key, bucket] of buckets) {
    if (!key.includes("|reserve|") || key.endsWith("|Benzine")) continue;
    const day = key.split("|")[0] ?? "";
    const delta = bucket.stockIn - bucket.withdraw;
    if (!delta) continue;
    byDay.set(day, (byDay.get(day) ?? 0) + delta);
  }

  const postDays = [...byDay.keys()].filter((d) =>
    d >= FUEL_RESERVE_ANCHOR_YMD
  ).sort();
  const applyAnchor =
    postDays.length > 0 || fuelReserveAnchorIsActive(asOfYmd);

  if (applyAnchor) {
    let reserve = FUEL_RESERVE_ANCHOR_LITERS;
    for (const day of postDays) reserve += byDay.get(day) ?? 0;
    return reserve;
  }

  let reserve = openingReserveDiesel;
  for (const day of [...byDay.keys()].sort()) {
    reserve += byDay.get(day) ?? 0;
  }
  return reserve;
}

export function computeFuelStockBalances(
  transactions: FuelTx[],
  opening?: {
    Diesel?: number;
    Benzine?: number;
    DieselReserve?: number;
    BenzineReserve?: number;
    asOfYmd?: string;
  },
): FuelStockBalances {
  const buckets = new Map<string, Bucket>();
  const bucketFor = (
    date: string,
    tank: "main" | "reserve",
    ft: "Diesel" | "Benzine",
  ) => {
    const key = `${date}|${tank}|${ft}`;
    let b = buckets.get(key);
    if (!b) {
      b = { stockIn: 0, withdraw: 0 };
      buckets.set(key, b);
    }
    return b;
  };

  const transferMachineDays = new Set<string>();
  for (const t of transactions) {
    if (t.category !== "Fuel" || String(t.type ?? "").toLowerCase() !== "expense") {
      continue;
    }
    const day = normalizeDate(t.date);
    if (!day || day < FUEL_STOCK_CUTOVER_YMD) continue;
    if (
      String(t.sub_category ?? "").trim() === FUEL_TRANSFER &&
      String(t.work_type ?? "").trim().toLowerCase() === "machine"
    ) {
      transferMachineDays.add(day);
    }
  }

  for (const t of transactions) {
    if (t.category !== "Fuel" || String(t.type ?? "").toLowerCase() !== "expense") {
      continue;
    }
    const day = normalizeDate(t.date);
    if (!day || day < FUEL_STOCK_CUTOVER_YMD) continue;
    const liters = fuelTxToLiters(t);
    if (!liters) continue;
    const ft = String(t.fuel_type ?? "").trim() === "Benzine" ? "Benzine" : "Diesel";
    const tank = fuelUsageTankOf(t);
    const bucket = bucketFor(day, tank, ft);
    const sub = String(t.sub_category ?? "").trim();
    const purpose = String(t.work_type ?? "").trim().toLowerCase();
    const movement = inferFuelMovement(t);

    if (movement === "stock_in") {
      bucket.stockIn += liters;
      continue;
    }
    if (sub === FUEL_WITHDRAW) {
      bucket.withdraw += liters;
      if (purpose === "machine" && !transferMachineDays.has(day)) {
        bucketFor(day, "reserve", ft).stockIn += liters;
      }
      continue;
    }
    if (
      sub === FUEL_TRANSFER ||
      sub === FUEL_SAND_SIEVE ||
      sub === FUEL_VEHICLE_USAGE
    ) {
      bucket.withdraw += liters;
    }
  }

  let mainD = opening?.Diesel ?? 0;
  let mainB = opening?.Benzine ?? 0;
  let reserveB = opening?.BenzineReserve ?? 0;
  for (const [key, bucket] of buckets) {
    const delta = bucket.stockIn - bucket.withdraw;
    const isReserve = key.includes("|reserve|");
    const isBenzine = key.endsWith("|Benzine");
    if (isReserve) {
      if (isBenzine) reserveB += delta;
      continue;
    }
    if (isBenzine) mainB += delta;
    else mainD += delta;
  }

  const reserveD = applyFuelReserveDieselAnchor(
    buckets,
    effectiveFuelOpeningReserveDiesel(opening?.DieselReserve ?? 0),
    opening?.asOfYmd,
  );

  return {
    mainDiesel: mainD,
    reserveDiesel: reserveD,
    mainBenzine: mainB,
    reserveBenzine: reserveB,
  };
}

export function formatLiters(n: number): string {
  const rounded = Math.round(n * 100) / 100;
  const isInt = Math.abs(rounded - Math.round(rounded)) < 1e-9;
  const core = isInt
    ? String(Math.round(rounded))
    : rounded.toFixed(2).replace(/\.?0+$/, "");
  const [intPart, dec] = core.split(".");
  const withComma = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return dec ? `${withComma}.${dec}` : withComma;
}

export function buildDailyFuelStockLineText(
  dateYmd: string,
  bal: FuelStockBalances,
  formatDateThaiBE: (ymd: string) => string,
): string {
  const lines = [
    `น้ำมันคงเหลือ ${formatDateThaiBE(dateYmd)}`,
    "",
    `ถังหลัก : ${formatLiters(bal.mainDiesel)} ลิตร`,
    `ถังสำรอง : ${formatLiters(bal.reserveDiesel)} ลิตร`,
    "",
    `รวม : ${formatLiters(bal.mainDiesel + bal.reserveDiesel)} ลิตร`,
  ];
  if (Math.abs(bal.mainBenzine) > 0.001 || Math.abs(bal.reserveBenzine) > 0.001) {
    lines.push(
      "",
      `เบนซิน ถังหลัก : ${formatLiters(bal.mainBenzine)} ลิตร`,
      `เบนซิน ถังสำรอง : ${formatLiters(bal.reserveBenzine)} ลิตร`,
    );
  }
  return lines.join("\n").trim();
}
