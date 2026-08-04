/// โหมดงานในแผง «บันทึกและนับจำนวน»
enum CountRecordWorkMode {
  trip,
  sand,
  both,
}

extension CountRecordWorkModeCodec on CountRecordWorkMode {
  String get storageValue => name;

  static CountRecordWorkMode? tryParse(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    for (final m in CountRecordWorkMode.values) {
      if (m.name == s) return m;
    }
    return null;
  }
}
