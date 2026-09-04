/**
 * LINE Messaging API — multicast text after advance (เบิกเงิน) saved.
 * Secrets: LINE_CHANNEL_ACCESS_TOKEN (Channel access token, long-lived from Messaging API tab)
 * Auth (verify_jwt = false ใน config.toml): อย่างใดอย่างหนึ่ง —
 *   - header `x-cm-notify-advance-secret` ตรงกับ NOTIFY_ADVANCE_INVOKER_SECRET บน Edge หรือ
 *   - JWT ที่ getUser() ยืนยันได้ (เช่น Anonymous / ผู้ใช้ Supabase Auth)
 *
 * หลังผ่าน auth แล้วตอบ status 200 + JSON เสมอ (ใช้ field `ok`) เพื่อให้ client อ่าน `data` ได้
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cm-notify-advance-secret",
};

/** LINE นับความยาวข้อความเป็น UTF-16 code units (ไม่ใช่จำนวน code point) */
const MAX_LINE_TEXT_UTF16 = 5000;

function stripBearerPrefix(t: string): string {
  const s = t.trim();
  if (/^Bearer\s+/i.test(s)) return s.replace(/^Bearer\s+/i, "").trim();
  return s;
}

function looksLikeChannelSecretNotAccessToken(t: string): boolean {
  const s = t.trim();
  return s.length === 32 && /^[a-f0-9]{32}$/i.test(s);
}

/** User U… / Group C… / Room R… */
function canonicalLineRecipientId(raw: string): string | null {
  const s = raw.trim();
  const m = s.match(/^([UCR])([a-f0-9]{32})$/i);
  if (!m) return null;
  return `${m[1].toUpperCase()}${m[2].toLowerCase()}`;
}

function isLineUserId(id: string): boolean {
  return id.startsWith("U");
}

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** ตัดให้ไม่เกิน UTF-16 code units ตามที่ LINE จำกัด */
function truncateForLineText(text: string): string {
  let out = "";
  let units = 0;
  for (const ch of text) {
    const cp = ch.codePointAt(0)!;
    const need = cp > 0xffff ? 2 : 1;
    if (units + need > MAX_LINE_TEXT_UTF16) break;
    out += ch;
    units += need;
  }
  return out;
}

function sanitizeText(s: string): string {
  return s
    .replace(/\u0000/g, "")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, "");
}

function lineApiErrorMessage(parsed: unknown): string {
  if (parsed && typeof parsed === "object" && "message" in parsed) {
    const m = (parsed as { message?: string }).message;
    if (typeof m === "string" && m.trim()) return m.trim();
  }
  if (typeof parsed === "string" && parsed.trim()) {
    return parsed.trim().slice(0, 400);
  }
  return "";
}

function normalizeToList(raw: unknown): string[] {
  if (Array.isArray(raw)) return raw.map((x) => String(x ?? ""));
  if (typeof raw === "string" && raw.trim()) return [raw];
  return [];
}

/** เปรียบเทียบ secret แบบคงที่เวลา (ความยาวเท่ากันเท่านั้น) */
function secureCompareStrings(a: string, b: string): boolean {
  const x = a.trim();
  const y = b.trim();
  if (!x || !y || x.length !== y.length) return false;
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x.charCodeAt(i) ^ y.charCodeAt(i);
  return d === 0;
}

/** 401 Response ถ้าไม่ผ่าน; null = ผ่าน */
async function assertCallerAuthorized(req: Request): Promise<Response | null> {
  const envSecret = (Deno.env.get("NOTIFY_ADVANCE_INVOKER_SECRET") ?? "").trim();
  const headerSecret = (req.headers.get("x-cm-notify-advance-secret") ?? "").trim();
  if (envSecret !== "" && headerSecret !== "" && secureCompareStrings(envSecret, headerSecret)) {
    return null;
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return jsonResponse(
      {
        error: "Missing authorization",
        hint_th:
          envSecret !== ""
            ? "ส่ง header x-cm-notify-advance-secret ให้ตรงกับ NOTIFY_ADVANCE_INVOKER_SECRET บน Edge และ Authorization: Bearer <anon key หรือ JWT>"
            : "ไม่มี Authorization — เปิด Anonymous sign-in (Authentication → Providers) หรือตั้ง NOTIFY_ADVANCE_INVOKER_SECRET บน Edge + ใน .env แล้วส่ง header x-cm-notify-advance-secret",
      },
      401,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonResponse(
      {
        error: "Server misconfigured",
        hint_th: "Edge ไม่มี SUPABASE_URL / SUPABASE_ANON_KEY",
      },
      500,
    );
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userErr } = await supabase.auth.getUser();
  if (userErr || !user) {
    return jsonResponse(
      {
        error: "Unauthorized",
        hint_th:
          envSecret !== ""
            ? "JWT ใช้ไม่ได้ — ตรวจ NOTIFY_ADVANCE_INVOKER_SECRET กับ header x-cm-notify-advance-secret หรือใช้ JWT ที่ยังไม่หมดอายุ"
            : "JWT ไม่ถูกต้องหรือหมดอายุ — เปิด Anonymous sign-in (Authentication → Providers → Anonymous)",
      },
      401,
    );
  }
  return null;
}

async function lineMulticast(
  chunk: string[],
  messages: { type: "text"; text: string }[],
  token: string,
): Promise<{ ok: boolean; status: number; body: unknown }> {
  const resp = await fetch("https://api.line.me/v2/bot/message/multicast", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ to: chunk, messages }),
  });
  const rawRespText = await resp.text();
  let parsed: unknown = rawRespText;
  try {
    parsed = JSON.parse(rawRespText);
  } catch { /* keep string */ }
  return { ok: resp.ok, status: resp.status, body: parsed };
}

