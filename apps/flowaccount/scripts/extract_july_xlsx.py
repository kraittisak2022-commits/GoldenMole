# -*- coding: utf-8 -*-
import zipfile
import xml.etree.ElementTree as ET
import json
import re
from pathlib import Path
from datetime import datetime, timedelta
from collections import Counter

path = Path(r"c:\Users\HP\Downloads\เดือนกรกฎาคม (จีน-ไทย).xlsx")
out = Path(
    r"c:\Users\HP\.gemini\antigravity\scratch\construction-management-app\apps\flowaccount\tmp-xlsx-rows.json"
)
NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"


def col_row(ref: str):
    m = re.match(r"([A-Z]+)(\d+)", ref)
    col = 0
    for ch in m.group(1):
        col = col * 26 + (ord(ch) - 64)
    return col - 1, int(m.group(2)) - 1


def excel_serial_to_date(n):
    try:
        n = float(n)
    except Exception:
        return None
    if n < 20000:
        return None
    dt = datetime(1899, 12, 30) + timedelta(days=int(n))
    if dt.year >= 2400:
        dt = dt.replace(year=dt.year - 543)
    return dt.strftime("%Y-%m-%d")


def to_num(v):
    if v is None or v == "":
        return None
    try:
        return float(str(v).replace(",", ""))
    except Exception:
        return None


with zipfile.ZipFile(path) as z:
    ss = []
    root = ET.fromstring(z.read("xl/sharedStrings.xml"))
    for si in root.findall(f"{NS}si"):
        texts = [t.text or "" for t in si.iter(f"{NS}t")]
        ss.append("".join(texts))

    wb = ET.fromstring(z.read("xl/workbook.xml"))
    sheets = [sh.attrib.get("name") for sh in wb.findall(f"{NS}sheets/{NS}sheet")]
    all_rows = []

    for i, name in enumerate(sheets, start=1):
        sroot = ET.fromstring(z.read(f"xl/worksheets/sheet{i}.xml"))
        rows = {}
        for c in sroot.findall(f".//{NS}c"):
            ref = c.attrib.get("r")
            if not ref:
                continue
            ci, ri = col_row(ref)
            t = c.attrib.get("t")
            v = c.find(f"{NS}v")
            is_el = c.find(f"{NS}is")
            val = None
            if t == "s" and v is not None and v.text is not None:
                val = ss[int(v.text)]
            elif t == "inlineStr" and is_el is not None:
                val = "".join(x.text or "" for x in is_el.iter(f"{NS}t"))
            elif v is not None:
                val = v.text
            rows.setdefault(ri, {})[ci] = val

        last_date = None
        for r in sorted(rows):
            cols = rows[r]
            date_raw = cols.get(0)
            desc = cols.get(1)
            if not desc or not str(desc).strip():
                continue
            dtxt = str(desc).strip()
            if dtxt in ("รายการ",) or "ว/ด/ป" in str(date_raw or ""):
                continue
            if dtxt.endswith("/其他") or dtxt.endswith("/燃油"):
                continue

            d = excel_serial_to_date(date_raw) if date_raw not in (None, "") else None
            if d:
                last_date = d
            elif last_date:
                d = last_date
            else:
                d = "2026-07-01"

            amount = to_num(cols.get(4))
            if amount is None:
                amount = to_num(cols.get(3))
            if amount is None:
                for ci in range(2, 8):
                    n = to_num(cols.get(ci))
                    if n is not None and n > 0:
                        amount = n
                        break
            if amount is None or amount <= 0:
                continue

            all_rows.append(
                {
                    "sheet": name,
                    "date": d,
                    "description": dtxt,
                    "amount": round(amount, 2),
                    "note": cols.get(5) or cols.get(6),
                }
            )

c = Counter(r["sheet"] for r in all_rows)
summary = {
    k: {
        "count": v,
        "sum": round(sum(r["amount"] for r in all_rows if r["sheet"] == k), 2),
    }
    for k, v in c.items()
}
payload = {"count": len(all_rows), "summary": summary, "rows": all_rows}
out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"count": len(all_rows), "summary": summary}, ensure_ascii=False))
