/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string;
  readonly VITE_SUPABASE_ANON_KEY: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

/** Id of this build; `/version.json` holds the id of the latest deploy. 'dev' when not built. */
declare const __BUILD_ID__: string;
