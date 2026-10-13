import { createAlbumAccess, pinMatches, requireAlbumViewer } from '../_lib/albumAccess.js';
import { loadAlbumByToken, loadMedia, toSharedAlbum } from '../_lib/albums.js';
import { assertNotLocked, clientIp, failureDelay, pinLimits, recordAttempt } from '../_lib/attempts.js';
import { HttpError, json, lastSegment, readJson, route } from '../_lib/http.js';

/** GET → SharedAlbum for signed-in staff or a device that entered the PIN (403 pin_required otherwise). */
export const GET = route(async (request) => {
  const album = await loadAlbumByToken(lastSegment(request));
  await requireAlbumViewer(request, album.id);
  return json(toSharedAlbum(album, await loadMedia(album.id)));
});

/**
 * POST { pin } → { access }: a 7-day token for this album, sent back in the x-album-access header.
 * 5 wrong PINs from one address or 30 for one album lock entry for 15 / 60 minutes; unknown links count too.
 */
export const POST = route(async (request) => {
  const ip = clientIp(request);
  await assertNotLocked(pinLimits(ip, null));

  let album;
  try {
    album = await loadAlbumByToken(lastSegment(request));
  } catch (err) {
    if (err instanceof HttpError && err.status === 404) await recordAttempt(pinLimits(ip, null), false);
    throw err;
  }

  const limits = pinLimits(ip, album.id);
  await assertNotLocked(limits);
  const body = await readJson(request);
  if (!pinMatches(body.pin)) {
    await recordAttempt(limits, false);
    await failureDelay();
    throw new HttpError('bad_pin', 400);
  }
  await recordAttempt(limits, true);
  return json({ access: createAlbumAccess(album.id) });
});
