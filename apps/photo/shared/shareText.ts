export function shareUrl(origin: string, token: string): string {
  return `${origin.replace(/\/+$/, '')}/a/${token}`;
}

/** What the Copy button puts on the clipboard: the report name, then the link. */
export function buildShareText(title: string, url: string): string {
  return `${title.trim()}\n${url}`;
}
