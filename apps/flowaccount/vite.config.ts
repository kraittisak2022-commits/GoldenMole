import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig(({ mode }) => {
  // Prefer .env / Vercel VITE_* ; fall back to unprefixed names used by some hosts
  const env = loadEnv(mode, process.cwd(), '');
  const supabaseUrl =
    env.VITE_SUPABASE_URL ||
    process.env.VITE_SUPABASE_URL ||
    process.env.SUPABASE_URL ||
    '';
  const supabaseAnonKey =
    env.VITE_SUPABASE_ANON_KEY ||
    process.env.VITE_SUPABASE_ANON_KEY ||
    process.env.SUPABASE_ANON_KEY ||
    '';

  return {
    plugins: [react()],
    // Only inject when present — never bake empty strings over Vite's env handling
    define: {
      ...(supabaseUrl
        ? { 'import.meta.env.VITE_SUPABASE_URL': JSON.stringify(supabaseUrl) }
        : {}),
      ...(supabaseAnonKey
        ? { 'import.meta.env.VITE_SUPABASE_ANON_KEY': JSON.stringify(supabaseAnonKey) }
        : {}),
    },
    server: {
      allowedHosts: ['flowaccount.goldenmole.pro', 'localhost'],
    },
    test: {
      environment: 'jsdom',
      setupFiles: './src/test/setup.ts',
      globals: true,
      css: false,
    },
  };
});