async function linePush(
  userId: string,
  messages: { type: "text"; text: string }[],
  token: string,
): Promise<{ ok: boolean; status: number; body: unknown }> {
  const resp = await fetch("https://api.line.me/v2/bot/message/push", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ to: userId, messages }),
  });
  const rawRespText = await resp.text();
  let parsed: unknown = rawRespText;
  try {
    parsed = JSON.parse(rawRespText);
  } catch { /* keep string */ }
  return { ok: resp.ok, status: resp.status, body: parsed };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: corsHeaders,
    });
  }

  const authDenied = await assertCallerAuthorized(req);
  if (authDenied) return authDenied;

  let body: { text?: string; to?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({
      ok: false,
      code: "invalid_json",
      message: "Invalid JSON",
      hint_th: "รูปแบบคำขอไม่ใช่ JSON ที่ถูกต้อง",
    }, 200);
  }

  if (!body || typeof body !== "object") {
    return jsonResponse({
      ok: false,
      code: "invalid_body",
      message: "Request body must be a JSON object",
      hint_th:
        "ส่ง JSON เช่น { \"text\": \"...\", \"to\": [\"U...\"] } หรือ \"to\": \"U...\" สตริงเดียว",
    }, 200);
  }

  const rawToken = stripBearerPrefix(
    Deno.env.get("LINE_CHANNEL_ACCESS_TOKEN") ?? "",
  );
  if (!rawToken) {
    return jsonResponse({
      ok: false,
      code: "missing_token",
      message: "LINE_CHANNEL_ACCESS_TOKEN not configured",
      hint_th:
        "ตั้ง secret LINE_CHANNEL_ACCESS_TOKEN ใน Supabase (ค่า = Channel access token จากแท็บ Messaging API ไม่ใช่ Channel secret)",
    }, 200);
  }

  if (looksLikeChannelSecretNotAccessToken(rawToken)) {
    return jsonResponse({
      ok: false,
      code: "token_looks_like_channel_secret",
      message: "Token is 32 hex chars — likely Channel secret, not access token",
      hint_th:
        "ค่าที่ตั้งดูเหมือน Channel secret (32 ตัว hex) — ให้ใช้ Channel access token (long-lived) จาก Messaging API → Issue แล้ววางใน secret แทน",
    }, 200);
  }

  const rawList = normalizeToList(body.to);
  const to = [
    ...new Set(
      rawList
        .map((x) => canonicalLineRecipientId(x))
        .filter((x): x is string => !!x),
    ),
  ].slice(0, 500);

  if (to.length === 0) {
    return jsonResponse({
      ok: false,
      code: "no_valid_recipients",
      message: "No valid LINE recipient IDs",
      hint_th:
        "ผู้รับต้องเป็น User ID (U…), Group ID (C…) หรือ Room ID (R…) — ตัวอักษร + hex 32 ตัว คั่นด้วย comma หรือส่ง to เป็น array",
    }, 200);
  }

  const rawText = sanitizeText(String(body.text ?? "").trim());
  const text = truncateForLineText(rawText);
  if (!text) {
    return jsonResponse({
      ok: false,
      code: "empty_text",
      message: "Empty text",
    }, 200);
  }

  const messages = [{ type: "text" as const, text }];
  const users = to.filter(isLineUserId);
  const chats = to.filter((id) => !isLineUserId(id));
  const details: unknown[] = [];
  let usedPushFallback = false;
  let okRecipients = 0;

  // กลุ่ม/ห้อง — ใช้ push ทีละ chat (multicast ใช้กับ user อย่างเดียว)
  for (const chatId of chats) {
    const pr = await linePush(chatId, messages, rawToken);
    details.push({ mode: "push_group_or_room", to: chatId, status: pr.status, body: pr.body });
    if (pr.ok) {
      okRecipients++;
      continue;
    }
    const lineMsg = lineApiErrorMessage(pr.body);
    let hint_th =
      "ส่งเข้ากลุ่ม/ห้องไม่สำเร็จ — ตรวจว่าเชิญบอทเข้ากลุ่มแล้ว และเปิด Allow bot to join group chats";
    if (pr.status === 403) {
      hint_th =
        "LINE 403: บอทยังไม่อยู่ในกลุ่ม หรือถูกเตะออก — เชิญ OA เข้ากลุ่มอีกครั้ง";
    } else if (pr.status === 400) {
      hint_th =
        "LINE 400: Group ID อาจผิด หรือบอทไม่ได้อยู่ในกลุ่มนี้";
      if (lineMsg) hint_th += ` | LINE: ${lineMsg}`;
    }
    return jsonResponse({
      ok: false,
      code: "line_api_error",
      message: "LINE API request failed (group/room)",
      lineStatus: pr.status,
      lineMessage: lineMsg || undefined,
      detail: pr.body,
      hint_th,
      partialOk: okRecipients,
    }, 200);
  }

  const chunkSize = 150;
  for (let i = 0; i < users.length; i += chunkSize) {
    const chunk = users.slice(i, i + chunkSize);
    const mc = await lineMulticast(chunk, messages, rawToken);
    details.push({ mode: "multicast", status: mc.status, body: mc.body });

    if (mc.ok) {
      okRecipients += chunk.length;
      continue;
    }

    const lineMsg = lineApiErrorMessage(mc.body);
    const tryPush =
      mc.status === 400 || mc.status === 403 || mc.status === 429;

    if (tryPush && chunk.length > 0) {
      usedPushFallback = true;
      const pushResults: unknown[] = [];
      let okCount = 0;
      for (const uid of chunk) {
        const pr = await linePush(uid, messages, rawToken);
        pushResults.push({ uid, status: pr.status, body: pr.body });
        if (pr.ok) okCount++;
      }
      details.push({
        mode: "push_fallback",
        multicastStatus: mc.status,
        pushResults,
      });

      if (okCount > 0) {
        okRecipients += okCount;
        if (okCount < chunk.length) {
          details.push({
            partialWarning:
              `ส่งถึง ${okCount}/${chunk.length} คน — บาง User ID อาจยังไม่ได้เพิ่มเพื่อน OA`,
          });
        }
        continue;
      }

      let hint_th =
        "LINE ปฏิเสธทั้ง multicast และ push — ตรวจ token และว่าผู้รับเป็นเพื่อน OA";
      if (mc.status === 401) {
        hint_th =
          "LINE 401: token ไม่ถูกต้องหรือหมดอายุ — ใช้ Channel access token จาก Messaging API";
      } else if (mc.status === 403) {
        hint_th =
          "LINE 403: ผู้รับยังไม่เพิ่มเพื่อน OA หรือบล็อกบอท — ให้กดเพิ่มเพื่อนบัญชีทางการของช่องนี้";
      } else if (mc.status === 400) {
        hint_th =
          "LINE 400: ตรวจ User ID ว่าเป็นของบัญชีที่เพิ่มเพื่อน OA นี้แล้ว และลองข้อความสั้น ๆ";
        if (lineMsg) hint_th += ` | LINE: ${lineMsg}`;
      }

      return jsonResponse({
        ok: false,
        code: "line_api_error",
        message: "LINE API request failed",
        lineStatus: mc.status,
        lineMessage: lineMsg || undefined,
        detail: { multicast: mc.body, pushFallback: pushResults },
        hint_th,
        partialChunks: Math.floor(i / chunkSize),
        partialOk: okRecipients,
      }, 200);
    }

    let hint_th =
      "LINE ปฏิเสธคำขอ — ตรวจสอบ Channel access token และว่าผู้รับเป็นเพื่อน OA แล้ว";
    if (mc.status === 401) {
      hint_th =
        "LINE 401: token ไม่ถูกต้องหรือหมดอายุ — ใช้ Channel access token จาก Messaging API (ไม่ใช่ Channel secret) แล้ว deploy secret ใหม่";
    } else if (mc.status === 403) {
      hint_th =
        "LINE 403: บอทไม่มีสิทธิ์หรือผู้รับยังไม่เพิ่มเพื่อน OA / บล็อกบอท";
    } else if (mc.status === 400) {
      hint_th =
        "LINE 400: มักเกิดจากผู้รับยังไม่ได้เพิ่มเพื่อน OA หรือ User ID ไม่ตรงช่อง";
      if (lineMsg) hint_th += ` | LINE: ${lineMsg}`;
    }

    return jsonResponse({
      ok: false,
      code: "line_api_error",
      message: "LINE API request failed",
      lineStatus: mc.status,
      lineMessage: lineMsg || undefined,
      detail: mc.body,
      hint_th,
      partialChunks: details.length - 1,
      partialOk: okRecipients,
    }, 200);
  }

  return jsonResponse({
    ok: true,
    recipients: to.length,
    okRecipients,
    users: users.length,
    groupsOrRooms: chats.length,
    usedPushFallback,
    details,
  });
});
