import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../calc/baht_text.dart';
import '../logic/format.dart';
import '../logic/promptpay.dart';
import '../models/models.dart';
import 'bill_data.dart';

/// CSS px per mm at 96 dpi; the bill is laid out in the web's px so sizes match the printed web bill.
const pxPerMm = 96 / 25.4;
const verifyBaseUrl = 'https://order.goldenmole.pro/v/';

const _navy = Color(0xFF1E3A5F);
const _s900 = Color(0xFF0F172A);
const _s700 = Color(0xFF334155);
const _s600 = Color(0xFF475569);
const _s500 = Color(0xFF64748B);
const _s400 = Color(0xFF94A3B8);
const _s300 = Color(0xFFCBD5E1);
const _s200 = Color(0xFFE2E8F0);
const _s100 = Color(0xFFF1F5F9);
const _s50 = Color(0xFFF8FAFC);
const _emerald = Color(0xFF047857);
const _stampInk = Color(0xFF1D4ED8);
const _tab = [FontFeature.tabularFigures()];

enum BillSize { a4, a5 }

enum BillCopy { original, copy }

class _Layout {
  const _Layout({
    required this.width,
    required this.minHeight,
    required this.padding,
    required this.headerGap,
    required this.logo,
    required this.company,
    required this.companyEn,
    required this.companyEnSpacing,
    required this.title,
    required this.payQr,
    required this.infoWidth,
    required this.totalsWidth,
    required this.padRows,
    required this.signersTop,
    required this.signersGap,
    required this.stampSize,
    required this.stampTopPaid,
    required this.stampTopUnpaid,
    required this.signLine,
    required this.signLineTop,
    required this.footerTop,
  });
  final double width;
  final double minHeight;
  final EdgeInsets padding;
  final double headerGap;
  final double logo;
  final double company;
  final double companyEn;
  final double companyEnSpacing;
  final double title;
  final double payQr;
  final double infoWidth;
  final double totalsWidth;
  final int padRows;
  final double signersTop;
  final double signersGap;
  final double stampSize;
  final double stampTopPaid;
  final double stampTopUnpaid;
  final double signLine;
  final double signLineTop;
  final double footerTop;
}

/// a5 is laid out narrower than A4 (same 1:√2 ratio) so it stays legible when fitted onto half an A4 sheet.
const _layouts = {
  BillSize.a4: _Layout(
    width: 210 * pxPerMm,
    minHeight: 297 * pxPerMm,
    padding: EdgeInsets.fromLTRB(14 * pxPerMm, 13 * pxPerMm, 14 * pxPerMm, 11 * pxPerMm),
    headerGap: 24,
    logo: 76,
    company: 17,
    companyEn: 9.5,
    companyEnSpacing: 0.95,
    title: 22,
    payQr: 72,
    infoWidth: 248,
    totalsWidth: 256,
    padRows: 5,
    signersTop: 24,
    signersGap: 32,
    stampSize: 140,
    stampTopPaid: -96,
    stampTopUnpaid: -56,
    signLine: 208,
    signLineTop: 40,
    footerTop: 20,
  ),
  BillSize.a5: _Layout(
    width: 160 * pxPerMm,
    minHeight: 226.3 * pxPerMm,
    padding: EdgeInsets.fromLTRB(9 * pxPerMm, 9 * pxPerMm, 9 * pxPerMm, 7 * pxPerMm),
    headerGap: 16,
    logo: 62,
    company: 15,
    companyEn: 8.5,
    companyEnSpacing: 0.25,
    title: 19,
    payQr: 64,
    infoWidth: 208,
    totalsWidth: 224,
    padRows: 3,
    signersTop: 16,
    signersGap: 24,
    stampSize: 112,
    stampTopPaid: -80,
    stampTopUnpaid: -48,
    signLine: 176,
    signLineTop: 32,
    footerTop: 16,
  ),
};

const _signers = {
  DocKind.delivery: ('ผู้รับสินค้า', 'ผู้ส่งสินค้า'),
  DocKind.receipt: ('ผู้จ่ายเงิน', 'ผู้รับเงิน'),
  DocKind.statement: ('ผู้รับวางบิล', 'ผู้วางบิล'),
};

