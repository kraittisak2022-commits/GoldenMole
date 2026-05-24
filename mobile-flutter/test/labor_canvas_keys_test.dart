import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/utils/labor_canvas_keys.dart';

void main() {
  test('maps web and legacy keys to Flutter canvas ids', () {
    expect(normalizeLaborCanvasKey('wash1'), 'wash_old');
    expect(normalizeLaborCanvasKey('wash2'), 'wash_new');
    expect(normalizeLaborCanvasKey('sand_watch'), 'sand_watch');
    expect(normalizeLaborCanvasKey('pierWatch'), 'sand_watch');
    expect(normalizeLaborCanvasKey('night_shift'), 'night_shift');
    expect(normalizeLaborCanvasKey('night_patrol'), 'night_shift');
    expect(normalizeLaborCanvasKey('nightPatrol'), 'night_shift');
    expect(normalizeLaborCanvasKey('dig_haul'), 'dig_haul');
    expect(normalizeLaborCanvasKey('macroDriver'), 'macro_driver');
    expect(normalizeLaborCanvasKey('macro_driver'), 'macro_driver');
    expect(normalizeLaborCanvasKey('wash_home'), 'washHome');
  });

  test('keeps Flutter canvas keys out of general work', () {
    for (final id in flutterLaborCanvasCategoryIds) {
      expect(normalizeLaborCanvasKey(id), id);
      expect(isGeneralLaborAssignmentKey(normalizeLaborCanvasKey(id)), isFalse);
    }
  });

  test('general sub-job keys stay prefixed', () {
    expect(normalizeLaborCanvasKey('general:abc'), 'general:abc');
    expect(isGeneralLaborAssignmentKey('general:abc'), isTrue);
  });
}
