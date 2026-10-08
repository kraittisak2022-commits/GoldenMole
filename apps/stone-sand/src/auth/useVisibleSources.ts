import { useMemo } from 'react';
import { ORDER_SOURCES, type OrderSource } from '../types';
import { useAuth } from './AuthProvider';

/** Order sources the signed-in account may see and create. */
export function useVisibleSources(): OrderSource[] {
  const { lockedSource } = useAuth();
  return useMemo(() => (lockedSource ? [lockedSource] : ORDER_SOURCES), [lockedSource]);
}
