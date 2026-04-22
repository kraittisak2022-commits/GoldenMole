import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import { execSync } from 'node:child_process'

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
    const env = loadEnv(mode, process.cwd(), '')
    const getCmd = (cmd: string) => {
        try {
            return execSync(cmd, { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
        } catch {
            return '';
        }
    };

    // Resolve Supabase env vars: check VITE_ prefix first, then Vercel's names via process.env
    const supabaseUrl = env.VITE_SUPABASE_URL || process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || '';
    const supabaseAnonKey = env.VITE_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY || '';
    const gitShortHash = getCmd('git rev-parse --short HEAD');
    const gitUpdatedAt = getCmd('git log -1 --format=%cs');
    const gitChangelogRaw = getCmd('git log -5 --pretty=format:%s');
    const gitChangelog = gitChangelogRaw ? gitChangelogRaw.split('\n').map(s => s.trim()).filter(Boolean) : [];
    const baseVersion = env.VITE_APP_VERSION || process.env.npm_package_version || 'dev';
    const appVersion = gitShortHash ? `${baseVersion}-${gitShortHash}` : baseVersion;
    const appUpdatedAt = env.VITE_APP_UPDATED_AT || gitUpdatedAt || new Date().toISOString().slice(0, 10);

    return {
        plugins: [react()],
        define: {
            // Inject Supabase env vars so client code can access them via import.meta.env
            'import.meta.env.VITE_SUPABASE_URL': JSON.stringify(supabaseUrl),
            'import.meta.env.VITE_SUPABASE_ANON_KEY': JSON.stringify(supabaseAnonKey),
            'import.meta.env.VITE_APP_VERSION': JSON.stringify(appVersion),
            'import.meta.env.VITE_APP_UPDATED_AT': JSON.stringify(appUpdatedAt),
            'import.meta.env.VITE_APP_AUTO_CHANGELOG': JSON.stringify(JSON.stringify(gitChangelog)),
        },
        server: {
            allowedHosts: ['goldenmole.pro', 'www.goldenmole.pro'],
        },
        build: {
            chunkSizeWarningLimit: 1000,
            rollupOptions: {
                output: {
                    manualChunks(id) {
                        if (!id.includes('node_modules')) return;
                        if (id.includes('react')) return 'vendor-react';
                        if (id.includes('recharts')) return 'vendor-charts';
                        if (id.includes('lucide-react')) return 'vendor-icons';
                        if (id.includes('@supabase')) return 'vendor-supabase';
                        return 'vendor-misc';
                    },
                },
            },
        },
        test: {
            environment: 'jsdom',
            setupFiles: './src/test/setup.ts',
            globals: true,
            css: false,
            exclude: ['e2e/**', 'node_modules/**'],
        },
    }
})
