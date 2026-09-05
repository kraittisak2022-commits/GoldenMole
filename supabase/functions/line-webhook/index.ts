/**
 * LINE Messaging API webhook
 * - เก็บ groupId จากกลุ่ม
 * - แชทส่วนตัว: AI เรียก tool อ่าน DB เดียวกับเว็บแอป แล้วตอบ
 * - รายงานอัตโนมัติส่งเข้ากลุ่มอย่างเดียว (ดู notify-daily-*)
 *
 * Webhook URL: https://<PROJECT_REF>.supabase.co/functions/v1/line-webhook
 * Secrets: LINE_CHANNEL_SECRET, LINE_CHANNEL_ACCESS_TOKEN,
 *          LINE_ADVANCE_NOTIFY_USER_IDS (U… = คนที่ถามได้, C… = กลุ่มรายงาน),
 *          OPENROUTER_API_KEY (ถาม–ตอบ AI + ดึง DB), LINE_QA_AI_MODEL (optional)
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";
import { parseQaUserIds } from "../_shared/line_recipients.ts";
import {
  answerLineQaWithAi,
  clearChatHistory,
  qaHelpText,
} from "../_shared/line_qa_reports.ts";

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
      source?: {
        type?: string;
        groupId?: string;
        roomId?: string;
        userId?: string;
      };
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
    } else if (src.type === "user" && src.userId) {
      out.push({
        id: src.userId,
        type: "user",
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

async function loadSeen(
  client: ReturnType<typeof createClient>,
): Promise<SeenChat[]> {
  const { data, error } = await client
    .from("app_settings")
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  if (error || !data) return [];
  const defaults = (data.app_defaults ?? {}) as Record<string, unknown>;
  const raw = defaults[SETTINGS_FIELD];
  if (Array.isArray(raw)) return raw as SeenChat[];
  if (
    raw &&
    typeof raw === "object" &&
    Array.isArray((raw as { chats?: unknown }).chats)
  ) {
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

function truncateLineText(text: string, max = 4900): string {
  if (text.length <= max) return text;
  return text.slice(0, max - 1) + "…";
}

async function lineReply(
  replyToken: string,
  text: string,
  token: string,
): Promise<boolean> {
  const resp = await fetch("https://api.line.me/v2/bot/message/reply", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      replyToken,
      messages: [{ type: "text", text: truncateLineText(text) }],
    }),
  });
  if (!resp.ok) {
    const body = await resp.text();
    console.error("LINE reply failed", resp.status, body);
    return false;
  }
  return true;
}

async function linePush(
  userId: string,
  text: string,
  token: string,
): Promise<void> {
  const resp = await fetch("https://api.line.me/v2/bot/message/push", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      to: userId,
      messages: [{ type: "text", text: truncateLineText(text) }],
    }),
  });
  if (!resp.ok) {
    const body = await resp.text();
    console.error("LINE push failed", resp.status, body);
  }
}

type LineEvent = {
  type?: string;
  replyToken?: string;
  source?: { type?: string; userId?: string; groupId?: string; roomId?: string };
  message?: { type?: string; text?: string };
};

function isHelpOnly(text: string): boolean {
  const q = text.trim().toLowerCase();
  return (
    q === "ช่วย" ||
    q === "เมนู" ||
    q === "help" ||
    q === "คำสั่ง" ||
    q.includes("ช่วยเหลือ")
  );
}

function isResetChat(text: string): boolean {
  const q = text.trim().toLowerCase();
  return (
    q === "เริ่มใหม่" ||
    q === "ล้างแชท" ||
    q === "ล้างบทสนทนา" ||
    q === "reset" ||
    q === "new chat"
  );
}

function isGreetingOnly(text: string): boolean {
  const q = text.trim().toLowerCase().replace(/[!！.。]+$/g, "");
  return (
    q === "สวัสดี" ||
    q === "สวัสดีครับ" ||
    q === "สวัสดีค่ะ" ||
    q === "หวัดดี" ||
    q === "ดีครับ" ||
    q === "ดีค่ะ" ||
    q === "hello" ||
    q === "hi" ||
    q === "hey"
  );
}

async function handleUserQa(
  events: unknown[],
  client: ReturnType<typeof createClient>,
): Promise<number> {
  const accessToken = (Deno.env.get("LINE_CHANNEL_ACCESS_TOKEN") ?? "").trim();
  if (!accessToken) {
    console.warn("LINE_CHANNEL_ACCESS_TOKEN missing — skip QA replies");
    return 0;
  }

  const allowUsers = parseQaUserIds(
    Deno.env.get("LINE_ADVANCE_NOTIFY_USER_IDS") ?? "",
  );
  if (allowUsers.length === 0) {
    console.warn("No U… in LINE_ADVANCE_NOTIFY_USER_IDS — QA disabled");
    return 0;
  }
  const allow = new Set(allowUsers);

  let replied = 0;
  for (const raw of events) {
    if (!raw || typeof raw !== "object") continue;
    const ev = raw as LineEvent;
    if (ev.type !== "message") continue;
    if (ev.source?.type !== "user") continue;
    if (ev.message?.type !== "text") continue;
    const userId = (ev.source.userId ?? "").trim();
    const replyToken = (ev.replyToken ?? "").trim();
    const text = (ev.message.text ?? "").trim();
    if (!userId || !replyToken || !text) continue;

    const canonical = userId.match(/^U([a-f0-9]{32})$/i)
      ? `U${userId.slice(1).toLowerCase()}`
      : "";
    if (!canonical || !allow.has(canonical)) {
      const shown = canonical || userId;
      console.warn(`LINE QA denied userId=${shown}`);
      await lineReply(
        replyToken,
        [
          "บัญชีนี้ยังไม่มีสิทธิ์คุยกับที่ปรึกษา GoldenMole",
          "",
          `LINE User ID ของคุณ:`,
          shown,
          "",
          "ส่งรหัสนี้ให้แอดมิน นำไปใส่ใน LINE_ADVANCE_NOTIFY_USER_IDS (คั่นด้วย comma คู่กับกลุ่ม C…)",
          "แล้วลองทักใหม่ได้เลย",
        ].join("\n"),
        accessToken,
      );
      replied++;
      continue;
    }

    if (isResetChat(text)) {
      try {
        await clearChatHistory(client, canonical);
      } catch (e) {
        console.warn("clearChatHistory failed", e);
      }
      await lineReply(
        replyToken,
        "เริ่มใหม่แล้วครับ เล่าสถานการณ์หรือถามอะไรก็ได้เลย — ผมช่วยดูข้อมูลแล้วคุยเป็นที่ปรึกษาให้",
        accessToken,
      );
      replied++;
      continue;
    }

    if (isHelpOnly(text) || isGreetingOnly(text)) {
      // ทักทาย/เมนู ก็ให้ AI คุยต่อได้แบบกันเอง (มีประวัติ)
      const result = await answerLineQaWithAi(client, text, {
        userId: canonical,
      });
      // ถ้า AI พัง ใช่ข้อความต้อนรับแทน
      const out = result.usedAi ? result.text : qaHelpText();
      const ok = await lineReply(replyToken, out, accessToken);
      if (!ok) await linePush(userId, out, accessToken);
      replied++;
      continue;
    }

    const result = await answerLineQaWithAi(client, text, {
      userId: canonical,
    });
    const ok = await lineReply(replyToken, result.text, accessToken);
    if (!ok) await linePush(userId, result.text, accessToken);
    replied++;
  }
  return replied;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

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
    const users = chats.filter((c) => c.type === "user");
    return jsonResponse({
      ok: true,
      hint_th:
        users.length > 0
          ? "คัดลอก users[].id (U…) ไปใส่ LINE_ADVANCE_NOTIFY_USER_IDS เพื่อเปิดถาม–ตอบส่วนตัว และใส่ C… สำหรับรายงานกลุ่ม"
          : groups.length > 0
          ? "คัดลอก id ที่ขึ้นต้นด้วย C ไปใส่ LINE_ADVANCE_NOTIFY_USER_IDS (รายงานเข้ากลุ่ม) — ทัก OA ส่วนตัว 1 ครั้งเพื่อเก็บ U…"
          : "ยังไม่มี groupId/userId — เชิญบอทเข้ากลุ่ม หรือทัก OA ส่วนตัว 1 ครั้ง แล้วรีเฟรชหน้านี้",
      groups,
      users,
      rooms: chats.filter((c) => c.type === "room"),
      all: chats,
      qa: "แชทส่วนตัว — ที่ปรึกษา AI คุยสองทาง (พิมพ์ เริ่มใหม่ เพื่อล้างประวัติ)",
    });
  }

  if (req.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: corsHeaders,
    });
  }

  const rawBody = await req.text();
  const channelSecret = (Deno.env.get("LINE_CHANNEL_SECRET") ?? "").trim();
  if (channelSecret) {
    const signature = req.headers.get("x-line-signature") ?? "";
    const expected = await hmacSha256Base64(channelSecret, rawBody);
    if (!secureCompare(signature, expected)) {
      return jsonResponse(
        {
          ok: false,
          error: "invalid signature",
          hint_th: "ลายเซ็น LINE ไม่ตรง — ตรวจ LINE_CHANNEL_SECRET",
        },
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

  const events = Array.isArray(payload.events) ? payload.events : [];
  const found = extractChats(events);
  for (const c of found) {
    console.log(
      `LINE webhook chat: type=${c.type} id=${c.id} event=${c.eventType}`,
    );
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

  let qaReplies = 0;
  if (client) {
    try {
      qaReplies = await handleUserQa(events, client);
    } catch (e) {
      console.error("handleUserQa failed", e);
    }
  }

  return jsonResponse({
    ok: true,
    received: events.length,
    chats: found,
    qaReplies,
  });
});
