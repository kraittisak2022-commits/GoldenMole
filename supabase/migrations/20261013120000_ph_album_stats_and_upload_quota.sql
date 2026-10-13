-- Album count/cover in one locked statement (parallel uploads no longer overwrite each other's count,
-- and a cover deleted meanwhile is never written back), and a per-album quota row for link upload starts.

CREATE OR REPLACE FUNCTION ph_refresh_album_stats(p_album_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  PERFORM 1 FROM ph_albums WHERE id = p_album_id FOR UPDATE;
  UPDATE ph_albums a
  SET media_count = (SELECT count(*) FROM ph_media m WHERE m.album_id = p_album_id),
      cover_media_id = COALESCE(
        (SELECT m.id FROM ph_media m WHERE m.id = a.cover_media_id AND m.album_id = p_album_id),
        (SELECT m.id FROM ph_media m WHERE m.album_id = p_album_id ORDER BY m.created_at, m.id LIMIT 1)
      ),
      updated_at = now()
  WHERE a.id = p_album_id;
END;
$$;

REVOKE ALL ON FUNCTION ph_refresh_album_stats(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION ph_refresh_album_stats(UUID) TO service_role;

ALTER TABLE ph_auth_attempts DROP CONSTRAINT IF EXISTS ph_auth_attempts_scope_check;
ALTER TABLE ph_auth_attempts
  ADD CONSTRAINT ph_auth_attempts_scope_check
  CHECK (scope IN ('login_ip', 'login_user', 'pin_ip', 'pin_album', 'link_upload'));
