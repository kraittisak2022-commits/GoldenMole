import { loadAlbumByToken, loadMedia, toSharedAlbum } from '../_lib/albums.js';
import { json, lastSegment, route } from '../_lib/http.js';

/** GET (public) → SharedAlbum for anyone holding the link. */
export const GET = route(async (request) => {
  const album = await loadAlbumByToken(lastSegment(request));
  return json(toSharedAlbum(album, await loadMedia(album.id)));
});
