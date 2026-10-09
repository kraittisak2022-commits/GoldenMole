String _field(String id, String value) => '$id${value.length.toString().padLeft(2, '0')}$value';

/// CRC-16/CCITT-FALSE as required by EMVCo QR.
String crc16(String payload) {
  var crc = 0xffff;
  for (final unit in payload.codeUnits) {
    crc ^= unit << 8;
    for (var j = 0; j < 8; j++) {
      crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1;
      crc &= 0xffff;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}

/// Normalised PromptPay target, or null when the id is not a mobile number / tax id / e-wallet id.
({String tag, String value})? promptPayTarget(String id) {
  final digits = id.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10 && digits.startsWith('0')) return (tag: '01', value: '0066${digits.substring(1)}');
  if (digits.length == 13) return (tag: '02', value: digits);
  if (digits.length == 15) return (tag: '03', value: digits);
  return null;
}

/// EMVCo "Thai QR / PromptPay" payload. Dynamic (one-time amount) when amount > 0.
String? promptPayPayload(String id, [num? amount]) {
  final target = promptPayTarget(id);
  if (target == null) return null;
  final dynamicAmount = amount != null && amount > 0;
  final merchant = _field('00', 'A000000677010111') + _field(target.tag, target.value);
  var payload = _field('00', '01') +
      _field('01', dynamicAmount ? '12' : '11') +
      _field('29', merchant) +
      _field('53', '764') +
      (dynamicAmount ? _field('54', amount.toStringAsFixed(2)) : '') +
      _field('58', 'TH');
  payload += '6304';
  return payload + crc16(payload);
}
