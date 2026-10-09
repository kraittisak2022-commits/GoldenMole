import 'dart:convert';

import 'package:flutter/material.dart';

import '../auth/auth_scope.dart';
import '../calc/pricing.dart';
import '../data/catalog_scope.dart';
import '../data/customers_repo.dart';
import '../data/db.dart';
import '../data/demo_repo.dart';
import '../data/orders_repo.dart';
import '../data/scope.dart';
import '../logic/order_draft.dart';
import '../logic/wizard_state.dart';
import '../models/models.dart';
import '../routes.dart';
import 'tour_steps.dart';

const tourStateKey = 'stone_sand_tour_v1';
const demoCustomerName = 'ลูกค้าตัวอย่าง (สาธิต)';

class TourState {
  const TourState({required this.step, this.vars = const TourVars(), this.paused = false});
  final int step;
  final TourVars vars;

  /// Overlay hidden; demo data and progress are kept so the tour can be resumed from the menu.
  final bool paused;

  TourState copyWith({int? step, TourVars? vars, bool? paused}) =>
      TourState(step: step ?? this.step, vars: vars ?? this.vars, paused: paused ?? this.paused);

  Map<String, dynamic> toJson() => {'step': step, 'vars': vars.toJson(), 'paused': paused};
}

TourState? loadTourState() {
  try {
    final raw = Prefs.instance.getString(tourStateKey);
    if (raw == null) return null;
    final j = jsonDecode(raw);
    final step = j is Map ? j['step'] : null;
    if (step is! int || step < 0) return null;
    return TourState(step: step, vars: TourVars.fromJson(j['vars']), paused: j['paused'] == true);
  } catch (_) {
    return null;
  }
}

void saveTourState(TourState? s) {
  try {
    if (s == null) {
      Prefs.instance.remove(tourStateKey);
    } else {
      Prefs.instance.setString(tourStateKey, jsonEncode(s.toJson()));
    }
  } catch (_) {}
}

String _doneKey(String userId) => 'stone_sand_tour_done_v1:$userId';

/// True once [userId] finished the whole tour on this device; the menu then stops offering it.
bool isTourDone(String? userId) {
  if (userId == null) return false;
  try {
    return Prefs.instance.getBool(_doneKey(userId)) ?? false;
  } catch (_) {
    return false;
  }
}

void markTourDone(String userId) {
  try {
    Prefs.instance.setBool(_doneKey(userId), true);
  } catch (_) {}
}

/// A ready-made credit pickup order so the tour can jump straight to วางบิล.
OrderDraft demoCreditDraft(Customer customer, Product product, OrderSource source) {
  const quantity = 2.0;
  return OrderDraft(
    source: source,
    orderDate: null,
    customer: customer,
    items: [
      OrderItem(
        id: 'demo-item',
        productId: product.id,
        name: product.name,
        unit: product.unit,
        unitPrice: product.pricePerUnit,
        quantity: quantity,
        amount: lineAmount(product.pricePerUnit, quantity),
      ),
    ],
    fulfillment: Fulfillment.pickup,
    deliveryAddress: '',
    pinLat: null,
    pinLng: null,
    zoneId: null,
    roadDistanceKm: null,
    truckSize: null,
    trips: 0,
    driverId: null,
    feePerCubic: 0,
    feePerTrip: 0,
    remoteSurcharge: 0,
    deliveryDiscount: 0,
    discountType: DiscountType.baht,
    discountValue: 0,
    paymentMethod: PaymentMethod.credit,
    paidNow: false,
    driverWage: 0,
    note: 'ออเดอร์สาธิต',
  );
}

/// Keeps the root navigator's route stack so markers know which screen is on top.
class _RouteStack extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (newRoute == null) return;
    if (i < 0) {
      routes.add(newRoute);
    } else {
      routes[i] = newRoute;
    }
  }

  /// Topmost full screen; dialogs and sheets sit above it without replacing it.
  Route<dynamic>? get topPage {
    for (final r in routes.reversed) {
      if (r is! PopupRoute) return r;
    }
    return null;
  }

  /// On the top screen or in a dialog/sheet over it.
  bool showing(Route<dynamic>? route) {
    if (route == null) return false;
    if (routes.isEmpty) return route.isCurrent;
    final top = topPage;
    final i = routes.indexOf(route);
    return i >= 0 && top != null && i >= routes.indexOf(top);
  }
}

class TourController extends ChangeNotifier {
  TourController({required this.auth, required this.catalog, required this.shell, required this.navigatorKey}) {
    if (demoSession() != null) _state = loadTourState();
  }

