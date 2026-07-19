/**
 * market-insights — daily AI analysis of Gold (Thai 96.5% + XAU/USD) and Oil
 * (Thai fuel + Brent/WTI). Collects raw prices + news, asks an AI model to
 * produce a strict JSON analysis, then upserts one row into `market_insights`.
 *
 * Auth (verify_jwt = false in config.toml): either
 *   - header `x-cm-market-secret` == MARKET_INSIGHTS_INVOKER_SECRET, or
 *   - a valid Supabase JWT (Authorization: Bearer ...)
 *
 * Secrets (set in Supabase → Edge Functions → Secrets):
 *   - MARKET_INSIGHTS_INVOKER_SECRET  (shared secret for the daily cron)
 *   - MARKET_AI_API_KEY               (AI model key)
 *   - MARKET_AI_BASE_URL              (default https://api.openai.com/v1)
 *   - MARKET_AI_MODEL                 (default gpt-4o-mini)
 *   - GOLDAPI_KEY        (optional, goldapi.io for XAU/USD)
 *   - NEWSAPI_KEY        (optional, newsapi.org for headlines)
 * SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY are provided by the runtime.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cm-market-secret",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function secureCompareStrings(a: string, b: string): boolean {
  const x = a.trim();
  const y = b.trim();
  if (!x || !y || x.length !== y.length) return false;
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x.charCodeAt(i) ^ y.charCodeAt(i);
  return d === 0;
}

async function assertCallerAuthorized(req: Request): Promise<Response | null> {
  const envSecret = (Deno.env.get("MARKET_INSIGHTS_INVOKER_SECRET") ?? "").trim();
  const headerSecret = (req.headers.get("x-cm-market-secret") ?? "").trim();
  if (envSecret !== "" && headerSecret !== "" && secureCompareStrings(envSecret, headerSecret)) {
    return null;
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return jsonResponse({
      ok: false,
      error: "Missing authorization",
      hint_th: "ส่ง header x-cm-market-secret ให้ตรงกับ MARKET_INSIGHTS_INVOKER_SECRET หรือ Authorization: Bearer <anon key / JWT>",
    }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonResponse({ ok: false, error: "Server misconfigured" }, 500);
  }
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }
  return null;
}

// ---- Data collection (best-effort; each source degrades independently) ----

type RawPoint = { source: string; value: number; unit: string; extra?: Record<string, unknown> };

async function fetchJSON(url: string, init?: RequestInit, timeoutMs = 12000): Promise<unknown | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const resp = await fetch(url, { ...init, signal: controller.signal });
    if (!resp.ok) return null;
    return await resp.json();
  } catch (_e) {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** USD/THB exchange rate (free, no key). */
async function fetchUsdThb(): Promise<number | null> {
  const data = await fetchJSON("https://open.er-api.com/v6/latest/USD") as
    | { rates?: { THB?: number } }
    | null;
  const thb = data?.rates?.THB;
  return typeof thb === "number" && thb > 0 ? thb : null;
}

/** Global gold XAU/USD per troy ounce. Tries goldapi.io (key) then a free fallback. */
async function fetchGlobalGoldUsd(): Promise<number | null> {
  const key = (Deno.env.get("GOLDAPI_KEY") ?? "").trim();
  if (key) {
    const data = await fetchJSON("https://www.goldapi.io/api/XAU/USD", {
      headers: { "x-access-token": key, "Content-Type": "application/json" },
    }) as { price?: number } | null;
    if (typeof data?.price === "number" && data.price > 0) return data.price;
  }
  // Free fallback (no key). Endpoint returns { price: number } for XAU in USD.
  const free = await fetchJSON("https://api.gold-api.com/price/XAU") as { price?: number } | null;
  if (typeof free?.price === "number" && free.price > 0) return free.price;
  return null;
}

/** News headlines about gold + oil (best-effort; needs NEWSAPI_KEY). */
async function fetchNews(): Promise<Array<Record<string, unknown>>> {
  const key = (Deno.env.get("NEWSAPI_KEY") ?? "").trim();
  if (!key) return [];
  const q = encodeURIComponent("gold OR oil OR crude OR ทองคำ OR น้ำมัน");
  const url =
    `https://newsapi.org/v2/everything?q=${q}&language=en&sortBy=publishedAt&pageSize=12&apiKey=${key}`;
  const data = await fetchJSON(url) as
    | { articles?: Array<{ title?: string; url?: string; source?: { name?: string }; publishedAt?: string; description?: string }> }
    | null;
  if (!data?.articles) return [];
  return data.articles.slice(0, 12).map((a) => ({
    title: a.title ?? "",
    url: a.url ?? "",
    source: a.source?.name ?? "",
    publishedAt: a.publishedAt ?? "",
    summary: a.description ?? "",
  }));
}

