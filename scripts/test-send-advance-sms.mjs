/**
 * Local smoke test: sign in to Supabase, invoke Edge Function send-advance-sms (same path as the app).
 *
 * Required (env or root .env):
 *   VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY
 *   SMS_TEST_EMAIL, SMS_TEST_PASSWORD — any project user that can sign in
 *   SMS_TEST_DEST — Thai mobile(s), comma-separated, e.g. 0812345678
 *
 * Usage: npm run test:sms
 * Do not commit real passwords; use a throwaway test user if needed.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');

function parseEnvFile(filePath) {
  const out = {};
  if (!fs.existsSync(filePath)) return out;
  const text = fs.readFileSync(filePath, 'utf8');
  for (const line of text.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    let val = trimmed.slice(eq + 1).trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    out[key] = val;
  }
  return out;
}

const fileEnv = parseEnvFile(path.join(root, '.env'));
const env = { ...fileEnv, ...process.env };

const url = env.VITE_SUPABASE_URL || '';
const anon = env.VITE_SUPABASE_ANON_KEY || '';
const email = env.SMS_TEST_EMAIL || '';
const password = env.SMS_TEST_PASSWORD || '';
const destRaw = env.SMS_TEST_DEST || '';

function need(name) {
  console.error(`Missing ${name}. Set in .env or process.env (see scripts/test-send-advance-sms.mjs header).`);
  process.exit(1);
}

if (!url) need('VITE_SUPABASE_URL');
if (!anon) need('VITE_SUPABASE_ANON_KEY');
if (!email) need('SMS_TEST_EMAIL');
if (!password) need('SMS_TEST_PASSWORD');
if (!destRaw) need('SMS_TEST_DEST');

const destinations = [
  ...new Set(
    destRaw
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
  ),
];

if (destinations.length === 0) {
  console.error('SMS_TEST_DEST has no valid numbers.');
  process.exit(1);
}

const supabase = createClient(url, anon);

const { data: authData, error: authErr } = await supabase.auth.signInWithPassword({
  email,
  password,
});

if (authErr || !authData.session) {
  console.error('Sign-in failed:', authErr?.message || 'no session');
  process.exit(1);
}

console.log('Signed in as', authData.user?.email ?? authData.user?.id);

const { data, error } = await supabase.functions.invoke('send-advance-sms', {
  body: {
    text: 'GoldenMole ทดสอบ SMS (สคริปต์ scripts/test-send-advance-sms.mjs)',
    destinations,
  },
});

if (error) {
  console.error('invoke error:', error.message);
  console.error(error);
  process.exit(1);
}

console.log('invoke ok:', JSON.stringify(data, null, 2));
process.exit(0);
