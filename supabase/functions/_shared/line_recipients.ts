/** Filter LINE recipient IDs from env CSV. */
export function canonicalLineRecipientId(raw: string): string | null {
  const s = raw.trim();
  const m = s.match(/^([UCR])([a-f0-9]{32})$/i);
  if (!m) return null;
  return `${m[1].toUpperCase()}${m[2].toLowerCase()}`;
}

export function parseAllRecipientIds(raw: string): string[] {
  return [
    ...new Set(
      raw
        .split(/[,;\s]+/)
        .map((x) => canonicalLineRecipientId(x))
        .filter((x): x is string => !!x),
    ),
  ];
}

/** รายงานเข้ากลุ่ม/ห้องเท่านั้น (C… / R…) */
export function parseGroupReportRecipientIds(raw: string): string[] {
  return parseAllRecipientIds(raw).filter((id) => !id.startsWith("U"));
}

/** ผู้ใช้ที่ถาม–ตอบในแชทส่วนตัวได้ (U…) */
export function parseQaUserIds(raw: string): string[] {
  return parseAllRecipientIds(raw).filter((id) => id.startsWith("U"));
}

const SETTINGS_IDS_FIELD = "lineAdvanceNotifyUserIds";

type SupabaseLike = {
  from: (table: string) => {
    select: (cols: string) => {
      eq: (
        col: string,
        val: string,
      ) => {
        maybeSingle: () => Promise<{
          data: { app_defaults?: Record<string, unknown> | null } | null;
          error: unknown;
        }>;
      };
    };
  };
};

/** รวม ID จาก array / CSV ใน app_defaults */
export function idsFromAppDefaults(defaults: Record<string, unknown> | null | undefined): string[] {
  if (!defaults) return [];
  const raw = defaults[SETTINGS_IDS_FIELD];
  if (Array.isArray(raw)) {
    return [
      ...new Set(
        raw
          .map((x) => canonicalLineRecipientId(String(x ?? "")))
          .filter((x): x is string => !!x),
      ),
    ];
  }
  if (typeof raw === "string") return parseAllRecipientIds(raw);
  return [];
}

/**
 * แหล่งผู้รับ LINE: ตั้งค่าเว็บ (app_defaults.lineAdvanceNotifyUserIds) ก่อน
 * ถ้ายังว่าง ใช้ Edge secret LINE_ADVANCE_NOTIFY_USER_IDS
 */
export async function resolveLineAdvanceNotifyIdsCsv(
  client: SupabaseLike | null,
): Promise<string> {
  if (client) {
    try {
      const { data, error } = await client
        .from("app_settings")
        .select("app_defaults")
        .eq("id", "default")
        .maybeSingle();
      if (!error && data) {
        const fromDb = idsFromAppDefaults(
          (data.app_defaults ?? {}) as Record<string, unknown>,
        );
        if (fromDb.length > 0) return fromDb.join(",");
      }
    } catch (e) {
      console.warn("resolveLineAdvanceNotifyIdsCsv app_settings failed", e);
    }
  }
  return Deno.env.get("LINE_ADVANCE_NOTIFY_USER_IDS") ?? "";
}
