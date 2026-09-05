/**
 * OpenRouter chat completions (OpenAI-compatible) + optional tool calling.
 * Secrets: OPENROUTER_API_KEY
 * Optional: LINE_QA_AI_MODEL (default openai/gpt-5.6-luna-pro)
 */

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

export type OpenRouterMessage = {
  role: "system" | "user" | "assistant" | "tool";
  content: string | null;
  tool_call_id?: string;
  tool_calls?: OpenRouterToolCall[];
  name?: string;
};

export type OpenRouterToolCall = {
  id: string;
  type: "function";
  function: { name: string; arguments: string };
};

export type OpenRouterToolDef = {
  type: "function";
  function: {
    name: string;
    description: string;
    parameters: Record<string, unknown>;
  };
};

export function defaultLineQaModel(): string {
  return (Deno.env.get("LINE_QA_AI_MODEL") ?? "openai/gpt-5.6-luna-pro").trim() ||
    "openai/gpt-5.6-luna-pro";
}

type ChatResult = {
  text: string;
  model: string;
  toolCalls: OpenRouterToolCall[];
  assistantMessage: OpenRouterMessage | null;
};

async function openRouterRequest(opts: {
  apiKey: string;
  messages: OpenRouterMessage[];
  model?: string;
  temperature?: number;
  maxTokens?: number;
  timeoutMs?: number;
  tools?: OpenRouterToolDef[];
  toolChoice?: "auto" | "none" | "required";
}): Promise<ChatResult> {
  const model = (opts.model ?? defaultLineQaModel()).trim();
  const controller = new AbortController();
  const timeoutMs = opts.timeoutMs ?? 55_000;
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const body: Record<string, unknown> = {
      model,
      temperature: opts.temperature ?? 0.2,
      max_tokens: opts.maxTokens ?? 1200,
      messages: opts.messages,
    };
    if (opts.tools && opts.tools.length > 0) {
      body.tools = opts.tools;
      body.tool_choice = opts.toolChoice ?? "auto";
    }
    const resp = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${opts.apiKey}`,
        "HTTP-Referer": "https://goldenmole.app",
        "X-Title": "GoldenMole LINE QA",
      },
      signal: controller.signal,
      body: JSON.stringify(body),
    });
    const raw = await resp.text();
    if (!resp.ok) {
      throw new Error(`OpenRouter HTTP ${resp.status}: ${raw.slice(0, 280)}`);
    }
    let data: {
      choices?: Array<{
        message?: {
          content?: string | null;
          tool_calls?: OpenRouterToolCall[];
          role?: string;
        };
      }>;
      model?: string;
    };
    try {
      data = JSON.parse(raw);
    } catch {
      throw new Error("OpenRouter returned non-JSON");
    }
    const msg = data.choices?.[0]?.message;
    const toolCalls = Array.isArray(msg?.tool_calls) ? msg!.tool_calls! : [];
    const text = (msg?.content ?? "").trim();
    return {
      text,
      model: data.model || model,
      toolCalls,
      assistantMessage: msg
        ? {
          role: "assistant",
          content: msg.content ?? null,
          tool_calls: toolCalls.length > 0 ? toolCalls : undefined,
        }
        : null,
    };
  } finally {
    clearTimeout(timer);
  }
}

export async function openRouterChat(opts: {
  apiKey: string;
  messages: OpenRouterMessage[];
  model?: string;
  temperature?: number;
  maxTokens?: number;
  timeoutMs?: number;
}): Promise<{ text: string; model: string }> {
  const r = await openRouterRequest({ ...opts, toolChoice: "none" });
  if (!r.text) throw new Error("OpenRouter empty content");
  return { text: r.text, model: r.model };
}

export async function openRouterChatWithTools(opts: {
  apiKey: string;
  messages: OpenRouterMessage[];
  tools: OpenRouterToolDef[];
  runTool: (name: string, args: Record<string, unknown>) => Promise<string>;
  model?: string;
  temperature?: number;
  maxTokens?: number;
  timeoutMs?: number;
  maxRounds?: number;
}): Promise<{ text: string; model: string; toolNames: string[] }> {
  const messages = [...opts.messages];
  const used: string[] = [];
  const maxRounds = opts.maxRounds ?? 3;
  let model = opts.model ?? defaultLineQaModel();
  const deadline = Date.now() + (opts.timeoutMs ?? 55_000);

  for (let round = 0; round < maxRounds; round++) {
    const remain = Math.max(8_000, deadline - Date.now());
    const r = await openRouterRequest({
      apiKey: opts.apiKey,
      messages,
      model: opts.model,
      temperature: opts.temperature,
      maxTokens: opts.maxTokens,
      timeoutMs: remain,
      tools: opts.tools,
      toolChoice: round === 0 ? "auto" : "auto",
    });
    model = r.model;

    if (r.toolCalls.length === 0) {
      if (!r.text) throw new Error("OpenRouter empty content");
      return { text: r.text, model, toolNames: used };
    }

    if (r.assistantMessage) messages.push(r.assistantMessage);

    for (const tc of r.toolCalls) {
      const name = tc.function?.name ?? "";
      let args: Record<string, unknown> = {};
      try {
        args = JSON.parse(tc.function?.arguments || "{}");
      } catch {
        args = {};
      }
      used.push(name);
      let result: string;
      try {
        result = await opts.runTool(name, args);
      } catch (e) {
        result = `ดึงข้อมูลไม่สำเร็จ: ${e instanceof Error ? e.message : String(e)}`;
      }
      // ตัดผลยาวเกิน เพื่อไม่ให้ context ระเบิด
      if (result.length > 6000) result = result.slice(0, 6000) + "\n…";
      messages.push({
        role: "tool",
        tool_call_id: tc.id,
        content: result,
      });
    }
  }

  // รอบสุดท้ายบังคับตอบข้อความ
  const remain = Math.max(8_000, deadline - Date.now());
  const final = await openRouterRequest({
    apiKey: opts.apiKey,
    messages: [
      ...messages,
      {
        role: "user",
        content: "สรุปคำตอบเป็นภาษาไทยจากข้อมูลเครื่องมือที่มีแล้ว ห้ามเรียกเครื่องมือเพิ่ม",
      },
    ],
    model: opts.model,
    temperature: opts.temperature,
    maxTokens: opts.maxTokens,
    timeoutMs: remain,
    toolChoice: "none",
  });
  if (!final.text) throw new Error("OpenRouter empty content after tools");
  return { text: final.text, model: final.model, toolNames: used };
}
