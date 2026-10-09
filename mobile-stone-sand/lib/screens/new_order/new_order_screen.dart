import 'dart:convert';

import 'package:flutter/material.dart';

import '../../auth/auth_scope.dart';
import '../../data/catalog_scope.dart';
import '../../data/customers_repo.dart';
import '../../data/db.dart';
import '../../data/orders_repo.dart';
import '../../data/scope.dart';
import '../../logic/driver_pay.dart';
import '../../logic/format.dart';
import '../../logic/wizard_state.dart';
import '../../models/models.dart';
import '../../routes.dart';
import '../../theme/app_theme.dart';
import '../../tour/tour_controller.dart';
import '../../tour/tour_steps.dart';
import '../../widgets/ui.dart';
import 'order_created_dialog.dart';
import 'step_confirm.dart';
import 'step_customer.dart';
import 'step_fulfillment.dart';
import 'step_products.dart';
import 'step_source.dart';
import 'step_summary.dart';

({int step, WizardState state})? readDraft() {
  try {
    final raw = Prefs.instance.getString(draftKey);
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final step = ((j['step'] as num?)?.toInt() ?? 0).clamp(0, steps.length - 1);
    final state = WizardState.fromJson(Map<String, dynamic>.from(j['state'] as Map));
    return (step: step, state: withDeliveryPlan(state));
  } catch (_) {
    return null;
  }
}

void clearDraft() => Prefs.instance.remove(draftKey);

void _saveDraft(int step, WizardState state) {
  Prefs.instance.setString(draftKey, jsonEncode({'step': step, 'state': state.toJson()}));
}

class NewOrderScreen extends StatefulWidget {
  const NewOrderScreen({super.key, this.customerId});