async function collectRawData(): Promise<{ raw: Record<string, unknown>; hasPrices: boolean }> {
  const [usdThb, goldUsd, news] = await Promise.all([
    fetchUsdThb(),
    fetchGlobalGoldUsd(),
    fetchNews(),
  ]);

  // Thai 96.5% gold ~ derived estimate (global XAU spot * baht weight * purity), for context only.
  // 1 baht of gold = 15.244 g; 1 troy oz = 31.1035 g; Thai bar is 96.5% purity.
  let thaiGoldPerBahtEst: number | null = null;
  if (goldUsd && usdThb) {
    const perGramUsd = goldUsd / 31.1035;
    const perBahtUsd = perGramUsd * 15.244 * 0.965;
    thaiGoldPerBahtEst = Math.round(perBahtUsd * usdThb);
  }

  const raw = {
    collectedAt: new Date().toISOString(),
    fx: { usdThb },
    gold: { globalUsdPerOz: goldUsd, thaiPerBahtEstimate: thaiGoldPerBahtEst },
    // Oil spot is left to the AI's latest knowledge when no key source is configured.
    oil: { note: "Provide latest Brent/WTI and Thai retail diesel/gasohol from best available knowledge." },
    news,
  };
  return { raw, hasPrices: Boolean(goldUsd) };
}

// ---- AI analysis ----

const OUTPUT_CONTRACT = `
คุณคือผู้ช่วยวิเคราะห์ตลาดทองคำและน้ำมันสำหรับผู้ใช้ชาวไทย ตอบเป็นภาษาไทยทั้งหมด
สร้างการวิเคราะห์ "รายวัน" ของ 4 สินทรัพย์นี้เท่านั้น (key ต้องตรง):
- thai_gold_965 : ทองคำแท่ง 96.5% ราคาไทย หน่วย "บาท" (ต่อทองหนัก 1 บาท), currency "THB"
- global_gold   : ทองคำตลาดโลก XAU/USD หน่วย "ออนซ์", currency "USD"
- thai_fuel     : น้ำมันไทย ใช้ดีเซลเป็นตัวแทน หน่วย "ลิตร", currency "THB"
- global_oil    : น้ำมันดิบ Brent หน่วย "บาร์เรล", currency "USD"

ใช้ข้อมูลดิบที่ให้มา (ราคาจริง/ค่าเงิน/ข่าว) เป็นหลัก ส่วนที่ไม่มีให้ประเมินจากความรู้ล่าสุดและตั้ง dataQuality ให้ต่ำลง
สำหรับ news ของแต่ละ asset ให้เลือกจากรายการข่าวที่ให้มา (ถ้ามี) หรือสรุปประเด็นสำคัญล่าสุดที่เกี่ยวข้อง 2-4 หัวข้อ
ต้องตอบเป็น JSON เท่านั้น ตาม schema นี้ (ห้ามมีข้อความอื่นนอก JSON):
{
  "as_of_date": "YYYY-MM-DD",
  "status": "ok" | "partial" | "failed",
  "assets": [
    {
      "key": "thai_gold_965",
      "label": "ทองคำ 96.5% (ไทย)",
      "unit": "บาท",
      "currency": "THB",
      "currentPrice": number,
      "prevClose": number,
      "changeAbs": number,
      "changePct": number,
      "direction": "up" | "down" | "flat",
      "probabilityUp": number,      // 0-100
      "probabilityDown": number,    // 0-100 (up+down+flat โดยประมาณ = 100)
      "forecast": {
        "direction": "up" | "down" | "flat",
        "expectedChangePct": number,
        "expectedLow": number,
        "expectedHigh": number,
        "horizon": "รายวัน",
        "confidence": number        // 0-1
      },
      "metrics": [ { "label": string, "value": string, "hint": string } ],
      "history": [ { "date": "YYYY-MM-DD", "price": number } ],  // ~14 จุดล่าสุด (ประเมินได้)
      "drivers": [ string ],        // ปัจจัยหลัก 3-5 ข้อ ภาษาไทย
      "news": [ { "title": string, "source": string, "url": string, "publishedAt": "YYYY-MM-DD", "sentiment": "positive"|"negative"|"neutral", "summary": string } ],
      "aiSummary": string,          // สรุปสั้น 2-4 ประโยค ภาษาไทย
      "dataQuality": "high" | "medium" | "low"
    }
    // ... อีก 3 สินทรัพย์ในรูปแบบเดียวกัน
  ],
  "disclaimer": "ข้อมูลนี้เป็นการวิเคราะห์เชิงสถิติ/AI ไม่ใช่คำแนะนำการลงทุน"
}
ต้องมีครบทั้ง 4 assets ตาม key ที่กำหนด ตัวเลขต้องสมเหตุสมผลกับหน่วยของสินทรัพย์นั้น`;

