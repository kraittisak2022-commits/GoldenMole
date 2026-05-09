/**
 * Receives SMSOK delivery / status callbacks (callback_url on POST https://api.smsok.co/s).
 * Set verify_jwt = false in supabase/config.toml (SMSOK servers do not send Supabase JWT).
 * Optional: SMSOK_WEBHOOK_SECRET — if set, require header x-smsok-webhook-secret to match.
 */
const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-smsok-webhook-secret",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST" && req.method !== "GET") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const secret = (Deno.env.get("SMSOK_WEBHOOK_SECRET") ?? "").trim();
  if (secret.length > 0) {
    const h =
      req.headers.get("x-smsok-webhook-secret") ??
      req.headers.get("X-Smsok-Webhook-Secret") ??
      "";
    if (h !== secret) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  let payload: unknown = null;
  try {
    if (req.method === "GET") {
      const u = new URL(req.url);
      const q: Record<string, string> = {};
      u.searchParams.forEach((v, k) => {
        q[k] = v;
      });
      payload = Object.keys(q).length > 0 ? q : { method: "GET", path: u.pathname };
    } else {
      const ct = req.headers.get("content-type") ?? "";
      if (ct.includes("application/json")) {
        payload = await req.json();
      } else {
        payload = await req.text();
      }
    }
  } catch {
    payload = null;
  }

  console.log("[smsok-dlr-webhook]", JSON.stringify(payload));

  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