  /// Starts a fresh order for this customer instead of resuming the saved draft.
  final String? customerId;

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  late int _step;
  late WizardState _state;
  String _stepError = '';
  bool _submitting = false;
  String _submitError = '';
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final initial = widget.customerId != null ? null : readDraft();
    _step = initial?.step ?? 0;
    final s = initial?.state ?? initialWizardState;
    final locked = AuthScope.read(context).lockedSource;
    _state = locked != null ? s.copyWith(source: locked) : s;
    final id = widget.customerId;
    if (id != null) {
      getCustomer(id)
          .then((c) {
            if (c != null && mounted) _selectCustomer(c);
          })
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _update(WizardState next, {int? step}) {
    setState(() {
      _state = next;
      if (step != null && step != _step) {
        _step = step;
        _stepError = '';
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    });
    _saveDraft(_step, _state);
  }

  void _patch(WizardState Function(WizardState s) update) => _update(withDeliveryPlan(update(_state)));

  void _setStep(int step) => _update(_state, step: step);

  void _selectCustomer(Customer? c) {
    var next = _state.copyWith(customer: c);
    if (c != null && c.isCredit && _state.paymentMethod == null) {
      next = next.copyWith(paymentMethod: PaymentMethod.credit, paidNow: false);
    }
    final onCustomer = _step == stepIndex(StepKey.customer);
    _update(next, step: c != null && onCustomer ? _step + 1 : null);
  }

  void _selectSource(OrderSource source) {
    final onSource = _step == stepIndex(StepKey.source);
    _update(_state.copyWith(source: source), step: onSource ? _step + 1 : null);
  }

  void _next() {
    final err = validateStep(_step, _state);
    if (err.isNotEmpty) return setState(() => _stepError = err);
    _setStep(_step + 1 < steps.length ? _step + 1 : _step);
  }

  void _back() {
    if (_step == 0) {
      _close();
      return;
    }
    _setStep(_step - 1);
  }

  Future<void> _close() async {
    final dirty = _state.customer != null || totalQuantity(quantitiesOf(_state.loads)) > 0;
    if (dirty) {
      final ok = await confirmDialog(
        context,
        title: 'ยกเลิกออเดอร์นี้?',
        message: 'ข้อมูลที่กรอกไว้จะหายไป',
        confirmLabel: 'ยกเลิกออเดอร์',
        destructive: true,
      );
      if (!ok) return;
    }
    clearDraft();
    if (mounted) Navigator.of(context).pop();
  }

  void _goTo(int target) {
    if (target < _step) return _setStep(target);
    for (var i = 0; i < target; i++) {
      final err = validateStep(i, _state);
      if (err.isNotEmpty) {
        _setStep(i);
        setState(() => _stepError = err);
        return;
      }
    }
    _setStep(target);
  }

  Future<void> _submit(List<Product> products, double driverFeePerTrip) async {
    for (var i = 0; i < steps.length - 1; i++) {
      final err = validateStep(i, _state);
      if (err.isNotEmpty) {
        _setStep(i);
        setState(() => _stepError = err);
        return;
      }
    }
    setState(() {
      _submitting = true;
      _submitError = '';
    });
    try {
      final by = AuthScope.read(context).by;
      final order = await createOrder(toDraft(_state, products, driverFeePerTrip), by);
      clearDraft();
      if (!mounted) return;
      // The guided tour expects to land on the bill straight away
      if (order.fulfillment == Fulfillment.delivery && demoSession() == null) {
        await showOrderCreatedDialog(context, order);
        if (!mounted) return;
      }
      await openOrderBill(context, order.id, created: true, replace: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = errorText(e, 'บันทึกออเดอร์ไม่สำเร็จ');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogScope.of(context);
    final auth = AuthScope.of(context);
    if (catalog.loading && catalog.products.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final s = _state;
    final products = catalog.products;
    final quantities = quantitiesOf(s.loads);
    final loadLines = [
      for (final p in products)
        if ((s.loads[p.id]?.perTrip ?? 0) > 0 && (s.loads[p.id]?.trips ?? 0) > 0)
          LoadLine(id: p.id, name: p.name, load: s.loads[p.id]!),
    ];
    final items = buildItems(products, quantities, s.unitDiscounts);
    final totals = wizardTotals(s, items);
    final zone = catalog.zoneById(s.zoneId);
    final driver = catalog.driverById(s.driverId);
    final stepKey = steps[_step];
    final last = _step == steps.length - 1;

    final body = switch (stepKey) {
      StepKey.source => StepSource(
        sources: auth.visibleSources,
        source: s.source,
        onSelect: _selectSource,
        orderDate: s.orderDate,
        onDateChange: (d) => _patch((st) => st.copyWith(orderDate: d)),
      ),
      StepKey.products => StepProducts(
        products: products,
        loads: s.loads,
        onChange: (l) => _patch((st) => st.copyWith(loads: l)),
      ),
      StepKey.customer => StepCustomer(customer: s.customer, onSelect: _selectCustomer),
      StepKey.fulfillment => StepFulfillment(
        state: s,
        patch: _patch,
        zones: catalog.zones,
        drivers: catalog.drivers,
        settings: catalog.settings,
        loadLines: loadLines,
        onEditProducts: () => _setStep(stepIndex(StepKey.products)),
      ),
      StepKey.summary => StepSummary(state: s, patch: _patch, items: items),
      StepKey.confirm => StepConfirm(state: s, items: items, zone: zone, driver: driver, onEdit: _setStep),
    };
    final bodyTarget = switch (stepKey) {
      StepKey.source => 'wiz-source',
      StepKey.products => 'wiz-products',
      StepKey.fulfillment => 'wiz-fulfillment',
      StepKey.confirm => 'wiz-confirm',
      StepKey.customer || StepKey.summary => null,
    };

    return TourMarker(
      page: TourPage.wizard,
      wizardStep: stepKey,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          backgroundColor: AppColors.page,
          appBar: AppBar(
            leading: IconButton(tooltip: 'ปิด', icon: const Icon(Icons.close), onPressed: _close),
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('สร้างออเดอร์', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                if (s.source != null)
                  Text(
                    'ออเดอร์${s.source!.label}${s.orderDate.isNotEmpty ? ' · ${formatDateShort(s.orderDate)}' : ''}',
                    style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '${_step + 1} / ${steps.length}',
                    style: const TextStyle(fontSize: 14, color: AppColors.muted, fontFeatures: tabular),
                  ),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: TourTarget(
                'wiz-progress',
                child: _Progress(step: _step, onTap: _goTo),
              ),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 672),
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (catalog.error.isNotEmpty) ...[
                    ErrorBox(catalog.error, onRetry: catalog.reload),
                    const SizedBox(height: 16),
                  ],
                  if (bodyTarget != null) TourTarget(bodyTarget, child: body) else body,
                  if (_submitError.isNotEmpty) ...[const SizedBox(height: 16), ErrorBox(_submitError)],
                ],
              ),
            ),
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_stepError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_stepError, style: const TextStyle(fontSize: 14, color: AppColors.destructive)),
                      ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: _step == 0 ? 'ยกเลิก' : 'ย้อนกลับ',
                          iconSize: 24,
                          onPressed: _back,
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('ยอดสุทธิ', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                              Text(
                                formatMoney(totals.total),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: tabular,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 52,
                          child: last
                              ? TourTarget(
                                  'wiz-submit',
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                                    onPressed: _submitting
                                        ? null
                                        : () => _submit(
                                              products,
                                              driverTripRate(zone, s.truckSize, s.roadDistanceKm, catalog.settings.delivery)
                                                  .perTrip,
                                            ),
                                    icon: const Icon(Icons.check, size: 18),
                                    label: Text(_submitting ? 'กำลังบันทึก…' : 'ยืนยันและออกบิล'),
                                  ),
                                )
                              : FilledButton(
                                  onPressed: _next,
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [Text('ถัดไป'), SizedBox(width: 6), Icon(Icons.arrow_forward, size: 18)],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.onTap});
  final int step;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                onTap: () => onTap(i),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= step ? AppColors.primary : AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      steps[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: i == step ? AppColors.ink : AppColors.muted,
                        fontWeight: i == step ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