async function runAI(raw: Record<string, unknown>): Promise<{ payload: Record<string, unknown> | null; error?: string }> {
  const apiKey = (Deno.env.get("MARKET_AI_API_KEY") ?? "").trim();
  if (!apiKey) return { payload: null, error: "MARKET_AI_API_KEY not set" };
  const baseUrl = (Deno.env.get("MARKET_AI_BASE_URL") ?? "https://api.openai.com/v1").replace(/\/+$/, "");
  const model = (Deno.env.get("MARKET_AI_MODEL") ?? "gpt-4o-mini").trim();

  const todayBkk = new Date(Date.now() + 7 * 3600 * 1000).toISOString().slice(0, 10);
  const body = {
    model,
    temperature: 0.4,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: OUTPUT_CONTRACT },
      {
        role: "user",
        content:
          `วันนี้ (Asia/Bangkok) = ${todayBkk}\nข้อมูลดิบล่าสุด (JSON):\n${JSON.stringify(raw)}\n\nโปรดวิเคราะห์และตอบตาม schema`,
      },
    ],
  };

  const resp = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const t = await resp.text();
    return { payload: null, error: `AI HTTP ${resp.status}: ${t.slice(0, 300)}` };
  }
  const data = await resp.json() as { choices?: Array<{ message?: { content?: string } }> };
  const content = data?.choices?.[0]?.message?.content ?? "";
  try {
    const parsed = JSON.parse(content) as Record<string, unknown>;
    return { payload: parsed };
  } catch (_e) {
    return { payload: null, error: "AI returned non-JSON content" };
  }
}

function validatePayload(payload: Record<string, unknown>): string | null {
  const assets = payload?.assets;
  if (!Array.isArray(assets) || assets.length < 4) return "assets ต้องมีครบ 4 รายการ";
  const required = new Set(["thai_gold_965", "global_gold", "thai_fuel", "global_oil"]);
  for (const a of assets) {
    const key = (a as { key?: string }).key;
    if (typeof key === "string") required.delete(key);
  }
  if (required.size > 0) return `ขาด asset: ${[...required].join(", ")}`;
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405, headers: corsHeaders });
  }

  const denied = await assertCallerAuthorized(req);
  if (denied) return denied;

  const serviceUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!serviceUrl || !serviceKey) {
    return jsonResponse({ ok: false, code: "misconfigured", message: "missing service role" }, 200);
  }

  const { raw, hasPrices } = await collectRawData();
  const ai = await runAI(raw);
  if (!ai.payload) {
    return jsonResponse({ ok: false, code: "ai_failed", message: ai.error ?? "AI failed" }, 200);
  }

  const validationError = validatePayload(ai.payload);
  if (validationError) {
    return jsonResponse({ ok: false, code: "invalid_ai_output", message: validationError }, 200);
  }

  const status = typeof ai.payload.status === "string"
    ? ai.payload.status as string
    : (hasPrices ? "ok" : "partial");
  const asOf = typeof ai.payload.as_of_date === "string"
    ? ai.payload.as_of_date as string
    : new Date(Date.now() + 7 * 3600 * 1000).toISOString().slice(0, 10);

  const admin = createClient(serviceUrl, serviceKey);
  const { error: insertErr } = await admin.from("market_insights").insert({
    as_of_date: asOf,
    status,
    payload: ai.payload,
  });
  if (insertErr) {
    return jsonResponse({ ok: false, code: "db_error", message: insertErr.message }, 200);
  }

  return jsonResponse({ ok: true, as_of_date: asOf, status, hasPrices });
});
