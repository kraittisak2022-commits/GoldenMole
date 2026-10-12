export type AdminRole = 'SuperAdmin' | 'Admin' | 'Assistant';
export type MediaKind = 'image' | 'video';

export interface StaffUser {
  id: string;
  username: string;
  displayName: string;
  role: AdminRole;
}

export interface MediaSources {
  /** Grid size (longest side ~640px). */
  thumb: string;
  /** Tried when `thumb` fails. */
  thumbFallback: string;
  /** Viewer size for images; poster for videos. */
  large: string;
  download: string;
  /** Embeddable player, videos only. */
  preview: string | null;
}

export interface MediaItem {
  id: string;
  kind: MediaKind;
  mime: string;
  name: string;
  width: number;
  height: number;
  takenAt: string | null;
  createdAt: string;
  uploadedByName: string | null;
  src: MediaSources;
}

export interface AlbumSummary {
  id: string;
  title: string;
  /** YYYY-MM-DD */
  reportDate: string;
  mediaCount: number;
  cover: MediaSources | null;
  allowLinkUpload: boolean;
  shareUrl: string;
  driveFolderUrl: string;
  createdAt: string;
  updatedAt: string;
}

export interface AlbumDetail extends AlbumSummary {
  media: MediaItem[];
}

export interface SharedAlbum {
  title: string;
  reportDate: string;
  mediaCount: number;
  allowLinkUpload: boolean;
  shareUrl: string;
  driveFolderUrl: string;
  media: MediaItem[];
}

/** Exactly one of albumId (staff) or shareToken (link) is set. */
export interface UploadTarget {
  albumId?: string;
  shareToken?: string;
}

export interface UploadStartRequest extends UploadTarget {
  name: string;
  mimeType: string;
  size: number;
}

export interface UploadCompleteRequest extends UploadTarget {
  fileId: string;
  width: number;
  height: number;
  takenAt: string | null;
  uploaderName?: string | null;
}

export interface GoogleStatus {
  connected: boolean;
  email: string | null;
  connectedAt: string | null;
}

export type ApiErrorCode =
  | 'bad_request'
  | 'unauthorized'
  | 'forbidden'
  | 'not_found'
  | 'bad_credentials'
  | 'drive_not_connected'
  | 'drive_error'
  | 'upload_disabled'
  | 'bad_type'
  | 'too_large'
  | 'empty_file'
  | 'rate_limited'
  | 'wrong_folder'
  | 'not_configured'
  | 'server_error';
