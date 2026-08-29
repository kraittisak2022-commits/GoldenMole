/// คีย์ canvas บันทึกการทำงาน (สอดคล้อง `normalizeLaborCanvasKey` บนเว็บ)
const kGeneralWorkPrefix = 'general:';

/// กล่องงานที่แสดงบนแอปมือถือ
const flutterLaborCanvasCategoryIds = <String>{
  'wash_sand',
  'washHome',
  'sand_watch',
  'macro_driver',
  'general',
};

bool isGeneralLaborAssignmentKey(String key) =>
    key == 'general' ||
    key == 'generalWork' ||
    key.startsWith(kGeneralWorkPrefix);

bool isFlutterLaborCanvasCategoryKey(String key) =>
    flutterLaborCanvasCategoryIds.contains(key);

/// รวมคีย์งานที่บ้านจากรูปแบบเก่า → `washHome`
String normalizeLaborWashHomeKey(String key) {
  switch (key.trim()) {
    case 'wash_home':
    case 'wash_yard_house':
    case 'sift_home':
    case 'washHome':
      return 'washHome';
    default:
      return key;
  }
}

/// แปลงคีย์จาก DB/เว็บ/ข้อมูลเก่า → คีย์กล่อง canvas บนแอปมือถือ
String normalizeLaborCanvasKey(String key) {
  final trimmed = key.trim();
  if (trimmed.isEmpty) return 'general';
  if (trimmed.startsWith(kGeneralWorkPrefix)) return 'general';

  final homeCanon = normalizeLaborWashHomeKey(trimmed);
  if (homeCanon == 'washHome') return 'washHome';

  switch (trimmed) {
    case 'wash1':
    case 'wash_old':
    case 'wash2':
    case 'wash_new':
    case 'wash_sand':
    case 'washSand':
      return 'wash_sand';
    case 'pierWatch':
    case 'sand_watch':
      return 'sand_watch';
    case 'nightShift':
    case 'night_shift':
    case 'nightPatrol':
    case 'night_patrol':
    case 'digHaul':
    case 'dig_haul':
    case 'excavator_control':
      return 'general';
    case 'macroDriver':
    case 'macro_driver':
      return 'macro_driver';
    case 'generalWork':
    case 'general':
      return 'general';
    case 'wash_yard':
    case 'new_machine':
    case 'new_house':
    case 'filter_a':
    case 'filter_b':
    case 'house_team':
      return 'general';
    default:
      if (isFlutterLaborCanvasCategoryKey(trimmed)) return trimmed;
      return 'general';
  }
}
