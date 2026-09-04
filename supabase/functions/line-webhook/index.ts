/**
 * LINE Messaging API webhook — รับอีเวนต์จากกลุ่มเพื่ออ่าน groupId (C…)
 *
 * วาง URL นี้ใน LINE Developers → Messaging API → Webhook URL:
 *   https://<PROJECT_REF>.supabase.co/functions/v1/line-webhook
 *
 * Secrets (แนะนำ):
 *   LINE_CHANNEL_SECRET — จากแท็บ Basic settings (ตรวจลายเซ็น)
 *
 * GET เรียกดู groupId ที่เพิ่งเห็นล่าสุด (ไม่ต้อง auth ในโหมดอ่านอย่างเดียว)
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-line-signature",
};

const SETTINGS_FIELD = "lineWebhookSeenChats";

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function hmacSha256Base64(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(body),
  );
  const bytes = new Uint8Array(sig);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

function secureCompare(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

type SeenChat = {
  id: string;
  type: string;
  at: string;
  eventType?: string;
};

function extractChats(events: unknown[]): SeenChat[] {
  const out: SeenChat[] = [];
  const now = new Date().toISOString();
  for (const ev of events) {
    if (!ev || typeof ev !== "object") continue;
    const e = ev as {
      type?: string;
      source?: { type?: string; groupId?: string; roomId?: string; userId?: string };
    };
    const src = e.source;
    if (!src) continue;
    if (src.type === "group" && src.groupId) {
      out.push({
        id: src.groupId,
        type: "group",
        at: now,
        eventType: e.type,
      });
    } else if (src.type === "room" && src.roomId) {
      out.push({
        id: src.roomId,
        type: "room",
        at: now,
        eventType: e.type,
      });
    }
  }
  return out;
}

function adminClient() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) return null;
  return createClient(url, key);
}

async function loadSeen(client: ReturnType<typeof createClient>): Promise<SeenChat[]> {
  const { data, error } = await client
    .from("app_settings")
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  if (error || !data) return [];
  const defaults = (data.app_defaults ?? {}) as Record<string, unknown>;
  const raw = defaults[SETTINGS_FIELD];
  if (Array.isArray(raw)) return raw as SeenChat[];
  if (raw && typeof raw === "object" && Array.isArray((raw as { chats?: unknown }).chats)) {
    return (raw as { chats: SeenChat[] }).chats;
  }
  return [];
}

async function saveSeen(
  client: ReturnType<typeof createClient>,
  chats: SeenChat[],
): Promise<void> {
  const trimmed = chats.slice(-30);
  const { data, error } = await client
    .from("app_settings")
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  if (error) throw error;
  const defaults = {
    ...((data?.app_defaults as Record<string, unknown> | null) ?? {}),
    [SETTINGS_FIELD]: {
      chats: trimmed,
      updatedAt: new Date().toISOString(),
    },
  };
  const { error: upErr } = await client
    .from("app_settings")
    .upsert({ id: "default", app_defaults: defaults }, { onConflict: "id" });
  if (upErr) throw upErr;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // อ่าน groupId ที่เคยเห็น — เปิดในเบราว์เซอร์ได้
  if (req.method === "GET") {
    const client = adminClient();
    if (!client) {
      return jsonResponse({
        ok: true,
        hint_th:
          "ยังอ่านประวัติไม่ได้ (ไม่มี SERVICE_ROLE) — ดู Logs ของฟังก์ชันแทนหลังมีคนพิมพ์ในกลุ่ม",
        webhook_url_path: "/functions/v1/line-webhook",
      });
    }
    const chats = await loadSeen(client);
    const groups = chats.filter((c) => c.type === "group");
    return jsonResponse({
      ok: true,
      hint_th:
        groups.length > 0
          ? "คัดลอก id ที่ขึ้นต้นด้วย C ไปใส่ LINE_ADVANCE_NOTIFY_USER_IDS"
          : "ยังไม่มี groupId — เชิญบอทเข้ากลุ่ม แล้วพิมพ์ข้อความในกลุ่ม 1 ครั้ง แล้วรีเฟรชหน้านี้",
      groups,
      rooms: chats.filter((c) => c.type === "room"),
      all: chats,
    });
  }

  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405, headers: corsHeaders });
  }

  const rawBody = await req.text();
  const channelSecret = (Deno.env.get("LINE_CHANNEL_SECRET") ?? "").trim();
  if (channelSecret) {
    const signature = req.headers.get("x-line-signature") ?? "";
    const expected = await hmacSha256Base64(channelSecret, rawBody);
    if (!secureCompare(signature, expected)) {
      return jsonResponse(
        { ok: false, error: "invalid signature", hint_th: "ลายเซ็น LINE ไม่ตรง — ตรวจ LINE_CHANNEL_SECRET" },
        401,
      );
    }
  }

  let payload: { events?: unknown[] };
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return jsonResponse({ ok: false, error: "invalid json" }, 400);
  }

  const found = extractChats(Array.isArray(payload.events) ? payload.events : []);
  for (const c of found) {
    console.log(`LINE webhook chat: type=${c.type} id=${c.id} event=${c.eventType}`);
  }

  const client = adminClient();
  if (client && found.length > 0) {
    try {
      const prev = await loadSeen(client);
      const byId = new Map<string, SeenChat>();
      for (const c of prev) byId.set(c.id, c);
      for (const c of found) byId.set(c.id, c);
      await saveSeen(client, [...byId.values()]);
    } catch (e) {
      console.error("saveSeen failed", e);
    }
  }

  // LINE ต้องการ 200 ภายในเวลาอันสั้น
  return jsonResponse({
    ok: true,
    received: Array.isArray(payload.events) ? payload.events.length : 0,
    chats: found,
  });
});
