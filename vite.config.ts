import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
    const env = loadEnv(mode, process.cwd(), '')

    // Resolve Supabase env vars: check VITE_ prefix first, then Vercel's names via process.env
    const supabaseUrl = env.VITE_SUPABASE_URL || process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || '';
    const supabaseAnonKey = env.VITE_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY || '';

    return {
        plugins: [react()],
        define: {
            // Inject Supabase env vars so client code can access them via import.meta.env
            'import.meta.env.VITE_SUPABASE_URL': JSON.stringify(supabaseUrl),
            'import.meta.env.VITE_SUPABASE_ANON_KEY': JSON.stringify(supabaseAnonKey),
        },
        server: {
            allowedHosts: ['goldenmole.pro', 'www.goldenmole.pro'],
        },
        build: {
            chunkSizeWarningLimit: 1000,
        },
    }
})
