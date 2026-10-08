import { defineConfig, loadEnv, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';

/** Writes /version.json so open tabs can tell a newer deploy is live. */
function versionFile(buildId: string): Plugin {
  return {
    name: 'stone-sand-version-file',
    apply: 'build',
    generateBundle() {
      this.emitFile({ type: 'asset', fileName: 'version.json', source: JSON.stringify({ buildId }) });
    },
  };
}

export default defineConfig(({ mode, command }) => {
  const buildId =
    command === 'build' ? (process.env.VERCEL_GIT_COMMIT_SHA || '').slice(0, 12) || Date.now().toString(36) : 'dev';
  // Prefer .env / Vercel VITE_* ; fall back to unprefixed names used by some hosts
  const env = loadEnv(mode, process.cwd(), '');
  const supabaseUrl =
    env.VITE_SUPABASE_URL ||
    env.SUPABASE_URL ||
    process.env.VITE_SUPABASE_URL ||
    process.env.SUPABASE_URL ||
    '';
  const supabaseAnonKey =
    env.VITE_SUPABASE_ANON_KEY ||
    env.SUPABASE_ANON_KEY ||
    process.env.VITE_SUPABASE_ANON_KEY ||
    process.env.SUPABASE_ANON_KEY ||
    '';

  return {
    plugins: [react(), versionFile(buildId)],
    // Only inject when present — never bake empty strings over Vite's env handling
    define: {
      __BUILD_ID__: JSON.stringify(buildId),
      ...(supabaseUrl
        ? { 'import.meta.env.VITE_SUPABASE_URL': JSON.stringify(supabaseUrl) }
        : {}),
      ...(supabaseAnonKey
        ? { 'import.meta.env.VITE_SUPABASE_ANON_KEY': JSON.stringify(supabaseAnonKey) }
        : {}),
    },
    server: {
      port: 5180,
      allowedHosts: ['localhost'],
    },
    test: {
      environment: 'jsdom',
      setupFiles: './src/test/setup.ts',
      globals: true,
      css: false,
    },
  };
});
