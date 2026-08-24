import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import ReportsModule from './ReportsModule';
import type { AppSettings, Transaction } from '../../types';
import { getToday } from '../../utils';

const settings = {
    appName: 'Goldenmole',
    cars: ['รถดรัมโอเว่น'],
    fuelOpeningStockLiters: { Diesel: 0, Benzine: 0 },
} as AppSettings;

function fuelTx(partial: Partial<Transaction> & Pick<Transaction, 'id'>): Transaction {
    return {
        date: getToday(),
        type: 'Expense',
        category: 'Fuel',
        description: 'น้ำมัน',
        amount: 0,
        ...partial,
    };
}

describe('ReportsModule', () => {
    it('shows fuel usage summary for the current month', () => {
        render(
            <ReportsModule
                settings={settings}
                transactions={[
                    fuelTx({
                        id: 'v1',
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

        expect(screen.getByRole('heading', { name: 'รายงานการใช้น้ำมัน' })).toBeInTheDocument();
        expect(screen.getAllByText('รถดรัมโอเว่น').length).toBeGreaterThan(0);
        expect(screen.getByText('เติมรถดรัม')).toBeInTheDocument();
        expect(screen.getByRole('button', { name: 'Export CSV' })).toBeInTheDocument();
        expect(screen.getByRole('button', { name: 'พิมพ์/PDF' })).toBeInTheDocument();
    });

    it('filters the table when a vehicle is selected', async () => {
        const user = userEvent.setup();
        render(
            <ReportsModule
                settings={settings}
                transactions={[
                    fuelTx({
                        id: 'v1',
                        fuelMovement: 'stock_out',
                        vehicleId: 'รถดรัมโอเว่น',
                        quantity: 60,
                        amount: 1800,
                        description: 'เติมโอเว่น',
                    }),
                    fuelTx({
                        id: 'v2',
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
});
