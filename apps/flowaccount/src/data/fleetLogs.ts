import { supabase } from '../lib/supabase';
import { calcFleetCost } from '../calc/fleet';
import type { FaFleetAsset, FaFleetLog } from '../types';
import { newId } from '../types';
import { saveLedgerEntry } from './ledger';

const map = (row: any): FaFleetLog => ({
  id: row.id,
  workDate: row.work_date,
  assetId: row.asset_id,
  driverName: row.driver_name || '',
  workDays: Number(row.work_days) || 0,
  otAmount: Number(row.ot_amount) || 0,
  incomeAmount: Number(row.income_amount) || 0,
  totalCost: Number(row.total_cost) || 0,
  dailyRateSnapshot: Number(row.daily_rate_snapshot) || 0,
  assetNameSnapshot: row.asset_name_snapshot || '',
  ledgerEntryId: row.ledger_entry_id,
  createdAt: row.created_at,
});

export async function listFleetLogs(): Promise<FaFleetLog[]> {
  const { data, error } = await supabase
    .from('fa_fleet_logs')
    .select('*')
    .order('work_date', { ascending: false });
  if (error) throw new Error(error.message);
  return (data || []).map(map);
}

export async function getFleetLog(id: string): Promise<FaFleetLog | null> {
  const { data, error } = await supabase.from('fa_fleet_logs').select('*').eq('id', id).maybeSingle();
  if (error) throw new Error(error.message);
  return data ? map(data) : null;
}

export async function createFleetLog(input: {
  asset: FaFleetAsset;
  workDate: string;
  driverName: string;
  workDays: number;
  otAmount: number;
  incomeAmount: number;
  postToLedger?: boolean;
  costCategoryId?: string;
  createdBy?: string;
}): Promise<FaFleetLog> {
  const totalCost = calcFleetCost({
    dailyRate: input.asset.dailyRate,
    workDays: input.workDays,
    otAmount: input.otAmount,
  });

  let ledgerEntryId: string | null = null;
  if (input.postToLedger && input.costCategoryId) {
    const ledger = await saveLedgerEntry({
      date: input.workDate,
      description: `ต้นทุนรถ: ${input.asset.name}`,
      categoryId: input.costCategoryId,
      entryType: 'expense',
      amount: totalCost,
      source: 'fleet',
      createdBy: input.createdBy ?? null,
    });
    ledgerEntryId = ledger.id;
  }

  const id = newId('flog');
  const row = {
    id,
    work_date: input.workDate,
    asset_id: input.asset.id,
    driver_name: input.driverName.trim(),
    work_days: Number(input.workDays) || 0,
    ot_amount: Number(input.otAmount) || 0,
    income_amount: Number(input.incomeAmount) || 0,
    total_cost: totalCost,
    daily_rate_snapshot: input.asset.dailyRate,
    asset_name_snapshot: input.asset.name,
    ledger_entry_id: ledgerEntryId,
  };

  const { data, error } = await supabase.from('fa_fleet_logs').insert(row).select('*').single();
  if (error) throw new Error(error.message);
  return map(data);
}
