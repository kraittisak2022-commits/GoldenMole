import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ReportsModule from './ReportsModule';
import type { AppSettings, Transaction } from '../../types';
import { THAI_MONTHS } from '../../utils';

vi.mock('../../utils', async (importOriginal) => {
    const actual = await importOriginal<typeof import('../../utils')>();
    return {
        ...actual,
        getToday: () => '2026-08-15',
    };
});

const settings = {
    appName: 'Goldenmole',
    cars: ['รถดรัมโอเว่น'],
    fuelOpeningStockLiters: { Diesel: 0, Benzine: 0 },
} as AppSettings;

function fuelTx(partial: Partial<Transaction> & Pick<Transaction, 'id' | 'date'>): Transaction {
    return {
        type: 'Expense',
        category: 'Fuel',
        description: 'น้ำมัน',
        amount: 0,
        ...partial,
    };
}

describe('ReportsModule', () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    it('shows liters-only fuel usage summary with Thai month date controls', () => {
        render(
            <ReportsModule
                settings={settings}
                transactions={[
                    fuelTx({
                        id: 'v1',
                        date: '2026-08-10',
                        fuelMovement: 'stock_out',
                        vehicleId: 'รถดรัมโอเว่น',
                        fuelType: 'Diesel',
                        quantity: 60,
                        amount: 1800,
                        description: 'เติมรถดรัม',
                    }),
                ]}
            />
        );

        expect(screen.getByRole('tab', { name: 'รายงานการใช้น้ำมัน' })).toBeInTheDocument();
        expect(screen.getByRole('tab', { name: 'รายงานการใช้รถ' })).toBeInTheDocument();
        expect(screen.getByRole('heading', { name: 'รายงานการใช้น้ำมัน' })).toBeInTheDocument();
        expect(screen.getAllByText('รถดรัมโอเว่น').length).toBeGreaterThan(0);
        expect(screen.getByText('เติมรถดรัม')).toBeInTheDocument();
        expect(screen.getByRole('button', { name: 'Export CSV' })).toBeInTheDocument();
        expect(screen.getByRole('button', { name: 'รายงานใช้น้ำมันรถแม็คโคร' })).toBeInTheDocument();
        expect(screen.getByRole('button', { name: 'รายงานการใช้น้ำมันเครื่องจักรร่อนทราย เครื่องปั่นไฟ' })).toBeInTheDocument();
        expect(screen.getByRole('button', { name: 'รายงานเติมน้ำมันอื่นๆทั้งหมด' })).toBeInTheDocument();
        expect(screen.getByRole('button', { name: 'รายงานรับน้ำมันเข้า' })).toBeInTheDocument();
        expect(screen.getAllByRole('button', { name: 'สรุปภาพรวมรายงานการใช้น้ำมัน' }).length).toBeGreaterThanOrEqual(1);
        expect(screen.getByRole('heading', { name: 'สรุปภาพรวมแต่ละรายงาน' })).toBeInTheDocument();
        expect(screen.getByRole('columnheader', { name: 'พิมพ์+ภาษาจีน' })).toBeInTheDocument();
        expect(screen.getAllByText('รายงานรับน้ำมันเข้า').length).toBeGreaterThanOrEqual(1);
        expect(screen.getAllByRole('button', { name: 'พิมพ์收油报表' }).length).toBeGreaterThanOrEqual(1);
        expect(screen.getAllByRole('button', { name: '燃油报表总览' }).length).toBeGreaterThanOrEqual(1);
        expect(screen.getAllByText(/60 ลิตร/).length).toBeGreaterThan(0);
        expect(screen.queryByText(/60 ล\./)).not.toBeInTheDocument();
        expect(screen.queryByRole('columnheader', { name: 'ประเภท' })).not.toBeInTheDocument();
        expect(screen.queryByRole('columnheader', { name: 'น้ำมัน' })).not.toBeInTheDocument();
        expect(screen.queryByText('ค่าใช้จ่าย')).not.toBeInTheDocument();
        expect(screen.queryByText(/฿/)).not.toBeInTheDocument();
        expect(screen.getByLabelText('ตั้งแต่ เดือน')).toBeInTheDocument();
        expect(screen.getByLabelText('ถึง เดือน')).toBeInTheDocument();
        for (const month of ['มกราคม', 'สิงหาคม', 'ธันวาคม'] as const) {
            expect(THAI_MONTHS).toContain(month);
        }
        expect(screen.getAllByRole('option', { name: 'สิงหาคม' }).length).toBeGreaterThan(0);
    });

    it('filters the table when a vehicle is selected', async () => {
        const user = userEvent.setup();
        render(
            <ReportsModule
                settings={settings}
                transactions={[
                    fuelTx({
                        id: 'v1',
                        date: '2026-08-10',
                        fuelMovement: 'stock_out',
                        vehicleId: 'รถดรัมโอเว่น',
                        quantity: 60,
                        amount: 1800,
                        description: 'เติมโอเว่น',
                    }),
                    fuelTx({
                        id: 'v2',
                        date: '2026-08-11',
                        fuelMovement: 'stock_out',
                        vehicleId: 'รถเก๋ง',
                        quantity: 10,
                        amount: 400,
                        description: 'เติมเก๋ง',
                    }),
                ]}
            />
        );

        await user.selectOptions(screen.getByLabelText('รถ'), 'รถเก๋ง');
        expect(screen.queryByText('เติมโอเว่น')).not.toBeInTheDocument();
        expect(screen.getByText('เติมเก๋ง')).toBeInTheDocument();
    });

    it('recalculates display when the selected month range changes', async () => {
        const user = userEvent.setup();
        render(
            <ReportsModule
                settings={settings}
                transactions={[
                    fuelTx({
                        id: 'aug',
                        date: '2026-08-10',
                        fuelMovement: 'stock_out',
                        vehicleId: 'รถดรัมโอเว่น',
                        quantity: 60,
                        description: 'เติมเดือนสิงหาคม',
                    }),
                    fuelTx({
                        id: 'jul',
                        date: '2026-07-15',
                        fuelMovement: 'stock_out',
                        vehicleId: 'รถดรัมโอเว่น',
                        quantity: 25,
                        description: 'เติมเดือนกรกฎาคม',
                    }),
                ]}
            />
        );

        expect(screen.getByText('เติมเดือนสิงหาคม')).toBeInTheDocument();
        expect(screen.queryByText('เติมเดือนกรกฎาคม')).not.toBeInTheDocument();
        expect(screen.getAllByText(/1 รายการ/).length).toBeGreaterThanOrEqual(1);

        await user.selectOptions(screen.getByLabelText('ตั้งแต่ เดือน'), '7');
        await user.selectOptions(screen.getByLabelText('ถึง เดือน'), '7');

        expect(screen.getByText('เติมเดือนกรกฎาคม')).toBeInTheDocument();
        expect(screen.queryByText('เติมเดือนสิงหาคม')).not.toBeInTheDocument();
        expect(screen.getByText(/01\/07\/2569 – 31\/07\/2569/)).toBeInTheDocument();
        expect(screen.getAllByText(/1 รายการ/).length).toBeGreaterThanOrEqual(1);
    });

    it('still calculates when start and end dates are inverted', async () => {
        const user = userEvent.setup();
        render(
            <ReportsModule
                settings={settings}
                transactions={[
                    fuelTx({
                        id: 'aug',
                        date: '2026-08-10',
                        fuelMovement: 'stock_out',
                        vehicleId: 'รถดรัมโอเว่น',
                        quantity: 60,
                        description: 'เติมเดือนสิงหาคม',
                    }),
                ]}
            />
        );

        // ตั้งแต่ = 31 ส.ค., ถึง = 1 ส.ค. → normalize เป็น 1–31 ส.ค.
        await user.selectOptions(screen.getByLabelText('ตั้งแต่ วัน'), '31');
        await user.selectOptions(screen.getByLabelText('ถึง วัน'), '1');

        expect(screen.getByText('เติมเดือนสิงหาคม')).toBeInTheDocument();
        expect(screen.getByText(/01\/08\/2569 – 31\/08\/2569/)).toBeInTheDocument();
    });

    it('switches to vehicle usage report submenu', async () => {
        const user = userEvent.setup();
        render(
            <ReportsModule
                settings={settings}
                employees={[{ id: 'e1', name: 'สมชาย', nickname: 'ชาย', type: 'Daily', positions: ['คนขับรถแม็คโคร'] }]}
                transactions={[
                    {
                        id: 'm1',
                        date: '2026-08-10',
                        type: 'Expense',
                        category: 'Vehicle',
                        description: 'แม็คโคร',
                        amount: 0,
                        vehicleId: 'แม็คโคร 01',
                        driverId: 'e1',
                        workType: 'FullDay',
                        workDetails: 'ขุดลาน',
                    },
                ]}
            />
        );

        await user.click(screen.getByRole('tab', { name: 'รายงานการใช้รถ' }));
        expect(screen.getByRole('tab', { name: 'รายงานรถแม็คโคร' })).toBeInTheDocument();
        expect(screen.getByRole('tab', { name: 'รายงานรถดั๊ม / สิบล้อ / ดรัม' })).toBeInTheDocument();
        expect(screen.getByRole('heading', { name: 'รายงานรถแม็คโคร' })).toBeInTheDocument();
        expect(screen.getByRole('button', { name: 'พิมพ์แม็คโคร 01' })).toBeInTheDocument();
        expect(screen.getAllByText('แม็คโคร 01').length).toBeGreaterThan(0);
        expect(screen.getByText('ขุดลาน')).toBeInTheDocument();
        expect(screen.getByText('ชาย')).toBeInTheDocument();
        expect(screen.queryByRole('columnheader', { name: 'สรุป' })).not.toBeInTheDocument();
        expect(screen.queryByRole('columnheader', { name: 'เที่ยว' })).not.toBeInTheDocument();
        expect(screen.queryByRole('columnheader', { name: 'คิว' })).not.toBeInTheDocument();
    });
});
