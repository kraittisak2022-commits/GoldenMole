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

/// True for a Thai QR / EMVCo payment payload with a valid checksum.
bool isThaiQrPayload(String payload) {
  final p = payload.trim();
  if (!p.startsWith('000201') || p.length < 12 || p.substring(p.length - 8, p.length - 4) != '6304') return false;
  return crc16(p.substring(0, p.length - 4)) == p.substring(p.length - 4).toUpperCase();
}

typedef _Tlv = ({String id, String value});

List<_Tlv>? _parseTlv(String payload) {
  final out = <_Tlv>[];
  var i = 0;
  while (i < payload.length) {
    if (i + 4 > payload.length) return null;
    final id = payload.substring(i, i + 2);
    final len = int.tryParse(payload.substring(i + 2, i + 4));
    if (!RegExp(r'^\d{2}$').hasMatch(id) || len == null || i + 4 + len > payload.length) return null;
    out.add((id: id, value: payload.substring(i + 4, i + 4 + len)));
    i += 4 + len;
  }
  return out;
}

String _joinTlv(List<_Tlv> fields) => fields.map((f) => _field(f.id, f.value)).join();

/// Bank apps only accept A-Z and 0-9 in references; Thai QR allows at most 25 characters there.
String qrReference(String text) {
  final clean = text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return clean.length > 25 ? clean.substring(0, 25) : clean;
}

List<_Tlv> _setTlv(List<_Tlv> fields, String id, String value) =>
    [...fields.where((f) => f.id != id), (id: id, value: value)]..sort((a, b) => a.id.compareTo(b.id));

/// The shop's Thai QR made for one bill: reference 3 (additional data 62, terminal label 07) set to [ref],
/// and with an [amount] > 0 the amount to pay (54), marked one-time (01 = 12) so banks fill it in.
/// Returns [payload] unchanged when it is not a valid Thai QR or there is nothing to set.
String billQrPayload(String payload, {required String ref, num? amount}) {
  final p = payload.trim();
  if (!isThaiQrPayload(p)) return payload;
  var fields = _parseTlv(p.substring(0, p.length - 8));
  if (fields == null) return payload;
  var changed = false;

  final value = qrReference(ref);
  final extra = fields.where((f) => f.id == '62').firstOrNull;
  final sub = extra == null ? <_Tlv>[] : _parseTlv(extra.value);
  if (value.isNotEmpty && sub != null) {
    fields = _setTlv(fields, '62', _joinTlv(_setTlv(sub, '07', value)));
    changed = true;
  }

  if (amount != null && amount.isFinite && amount > 0) {
    fields = _setTlv(_setTlv(fields, '54', amount.toStringAsFixed(2)), '01', '12');
    changed = true;
  }

  if (!changed) return payload;
  final body = '${_joinTlv(fields)}6304';
  return body + crc16(body);
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
