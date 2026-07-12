import { useEffect, useRef, useState } from 'react';
import { supabase, hasSupabaseConfig } from '../lib/supabase';

export interface MobileDevice {
    id: string;
    username: string;
    device: string;
    platform: string;
    onlineSince: number;
}

interface PresencePayload {
    username?: string;
    device?: string;
    platform?: string;
    at?: number;
}

const CHANNEL_NAME = 'mobile-presence';

function parsePresenceState(state: Record<string, PresencePayload[]>): MobileDevice[] {
    const devices: MobileDevice[] = [];
    for (const [id, presences] of Object.entries(state)) {
        const p = presences[0];
        if (!p) continue;
        devices.push({
            id,
            username: String(p.username ?? 'unknown'),
            device: String(p.device ?? 'Mobile'),
            platform: String(p.platform ?? ''),
            onlineSince: typeof p.at === 'number' ? p.at : Date.now(),
        });
    }
    return devices.sort((a, b) => a.username.localeCompare(b.username));
}

export interface UseMobilePresenceResult {
    devices: MobileDevice[];
    isOnline: boolean;
    isTracking: boolean;
    channelStatus: 'idle' | 'connecting' | 'connected' | 'error';
}

export function useMobilePresence(): UseMobilePresenceResult {
    const [devices, setDevices] = useState<MobileDevice[]>([]);
    const [channelStatus, setChannelStatus] = useState<UseMobilePresenceResult['channelStatus']>('idle');
    const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null);

    useEffect(() => {
        if (!hasSupabaseConfig) return;

        setChannelStatus('connecting');
        const channel = supabase.channel(CHANNEL_NAME, {
            config: { presence: { key: 'web-monitor' } },
        });

        channel
            .on('presence', { event: 'sync' }, () => {
                const state = channel.presenceState() as Record<string, PresencePayload[]>;
                const mobileOnly = parsePresenceState(state).filter((d) => d.id !== 'web-monitor');
                setDevices(mobileOnly);
            })
            .subscribe((status) => {
                if (status === 'SUBSCRIBED') {
                    setChannelStatus('connected');
                } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
                    setChannelStatus('error');
                } else if (status === 'CLOSED') {
                    setChannelStatus('idle');
                }
            });

        channelRef.current = channel;

        return () => {
            void supabase.removeChannel(channel);
            channelRef.current = null;
            setDevices([]);
            setChannelStatus('idle');
        };
    }, []);

    return {
        devices,
        isOnline: devices.length > 0,
        isTracking: channelStatus === 'connected',
        channelStatus,
    };
}
