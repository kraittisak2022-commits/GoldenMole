import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_scope.dart';
import '../calc/pricing.dart';
import '../data/catalog_scope.dart';
import '../data/db.dart';
import '../data/orders_repo.dart';
import '../data/statements_repo.dart';
import '../logic/driver_pay.dart';
import '../logic/format.dart';
import '../logic/latlng.dart';
import '../logic/order_status.dart';
import '../models/models.dart';
import '../routes.dart';
import '../theme/app_theme.dart';
import '../tour/tour_controller.dart';
import '../tour/tour_steps.dart';
import '../widgets/delivery_map.dart';
import '../widgets/ui.dart';
import 'new_order/wizard_widgets.dart';
import 'order_edit_screen.dart';

const _deliverySteps = [DeliveryStatus.waiting, DeliveryStatus.dispatched, DeliveryStatus.delivered];

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Order? _order;
  Statement? _statement;
  String? _error;
  bool _loading = true;
  String _busy = '';
  String _actionError = '';

  String _driverId = '';
  double _wage = 0;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final o = await getOrder(widget.orderId);
      if (!mounted) return;
      if (o == null) {
        setState(() => _error = 'ไม่พบออเดอร์');
      } else {
        await _setOrder(o);
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Resets the driver/wage/note inputs when the saved values change, like the web's effect.
  Future<void> _setOrder(Order o) async {
    final prev = _order;
    final sync =
        prev == null ||
        prev.id != o.id ||
        prev.driverId != o.driverId ||
        prev.driverWage != o.driverWage ||
        prev.note != o.note;
    final statementChanged = prev?.statementId != o.statementId || prev?.total != o.total;
    setState(() {
      _order = o;
      if (sync) {
        _driverId = o.driverId ?? '';
        _wage = o.driverWage;
        _note.text = o.note;
      }
    });
    if (o.statementId == null) {
      if (_statement != null) setState(() => _statement = null);
    } else if (statementChanged || _statement == null) {
      try {
        final s = await getStatement(o.statementId!);
        if (mounted) setState(() => _statement = s);
      } catch (_) {}
    }
  }

  Future<void> _run(String key, Future<Order> Function() fn) async {
    setState(() {
      _busy = key;
      _actionError = '';
    });
    try {
      await _setOrder(await fn());
    } catch (e) {
      if (mounted) setState(() => _actionError = errorText(e, 'ทำรายการไม่สำเร็จ'));
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  String get _by => AuthScope.read(context).by;

  Future<void> _undoPay(Order o) async {
    final ok = await confirmDialog(
      context,
      title: 'ยกเลิกสถานะ "จ่ายแล้ว" ของออเดอร์นี้?',
      confirmLabel: 'ยกเลิกการรับเงิน',
    );
    if (ok) await _run('unpay', () => markOrderUnpaid(o.id, _by));
  }

  Future<void> _remove(Order o) async {
    final inStatement = _statement != null ? ' และเอาออกจากใบวางบิล ${_statement!.statementNo}' : '';
    final ok = await confirmDialog(
      context,
      title: 'ลบออเดอร์ ${o.orderNo} ถาวร?',
      message: 'ลบถาวร$inStatement กู้คืนไม่ได้',
      confirmLabel: 'ลบออเดอร์',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = 'delete';
      _actionError = '';
    });
    try {
      await deleteOrder(o.id);
      if (!mounted) return;
      showSnack(context, 'ลบออเดอร์ ${o.orderNo} แล้ว');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _actionError = errorText(e, 'ลบไม่สำเร็จ');
          _busy = '';
        });
      }
    }
  }

  Future<void> _toggleCancel(Order o) async {
    final ok = await confirmDialog(
      context,
      title: o.cancelled ? 'กู้คืนออเดอร์นี้?' : 'ยกเลิกออเดอร์นี้?',
      message: o.cancelled ? null : 'บิลจะแสดงว่ายกเลิก',
      confirmLabel: o.cancelled ? 'กู้คืนออเดอร์' : 'ยกเลิกออเดอร์',
      destructive: !o.cancelled,
    );
    if (ok) await _run('cancel', () => updateOrderFields(o.id, _by, o, cancelled: !o.cancelled));
  }

  void _pickDriver(Order o, String id) {
    final catalog = CatalogScope.read(context);
    final perTrip = driverTripRate(catalog.zoneById(o.zoneId), o.truckSize, o.roadDistanceKm, catalog.settings.delivery).perTrip;
    setState(() {
      _driverId = id;
      if (id.isNotEmpty && perTrip > 0) _wage = perTrip * o.trips;
    });
  }

  Future<void> _saveDriver(Order o) {
    final next = _driverId.isEmpty ? null : _driverId;
    final driverChanged = next != o.driverId;
    final wageChanged = _wage != o.driverWage;
    return _run(
      'driver',
      () => driverChanged
          ? updateOrderFields(o.id, _by, o, driverId: next, driverWage: wageChanged ? _wage : null)
          : updateOrderFields(o.id, _by, o, driverWage: wageChanged ? _wage : null),
    );
  }

  Future<void> _edit(Order o) async {
    final next = await Navigator.of(context).push<Order>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OrderEditScreen(order: o, by: _by),
      ),
    );
    if (next != null && mounted) {
      await _setOrder(next);
      if (mounted) showSnack(context, 'บันทึกการแก้ไขแล้ว');
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final auth = AuthScope.of(context);
    final canEdit = o != null && (auth.isSuperAdmin || o.demo);
    return TourMarker(
      page: TourPage.order,
      id: o?.id ?? widget.orderId,
      order: o == null ? null : TourOrder.of(o),
      child: Scaffold(
        appBar: AppBar(
          title: Text(o?.orderNo ?? 'ออเดอร์', style: const TextStyle(fontFeatures: tabular)),
          actions: [
            if (canEdit)
              TourTarget(
                'edit-order',
                child: IconButton(
                  tooltip: 'แก้ไขออเดอร์',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _busy.isEmpty ? () => _edit(o) : null,
                ),
              ),
            if (o != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TourTarget(
                  'bill-link',
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () => openOrderBill(context, o.id),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('ดู / พิมพ์บิล'),
                  ),
                ),
              ),
          ],
        ),
        body: _body(context, o),
      ),
    );
  }

  Widget _body(BuildContext context, Order? o) {
    if (_loading && o == null) return const Padding(padding: EdgeInsets.all(16), child: LoadingList(rows: 4));
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorBox(_error!, onRetry: _load),
      );
    }
    if (o == null) return const Center(child: EmptyState('ไม่พบออเดอร์'));

    final catalog = CatalogScope.of(context);
    final auth = AuthScope.of(context);
    final st = _statement;
    final inOpen = st != null && !st.isCleared;
    final inCleared = st != null && st.isCleared;
    final busy = _busy.isNotEmpty;

    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(16.0, (width - 768) / 2);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(side, 12, side, 32),
        children: [
          _Header(order: o),
          const SizedBox(height: 12),
          if (o.cancelled) ...[
            const _Banner(icon: Icons.block, text: 'ออเดอร์นี้ถูกยกเลิกแล้ว'),
            const SizedBox(height: 12),
          ],
          if (_actionError.isNotEmpty) ...[ErrorBox(_actionError), const SizedBox(height: 12)],
          _statusCard(o, st, inOpen, inCleared, busy),
          const SizedBox(height: 12),
          _customerCard(o),
          const SizedBox(height: 12),
          _itemsCard(o),
          const SizedBox(height: 12),
          if (o.fulfillment == Fulfillment.delivery)
            _deliveryCard(o, catalog, busy)
          else
            const AppCard(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined, size: 18, color: AppColors.primary),
                  SizedBox(width: 10),
                  Text('ลูกค้ามารับเองที่ท่าทราย', style: TextStyle(color: AppColors.muted)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _noteCard(o, busy),
          const SizedBox(height: 12),
          _historyCard(o, catalog),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (auth.isSuperAdmin || o.demo)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
                  onPressed: busy ? null : () => _remove(o),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('ลบออเดอร์'),
                ),
              if (!inOpen && !inCleared)
                TourTarget(
                  'cancel-order',
                  child: o.cancelled
                      ? OutlinedButton.icon(
                          onPressed: busy ? null : () => _toggleCancel(o),
                          icon: const Icon(Icons.restore, size: 18),
                          label: const Text('กู้คืนออเดอร์'),
                        )
                      : TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                          onPressed: busy ? null : () => _toggleCancel(o),
                          icon: const Icon(Icons.block, size: 18),
                          label: const Text('ยกเลิกออเดอร์'),
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusCard(Order o, Statement? st, bool inOpen, bool inCleared, bool busy) {
    final pay = paymentBadge(o);
    final del = deliveryBadge(o);
    final delivery = o.fulfillment == Fulfillment.delivery;
    return TourTarget(
      'status-card',
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('สถานะ'),
            _StatusRow(
              label: 'การชำระเงิน',
              badge: AppBadge(pay.label, tone: pay.tone),
              children: [
                _muted('${o.paymentMethod.label}${o.paidAt != null ? ' · รับเงิน ${formatDateTime(o.paidAt)}' : ''}'),
                if (o.driverCashReported != null && o.paymentStatus != PaymentStatus.paid && !o.cancelled)
                  Text(
                    'คนขับแจ้งเก็บเงินสด ${formatMoney(o.driverCashReported)} บาท'
                    '${o.driverCashReported! < o.total ? ' (ขาด ${formatMoney(o.total - o.driverCashReported!)} บาท)' : ''}'
                    '${o.driverReportedAt != null ? ' · ${formatDateTime(o.driverReportedAt)}' : ''}'
                    ' — รับเงินจากคนขับตอนเคลียร์ค่ารถ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: o.driverCashReported! < o.total ? AppColors.warning : AppColors.success,
                    ),
                  ),
                if (!o.cancelled && o.paymentStatus != PaymentStatus.paid)
                  if (inOpen)
                    _LinkText(
                      prefix: 'อยู่ในใบวางบิล ',
                      link: st!.statementNo,
                      suffix: ' — เคลียร์ผ่านใบวางบิล',
                      onTap: () => goTo(context, Dest.statements, {'open': st.id}),
                    )
                  else
                    TourTarget(
                      'pay-buttons',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                            onPressed: busy ? null : () => _run('pay-cash', () => markOrderPaid(o.id, 'cash', _by)),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('รับเงินสด'),
                          ),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => _run('pay-transfer', () => markOrderPaid(o.id, 'transfer', _by)),
                            child: const Text('รับโอนแล้ว'),
                          ),
                          if (o.paymentMethod == PaymentMethod.cod)
                            OutlinedButton(
                              onPressed: busy ? null : () => _run('pay-cod', () => markOrderPaid(o.id, 'cod', _by)),
                              child: const Text('เก็บปลายทางแล้ว'),
                            ),
                        ],
                      ),
                    ),
                if (o.paymentStatus == PaymentStatus.paid && !inCleared && !o.cancelled)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: AppColors.muted, padding: EdgeInsets.zero),
                      onPressed: busy ? null : () => _undoPay(o),
                      icon: const Icon(Icons.undo, size: 16),
                      label: const Text('ยกเลิกการรับเงิน', style: TextStyle(decoration: TextDecoration.underline)),
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            if (delivery)
              _StatusRow(
                label: 'การจัดส่ง',
                badge: AppBadge(del.label, tone: del.tone),
                children: [
                  if (o.deliveredAt != null) _muted('ส่งถึง ${formatDateTime(o.deliveredAt)}'),
                  if (!o.cancelled)
                    TourTarget(
                      'delivery-steps',
                      child: Semantics(
                        label: 'สถานะจัดส่ง',
                        child: Segmented<DeliveryStatus>(
                          values: _deliverySteps,
                          selected: o.deliveryStatus,
                          labelOf: (s) => s.label,
                          onChanged: (s) {
                            if (busy || s == o.deliveryStatus) return;
                            _run('del-${s.name}', () => setDeliveryStatus(o.id, s, _by));
                          },
                        ),
                      ),
                    ),
                ],
              )
            else
              const _StatusRow(label: 'การรับสินค้า', badge: AppBadge('มารับเอง')),
            const Divider(height: 24),
            _StatusRow(
              label: 'เคลียร์บิล',
              badge: o.cleared
                  ? const AppBadge('เคลียร์แล้ว', tone: BadgeTone.success)
                  : const AppBadge('ยังไม่เคลียร์', tone: BadgeTone.warning),
              children: [
                if (o.clearedAt != null) _muted('เคลียร์เมื่อ ${formatDateTime(o.clearedAt)}'),
                if (st != null)
                  _LinkText(prefix: 'ใบวางบิล ', link: st.statementNo, onTap: () => openStatementBill(context, st.id))
                else if (!o.cleared && o.paymentStatus == PaymentStatus.credit && !o.cancelled)
                  TourTarget(
                    'to-statement',
                    child: _LinkText(
                      link: 'รวมเข้าใบวางบิลรายเดือน',
                      onTap: () => goTo(context, Dest.statements, {'customer': o.customerId, 'source': o.source.name}),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerCard(Order o) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('ลูกค้า'),
          Text(o.customer.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          if (o.customer.phone.isNotEmpty)
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => _call(o.customer.phone),
              icon: const Icon(Icons.phone_outlined, size: 16),
              label: Text(formatPhone(o.customer.phone)),
            ),
          if (o.customer.address.isNotEmpty) _muted(o.customer.address),
          const SizedBox(height: 4),
          _LinkText(link: 'ดูประวัติลูกค้า', onTap: () => goTo(context, Dest.customers, {'open': o.customerId})),
        ],
      ),
    );
  }

  Widget _itemsCard(Order o) {
    final delivery = o.fulfillment == Fulfillment.delivery;
    final otherDiscount = o.discountAmount - o.deliveryDiscount;
    final hasItemDiscount = o.items.any((it) => it.discountPerUnit != 0);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: SectionTitle('รายการสินค้า')),
          const Divider(height: 1),
          for (final it in o.items) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                        _muted('${formatNumber(it.quantity)} ${it.unit} × ${formatNumber(it.unitPrice)}'),
                        if (it.discountPerUnit != 0)
                          Text(
                            'ลด${it.unit}ละ ${formatNumber(it.discountPerUnit)} บาท '
                            '(-${formatMoney(lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit))})',
                            style: const TextStyle(fontSize: 14, color: AppColors.success),
                          ),
                      ],
                    ),
                  ),
                  Text(formatMoney(it.amount), style: const TextStyle(fontFeatures: tabular)),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoRow('ค่าสินค้า', formatMoney(o.subtotal)),
                if (delivery)
                  InfoRow(
                    'ค่าจัดส่ง (${deliveryFeeFormula(feePerCubic: o.feePerCubic, cubic: totalCubic(o.items.map((it) => it.quantity)), feePerTrip: o.feePerTrip, trips: o.trips, remoteSurcharge: o.remoteSurcharge)})',
                    formatMoney(o.deliveryTotal),
                  ),
                if (o.deliveryDiscount != 0) InfoRow('ส่วนลดค่าส่ง', '-${formatMoney(o.deliveryDiscount)}'),
                if (otherDiscount > 0)
                  InfoRow(
                    hasItemDiscount
                        ? 'ส่วนลด (ต่อคิว + ท้ายบิล)'
                        : 'ส่วนลด${o.discountType == DiscountType.percent ? ' ${formatNumber(o.discountValue)}%' : ''}',
                    '-${formatMoney(otherDiscount)}',
                  ),
                const Divider(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Expanded(
                      child: Text('ยอดสุทธิ', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text(
                      formatMoney(o.total),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        fontFeatures: tabular,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deliveryCard(Order o, CatalogController catalog, bool busy) {
    final zone = catalog.zoneById(o.zoneId);
    final driver = catalog.driverById(o.driverId);
    final wagePaid = o.driverPayoutId != null;
    final locked = o.cancelled || wagePaid;
    final dirty = (_driverId.isEmpty ? null : _driverId) != o.driverId || _wage != o.driverWage;
    final message = driverMessage(o, zone, catalog.driverById(_driverId) ?? driver);
    final drivers = catalog.drivers.where((d) => d.active || d.id == o.driverId).toList();
    final hasPin = o.pinLat != null && o.pinLng != null;

    final infos = [
      _InfoTile('ตำบล', zone?.name ?? '—'),
      _InfoTile('รถ', o.truckSize != null ? '${o.truckSize} คิว × ${o.trips}' : '—'),
      _InfoTile('ห่างถนนใหญ่', o.roadDistanceKm != null ? '${formatNumber(o.roadDistanceKm)} กม.' : '—'),
      if (o.feePerCubic > 0)
        _InfoTile(
          'ค่าส่ง',
          '${formatNumber(o.feePerCubic)}/คิว${o.feePerTrip != 0 ? ' + ${formatNumber(o.feePerTrip)}/เที่ยว' : ''}',
        )
      else
        _InfoTile('ค่าส่ง/เที่ยว', formatNumber(o.feePerTrip)),
    ];

    final driverField = DropdownButtonFormField<String>(
      key: ValueKey('drv-${o.id}-${o.driverId}-$_driverId'),
      initialValue: _driverId,
      isExpanded: true,
      decoration: const InputDecoration(),
      items: [
        const DropdownMenuItem(value: '', child: Text('— ยังไม่ระบุ —')),
        for (final d in drivers)
          DropdownMenuItem(
            value: d.id,
            child: Text('${d.name} · ${d.truckSize} คิว · ${d.routeGroup.label}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: locked ? null : (v) => _pickDriver(o, v ?? ''),
    );
    final wageField = NumberField(
      value: _wage,
      decimal: false,
      enabled: !locked,
      semanticLabel: 'ค่าจ้างคนขับ (บาท)',
      onChanged: (v) => setState(() => _wage = math.max(0, v)),
    );

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.local_shipping_outlined, size: 16, color: AppColors.muted),
              SizedBox(width: 6),
              Expanded(child: SectionTitle('การจัดส่ง')),
            ],
          ),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 560 ? 4 : 2;
              final w = (c.maxWidth - 8 * (cols - 1)) / cols;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final t in infos) SizedBox(width: w, child: t)],
              );
            },
          ),
          if (o.deliveryAddress.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.place_outlined, size: 16, color: AppColors.muted),
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(o.deliveryAddress, style: const TextStyle(fontSize: 14))),
              ],
            ),
          ],
          if (hasPin) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(kRadius),
              child: DeliveryMap(value: LatLngValue(o.pinLat!, o.pinLng!), height: 220, readOnly: true),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () =>
                    launchUrl(Uri.parse(googleMapsUrl(o.pinLat!, o.pinLng!)), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('เปิดใน Google Maps'),
              ),
            ),
          ],
          const Divider(height: 28),
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= 560) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: FieldLabel('คนขับ', child: driverField)),
                    const SizedBox(width: 12),
                    SizedBox(width: 160, child: FieldLabel('ค่าจ้างคนขับ (บาท)', child: wageField)),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FieldLabel('คนขับ', child: driverField),
                  const SizedBox(height: 12),
                  FieldLabel('ค่าจ้างคนขับ (บาท)', child: wageField),
                ],
              );
            },
          ),
          if (o.driverId != null) ...[
            const SizedBox(height: 10),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (wagePaid) ...[
                  const AppBadge('จ่ายค่ารถแล้ว', tone: BadgeTone.success),
                  _muted('ลบรายการจ่ายในหน้าเคลียร์ค่ารถก่อน ถ้าต้องการแก้คนขับหรือค่าจ้าง'),
                ] else
                  const AppBadge('ค่ารถยังไม่จ่าย', tone: BadgeTone.warning),
                _LinkText(link: 'เคลียร์ค่ารถ', onTap: () => goTo(context, Dest.driverPay, {'driver': o.driverId!})),
              ],
            ),
          ],
          if (driver != null && driver.contacts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in driver.contacts)
                  OutlinedButton.icon(
                    onPressed: () => _call(c.phone),
                    icon: const Icon(Icons.phone_outlined, size: 16),
                    label: Text('${c.label.isNotEmpty ? '${c.label} ' : ''}${formatPhone(c.phone)}'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (dirty) FilledButton(onPressed: busy ? null : () => _saveDriver(o), child: const Text('บันทึกคนขับ')),
              TourTarget(
                'copy-driver',
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: message));
                    if (mounted) showSnack(context, 'คัดลอกข้อความส่งคนขับแล้ว');
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('คัดลอกข้อความส่งคนขับ'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://line.me/R/share?text=${Uri.encodeComponent(message)}'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('ส่งทาง LINE'),
              ),
              IconButton(
                tooltip: 'แชร์',
                onPressed: () => SharePlus.instance.share(ShareParams(text: message)),
                icon: const Icon(Icons.share_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _noteCard(Order o, bool busy) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(
            'หมายเหตุ',
            child: TextField(controller: _note, minLines: 2, maxLines: 5, onChanged: (_) => setState(() {})),
          ),
          if (_note.text != o.note) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: busy ? null : () => _run('note', () => updateOrderFields(o.id, _by, o, note: _note.text)),
                child: const Text('บันทึกหมายเหตุ'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyCard(Order o, CatalogController catalog) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('ประวัติ'),
          for (final e in o.statusLog.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7, right: 12),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.6)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          orderLogLabel(e, (id) => catalog.driverById(id)?.name),
                          style: const TextStyle(fontSize: 14),
                        ),
                        Text(
                          '${formatDateTime(e.at)}${e.by.isNotEmpty ? ' · ${e.by}' : ''}',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _call(String phone) => launchUrl(Uri(scheme: 'tel', path: digitsOnly(phone)));
}

Widget _muted(String text) => Text(text, style: const TextStyle(fontSize: 14, color: AppColors.muted));

class _Header extends StatelessWidget {
  const _Header({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              o.orderNo,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, fontFeatures: tabular),
            ),
            SourceBadge(o.source, long: true),
            if (o.demo) const DemoBadge(),
          ],
        ),
        const SizedBox(height: 2),
        _muted(
          '${formatDateShort(o.orderDate)}'
          '${o.receiptNo != null ? ' · ใบเสร็จ ${o.receiptNo}' : ''}'
          '${o.createdBy != null && o.createdBy!.isNotEmpty ? ' · โดย ${o.createdBy}' : ''}',
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(BadgeTone.danger);
    return AppCard(
      color: c.bg,
      borderColor: c.border,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 14, color: c.fg)),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.badge, this.children = const []});
  final String label;
  final Widget badge;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            badge,
          ],
        ),
        for (final c in children) Padding(padding: const EdgeInsets.only(top: 8), child: c),
      ],
    );
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText({required this.link, required this.onTap, this.prefix = '', this.suffix = ''});
  final String prefix;
  final String link;
  final String suffix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: prefix),
                TextSpan(
                  text: link,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                ),
                TextSpan(text: suffix),
              ],
            ),
            style: const TextStyle(fontSize: 14, color: AppColors.muted),
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppColors.subtle, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
