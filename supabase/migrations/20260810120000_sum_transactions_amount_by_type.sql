-- Aggregate income/expense totals without shipping every amount row (Disk IO).
CREATE OR REPLACE FUNCTION public.sum_transactions_amount_by_type(p_type text)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT COALESCE(SUM(amount), 0)
  FROM public.transactions
  WHERE type = p_type;
$$;

REVOKE ALL ON FUNCTION public.sum_transactions_amount_by_type(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sum_transactions_amount_by_type(text) TO anon, authenticated, service_role;
