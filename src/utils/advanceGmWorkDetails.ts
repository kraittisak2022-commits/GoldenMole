export type AdvancePayoutSlot = 'midday' | 'evening';
export type AdvancePaymentMethod = 'cash' | 'transfer';

export interface AdvanceGmStored {
    payoutSlot: AdvancePayoutSlot;
    paymentMethod: AdvancePaymentMethod;
    bank: string;
    accountNumber: string;
}

const KEY = 'gm_advance';

const defaults = (): AdvanceGmStored => ({
    payoutSlot: 'midday',
    paymentMethod: 'cash',
    bank: '',
    accountNumber: '',
});

export function decodeAdvanceGm(workDetails?: string | null): AdvanceGmStored {
    const out = defaults();
    const raw = String(workDetails || '').trim();
    if (!raw.startsWith('{') || !raw.endsWith('}')) return out;
    try {
        const root = JSON.parse(raw) as Record<string, unknown>;
        const adv = root[KEY] as Record<string, unknown> | undefined;
        if (!adv || typeof adv !== 'object') return out;
        const payout = `${adv['payout_slot'] ?? ''}`.toLowerCase();
        const pay = `${adv['payment_method'] ?? ''}`.toLowerCase();
        return {
            payoutSlot: payout === 'evening' ? 'evening' : 'midday',
            paymentMethod: pay === 'transfer' ? 'transfer' : 'cash',
            bank: `${adv['bank'] ?? ''}`.trim(),
            accountNumber: `${adv['account_number'] ?? ''}`.trim(),
        };
    } catch {
        return out;
    }
}

export function encodeAdvanceGm(existing: string | undefined | null, meta: AdvanceGmStored): string {
    let root: Record<string, unknown> = {};
    const ex = String(existing || '').trim();
    if (ex.startsWith('{') && ex.endsWith('}')) {
        try {
            root = JSON.parse(ex) as Record<string, unknown>;
        } catch {
            root = {};
        }
    }
    root[KEY] = {
        payout_slot: meta.payoutSlot,
        payment_method: meta.paymentMethod,
        bank: meta.bank.trim(),
        account_number: meta.accountNumber.trim(),
        schema_version: 1,
    };
    return JSON.stringify(root);
}
