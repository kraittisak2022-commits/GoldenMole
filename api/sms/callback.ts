/**
 * SMSOK delivery / status webhook — public URL:
 *   https://goldenmole.pro/sms/callback  (via vercel.json rewrite from /sms/callback)
 *
 * Set on Vercel (Environment Variables), never commit secrets:
 *   SMSOK_WEBHOOK_SECRET — optional; if set, require header x-smsok-webhook-secret to match
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';

function header(req: VercelRequest, name: string): string | undefined {
  const v = req.headers[name.toLowerCase()];
  if (Array.isArray(v)) return v[0];
  return typeof v === 'string' ? v : undefined;
}

export default async function handler(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Smsok-Webhook-Secret, X-Smsok-Signature',
  );

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  if (req.method !== 'GET' && req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const expected = (process.env.SMSOK_WEBHOOK_SECRET ?? '').trim();
  if (expected.length > 0) {
    const h =
      header(req, 'x-smsok-webhook-secret') ??
      header(req, 'X-Smsok-Webhook-Secret') ??
      '';
    if (h !== expected) {
      res.status(403).json({ error: 'Forbidden' });
      return;
    }
  }

    try {
      let payload: unknown;
      if (req.method === 'GET') {
        payload = { ...req.query };
      } else {
        const ct = (header(req, 'content-type') ?? '').toLowerCase();
        if (ct.includes('application/json')) {
          if (req.body == null || req.body === '') {
            payload = {};
          } else if (typeof req.body === 'object') {
            payload = req.body;
          } else {
            payload = JSON.parse(String(req.body));
          }
        } else {
          payload = req.body ?? null;
        }
      }
    console.log(
      '[smsok webhook goldenmole.pro]',
      JSON.stringify({ method: req.method, payload }),
    );
  } catch (e) {
    console.error('[smsok webhook goldenmole.pro] parse error', e);
  }

  res.status(200).json({ ok: true, receivedAt: new Date().toISOString() });
}
