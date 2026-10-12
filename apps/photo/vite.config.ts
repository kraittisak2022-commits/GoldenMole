import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import { devApi } from './dev/devApi';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  for (const [key, value] of Object.entries(env)) {
    if (process.env[key] === undefined) process.env[key] = value;
  }

  return {
    plugins: [react(), devApi({ mock: process.env.PHOTO_MOCK_API === '1' })],
    server: {
      port: 5190,
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
