import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { getSettings, listProducts, listZones } from '../data/catalog';
import { listDrivers } from '../data/drivers';
import { DEFAULT_SETTINGS, type AppSettings, type Driver, type Product, type Zone } from '../types';

interface CatalogValue {
  products: Product[];
  zones: Zone[];
  drivers: Driver[];
  settings: AppSettings;
  loading: boolean;
  error: string;
  reload: () => Promise<void>;
  zoneById: (id: string | null | undefined) => Zone | undefined;
  zoneByName: (name: string | null | undefined) => Zone | undefined;
  driverById: (id: string | null | undefined) => Driver | undefined;
}

const CatalogContext = createContext<CatalogValue | null>(null);

export function CatalogProvider({ children }: { children: ReactNode }) {
  const [products, setProducts] = useState<Product[]>([]);
  const [zones, setZones] = useState<Zone[]>([]);
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_SETTINGS);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const reload = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const [p, z, d, s] = await Promise.all([
        listProducts(),
        listZones(),
        listDrivers({ includeInactive: true }),
        getSettings(),
      ]);
      setProducts(p);
      setZones(z);
      setDrivers(d);
      setSettings(s);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'โหลดข้อมูลหลักไม่สำเร็จ');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  const value = useMemo<CatalogValue>(
    () => ({
      products,
      zones,
      drivers,
      settings,
      loading,
      error,
      reload,
      zoneById: (id) => zones.find((z) => z.id === id),
      zoneByName: (name) => zones.find((z) => z.name === name),
      driverById: (id) => drivers.find((d) => d.id === id),
    }),
    [products, zones, drivers, settings, loading, error, reload],
  );

  return <CatalogContext.Provider value={value}>{children}</CatalogContext.Provider>;
}

export function useCatalog(): CatalogValue {
  const ctx = useContext(CatalogContext);
  if (!ctx) throw new Error('useCatalog must be used within CatalogProvider');
  return ctx;
}
