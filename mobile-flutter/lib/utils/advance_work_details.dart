import 'dart:convert';

/// เมทาดาต้าเบิกล่วงหน้า — เก็บใน JSON ที่ `gm_advance` ในคอลัมน์ `work_details` (ให้ซิงก์กับเว็บ)
class AdvanceGmMeta {
  AdvanceGmMeta({
    this.payoutSlot = midday,
    this.paymentMethod = cash,
    this.bank = '',
    this.accountNumber = '',
  });

  static const midday = 'midday';
  static const evening = 'evening';
  static const cash = 'cash';
  static const transfer = 'transfer';

  final String payoutSlot;
  final String paymentMethod;
  final String bank;
  final String accountNumber;

  static AdvanceGmMeta decode(String? workDetails) {
    var payout = midday;
    var pay = cash;
    var bank = '';
    var account = '';
    final raw = workDetails?.trim();
    if (raw != null &&
        raw.isNotEmpty &&
        raw.startsWith('{') &&
        raw.endsWith('}')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final adv = decoded['gm_advance'];
          if (adv is Map<String, dynamic>) {
            final ps = '${adv['payout_slot'] ?? ''}'.toLowerCase();
            payout = ps == AdvanceGmMeta.evening
                ? AdvanceGmMeta.evening
                : AdvanceGmMeta.midday;
            final pm = '${adv['payment_method'] ?? ''}'.toLowerCase();
            pay = pm == AdvanceGmMeta.transfer
                ? AdvanceGmMeta.transfer
                : AdvanceGmMeta.cash;
            bank = '${adv['bank'] ?? ''}'.trim();
            account = '${adv['account_number'] ?? ''}'.trim();
          }
        }
      } catch (_) {}
    }
    return AdvanceGmMeta(
      payoutSlot: payout,
      paymentMethod: pay,
      bank: bank,
      accountNumber: account,
    );
  }

  static String encodeIntoWorkDetails({
    String? existingWorkDetails,
    required AdvanceGmMeta meta,
  }) {
    Map<String, dynamic> root = {};
    final ex = existingWorkDetails?.trim();
    if (ex != null && ex.startsWith('{') && ex.endsWith('}')) {
      try {
        final d = jsonDecode(ex);
        if (d is Map<String, dynamic>) {
          root = Map<String, dynamic>.from(d);
        }
      } catch (_) {}
    }
    root['gm_advance'] = <String, dynamic>{
      'payout_slot': meta.payoutSlot,
      'payment_method': meta.paymentMethod,
      'bank': meta.bank.trim(),
      'account_number': meta.accountNumber.trim(),
      'schema_version': 1,
    };
    return jsonEncode(root);
  }
}
