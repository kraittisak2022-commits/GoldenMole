import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import RecordManager from './RecordManager';
import { SessionDialogProvider } from '../../context/SessionDialogContext';
import { Transaction } from '../../types';

vi.mock('@tanstack/react-virtual', () => ({
    useVirtualizer: ({ count, estimateSize }: { count: number; estimateSize: (index: number) => number }) => {
        const visibleCount = Math.min(count, 40);
        let offset = 0;
        const virtualItems = Array.from({ length: visibleCount }, (_, index) => {
            const start = offset;
            offset += estimateSize(index);
            return { key: index, index, start };
        });
        return {
            getTotalSize: () => Array.from({ length: count }, (_, i) => estimateSize(i)).reduce((a, b) => a + b, 0),
            getVirtualItems: () => virtualItems,
            measureElement: () => {},
        };
    },
}));

function makeTx(id: number): Transaction {
    return {
        id: String(id),
        date: '2026-04-22',
        type: id % 2 === 0 ? 'Expense' : 'Income',
        category: id % 2 === 0 ? 'Fuel' : 'Income',
        description: `row-${id}`,
        amount: id * 10 + 1,
    };
}

describe('RecordManager integration', () => {
    it('asks confirmation before delete in both cancel and confirm flows', async () => {
        const user = userEvent.setup();
        const handleDelete = vi.fn();
        render(
            <SessionDialogProvider>
                <RecordManager transactions={[makeTx(1), makeTx(2)]} onDeleteTransaction={handleDelete} compact />
            </SessionDialogProvider>
        );

        const deleteBtn = screen.getAllByLabelText('ลบ')[0];
        await user.click(deleteBtn);
        expect(screen.getByText('ลบรายการนี้?')).toBeInTheDocument();
        await user.click(screen.getByRole('button', { name: 'ยกเลิก' }));
        expect(handleDelete).not.toHaveBeenCalled();

        await user.click(deleteBtn);
        await user.click(screen.getByRole('button', { name: 'ตกลง' }));
        expect(handleDelete).toHaveBeenCalledWith('1');
    });

    it('keeps virtualized rendering functional while filtering/searching', async () => {
        const user = userEvent.setup();
        const txs = Array.from({ length: 220 }, (_, i) => makeTx(i + 1));
        render(
            <SessionDialogProvider>
                <RecordManager transactions={txs} compact />
            </SessionDialogProvider>
        );

        expect(screen.getByText('row-1')).toBeInTheDocument();
        // Virtualized list should not eagerly render every row.
        expect(screen.queryByText('row-220')).not.toBeInTheDocument();

        const search = screen.getByPlaceholderText('ค้นหา...');
        await user.type(search, 'row-220');
        expect(await screen.findByText('row-220')).toBeInTheDocument();
    });
});
