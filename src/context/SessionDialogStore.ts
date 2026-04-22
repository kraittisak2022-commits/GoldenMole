import { createContext } from 'react';
import { SessionDialogContextValue } from './useSessionDialog';

export const SessionDialogContext = createContext<SessionDialogContextValue | null>(null);
