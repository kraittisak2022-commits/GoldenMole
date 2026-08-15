# -*- coding: utf-8 -*-
import json
from pathlib import Path

rows = json.loads(
    Path("apps/flowaccount/tmp-xlsx-rows.json").read_text(encoding="utf-8")
)["rows"]

MAP = {
    "ของใช้ทั่วไป": ("cat-supplies", "ของใช้ทั่วไป", "expense", 30),
    "ซ่อมบำรุงเครื่องจักร": ("cat-repair", "ซ่อมบำรุงเครื่องจักร", "expense", 20),
    "น้ำมัน": ("cat-fuel", "น้ำมัน", "expense", 10),
    "อื่นๆ": ("cat-misc", "อื่นๆ", "expense", 60),
    "บ้านแม่เลียบ": ("cat-ban-mae-liap", "บ้านแม่เลียบ", "expense", 70),
    "โต๊ะสั่น": ("cat-to-san", "โต๊ะสั่น", "expense", 80),
}


def esc(s: str) -> str:
    return str(s).replace("'", "''")


cats = {meta[0]: meta for meta in MAP.values()}
lines: list[str] = []
lines.append("-- Import July 2026 ledger from xlsx")
lines.append(
    "INSERT INTO fa_categories (id, name, kind, archived, sort_order) VALUES"
)
cat_vals = [
    f"  ('{cid}', '{esc(name)}', '{kind}', false, {sort})"
    for cid, name, kind, sort in cats.values()
]
lines.append(",\n".join(cat_vals))
lines.append(
    "ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, kind = EXCLUDED.kind, "
    "sort_order = EXCLUDED.sort_order, archived = false;"
)
lines.append("")
lines.append("DELETE FROM fa_ledger_entries WHERE id LIKE 'led-jul26-%';")
lines.append("")
lines.append(
    "INSERT INTO fa_ledger_entries "
    "(id, date, description, category_id, entry_type, amount, source, created_by) VALUES"
)

vals = []
for i, r in enumerate(rows, start=1):
    meta = MAP.get(r["sheet"])
    if not meta:
        raise SystemExit(f"unknown sheet {r['sheet']!r}")
    cid = meta[0]
    desc = r["description"]
    if r.get("note"):
        desc = f"{desc} ({r['note']})"
    vals.append(
        f"  ('led-jul26-{i:04d}', '{r['date']}', '{esc(desc)}', '{cid}', "
        f"'expense', {r['amount']}, 'manual', 'xlsx-import')"
    )

lines.append(",\n".join(vals) + ";")
sql_path = Path("apps/flowaccount/sql/import-july-2026-ledger.sql")
sql_path.write_text("\n".join(lines), encoding="utf-8")
print(f"rows={len(rows)} sql={sql_path} bytes={sql_path.stat().st_size}")