  final AuthController auth;
  final CatalogController catalog;
  final ShellController shell;
  final GlobalKey<NavigatorState> navigatorKey;
  final _stack = _RouteStack();
  NavigatorObserver get observer => _stack;

  TourState? _state;
  TourState? get state => _state;
  bool starting = false;
  bool busy = false;
  String error = '';

  final _markers = <TourMarkerState>{};
  final _targets = <TourTargetState>{};

  bool get active => _state != null && !_state!.paused;
  TourStep? get step {
    final s = _state;
    return s == null || s.step >= tourSteps.length ? null : tourSteps[s.step];
  }

  void _set(TourState? s) {
    _state = s;
    saveTourState(s);
    notifyListeners();
  }

  TourEnv env() {
    final top = _stack.topPage;
    TourMarkerState? marker;
    for (final m in _markers) {
      if (!m.mounted || !m.tickerEnabled) continue;
      if (top != null ? m.route == top : (m.route?.isCurrent ?? false)) marker = m;
    }
    final w = marker?.widget;
    return TourEnv(
      page: w?.page,
      pageId: w?.id,
      targets: {
        for (final t in _targets)
          if (_visible(t)) t.widget.name,
      },
      wizardStep: w?.wizardStep,
      order: w?.order,
      vars: _state?.vars ?? const TourVars(),
    );
  }

  bool _visible(TourTargetState t) {
    if (!t.mounted || !t.tickerEnabled || !_stack.showing(t.route)) return false;
    final box = t.context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize && !box.size.isEmpty;
  }

  /// The on-screen copy of a target (the same name can sit in a hidden tab too).
  BuildContext? targetContext(String name) {
    for (final t in _targets) {
      if (t.widget.name == name && _visible(t)) return t.context;
    }
    return null;
  }

  void goToStep(int index, [TourVars? vars]) {
    final s = _state;
    if (s == null) return;
    error = '';
    _set(s.copyWith(step: index.clamp(0, tourSteps.length - 1), vars: vars == null ? s.vars : s.vars.merge(vars)));
    _followStep();
  }

  void advance([TourVars? vars]) => goToStep((_state?.step ?? 0) + 1, vars);
  void back() => goToStep((_state?.step ?? 1) - 1);

  void pause() {
    final s = _state;
    if (s != null) _set(s.copyWith(paused: true));
  }

  void resume() {
    final s = _state;
    if (s == null) return;
    _set(s.copyWith(paused: false));
    _followStep();
  }

