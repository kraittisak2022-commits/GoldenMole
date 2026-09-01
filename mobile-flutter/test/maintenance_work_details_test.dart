import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/utils/maintenance_work_details.dart';

void main() {
  group('MaintenancePhotoMeta', () {
    test('decode empty and invalid', () {
      expect(MaintenancePhotoMeta.decode(null).isEmpty, isTrue);
      expect(MaintenancePhotoMeta.decode('').isEmpty, isTrue);
      expect(MaintenancePhotoMeta.decode('plain text').isEmpty, isTrue);
    });

    test('encode and decode roundtrip', () {
      final meta = MaintenancePhotoMeta(
        localPaths: ['maintenance_photos/tx1/0.jpg'],
        remoteUrls: ['https://example.com/a.jpg'],
      );
      final json = MaintenancePhotoMeta.encodeIntoWorkDetails(meta: meta);
      final decoded = MaintenancePhotoMeta.decode(json);
      expect(decoded.localPaths, meta.localPaths);
      expect(decoded.remoteUrls, meta.remoteUrls);
      expect(decoded.count, 1);
    });

    test('encodeIntoWorkDetails merges with existing gm_advance', () {
      const existing =
          '{"gm_advance":{"payout_slot":"evening","payment_method":"cash"}}';
      final json = MaintenancePhotoMeta.encodeIntoWorkDetails(
        existingWorkDetails: existing,
        meta: MaintenancePhotoMeta(localPaths: ['maintenance_photos/x/0.jpg']),
      );
      final decoded = MaintenancePhotoMeta.decode(json);
      expect(decoded.localPaths, ['maintenance_photos/x/0.jpg']);
      expect(json.contains('gm_advance'), isTrue);
    });

    test('encode empty clears gm_maint_photos only', () {
      const existing =
          '{"gm_maint_photos":{"local":["a"],"remote":[],"schema_version":1},"gm_advance":{"payout_slot":"evening"}}';
      final json = MaintenancePhotoMeta.encodeIntoWorkDetails(
        existingWorkDetails: existing,
        meta: MaintenancePhotoMeta(),
      );
      expect(json.contains('gm_maint_photos'), isFalse);
      expect(json.contains('gm_advance'), isTrue);
    });
  });
}
