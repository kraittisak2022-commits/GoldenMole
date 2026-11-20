import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/utils/macro_vehicle_summary.dart';

void main() {
  group('resolveMacroVehicleRowStatus', () {
    test('returns saved when saved and complete', () {
      expect(
        resolveMacroVehicleRowStatus(
          isSaved: true,
          hasDriver: true,
          hasWorkTags: true,
        ),
        MacroVehicleRowStatus.saved,
      );
    });

    test('returns readyToSave when unsaved and complete', () {
      expect(
        resolveMacroVehicleRowStatus(
          isSaved: false,
          hasDriver: true,
          hasWorkTags: true,
        ),
        MacroVehicleRowStatus.readyToSave,
      );
    });

    test('returns missingDriver when work tags exist without a driver', () {
      expect(
        resolveMacroVehicleRowStatus(
          isSaved: false,
          hasDriver: false,
          hasWorkTags: true,
        ),
        MacroVehicleRowStatus.missingDriver,
      );
    });

    test('returns idle when no work tags are selected', () {
      expect(
        resolveMacroVehicleRowStatus(
          isSaved: false,
          hasDriver: true,
          hasWorkTags: false,
        ),
        MacroVehicleRowStatus.idle,
      );
      expect(
        resolveMacroVehicleRowStatus(
          isSaved: true,
          hasDriver: false,
          hasWorkTags: false,
        ),
        MacroVehicleRowStatus.idle,
      );
    });
  });

  group('matchesMacroFleetFilter', () {
    test('filters all, working, and idle cleanly', () {
      expect(
        matchesMacroFleetFilter(MacroVehicleRowStatus.idle, MacroFleetFilter.all),
        isTrue,
      );
      expect(
        matchesMacroFleetFilter(
          MacroVehicleRowStatus.saved,
          MacroFleetFilter.working,
        ),
        isTrue,
      );
      expect(
        matchesMacroFleetFilter(
          MacroVehicleRowStatus.readyToSave,
          MacroFleetFilter.working,
        ),
        isTrue,
      );
      expect(
        matchesMacroFleetFilter(
          MacroVehicleRowStatus.missingDriver,
          MacroFleetFilter.working,
        ),
        isTrue,
      );
      expect(
        matchesMacroFleetFilter(
          MacroVehicleRowStatus.idle,
          MacroFleetFilter.working,
        ),
        isFalse,
      );
      expect(
        matchesMacroFleetFilter(
          MacroVehicleRowStatus.idle,
          MacroFleetFilter.idle,
        ),
        isTrue,
      );
      expect(
        matchesMacroFleetFilter(
          MacroVehicleRowStatus.saved,
          MacroFleetFilter.idle,
        ),
        isFalse,
      );
    });
  });

  group('MacroFleetOverview & buildMacroSaveButtonLabel', () {
    test('computes active ratio safely for empty and populated fleets', () {
      const empty = MacroFleetOverview(
        totalCount: 0,
        activeCount: 0,
        savedCount: 0,
        idleCount: 0,
      );
      expect(empty.activeRatio, 0.0);

      const partial = MacroFleetOverview(
        totalCount: 4,
        activeCount: 3,
        savedCount: 2,
        idleCount: 1,
      );
      expect(partial.activeRatio, closeTo(0.75, 1e-6));
    });

    test('formats dynamic save button labels accurately', () {
      expect(
        buildMacroSaveButtonLabel(
          saving: true,
          completeCount: 3,
          clearedSavedCount: 0,
          compact: true,
        ),
        'กำลังบันทึก...',
      );
      expect(
        buildMacroSaveButtonLabel(
          saving: false,
          completeCount: 3,
          clearedSavedCount: 0,
          compact: true,
        ),
        'บันทึกการใช้รถ · 3 คัน',
      );
      expect(
        buildMacroSaveButtonLabel(
          saving: false,
          completeCount: 2,
          clearedSavedCount: 1,
          compact: false,
        ),
        'บันทึก 2 คัน · ลบที่ล้าง 1 คัน',
      );
      expect(
        buildMacroSaveButtonLabel(
          saving: false,
          completeCount: 0,
          clearedSavedCount: 2,
          compact: true,
        ),
        'ลบรายการที่ล้าง (2 คัน)',
      );
      expect(
        buildMacroSaveButtonLabel(
          saving: false,
          completeCount: 0,
          clearedSavedCount: 0,
          compact: false,
        ),
        'บันทึกการใช้รถแม็คโคร',
      );
    });
  });
}
