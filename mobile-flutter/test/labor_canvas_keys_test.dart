import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/utils/labor_canvas_keys.dart';

void main() {
  test('maps web and legacy keys to Flutter canvas ids', () {
    expect(normalizeLaborCanvasKey('wash1'), 'wash_sand');
    expect(normalizeLaborCanvasKey('wash2'), 'wash_sand');
    expect(normalizeLaborCanvasKey('wash_old'), 'wash_sand');
    expect(normalizeLaborCanvasKey('wash_new'), 'wash_sand');
    expect(normalizeLaborCanvasKey('washSand'), 'wash_sand');
    expect(normalizeLaborCanvasKey('sand_watch'), 'sand_watch');
    expect(normalizeLaborCanvasKey('pierWatch'), 'sand_watch');
    expect(normalizeLaborCanvasKey('night_shift'), 'general');
    expect(normalizeLaborCanvasKey('night_patrol'), 'general');
    expect(normalizeLaborCanvasKey('dig_haul'), 'general');
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
