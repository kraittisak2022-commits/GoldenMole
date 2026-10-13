import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/admin_user.dart';
import 'package:mobile_flutter/services/photo_album_service.dart';
import 'package:mobile_flutter/utils/photo_album_format.dart';

void main() {
  test('PIN gate accepts only 8888', () {
    expect(photoAlbumPinMatches('8888'), isTrue);
    expect(photoAlbumPinMatches(' 8888 '), isTrue);
    expect(photoAlbumPinMatches('1234'), isFalse);
    expect(photoAlbumPinMatches(''), isFalse);
  });

  test('only SuperAdmin may edit or delete albums', () {
    AdminUser user(String role) =>
        AdminUser(id: 'u', username: 'u', password: '', displayName: 'U', role: role);
    expect(canManagePhotoAlbums(user('SuperAdmin')), isTrue);
    expect(canManagePhotoAlbums(user('Admin')), isFalse);
    expect(canManagePhotoAlbums(user('Assistant')), isFalse);
  });

  test('allowLinkUpload defaults to true and reads false', () {
    expect(PhotoAlbumSummary.fromJson({'id': 'a'}).allowLinkUpload, isTrue);
    expect(PhotoAlbumSummary.fromJson({'id': 'a', 'allowLinkUpload': false}).allowLinkUpload, isFalse);
  });

  test('album summary parses the Photos API shape', () {
    final album = PhotoAlbumSummary.fromJson({
      'id': 'a1',
      'title': 'เทปูนชั้น 2',
      'reportDate': '2026-10-06',
      'mediaCount': 3,
      'cover': {
        'thumb': 'https://lh3.googleusercontent.com/d/x=s640',
        'thumbFallback': 'https://drive.google.com/thumbnail?id=x&sz=w640',
        'large': 'https://lh3.googleusercontent.com/d/x=s2048',
        'download': 'https://drive.google.com/uc?export=download&id=x',
        'preview': null,
      },
      'allowLinkUpload': true,
      'shareUrl': 'https://photo.goldenmole.pro/a/tok',
      'driveFolderUrl': 'https://drive.google.com/drive/folders/f',
    });
    expect(album.title, 'เทปูนชั้น 2');
    expect(album.mediaCount, 3);
    expect(album.cover?.thumb, contains('=s640'));
    expect(album.cover?.preview, isNull);
    expect(album.shareText, 'เทปูนชั้น 2\nhttps://photo.goldenmole.pro/a/tok');
  });

  test('album detail parses media and album without cover', () {
    final detail = PhotoAlbumDetail.fromJson({
      'id': 'a1',
      'title': 'T',
      'reportDate': '2026-10-06',
      'mediaCount': 1,
      'cover': null,
      'shareUrl': '',
      'driveFolderUrl': '',
      'media': [
        {
          'id': 'm1',
          'kind': 'video',
          'mime': 'video/mp4',
          'name': 'v.mp4',
          'width': 0,
          'height': 0,
          'takenAt': null,
          'createdAt': '2026-10-06T00:00:00Z',
          'uploadedByName': 'Yame',
          'src': {'thumb': 't', 'thumbFallback': 'f', 'large': 'l', 'download': 'd', 'preview': 'p'},
        },
      ],
    });
    expect(detail.album.cover, isNull);
    expect(detail.media.single.isVideo, isTrue);
    expect(detail.media.single.src.preview, 'p');
    expect(detail.media.single.uploadedByName, 'Yame');
  });

  test('Drive Range header gives the next offset', () {
    expect(driveNextOffset('bytes=0-1048575'), 1048576);
    expect(driveNextOffset(null), 0);
    expect(driveNextOffset('garbage'), 0);
  });

  test('mime type from file extension', () {
    expect(photoMimeTypeForPath('/x/IMG_1.JPG'), 'image/jpeg');
    expect(photoMimeTypeForPath('/x/a.png'), 'image/png');
    expect(photoMimeTypeForPath('/x/a.heic'), 'image/heic');
    expect(photoMimeTypeForPath('/x/noext'), 'image/jpeg');
  });

  test('upload file name and Thai album date', () {
    expect(
      photoUploadFileName(DateTime(2026, 10, 6, 9, 5, 7), 0, 'jpg'),
      'IMG_20261006_090507_1.jpg',
    );
    expect(formatPhotoAlbumDate('2026-10-06'), '6 ต.ค. 2569');
    expect(formatPhotoAlbumDate('bad'), 'bad');
  });

  test('error codes map to Thai messages', () {
    expect(const PhotoAlbumException('forbidden').message, contains('สิทธิ์'));
    expect(const PhotoAlbumException('drive_not_connected').message, contains('Google Drive'));
    expect(const PhotoAlbumException('weird').message, contains('weird'));
  });
}
