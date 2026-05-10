-- รายรับ: สถานะรับเงิน (Unpaid = ยังไม่ได้จ่าย, Paid = จ่ายเงินแล้ว)
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS income_payment_status text;

COMMENT ON COLUMN public.transactions.income_payment_status IS 'Income: Unpaid | Paid';