const _paymentChoices = ['cash', 'transfer', 'cod', 'credit'];

/// One printable bill sheet (ใบส่งของ / ใบเสร็จ / ใบวางบิล), drawn at its paper size in CSS px.
class BillDocument extends StatelessWidget {
  const BillDocument({
    super.key,
    required this.bill,
    required this.copy,
    required this.company,
    required this.payment,
    this.size = BillSize.a5,
    this.printedAt,
  });
  final BillData bill;
  final BillCopy copy;
  final CompanySettings company;
  final PaymentSettings payment;
  final BillSize size;

  /// Defaults to now; fixed in tests.
  final DateTime? printedAt;

  @override
  Widget build(BuildContext context) {
    final b = bill;
    final l = _layouts[size]!;
    final statement = b.kind == DocKind.statement;
    final showPromptPay = _payNow && payment.promptPayId.isNotEmpty;
    final ppPayload = showPromptPay ? promptPayPayload(payment.promptPayId, b.total) : null;
    final (customerSigner, companySigner) = _signers[b.kind]!;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(l),
        const SizedBox(height: 12),
        _info(l, statement),
        if (b.delivery != null)
          _strip(Wrap(
            spacing: 20,
            runSpacing: 2,
            children: [
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'จัดส่ง ', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: '${b.delivery!.zone.isNotEmpty ? 'ต.${b.delivery!.zone} ' : ''}${b.delivery!.address}'),
              ])),
              if (b.delivery!.truck.isNotEmpty) Text(b.delivery!.truck),
              if (b.delivery!.driver.isNotEmpty) Text('คนขับ: ${b.delivery!.driver}'),
            ],
          ))
        else if (!statement)
          _strip(const Text.rich(TextSpan(children: [
            TextSpan(text: 'รับสินค้า ', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: 'ลูกค้ามารับเองที่ท่าทราย'),
          ]))),
        const SizedBox(height: 12),
        _table(l, statement),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _paymentColumn(statement, ppPayload)),
            const SizedBox(width: 16),
            SizedBox(width: l.totalsWidth, child: _totals(statement)),
          ],
        ),
        const Expanded(child: SizedBox.shrink()),
        Padding(
          padding: EdgeInsets.only(top: l.signersTop),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Signature(title: customerSigner, line: l.signLine, lineTop: l.signLineTop, date: b.signDate),
              ),
              SizedBox(width: l.signersGap),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    _Signature(
                      title: companySigner,
                      org: 'ในนาม ${company.nameTh}',
                      line: l.signLine,
                      lineTop: l.signLineTop,
                      date: b.signDate,
                    ),
                    Positioned(
                      top: b.paid ? l.stampTopPaid : l.stampTopUnpaid,
                      child: IgnorePointer(
                        child: BillStamp(
                          size: l.stampSize,
                          paidDate: b.paid ? formatDateTh((b.paidAt ?? '').isNotEmpty ? b.paidAt : b.date) : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: EdgeInsets.only(top: l.footerTop),
          padding: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: _s300))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (b.verifyToken.isNotEmpty) ...[
                SizedBox.square(
                  dimension: 40,
                  child: QrImageView(
                    data: '$verifyBaseUrl${b.verifyToken}',
                    padding: EdgeInsets.zero,
                    size: 40,
                    semanticsLabel: 'QR ตรวจสอบเอกสาร',
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (b.verifyToken.isNotEmpty)
                      const Text('สแกนเพื่อตรวจสอบความถูกต้องของเอกสาร', style: TextStyle(fontSize: 10, color: _s600)),
                    Text('พิมพ์เมื่อ ${formatDateTime(printedAt ?? DateTime.now())}',
                        style: const TextStyle(fontSize: 10, color: _s600)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(border: Border.all(color: _s400), borderRadius: BorderRadius.circular(4)),
                child: const Text(
                  'เอกสารนี้ไม่ใช่ใบกำกับภาษี',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _s700),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return DefaultTextStyle(
      style: const TextStyle(fontSize: 12.5, height: 1.375, color: _s900, fontFamily: 'NotoSansThai'),
      child: Container(
        width: l.width,
        constraints: BoxConstraints(minHeight: l.minHeight),
        color: Colors.white,
        child: Stack(
          children: [
            Padding(
              padding: l.padding,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: l.minHeight - l.padding.vertical),
                child: IntrinsicHeight(child: body),
              ),
            ),
            if (b.cancelled)
              const Positioned.fill(
                child: _Overlay(
                  color: Color(0xFFDC2626),
                  opacity: 0.6,
                  border: 6,
                  title: 'ยกเลิก / VOID',
                  titleSize: 64,
                ),
              ),
            if (b.demo)
              const Positioned.fill(
                child: _Overlay(
                  color: Color(0xFF8B5CF6),
                  opacity: 0.45,
                  border: 5,
                  title: 'ตัวอย่าง',
                  titleSize: 40,
                  subtitle: 'ไม่ใช่เอกสารจริง · สาธิตการใช้งาน',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(_Layout l) {
    final original = copy == BillCopy.original;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Image.asset('assets/branding/pirasit-logo.png', height: l.logo),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          border: Border(left: BorderSide(color: _navy.withValues(alpha: 0.2), width: 2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              company.nameTh,
                              style: TextStyle(fontSize: l.company, fontWeight: FontWeight.w700, color: _navy, height: 1.25),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              company.nameEn.toUpperCase(),
                              style: TextStyle(
                                fontSize: l.companyEn,
                                fontWeight: FontWeight.w600,
                                color: _s500,
                                letterSpacing: l.companyEnSpacing,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(company.address, style: const TextStyle(fontSize: 10.5, color: _s700)),
                            Text.rich(
                              TextSpan(children: [
                                const TextSpan(text: 'เลขประจำตัวผู้เสียภาษี ', style: TextStyle(color: _s500)),
                                TextSpan(text: company.taxId),
                                const TextSpan(text: '  |  ', style: TextStyle(color: _s300)),
                                const TextSpan(text: 'โทร ', style: TextStyle(color: _s500)),
                                TextSpan(text: company.phone),
                              ]),
                              style: const TextStyle(fontSize: 10.5, color: _s700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: l.headerGap),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(6)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          bill.kind.th,
                          style: TextStyle(fontSize: l.title, fontWeight: FontWeight.w700, color: Colors.white, height: 1.1),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bill.kind.en,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.4,
                            color: Color(0xBFFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_showPayChannel) ...[
                    const SizedBox(height: 8),
                    _payChannel(l),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: original ? _navy : _s400),
                    ),
                    child: Text(
                      original ? 'ต้นฉบับ / ORIGINAL' : 'สำเนา / COPY',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: original ? _navy : _s500),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(height: 3, decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 2),
        Container(height: 1, color: _navy.withValues(alpha: 0.35)),
      ],
    );
  }

  bool get _showPayChannel =>
      !bill.paid && !bill.cancelled && (payment.qrPayload.isNotEmpty || payment.bankAccountNo.isNotEmpty);

  /// A credit delivery note is paid later through its statement, so it asks for no amount now.
  bool get _payNow =>
      !bill.paid &&
      !bill.cancelled &&
      bill.total > 0 &&
      (bill.kind == DocKind.statement || bill.paymentMethod != 'credit');

  /// Shop bank account and receiving QR, top right of an unpaid bill.
  Widget _payChannel(_Layout l) {
    const small = TextStyle(fontSize: 10, height: 1.3, color: _s700);
    const hint = TextStyle(fontSize: 10, height: 1.3, color: _s500);
    final qr = payment.qrPayload.isEmpty
        ? ''
        : billQrPayload(payment.qrPayload, ref: bill.docNo, amount: _payNow ? bill.total : null);
    final qrIsBill = qr.isNotEmpty && qr != payment.qrPayload.trim();
    final ref = qrIsBill ? qrReference(bill.docNo) : '';
    final qrAmount = qrIsBill && _payNow ? bill.total : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(border: Border.all(color: _s300), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (qr.isNotEmpty) ...[
            SizedBox.square(
              dimension: l.payQr,
              child: QrImageView(
                data: qr,
                padding: EdgeInsets.zero,
                size: l.payQr,
                semanticsLabel: 'QR รับเงิน',
              ),
            ),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('ช่องทางรับเงิน', style: TextStyle(fontSize: 10, height: 1.3, fontWeight: FontWeight.w600, color: _navy)),
              if (payment.bankName.isNotEmpty) Text(payment.bankName, style: small),
              if (payment.bankAccountNo.isNotEmpty)
                Text(
                  payment.bankAccountNo,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: _s900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              if (payment.bankAccountName.isNotEmpty) Text(payment.bankAccountName, style: small),
              if (qr.isNotEmpty) const Text('สแกน QR เพื่อชำระ', style: hint),
              if (qrAmount > 0)
                Text(
                  'ยอด ${formatMoney(qrAmount)} บาท',
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: _s900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              if (ref.isNotEmpty) Text('อ้างอิง $ref', style: hint),
            ],
          ),
        ],
      ),
    );
  }

  Widget _info(_Layout l, bool statement) {
    final b = bill;
    final c = b.customer;
    final contact = [
      if (c.phone.isNotEmpty) 'โทร ${formatPhone(c.phone)}',
      if (c.taxId.isNotEmpty) 'เลขผู้เสียภาษี ${c.taxId}',
    ].join(' · ');
    final pairs = <(String, String)>[
      ('เลขที่', b.docNo),
      ('วันที่', formatDateTh(b.date)),
      if (b.period != null) ('รอบบิล', '${formatDateShort(b.period!.from)} – ${formatDateShort(b.period!.to)}'),
      for (final r in b.refs) (r.label, r.value),
      if ((b.issuedBy ?? '').isNotEmpty) ('ผู้ออกเอกสาร', b.issuedBy!),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Box(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ลูกค้า / CUSTOMER', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _s500)),
                  Text(c.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if (c.address.isNotEmpty) Text(c.address, style: const TextStyle(color: _s700)),
                  if (contact.isNotEmpty) Text(contact, style: const TextStyle(color: _s700)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: l.infoWidth,
            child: _Box(
              child: Column(
                children: [
                  for (final (i, (label, value)) in pairs.indexed)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: const TextStyle(color: _s500)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            value,
                            textAlign: TextAlign.right,
                            style: TextStyle(fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400, fontFeatures: _tab),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _strip(Widget child) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: _s50, borderRadius: BorderRadius.circular(6)),
        child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 11.5), child: child),
      );

  Widget _table(_Layout l, bool statement) {
    final b = bill;
    Widget th(String t, {TextAlign align = TextAlign.left, double pad = 8}) => Padding(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 6),
          child: Text(t,
              textAlign: align,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
        );
    Widget td(String t, {TextAlign align = TextAlign.left}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(t, textAlign: align, style: const TextStyle(fontSize: 12, fontFeatures: _tab)),
        );

    final widths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(44),
      if (statement) ...{
        1: const FixedColumnWidth(96),
        2: const FlexColumnWidth(),
        3: const FixedColumnWidth(112),
      } else ...{
        1: const FlexColumnWidth(),
        2: const FixedColumnWidth(64),
        3: const FixedColumnWidth(56),
        4: const FixedColumnWidth(96),
        5: const FixedColumnWidth(112),
      },
    };
    final cols = statement ? 4 : 6;
    final padCount = math.max(0, l.padRows + (statement ? 1 : 0) - b.lines.length);

    return Table(
      columnWidths: widths,
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          decoration: const BoxDecoration(color: _navy),
          children: [
            th('ลำดับ', align: TextAlign.center, pad: 2),
            if (statement) th('วันที่'),
            th(statement ? 'เลขที่เอกสาร / รายละเอียด' : 'รายการ'),
            if (!statement) ...[
              th('จำนวน', align: TextAlign.right),
              th('หน่วย', align: TextAlign.center),
              th('ราคา/หน่วย', align: TextAlign.right),
            ],
            th('จำนวนเงิน', align: TextAlign.right),
          ],
        ),
        for (final (i, line) in b.lines.indexed)
          TableRow(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _s200))),
            children: [
              td('${i + 1}', align: TextAlign.center),
              if (statement) td(line.date != null ? formatDateTh(line.date) : ''),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.description, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    if (line.detail != null && line.detail!.isNotEmpty)
                      Text(line.detail!, style: const TextStyle(fontSize: 11, color: _s500)),
                  ],
                ),
              ),
              if (!statement) ...[
                td(line.quantity != null ? formatNumber(line.quantity) : '', align: TextAlign.right),
                td(line.unit ?? '', align: TextAlign.center),
                td(line.unitPrice != null ? formatMoney(line.unitPrice) : '', align: TextAlign.right),
              ],
              td(formatMoney(line.amount), align: TextAlign.right),
            ],
          ),
        for (var i = 0; i < padCount; i++)
          TableRow(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _s100))),
            children: [for (var c = 0; c < cols; c++) const SizedBox(height: 28)],
          ),
      ],
    );
  }

  Widget _paymentColumn(bool statement, String? ppPayload) {
    final b = bill;
    const small = TextStyle(fontSize: 11.5, color: _s700);
    final children = <Widget>[
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: _s100, borderRadius: BorderRadius.circular(6)),
        child: Text(
          '(${bahtText(b.total)})',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ),
    ];
    if (statement) {
      children.add(DefaultTextStyle.merge(
        style: small,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('การชำระเงิน', style: TextStyle(fontWeight: FontWeight.w600, color: _s900)),
            Text(b.paid
                ? 'ชำระแล้ว${(b.paymentMethod ?? '').isNotEmpty ? ' (${paymentMethodLabel(b.paymentMethod)})' : ''}'
                    '${(b.paidAt ?? '').isNotEmpty ? ' เมื่อ ${formatDateTh(b.paidAt)}' : ''}'
                : 'กรุณาชำระตามยอดข้างต้น${payment.bankText.isNotEmpty ? ' · ${payment.bankText}' : ''}'),
          ],
        ),
      ));
    } else {
      final Widget? status = b.paid
          ? Text('ชำระแล้ว${(b.paidAt ?? '').isNotEmpty ? ' ${formatDateTh(b.paidAt)}' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: _emerald))
          : b.paymentMethod == 'credit'
              ? const Text('เครดิต — รวมเคลียร์ในใบวางบิลรายเดือน', style: TextStyle(fontWeight: FontWeight.w700))
              : null;
      children.add(DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 11.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                b.kind == DocKind.receipt ? 'ได้รับเงินถูกต้องแล้ว โดย' : 'การชำระเงิน',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                for (final m in _paymentChoices)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(border: Border.all(color: _s500)),
                        child: b.paymentMethod == m ? const Icon(Icons.check, size: 12, color: _s900) : null,
                      ),
                      const SizedBox(width: 6),
                      Text(paymentMethodLabel(m)),
                    ],
                  ),
              ],
            ),
            if (status != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Text('สถานะ: ', style: TextStyle(color: _s600)),
                Flexible(child: status),
              ]),
            ],
            if (!b.paid && payment.bankText.isNotEmpty && b.paymentMethod != 'credit')
              Text(payment.bankText, style: const TextStyle(color: _s600)),
          ],
        ),
      ));
    }
    if (ppPayload != null) {
      children.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: _s300), borderRadius: BorderRadius.circular(6)),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 76,
              child: QrImageView(data: ppPayload, padding: EdgeInsets.zero, size: 76, semanticsLabel: 'QR พร้อมเพย์'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 11, color: _s700),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('สแกนจ่ายด้วยพร้อมเพย์', style: TextStyle(fontWeight: FontWeight.w600, color: _s900)),
                    Text('ยอด ${formatMoney(b.total)} บาท'),
                    Text('พร้อมเพย์ ${payment.promptPayId}'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ));
    }
    if ((b.note ?? '').isNotEmpty) children.add(Text('หมายเหตุ: ${b.note}', style: small));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in children.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 8), child: c),
      ],
    );
  }

  Widget _totals(bool statement) {
    final b = bill;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(color: _s600))),
            Text(value, style: const TextStyle(fontFeatures: _tab)),
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!statement) ...[
          row('รวมเงิน', formatMoney(b.gross)),
          if (b.discountAmount != 0) row(b.discountLabel ?? 'ส่วนลด', '-${formatMoney(b.discountAmount)}'),
        ] else
          row('จำนวน ${b.lines.length} รายการ', ''),
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            const Expanded(
              child: Text('ยอดสุทธิ', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
            ),
            Text(
              formatMoney(b.total),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, fontFeatures: _tab),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('ราคานี้ไม่มีภาษีมูลค่าเพิ่ม', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, color: _s500)),
        ),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: _s300), borderRadius: BorderRadius.circular(6)),
        child: child,
      );
}

