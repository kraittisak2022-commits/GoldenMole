"""Bulk-import July xlsx ledger rows via Supabase PostgREST."""
from __future__ import annotations

import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / ".env"
ROWS_PATH = ROOT / "tmp-xlsx-rows.json"

MAP = {
    "ของใช้ทั่วไป": "cat-supplies",
    "ซ่อมบำรุงเครื่องจักร": "cat-repair",
    "น้ำมัน": "cat-fuel",
    "อื่นๆ": "cat-misc",
    "บ้านแม่เลียบ": "cat-ban-mae-liap",
    "โต๊ะสั่น": "cat-to-san",
}

CATS = [
    {"id": "cat-supplies", "name": "ของใช้ทั่วไป", "kind": "expense", "archived": False, "sort_order": 30},
    {"id": "cat-repair", "name": "ซ่อมบำรุงเครื่องจักร", "kind": "expense", "archived": False, "sort_order": 20},
    {"id": "cat-fuel", "name": "น้ำมัน", "kind": "expense", "archived": False, "sort_order": 10},
    {"id": "cat-misc", "name": "อื่นๆ", "kind": "expense", "archived": False, "sort_order": 60},
    {"id": "cat-ban-mae-liap", "name": "บ้านแม่เลียบ", "kind": "expense", "archived": False, "sort_order": 70},
    {"id": "cat-to-san", "name": "โต๊ะสั่น", "kind": "expense", "archived": False, "sort_order": 80},
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
        with urllib.request.urlopen(request) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, raw, resp.headers

    status, _, _ = req("POST", "/rest/v1/fa_categories", CATS, "resolution=merge-duplicates,return=minimal")
    print("cats", status)

    status, _, _ = req("DELETE", "/rest/v1/fa_ledger_entries?id=like.led-jul26-*", None, "return=minimal")
    print("delete", status)

    payload = []
    for i, row in enumerate(rows, start=1):
        desc = row["description"]
        if row.get("note"):
            desc = f"{desc} ({row['note']})"
        payload.append(
            {
                "id": f"led-jul26-{i:04d}",
                "date": row["date"],
                "description": desc,
                "category_id": MAP[row["sheet"]],
                "entry_type": "expense",
                "amount": row["amount"],
                "source": "manual",
                "created_by": "xlsx-import",
            }
        )

    for i in range(0, len(payload), 50):
        chunk = payload[i : i + 50]
        status, _, _ = req("POST", "/rest/v1/fa_ledger_entries", chunk, "return=minimal")
        print("insert", i, len(chunk), status)

    status, raw, headers = req(
        "GET",
        "/rest/v1/fa_ledger_entries?id=like.led-jul26-*&select=id",
        None,
        "count=exact",
    )
    count = headers.get("Content-Range", headers.get("content-range", "?"))
    print("verify_status", status, "content_range", count, "rows_in_body", len(json.loads(raw) if raw else []))


if __name__ == "__main__":
    main()
