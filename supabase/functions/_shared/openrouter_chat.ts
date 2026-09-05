/**
 * OpenRouter chat completions (OpenAI-compatible).
 * Secrets: OPENROUTER_API_KEY
 * Optional: LINE_QA_AI_MODEL (default openai/gpt-5.6-luna-pro)
 */

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

export type OpenRouterMessage = {
  role: "system" | "user" | "assistant";
  content: string;
};

export function defaultLineQaModel(): string {
  return (Deno.env.get("LINE_QA_AI_MODEL") ?? "openai/gpt-5.6-luna-pro").trim() ||
    "openai/gpt-5.6-luna-pro";
}

export async function openRouterChat(opts: {
  apiKey: string;
  messages: OpenRouterMessage[];
  model?: string;
  temperature?: number;
  maxTokens?: number;
  timeoutMs?: number;
}): Promise<{ text: string; model: string }> {
  const model = (opts.model ?? defaultLineQaModel()).trim();
  const controller = new AbortController();
  const timeoutMs = opts.timeoutMs ?? 55_000;
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const resp = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${opts.apiKey}`,
        "HTTP-Referer": "https://goldenmole.app",
        "X-Title": "GoldenMole LINE QA",
      },
      signal: controller.signal,
      body: JSON.stringify({
        model,
        temperature: opts.temperature ?? 0.2,
        max_tokens: opts.maxTokens ?? 1200,
        messages: opts.messages,
      }),
    });
    const raw = await resp.text();
    if (!resp.ok) {
      throw new Error(`OpenRouter HTTP ${resp.status}: ${raw.slice(0, 280)}`);
    }
    let data: {
      choices?: Array<{ message?: { content?: string | null } }>;
    };
    try {
      data = JSON.parse(raw);
    } catch {
      throw new Error("OpenRouter returned non-JSON");
    }
    const text = (data.choices?.[0]?.message?.content ?? "").trim();
    if (!text) throw new Error("OpenRouter empty content");
    return { text, model };
  } finally {
    clearTimeout(timer);
  }
}
