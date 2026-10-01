import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import SettingsModule from './SettingsModule';
import type { AdminUser, AppSettings } from '../../types';

vi.mock('../../lib/supabase', () => {
    const chain: unknown = new Proxy(() => chain, {
        get: (_t, p) => (p === 'then'
            ? (resolve: (v: unknown) => void) => resolve({ data: [], error: null, count: 0 })
            : chain),
        apply: () => chain,
    });
    return { supabase: chain, isSupabaseConfigured: () => true };
});

const settings = {
    appName: 'Goldenmole Dashboard',
    appSubtext: 'ระบบจัดการ',
    appIcon: '/icons/icon-192.png',
    appIconDark: '/icons/icon-192.png',
    cars: ['ดั๊มพี่โก', 'รถดั๊มนายกนิต'],
    jobDescriptions: ['งานทั่วไป'],
    incomeTypes: ['ขายทราย'],
    expenseTypes: ['ค่าไฟ'],
    maintenanceTypes: ['ปะยาง'],
    locations: ['หน้างาน A'],
    landGroups: ['โครงการหนองจอก'],
    employeePositions: ['คนขับรถ'],
    versionNotes: ['note'],
    fuelOpeningStockLiters: { Diesel: 0, Benzine: 0 },
    orgProfile: {},
    appDefaults: {
        sandCubicPerTrip: 3,
        vehicleDefaultMachineWage: 4500,
        lineAdvanceNotifyUserIds: ['C492793a821494a324a5a0a65340183ee'],
        lineDailySendBudget: { ymd: '2026-10-01', count: 2, limit: 5 },
        lineMessagingQuotaBlockUntil: '2026-09-30T17:00:00.000Z',
        lineWebhookSeenChats: {
            chats: [{ at: '2026-09-09T02:05:25.670Z', id: 'C492793a821494a324a5a0a65340183ee', type: 'group', eventType: 'message' }],
        },
        vehicleDefaultDrivers: { 'ดั๊มพี่โก': '1780298241203' },
    },
} as unknown as AppSettings;

describe('SettingsModule', () => {
    it('opens and switches through every tab without runtime errors', async () => {
        const user = userEvent.setup();
        const errors: string[] = [];
        const spy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
            errors.push(String(args[0]).slice(0, 300));
        });

        render(
            <SettingsModule
                settings={settings}
                setSettings={() => {}}
                backupPayload={{ employees: [], transactions: [], projects: [], admins: [], adminLogs: [] }}
                currentAdmin={{ id: 'a1', username: 'admin', displayName: 'Admin', role: 'SuperAdmin' } as unknown as AdminUser}
            />,
        );

        const tabButtons = screen.getAllByRole('button').filter((b) => b.closest('.md\\:col-span-1'));
        expect(tabButtons.length).toBeGreaterThan(5);
        expect(screen.getByRole('button', { name: 'AI LINE กลุ่ม' })).toBeInTheDocument();
        for (const button of tabButtons) {
            await user.click(button);
        }

        spy.mockRestore();
        expect(errors).toEqual([]);
    });
});
