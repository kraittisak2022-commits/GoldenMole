#!/usr/bin/env node
/**
 * Merge androidLatestVersionCode / androidLatestVersionName into app_settings.app_defaults.
 * Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (never commit the service role key).
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const flutterRoot = join(__dirname, "..");

function fail(message) {
  console.error(`update-android-soft-version: ${message}`);
  process.exit(1);
}

function readPubspecVersion() {
  const pubspec = readFileSync(join(flutterRoot, "pubspec.yaml"), "utf8");
  const match = pubspec.match(/^version:\s*([\d.]+)\+(\d+)/m);
  if (!match) fail("Could not parse version from pubspec.yaml");
  return { versionName: match[1], versionCode: Number.parseInt(match[2], 10) };
}

function supabaseHeaders(serviceRoleKey) {
  return {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  };
}

async function main() {
  const supabaseUrl = (process.env.SUPABASE_URL ?? "").replace(/\/$/, "");
  const serviceRoleKey = (process.env.SUPABASE_SERVICE_ROLE_KEY ?? "").trim();
  if (!supabaseUrl) fail("Set SUPABASE_URL");
  if (!serviceRoleKey) fail("Set SUPABASE_SERVICE_ROLE_KEY");

  const fromEnvName = (process.env.ANDROID_VERSION_NAME ?? "").trim();
  const fromEnvCode = (process.env.ANDROID_VERSION_CODE ?? "").trim();
  const fromPubspec = readPubspecVersion();
  const versionName = fromEnvName || fromPubspec.versionName;
  const versionCodeRaw = fromEnvCode || String(fromPubspec.versionCode);
  const versionCode = Number.parseInt(versionCodeRaw, 10);
  if (!Number.isFinite(versionCode) || versionCode <= 0) {
    fail(`Invalid ANDROID_VERSION_CODE: ${versionCodeRaw}`);
  }

  const settingsUrl = `${supabaseUrl}/rest/v1/app_settings?id=eq.default&select=app_defaults`;
  const getRes = await fetch(settingsUrl, { headers: supabaseHeaders(serviceRoleKey) });
  if (!getRes.ok) {
    fail(`Fetch app_settings failed (${getRes.status}): ${await getRes.text()}`);
  }

  const rows = await getRes.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    fail("app_settings row id=default not found");
  }

  const currentDefaults =
    rows[0].app_defaults && typeof rows[0].app_defaults === "object"
      ? { ...rows[0].app_defaults }
      : {};

  const nextDefaults = {
    ...currentDefaults,
    androidLatestVersionCode: versionCode,
    androidLatestVersionName: versionName,
  };

  const patchUrl = `${supabaseUrl}/rest/v1/app_settings?id=eq.default`;
  const patchRes = await fetch(patchUrl, {
    method: "PATCH",
    headers: { ...supabaseHeaders(serviceRoleKey), Prefer: "return=minimal" },
    body: JSON.stringify({ app_defaults: nextDefaults }),
  });
  if (!patchRes.ok) {
    fail(`Update app_settings failed (${patchRes.status}): ${await patchRes.text()}`);
  }

  console.log(
    `Updated app_settings.app_defaults: androidLatestVersionName="${versionName}", androidLatestVersionCode=${versionCode}`,
  );
}

main().catch((err) => {
  fail(err instanceof Error ? err.message : String(err));
});
