import { supabase } from '../lib/supabase';
import { hashPasswordForStorage } from '../utils/passwordAuth';

export interface DashboardShareSettings {
    id: 'default';
    enabled: boolean;
    shareToken: string;
    pinHash: string | null;
    showFinancial: boolean;
    updatedAt: string;
}

const mapShareRow = (row: Record<string, unknown>): DashboardShareSettings => ({
    id: 'default',
    enabled: !!row.enabled,
    shareToken: String(row.share_token || ''),
    pinHash: row.pin_hash != null ? String(row.pin_hash) : null,
    showFinancial: !!row.show_financial,
    updatedAt: String(row.updated_at || new Date().toISOString()),
});

export const generateShareToken = (): string => {
    const part = () => crypto.randomUUID().replace(/-/g, '');
    return `${part()}${part()}`;
};

export const fetchShareSettings = async (): Promise<DashboardShareSettings | null> => {
    const { data, error } = await supabase
        .from('dashboard_share_settings')
        .select('*')
        .eq('id', 'default')
        .maybeSingle();
    if (error) {
        console.error('fetchShareSettings error:', error);
        return null;
    }
    if (!data) return null;
    return mapShareRow(data as Record<string, unknown>);
};

export const ensureShareSettings = async (): Promise<DashboardShareSettings> => {
    const existing = await fetchShareSettings();
    if (existing) {
        if (!existing.shareToken) {
            const token = generateShareToken();
            const updated = { ...existing, shareToken: token };
            await saveShareSettings(updated);
            return { ...updated, shareToken: token };
        }
        return existing;
    }

    const defaults: DashboardShareSettings = {
        id: 'default',
        enabled: false,
        shareToken: generateShareToken(),
        pinHash: null,
        showFinancial: false,
        updatedAt: new Date().toISOString(),
    };
    await saveShareSettings(defaults);
    return defaults;
};

export const saveShareSettings = async (settings: DashboardShareSettings): Promise<boolean> => {
    const row = {
        id: 'default',
        enabled: settings.enabled,
        share_token: settings.shareToken,
        pin_hash: settings.pinHash,
        show_financial: settings.showFinancial,
        updated_at: new Date().toISOString(),
    };
    const { error } = await supabase.from('dashboard_share_settings').upsert(row, { onConflict: 'id' });
    if (error) {
        console.error('saveShareSettings error:', error);
        return false;
    }
    return true;
};

export const hashSharePinForStorage = async (plainPin: string): Promise<string> => {
    return hashPasswordForStorage(plainPin);
};

export const buildShareUrl = (shareToken: string): string => {
    const url = new URL(window.location.href);
    url.search = '';
    url.hash = '';
    url.searchParams.set('share', shareToken);
    return url.toString();
};
