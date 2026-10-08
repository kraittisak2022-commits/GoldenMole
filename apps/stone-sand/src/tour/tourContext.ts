import { createContext, useContext } from 'react';
import type { TourState } from './tourEngine';

export interface TourApi {
  state: TourState | null;
  starting: boolean;
  error: string;
  start: () => Promise<void>;
  resume: () => void;
  /** Delete every demo row created in this tour and leave demo mode. */
  end: () => Promise<void>;
}

export const TourContext = createContext<TourApi | null>(null);

export function useTour(): TourApi {
  const api = useContext(TourContext);
  if (!api) throw new Error('useTour must be used inside TourProvider');
  return api;
}