  /// Takes the user to the step's screen once the screens pushed this frame have reported in.
  void _followStep() {
    final index = _state?.step;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      binding.addPostFrameCallback((_) {
        final st = step;
        if (!active || st == null || _state?.step != index) return;
        if (st.isOn(env().page)) return;
        final to = st.route?.call(_state!.vars);
        if (to != null) navigate(to);
      });
      binding.scheduleFrame();
    });
    binding.scheduleFrame();
  }

  void navigate(TourNav to) {
    final ctx = navigatorKey.currentContext;
    final nav = navigatorKey.currentState;
    if (ctx == null || nav == null) return;
    void root() => nav.popUntil((r) => r.isFirst);
    switch (to.page) {
      case TourPage.home:
        goTo(ctx, Dest.dashboard);
      case TourPage.menu:
        goTo(ctx, Dest.menu);
      case TourPage.wizard:
        root();
        openNewOrder(ctx);
      case TourPage.order || TourPage.orderEdit:
        if (to.id == null) return;
        root();
        openOrder(ctx, to.id!);
      case TourPage.orderBill:
        if (to.id == null) return;
        root();
        openOrder(ctx, to.id!);
        openOrderBill(ctx, to.id!);
      case TourPage.statements:
        goTo(ctx, Dest.statements);
      case TourPage.statementCreate:
        goTo(ctx, Dest.statements, {'customer': ?to.id});
      case TourPage.statementBill:
        if (to.id == null) return;
        goTo(ctx, Dest.statements);
        openStatementBill(ctx, to.id!);
    }
  }

  void _clearDraft() {
    try {
      Prefs.instance.remove(draftKey);
    } catch (_) {}
  }

  Future<void> start() async {
    starting = true;
    error = '';
    notifyListeners();
    try {
      await deleteStaleDemoSessions().catchError((_) {});
      final previous = demoSession();
      if (previous != null) await deleteDemoSession(previous).catchError((_) {});
      startDemoSession();
      final customer = await saveCustomer(
        const Customer(
          id: '',
          name: demoCustomerName,
          aliases: ['ตัวอย่าง'],
          phone: '0800000000',
          address: '99 หมู่ 1 (ที่อยู่สาธิต)',
          note: 'สร้างโดยโหมดสอนใช้งาน',
        ),
      );
      _clearDraft();
      notifyDataChanged();
      starting = false;
      _set(TourState(step: 0, vars: TourVars(customerId: customer.id)));
      navigate(const TourNav(TourPage.home));
    } catch (e) {
      endDemoSession();
      starting = false;
      error = errorText(e, 'เริ่มโหมดสอนใช้งานไม่สำเร็จ');
      notifyListeners();
    }
  }

  /// Finished the whole tour, so it is offered from Settings only.
  bool get done => isTourDone(auth.user?.id);

  /// Deletes the demo data; true when the tour ended. [completed] is the last step's finish button.
  Future<bool> end({bool completed = false}) async {
    busy = true;
    error = '';
    notifyListeners();
    final session = demoSession();
    try {
      if (session != null) await deleteDemoSession(session);
    } catch (_) {
      busy = false;
      error = 'ลบข้อมูลสาธิตไม่สำเร็จ ตรวจสอบอินเทอร์เน็ตแล้วลองอีกครั้ง';
      notifyListeners();
      return false;
    }
    final onMenu = env().page == TourPage.menu;
    final userId = auth.user?.id;
    if (completed && userId != null) markTourDone(userId);
    endDemoSession();
    _clearDraft();
    notifyDataChanged();
    busy = false;
    _set(null);
    navigate(TourNav(completed || onMenu ? TourPage.home : TourPage.menu));
    return true;
  }

  Future<void> runAction(TourAction action) async {
    if (action == TourAction.finish) {
      await end(completed: true);
      return;
    }
    final s = _state;
    if (s == null) return;
    busy = true;
    error = '';
    notifyListeners();
    try {
      final id = s.vars.customerId;
      final customer = id == null ? null : await getCustomer(id);
      final products = catalog.products;
      final product = products.where((p) => p.active).firstOrNull ?? products.firstOrNull;
      if (customer == null || product == null) throw const AppException('ไม่พบลูกค้าหรือสินค้าสำหรับออเดอร์ตัวอย่าง');
      final order = await createOrder(
        demoCreditDraft(customer, product, auth.lockedSource ?? OrderSource.shop),
        auth.by,
      );
      busy = false;
      navigate(TourNav(TourPage.order, order.id));
      goToStep(s.step + 1, TourVars(creditOrderId: order.id));
    } catch (e) {
      busy = false;
      error = errorText(e, 'สร้างออเดอร์ตัวอย่างไม่สำเร็จ');
      notifyListeners();
    }
  }
}

class TourScope extends InheritedNotifier<TourController> {
  const TourScope({super.key, required TourController controller, required super.child}) : super(notifier: controller);

  static TourController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TourScope>()?.notifier;

  static TourController? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TourScope>()?.notifier;
}

mixin _Registered<T extends StatefulWidget> on State<T> {
  TourController? _tour;
  ModalRoute<dynamic>? route;
  bool tickerEnabled = true;

  void _add(TourController t);
  void _remove(TourController t);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
    tickerEnabled = TickerMode.valuesOf(context).enabled;
    final t = TourScope.maybeRead(context);
    if (!identical(t, _tour)) {
      if (_tour != null) _remove(_tour!);
      _tour = t;
      if (t != null) _add(t);
    }
  }

  @override
  void dispose() {
    if (_tour != null) _remove(_tour!);
    super.dispose();
  }
}

/// Tells the tour which screen this is (and the wizard step / order shown on it).
class TourMarker extends StatefulWidget {
  const TourMarker({super.key, required this.page, this.id, this.wizardStep, this.order, required this.child});
  final TourPage page;
  final String? id;
  final StepKey? wizardStep;
  final TourOrder? order;
  final Widget child;

  @override
  State<TourMarker> createState() => TourMarkerState();
}

class TourMarkerState extends State<TourMarker> with _Registered {
  @override
  void _add(TourController t) => t._markers.add(this);
  @override
  void _remove(TourController t) => t._markers.remove(this);

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Something the tour can spotlight.
class TourTarget extends StatefulWidget {
  const TourTarget(this.name, {super.key, required this.child});
  final String name;
  final Widget child;

  @override
  State<TourTarget> createState() => TourTargetState();
}

class TourTargetState extends State<TourTarget> with _Registered {
  @override
  void _add(TourController t) => t._targets.add(this);
  @override
  void _remove(TourController t) => t._targets.remove(this);

  @override
  Widget build(BuildContext context) => widget.child;
}
