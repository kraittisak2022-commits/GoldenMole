import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../bill/bill_data.dart';
import '../bill/bill_document.dart';
import '../bill/bill_export.dart';
import '../data/catalog_scope.dart';
import '../data/db.dart';
import '../data/orders_repo.dart';
import '../data/statements_repo.dart';
import '../logic/format.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../tour/tour_controller.dart';
import '../tour/tour_steps.dart';
import '../widgets/ui.dart';
import 'new_order/new_order_screen.dart';
import 'order_detail_screen.dart';

enum BillCopies { both, original }

class BillScreen extends StatefulWidget {
  const BillScreen.order({super.key, required String this.orderId, this.created = false}) : statementId = null;
  const BillScreen.statement({super.key, required String this.statementId}) : orderId = null, created = false;

  final String? orderId;
  final String? statementId;

  /// Just saved from the wizard: show the "order saved" banner with "next order".
  final bool created;

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen> {
  final _sheetKey = GlobalKey();
  Order? _order;
  Statement? _statement;
  List<Order> _orders = const [];
  String? _error;
  bool _loading = true;
  DocKind? _kind;
  BillCopies _copies = BillCopies.both;
  String _busy = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/branding/pirasit-logo.png'), context);
    precacheImage(const AssetImage('assets/branding/pirasit-stamp.png'), context);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.orderId != null) {
        final o = await getOrder(widget.orderId!);
        if (mounted) setState(() => _order = o);
      } else {
        final s = await getStatement(widget.statementId!);
        final orders = s == null ? const <Order>[] : await getOrdersByIds(s.orderIds);
        if (mounted) {
          setState(() {
            _statement = s;
            _orders = orders;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DocKind get _effectiveKind {
    final o = _order;
    return _kind ??
        (o != null && o.paymentStatus == PaymentStatus.paid && (o.receiptNo ?? '').isNotEmpty
            ? DocKind.receipt
            : DocKind.delivery);
  }

  BillData? _bill(CatalogController catalog) {
    final o = _order;
    if (o != null) {
      return billFromOrder(o, _effectiveKind, zone: catalog.zoneById(o.zoneId), driver: catalog.driverById(o.driverId));
    }
    final s = _statement;
    return s == null ? null : billFromStatement(s, _orders);
  }

  Future<void> _export(String key, Future<void> Function(Uint8List png) action) async {
    setState(() => _busy = key);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final png = await captureBoundary(_sheetKey);
      await action(png);
    } catch (e) {
      if (mounted) showSnack(context, errorText(e, 'สร้างไฟล์บิลไม่สำเร็จ'), error: true);
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<Uint8List> _pdf(Uint8List png, String docNo) =>
      billPdf(png, landscape: _copies == BillCopies.both, title: docNo);

  void _print(BillData b) => _export('print', (png) async {
    final pdf = await _pdf(png, b.docNo);
    await Printing.layoutPdf(
      name: b.docNo,
      format: _copies == BillCopies.both ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      onLayout: (_) async => pdf,
    );
  });

  void _sharePdf(BillData b) => _export('pdf', (png) async {
    final pdf = await _pdf(png, b.docNo);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(pdf, mimeType: 'application/pdf', name: '${b.docNo}.pdf')],
        fileNameOverrides: ['${b.docNo}.pdf'],
        subject: '${b.kind.th} ${b.docNo}',
      ),
    );
  });

  void _shareImage(BillData b) => _export('png', (png) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png', name: '${b.docNo}.png')],
        fileNameOverrides: ['${b.docNo}.png'],
        subject: '${b.kind.th} ${b.docNo}',
      ),
    );
  });

  /// A just-created order bill replaced the wizard, so "back" means the order itself.
  void _back() {
    final id = widget.orderId;
    if (widget.created && id != null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => OrderDetailScreen(orderId: id)));
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogScope.of(context);
    final bill = _bill(catalog);
    final busy = _busy.isNotEmpty;
    final orderId = widget.orderId;
    return TourMarker(
      page: orderId != null ? TourPage.orderBill : TourPage.statementBill,
      id: orderId ?? widget.statementId,
      child: PopScope(
        canPop: !widget.created,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: _scaffold(catalog, bill, busy),
      ),
    );
  }

  Widget _scaffold(CatalogController catalog, BillData? bill, bool busy) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        leading: TourTarget('bill-back', child: BackButton(onPressed: _back)),
        title: bill == null
            ? const Text('บิล')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bill.docNo, style: const TextStyle(fontFeatures: tabular)),
                  Text(
                    '${bill.customer.name} · ${formatMoney(bill.total)} บาท',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.muted),
                  ),
                ],
              ),
        actions: bill == null
            ? null
            : [
                TourTarget(
                  'bill-print',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'บันทึกรูป / ส่ง LINE',
                        onPressed: busy ? null : () => _shareImage(bill),
                        icon: _busy == 'png' ? const _Spinner() : const Icon(Icons.image_outlined),
                      ),
                      IconButton(
                        tooltip: 'แชร์ PDF',
                        onPressed: busy ? null : () => _sharePdf(bill),
                        icon: _busy == 'pdf' ? const _Spinner() : const Icon(Icons.picture_as_pdf_outlined),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(44, 40)),
                        onPressed: busy ? null : () => _print(bill),
                        icon: _busy == 'print'
                            ? const _Spinner(light: true)
                            : const Icon(Icons.print_outlined, size: 18),
                        label: const Text('พิมพ์'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
      ),
      body: _body(catalog, bill),
    );
  }

  Widget _body(CatalogController catalog, BillData? bill) {
    if (_loading && bill == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Padding(padding: const EdgeInsets.all(16), child: ErrorBox(_error!, onRetry: _load));
    }
    if (bill == null) return const Padding(padding: EdgeInsets.all(16), child: ErrorBox('ไม่พบเอกสาร'));

    final o = _order;
    final settings = catalog.settings;
    Widget doc(BillCopy copy, BillSize size) =>
        BillDocument(bill: bill, copy: copy, company: settings.company, payment: settings.payment, size: size);
    final sheet = _copies == BillCopies.both
        ? BillSpread(left: doc(BillCopy.original, BillSize.a5), right: doc(BillCopy.copy, BillSize.a5))
        : BillA4Page(child: doc(BillCopy.original, BillSize.a4));
    final sheetSize = _copies == BillCopies.both ? BillSpread.size : BillA4Page.size;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TourTarget(
                  'bill-options',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (o != null && (o.receiptNo ?? '').isNotEmpty) ...[
                        Semantics(
                          label: 'ประเภทเอกสาร',
                          child: Segmented<DocKind>(
                            values: const [DocKind.delivery, DocKind.receipt],
                            selected: _effectiveKind,
                            labelOf: (k) => k == DocKind.delivery ? 'ใบส่งของ' : 'ใบเสร็จรับเงิน',
                            onChanged: (k) => setState(() => _kind = k),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Semantics(
                        label: 'จำนวนชุดที่พิมพ์',
                        child: Segmented<BillCopies>(
                          values: BillCopies.values,
                          selected: _copies,
                          labelOf: (c) => c == BillCopies.both ? 'ต้นฉบับ + สำเนา' : 'ต้นฉบับอย่างเดียว',
                          onChanged: (c) => setState(() => _copies = c),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.created) ...[
                  const SizedBox(height: 12),
                  _CreatedBanner(
                    onNext: () => Navigator.of(
                      context,
                    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => const NewOrderScreen())),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  _copies == BillCopies.both
                      ? 'กระดาษ A4 แนวนอน · ต้นฉบับซ้าย สำเนาขวา (ขนาด A5) ตัดตามเส้นประ'
                      : 'กระดาษ A4 แนวตั้ง · ต้นฉบับเต็มแผ่น',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        TourTarget(
          'bill-sheet',
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _copies == BillCopies.both ? 1123 : 794),
              child: AspectRatio(
                aspectRatio: sheetSize.width / sheetSize.height,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
                  ),
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: RepaintBoundary(key: _sheetKey, child: sheet),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'แตะสองนิ้วเพื่อซูม · พิมพ์ผ่าน AirPrint / เครื่องพิมพ์ Android หรือแชร์ PDF / รูปทาง LINE',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _CreatedBanner extends StatelessWidget {
  const _CreatedBanner({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(BadgeTone.success);
    return AppCard(
      color: c.bg,
      borderColor: c.border,
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: c.fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'บันทึกออเดอร์เรียบร้อย พิมพ์บิลหรือบันทึกรูปส่งให้ลูกค้าได้เลย',
              style: TextStyle(fontSize: 14, color: c.fg),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(backgroundColor: AppColors.surface, minimumSize: const Size(44, 40)),
            onPressed: onNext,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('ออเดอร์ถัดไป'),
          ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({this.light = false});
  final bool light;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2, color: light ? Colors.white : null),
  );
}
