import { useContext } from 'react';
import { SessionDialogContext } from './SessionDialogStore';

export type SessionDialogContextValue = {
    alert: (message: string, opts?: { title?: string }) => Promise<void>;
    confirm: (message: string, opts?: { title?: string }) => Promise<boolean>;
};

export function useSessionDialog(): SessionDialogContextValue {
    const ctx = useContext(SessionDialogContext);
    if (!ctx) {
        return {
            alert: async (message: string) => {
                window.alert(message);
            },
            confirm: async (message: string) => window.confirm(message),
        };
    }
    return ctx;
}
