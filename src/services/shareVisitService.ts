import { supabase } from '../lib/supabase';

const DEVICE_KEY_STORAGE = 'cm_share_device_key_v1';
const DEVICE_LABEL_STORAGE = 'cm_share_device_label_v1';

export interface DashboardShareVisit {
    id: string;
    shareToken: string;
    deviceKey: string;
    deviceLabel: string;
    ipAddress: string;
    userAgent: string;
    visitCount: number;
    firstSeenAt: string;
    lastSeenAt: string;
}

const mapVisitRow = (row: Record<string, unknown>): DashboardShareVisit => ({
    id: String(row.id ?? ''),
    shareToken: String(row.share_token ?? ''),
    deviceKey: String(row.device_key ?? ''),
    deviceLabel: String(row.device_label ?? ''),
    ipAddress: String(row.ip_address ?? ''),
    userAgent: String(row.user_agent ?? ''),
    visitCount: Number(row.visit_count ?? 1) || 1,
    firstSeenAt: String(row.first_seen_at ?? ''),
    lastSeenAt: String(row.last_seen_at ?? ''),
});

export const getOrCreateShareDeviceKey = (): string => {
    if (typeof window === 'undefined') return '';
    try {
        const existing = window.localStorage.getItem(DEVICE_KEY_STORAGE)?.trim();
        if (existing) return existing;
        const key = crypto.randomUUID().replace(/-/g, '');
        window.localStorage.setItem(DEVICE_KEY_STORAGE, key);
        return key;
    } catch {
        return `tmp_${Date.now()}`;
    }
};

export const getShareDeviceLabel = (): string => {
    if (typeof window === 'undefined') return '';
    try {
        return window.localStorage.getItem(DEVICE_LABEL_STORAGE)?.trim() ?? '';
    } catch {
        return '';
    }
};

export const setShareDeviceLabelLocal = (label: string): void => {
    if (typeof window === 'undefined') return;
    try {
        window.localStorage.setItem(DEVICE_LABEL_STORAGE, label.trim());
    } catch {
        /* ignore quota */
    }
};

async function fetchClientIp(): Promise<string> {
    try {
        const ctrl = new AbortController();
        const timer = window.setTimeout(() => ctrl.abort(), 4000);
        const res = await fetch('https://api.ipify.org?format=json', { signal: ctrl.signal });
        window.clearTimeout(timer);
        if (!res.ok) return '';
        const data = (await res.json()) as { ip?: string };
        return String(data.ip ?? '').trim();
    } catch {
        return '';
    }
}

function browserHint(ua: string): string {
    const s = ua.toLowerCase();
    if (s.includes('iphone') || s.includes('ipad')) return 'iPhone/iPad';
    if (s.includes('android')) return 'Android';
    if (s.includes('windows')) return 'Windows';
    if (s.includes('mac os') || s.includes('macintosh')) return 'Mac';
    if (s.includes('linux')) return 'Linux';
    return 'อุปกรณ์';
}

/** Record a successful share unlock / view. Dedupes by device_key and increments visit_count. */
export const recordShareVisit = async (shareToken: string): Promise<DashboardShareVisit | null> => {
    const token = shareToken.trim();
    const deviceKey = getOrCreateShareDeviceKey();
    if (!token || !deviceKey) return null;

    const deviceLabel = getShareDeviceLabel();
    const userAgent = typeof navigator !== 'undefined' ? navigator.userAgent.slice(0, 500) : '';
    const ipAddress = await fetchClientIp();
    const now = new Date().toISOString();

    const { data: existing, error: readError } = await supabase
        .from('dashboard_share_visits')
        .select('*')
        .eq('device_key', deviceKey)
        .maybeSingle();

    if (readError) {
        console.error('recordShareVisit read error:', readError);
        return null;
    }

    if (existing) {
        const row = existing as Record<string, unknown>;
        const nextLabel = deviceLabel || String(row.device_label ?? '') || browserHint(userAgent);
        const { data, error } = await supabase
            .from('dashboard_share_visits')
            .update({
                share_token: token,
                device_label: nextLabel,
                ip_address: ipAddress || String(row.ip_address ?? ''),
                user_agent: userAgent || String(row.user_agent ?? ''),
                visit_count: (Number(row.visit_count ?? 0) || 0) + 1,
                last_seen_at: now,
            })
            .eq('id', row.id)
            .select('*')
            .maybeSingle();
        if (error) {
            console.error('recordShareVisit update error:', error);
            return null;
        }
        return data ? mapVisitRow(data as Record<string, unknown>) : null;
    }

    const insertLabel = deviceLabel || browserHint(userAgent);
    const { data, error } = await supabase
        .from('dashboard_share_visits')
        .insert({
            share_token: token,
            device_key: deviceKey,
            device_label: insertLabel,
            ip_address: ipAddress,
            user_agent: userAgent,
            visit_count: 1,
            first_seen_at: now,
            last_seen_at: now,
        })
        .select('*')
        .maybeSingle();

    if (error) {
        console.error('recordShareVisit insert error:', error);
        return null;
    }
    return data ? mapVisitRow(data as Record<string, unknown>) : null;
};

export const fetchShareVisits = async (): Promise<DashboardShareVisit[]> => {
    const { data, error } = await supabase
        .from('dashboard_share_visits')
        .select('*')
        .order('last_seen_at', { ascending: false })
        .limit(200);
    if (error) {
        console.error('fetchShareVisits error:', error);
        return [];
    }
    return (data ?? []).map((row) => mapVisitRow(row as Record<string, unknown>));
};

export const updateShareVisitLabel = async (visitId: string, label: string): Promise<boolean> => {
    const { error } = await supabase
        .from('dashboard_share_visits')
        .update({ device_label: label.trim() })
        .eq('id', visitId);
    if (error) {
        console.error('updateShareVisitLabel error:', error);
        return false;
    }
    return true;
};

/** Persist local device name and sync to visit row if it exists. */
export const saveViewerDeviceLabel = async (shareToken: string, label: string): Promise<boolean> => {
    setShareDeviceLabelLocal(label);
    const deviceKey = getOrCreateShareDeviceKey();
    if (!deviceKey) return true;
    const payload: Record<string, string> = { device_label: label.trim() };
    const token = shareToken.trim();
    if (token) payload.share_token = token;
    const { error } = await supabase.from('dashboard_share_visits').update(payload).eq('device_key', deviceKey);
    if (error) {
        console.error('saveViewerDeviceLabel error:', error);
        return false;
    }
    return true;
};

export const formatVisitWhen = (iso: string): string => {
    if (!iso) return '—';
    try {
        return new Intl.DateTimeFormat('th-TH', {
            dateStyle: 'medium',
            timeStyle: 'short',
        }).format(new Date(iso));
    } catch {
        return iso;
    }
};
