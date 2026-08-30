import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import EmployeeManager from './EmployeeManager';
import type { AppSettings, Employee, Transaction } from '../../types';

const baseSettings: AppSettings = {
    appName: 'CM',
    appSubtext: '',
    appIcon: '',
    cars: [],
    jobDescriptions: [],
    incomeTypes: [],
    expenseTypes: [],
    maintenanceTypes: [],
    locations: [],
    landGroups: [],
    appDefaults: {},
};

const buildEmployee = (id: string, nickname: string): Employee => ({
    id,
    name: nickname,
    nickname,
    type: 'Daily',
    baseWage: 400,
});

describe('EmployeeManager merge — preserves transactions outside the visible subset', () => {
    const originalConfirm = window.confirm;
    const originalAlert = window.alert;

    beforeEach(() => {
        window.confirm = () => true;
        window.alert = () => undefined;
    });
    afterEach(() => {
        window.confirm = originalConfirm;
        window.alert = originalAlert;
    });

    it('uses a functional updater so callers that pass a filtered subset never delete out-of-view rows', () => {
        // The PARENT (App.tsx) holds the full list of transactions and forwards
        // a *filtered* subset (visibleTransactions) into EmployeeManager. If the
        // merge handler replaced state with a mapped copy of that subset, the
        // parent's setter would treat every excluded row as a deletion and wipe
        // the database. We assert here that the merge invokes the functional
        // form so the parent can map over its full snapshot safely.
        const fullStore: Transaction[] = [
            {
                id: 'visible-1',
                date: '2026-04-01',
                type: 'Expense',
                category: 'Labor',
                description: 'work day',
                amount: 400,
                employeeIds: ['emp-from'],
            },
            {
                id: 'hidden-1',
                date: '2026-04-02',
                type: 'Expense',
                category: 'Labor',
                description: 'soft-hidden duplicate',
                amount: 400,
                employeeIds: ['emp-from'],
            },
            {
                id: 'restricted-1',
                date: '2026-04-03',
                type: 'Income',
                category: 'Income',
                description: 'restricted category',
                amount: 1000,
                employeeIds: ['emp-from'],
            },
        ];
        const visibleSubset = fullStore.filter(t => t.id === 'visible-1');

        const setEmployees = vi.fn();
        const setSettings = vi.fn();
        const setTransactions = vi.fn();

        const employees: Employee[] = [buildEmployee('emp-from', 'A'), buildEmployee('emp-to', 'B')];

        render(
            <EmployeeManager
                employees={employees}
                setEmployees={setEmployees}
                transactions={visibleSubset}
                setTransactions={setTransactions}
                settings={baseSettings}
                setSettings={setSettings}
            />,
        );

        fireEvent.click(screen.getByRole('button', { name: /รวมพนักงานซ้ำ/ }));

        const selects = screen.getAllByRole('combobox');
        fireEvent.change(selects[0], { target: { value: 'emp-from' } });
        fireEvent.change(selects[1], { target: { value: 'emp-to' } });
        fireEvent.click(screen.getByRole('button', { name: 'รวมข้อมูล' }));

        expect(setTransactions).toHaveBeenCalledTimes(1);
        const updater = setTransactions.mock.calls[0][0];
        expect(typeof updater).toBe('function');

        const next = updater(fullStore);
        expect(next).toHaveLength(fullStore.length);
        const ids = new Set(next.map((t: Transaction) => t.id));
        expect(ids.has('visible-1')).toBe(true);
        expect(ids.has('hidden-1')).toBe(true);
        expect(ids.has('restricted-1')).toBe(true);
        for (const tx of next) {
            expect(tx.employeeIds).toEqual(['emp-to']);
        }
    });
});
