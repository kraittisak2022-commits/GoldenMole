import { useState } from 'react';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { SessionDialogProvider } from './SessionDialogContext';
import { useSessionDialog } from './useSessionDialog';

function QueueHarness() {
    const { confirm } = useSessionDialog();
    const [log, setLog] = useState<string[]>([]);

    return (
        <div>
            <button
                type="button"
                onClick={async () => {
                    const first = await confirm('first confirm');
                    setLog(prev => [...prev, `first:${first}`]);
                }}
            >
                open-first
            </button>
            <button
                type="button"
                onClick={async () => {
                    const second = await confirm('second confirm');
                    setLog(prev => [...prev, `second:${second}`]);
                }}
            >
                open-second
            </button>
            <div data-testid="log">{log.join(',')}</div>
        </div>
    );
}

function FocusHarness() {
    const { confirm } = useSessionDialog();
    return (
        <button
            type="button"
            onClick={async () => {
                await confirm('focus confirm');
            }}
        >
            open-focus
        </button>
    );
}

describe('SessionDialogProvider queue', () => {
    it('queues overlapping confirm calls in order', async () => {
        const user = userEvent.setup();
        render(
            <SessionDialogProvider>
                <QueueHarness />
            </SessionDialogProvider>
        );

        await user.click(screen.getByRole('button', { name: 'open-first' }));
        await user.click(screen.getByRole('button', { name: 'open-second' }));

        expect(screen.getByText('first confirm')).toBeInTheDocument();
        await user.click(screen.getByRole('button', { name: 'ตกลง' }));
        expect(screen.getByText('second confirm')).toBeInTheDocument();
        await user.click(screen.getByRole('button', { name: 'ยกเลิก' }));

        expect(screen.getByTestId('log')).toHaveTextContent('first:true,second:false');
    });

    it('restores focus to trigger button after dialog closes', async () => {
        const user = userEvent.setup();
        render(
            <SessionDialogProvider>
                <FocusHarness />
            </SessionDialogProvider>
        );

        const trigger = screen.getByRole('button', { name: 'open-focus' });
        trigger.focus();
        await user.click(trigger);

        expect(screen.getByText('focus confirm')).toBeInTheDocument();
        const okBtn = screen.getByRole('button', { name: 'ตกลง' });
        expect(okBtn).toHaveFocus();
        await user.click(okBtn);
        expect(trigger).toHaveFocus();
    });
});
