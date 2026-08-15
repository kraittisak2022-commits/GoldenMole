-- Import July 2026 ledger from xlsx
INSERT INTO fa_categories (id, name, kind, archived, sort_order) VALUES
  ('cat-supplies', 'ของใช้ทั่วไป', 'expense', false, 30),
  ('cat-repair', 'ซ่อมบำรุงเครื่องจักร', 'expense', false, 20),
  ('cat-fuel', 'น้ำมัน', 'expense', false, 10),
  ('cat-misc', 'อื่นๆ', 'expense', false, 60),
  ('cat-ban-mae-liap', 'บ้านแม่เลียบ', 'expense', false, 70),
  ('cat-to-san', 'โต๊ะสั่น', 'expense', false, 80)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, kind = EXCLUDED.kind, sort_order = EXCLUDED.sort_order, archived = false;

DELETE FROM fa_ledger_entries WHERE id LIKE 'led-jul26-%';