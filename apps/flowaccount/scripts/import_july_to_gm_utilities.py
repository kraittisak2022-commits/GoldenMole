"""Import July xlsx rows into GoldenMole รายรับ-รายจ่าย (Utilities + expense_types)."""
from __future__ import annotations

import json
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / ".env"
ROWS_PATH = ROOT / "tmp-xlsx-rows.json"

SHEET_CATEGORIES = [
    "น้ำมัน",
    "ซ่อมบำรุงเครื่องจักร",
    "ของใช้ทั่วไป",
    "อื่นๆ",
    "บ้านแม่เลียบ",
    "โต๊ะสั่น",
]


def load_env(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def main() -> None:
    env = load_env(ENV_PATH)
    url = env["VITE_SUPABASE_URL"].rstrip("/")
    key = env["VITE_SUPABASE_ANON_KEY"]
    rows = json.loads(ROWS_PATH.read_text(encoding="utf-8"))["rows"]

    def req(method: str, path: str, body=None, prefer: str | None = None):
        data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers = {
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        }
        if prefer:
            headers["Prefer"] = prefer
        request = urllib.request.Request(url + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request) as resp:
                raw = resp.read().decode("utf-8")
                return resp.status, raw, resp.headers
        except urllib.error.HTTPError as e:
            err = e.read().decode("utf-8", errors="replace")
            raise SystemExit(f"HTTP {e.code} {path}: {err}") from e

    # Merge expense_types categories
    status, raw, _ = req("GET", "/rest/v1/app_settings?id=eq.default&select=expense_types,income_types")
    settings = json.loads(raw)
    if not settings:
        raise SystemExit("app_settings default row missing")
    existing = settings[0].get("expense_types") or []
    if not isinstance(existing, list):
        existing = []
    merged: list[str] = []
    seen: set[str] = set()
    for name in [*existing, *SHEET_CATEGORIES]:
        s = str(name).strip()
        if not s or s in seen:
            continue
        seen.add(s)
        merged.append(s)
    status, _, _ = req(
        "PATCH",
        "/rest/v1/app_settings?id=eq.default",
        {"expense_types": merged},
        "return=minimal",
    )
    print("expense_types", status, len(merged), merged)

    # Replace previous July import in transactions
    status, _, _ = req(
        "DELETE",
        "/rest/v1/transactions?id=like.jul26-utils-*",
        None,
        "return=minimal",
    )
    print("delete", status)

    payload = []
    for i, row in enumerate(rows, start=1):
        desc = str(row["description"]).strip()
        if row.get("note"):
            desc = f"{desc} ({row['note']})"
        sheet = str(row["sheet"]).strip()
        payload.append(
            {
                "id": f"jul26-utils-{i:04d}",
                "date": row["date"],
                "type": "Expense",
                "category": "Utilities",
                "sub_category": sheet,
                "description": desc,
                "amount": row["amount"],
                "note": "xlsx-import-july-2026",
            }
        )

    for i in range(0, len(payload), 40):
        chunk = payload[i : i + 40]
        status, _, _ = req("POST", "/rest/v1/transactions", chunk, "return=minimal")
        print("insert", i, len(chunk), status)

    status, raw, headers = req(
        "GET",
        "/rest/v1/transactions?id=like.jul26-utils-*&select=id,sub_category,amount",
        None,
        "count=exact",
    )
    print("verify", status, headers.get("Content-Range") or headers.get("content-range"))
    by_cat: dict[str, dict[str, float]] = {}
    for item in json.loads(raw):
        cat = item["sub_category"]
        bucket = by_cat.setdefault(cat, {"n": 0, "sum": 0.0})
        bucket["n"] += 1
        bucket["sum"] += float(item["amount"])
    for cat, stats in sorted(by_cat.items()):
        print(f"  {cat}: {int(stats['n'])} / {stats['sum']:.2f}")


if __name__ == "__main__":
    main()