class _Signature extends StatelessWidget {
  const _Signature({required this.title, required this.line, required this.lineTop, this.org, this.date});
  final String title;
  final String? org;
  final String? date;
  final double line;
  final double lineTop;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 11.5),
      textAlign: TextAlign.center,
      child: Column(
        children: [
          SizedBox(height: lineTop),
          SizedBox(width: line, child: CustomPaint(size: Size(line, 1), painter: _DottedLine())),
          const SizedBox(height: 4),
          const Text('( ........................................ )'),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (org != null) Text(org!, style: const TextStyle(fontSize: 10, color: _s500)),
          const SizedBox(height: 4),
          if (date == null)
            const Text('วันที่ ........ / ........ / ........', style: TextStyle(color: _s500))
          else
            Text.rich(TextSpan(
              text: 'วันที่ ',
              style: const TextStyle(color: _s500),
              children: [
                TextSpan(
                  text: formatDateTh(date),
                  style: const TextStyle(color: _s900, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            )),
        ],
      ),
    );
  }
}

class _DottedLine extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _s500
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 3) {
      canvas.drawLine(Offset(x, 0.5), Offset(math.min(x + 1, size.width), 0.5), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Company seal in stamp ink, with a "ชำระเงินแล้ว" box under it once paid.
class BillStamp extends StatelessWidget {
  const BillStamp({super.key, required this.size, this.paidDate});
  final double size;
  final String? paidDate;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.9,
      child: Transform.rotate(
        angle: -8 * math.pi / 180,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/branding/pirasit-stamp.png', width: size, semanticLabel: 'ตราประทับบริษัท'),
            if (paidDate != null)
              Transform.translate(
                offset: const Offset(0, -4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: _stampInk, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    children: [
                      const Text('ชำระเงินแล้ว',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _stampInk, height: 1.25)),
                      Text(paidDate!,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _stampInk, height: 1.25)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.color,
    required this.opacity,
    required this.border,
    required this.title,
    required this.titleSize,
    this.subtitle,
  });
  final Color color;
  final double opacity;
  final double border;
  final String title;
  final double titleSize;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: -28 * math.pi / 180,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: color, width: border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w800, color: color, height: 1.2)),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _halfW = 148.5 * pxPerMm;
const _halfH = 210 * pxPerMm;

/// Landscape A4 with the original on the left and the copy on the right (each A5), with a cut line.
class BillSpread extends StatelessWidget {
  const BillSpread({super.key, required this.left, this.right});
  final Widget left;
  final Widget? right;

  static const size = Size(_halfW * 2, _halfH);

  @override
  Widget build(BuildContext context) {
    Widget half(Widget child) => SizedBox(
          width: _halfW,
          height: _halfH,
          child: FittedBox(fit: BoxFit.contain, alignment: Alignment.topCenter, child: child),
        );
    return Container(
      width: size.width,
      height: size.height,
      color: Colors.white,
      child: Stack(
        children: [
          Row(children: [half(left), if (right != null) half(right!)]),
          Positioned(
            left: _halfW,
            top: 5 * pxPerMm,
            bottom: 5 * pxPerMm,
            child: CustomPaint(size: const Size(1, double.infinity), painter: _DashedVertical()),
          ),
        ],
      ),
    );
  }
}

class _DashedVertical extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _s300
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 6) {
      canvas.drawLine(Offset(0.5, y), Offset(0.5, math.min(y + 3, size.height)), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A4 portrait page holding one full-size bill (scaled down if a long statement overflows).
class BillA4Page extends StatelessWidget {
  const BillA4Page({super.key, required this.child});
  final Widget child;

  static const size = Size(210 * pxPerMm, 297 * pxPerMm);

  @override
  Widget build(BuildContext context) => Container(
        width: size.width,
        height: size.height,
        color: Colors.white,
        child: FittedBox(fit: BoxFit.contain, alignment: Alignment.topCenter, child: child),
      );
}
