import { createAlbumAccess, pinMatches, requireAlbumViewer } from '../_lib/albumAccess.js';
import { loadAlbumByToken, loadMedia, toSharedAlbum } from '../_lib/albums.js';
import { attemptSucceeded, beginAttempt, clientIp, failureDelay, pinAlbumLimit, pinIpLimit } from '../_lib/attempts.js';
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
  const byIp = await beginAttempt([pinIpLimit(clientIp(request))]);
  const album = await loadAlbumByToken(lastSegment(request));
  const byAlbum = await beginAttempt([pinAlbumLimit(album.id)]);

  const body = await readJson(request);
  if (!pinMatches(body.pin)) {
    await failureDelay();
    throw new HttpError('bad_pin', 400);
  }
  await Promise.all([attemptSucceeded(byIp), attemptSucceeded(byAlbum)]);
  return json({ access: createAlbumAccess(album.id) });
});
