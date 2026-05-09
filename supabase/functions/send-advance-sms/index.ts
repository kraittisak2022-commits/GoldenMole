/**
 * Proxies advance-notification SMS to SMSOK (https://developer.smsok.co — POST /s).
 * Secrets: SMSOK_API_USER, SMSOK_API_PASSWORD, SMSOK_SENDER_ID
 * Optional: SMSOK_CALLBACK_URL (full URL to smsok-dlr-webhook for DLR callbacks)
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function normalizeThaiPhone(raw: string): string | null {
  const d = String(raw ?? "").replace(/\D/g, "");
  if (!d) return null;
  if (d.length === 10 && d.startsWith("0")) return d;
  if (d.length === 11 && d.startsWith("66")) return `0${d.slice(2)}`;
  if (d.length === 12 && d.startsWith("666")) return `0${d.slice(3)}`;
  if (d.length >= 10) {
    const tail = d.slice(-10);
    return tail.startsWith("0") ? tail : null;
  }
  return null;
}

function basicAuthHeader(user: string, pass: string): string {
  const combined = new TextEncoder().encode(`${user}:${pass}`);
  let binary = "";
  for (let i = 0; i < combined.length; i++) {
    binary += String.fromCharCode(combined[i]!);
  }
  return `Basic ${btoa(binary)}`;
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

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Missing authorization" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userErr } = await supabase.auth.getUser();
  if (userErr || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let body: { text?: string; destinations?: string[] };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const smsUser = Deno.env.get("SMSOK_API_USER");
  const smsPass = Deno.env.get("SMSOK_API_PASSWORD");
  const sender = Deno.env.get("SMSOK_SENDER_ID");
  if (!smsUser || !smsPass || !sender) {
    return new Response(
      JSON.stringify({ error: "SMSOK credentials not configured (Edge secrets)" }),
      {
        status: 503,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const rawList = Array.isArray(body.destinations) ? body.destinations : [];
  const cleaned = [
    ...new Set(
      rawList
        .map((x) => normalizeThaiPhone(String(x)))
        .filter((p): p is string => !!p),
    ),
  ].slice(0, 25);
  if (cleaned.length === 0) {
    return new Response(JSON.stringify({ error: "No valid phone numbers" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const text = String(body.text ?? "").trim().slice(0, 500);
  if (!text) {
    return new Response(JSON.stringify({ error: "Empty text" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const callbackUrl = (Deno.env.get("SMSOK_CALLBACK_URL") ?? "").trim();
  const payload: Record<string, unknown> = {
    sender,
    text,
    destinations: cleaned.map((destination) => ({ destination })),
  };
  if (callbackUrl) {
    payload.callback_url = callbackUrl;
    payload.callback_method = "POST";
  }

  const resp = await fetch("https://api.smsok.co/s", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: basicAuthHeader(smsUser, smsPass),
    },
    body: JSON.stringify(payload),
  });

  const rawText = await resp.text();
  let detail: unknown = rawText;
  try {
    detail = JSON.parse(rawText);
  } catch { /* keep string */ }

  if (!resp.ok) {
    return new Response(
      JSON.stringify({
        error: "SMSOK request failed",
        status: resp.status,
        detail,
      }),
      {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  return new Response(JSON.stringify({ ok: true, smsok: detail }), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
