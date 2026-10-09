import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/auth/auth_scope.dart';
import 'package:mobile_stone_sand/auth/session.dart';
import 'package:mobile_stone_sand/data/catalog_scope.dart';
import 'package:mobile_stone_sand/data/db.dart';
import 'package:mobile_stone_sand/data/scope.dart';
import 'package:mobile_stone_sand/logic/wizard_state.dart';
import 'package:mobile_stone_sand/models/models.dart';
import 'package:mobile_stone_sand/routes.dart';
import 'package:mobile_stone_sand/tour/tour_controller.dart';
import 'package:mobile_stone_sand/tour/tour_overlay.dart';
import 'package:mobile_stone_sand/tour/tour_steps.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs.setForTest(await SharedPreferences.getInstance());
    endDemoSession();
  });

  group('tour state', () {
    test('round-trips through prefs', () {
      saveTourState(
        const TourState(
          step: 7,
          vars: TourVars(customerId: 'c1', orderId: 'o1'),
          paused: true,
        ),
      );
      final s = loadTourState()!;
      expect(s.step, 7);
      expect(s.paused, isTrue);
      expect(s.vars.customerId, 'c1');
      expect(s.vars.orderId, 'o1');
      expect(s.vars.statementId, isNull);

      saveTourState(null);
      expect(loadTourState(), isNull);
    });

    test('ignores broken saved state', () {
      Prefs.instance.setString(tourStateKey, 'not json');
      expect(loadTourState(), isNull);
      Prefs.instance.setString(tourStateKey, '{"step":-1}');
      expect(loadTourState(), isNull);
    });

    test('vars merge keeps earlier captures', () {
      const a = TourVars(customerId: 'c1', orderId: 'o1');
      final b = a.merge(const TourVars(creditOrderId: 'o2'));
      expect(b.customerId, 'c1');
      expect(b.orderId, 'o1');
      expect(b.creditOrderId, 'o2');
      expect(b.toJson().containsKey('statementId'), isFalse);
    });
  });

  group('step script', () {
    test('every chapter is used in order and the tour ends with finish', () {
      var last = 0;
      for (final s in tourSteps) {
        expect(s.chapter, greaterThanOrEqualTo(last));
        expect(s.chapter, lessThan(tourChapters.length));
        last = s.chapter;
        if (s.action != null) expect(s.actionLabel, isNotEmpty);
        if (s.target != null) expect(s.route, isNotNull, reason: s.title);
      }
      expect(last, tourChapters.length - 1);
      expect(tourSteps.last.action, TourAction.finish);
    });

    test('every spotlight target is wired into a screen', () {
      final source = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.contains('tour_steps'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      expect(source, contains('TourTarget('));
      for (final name in {for (final s in tourSteps) ?s.target}) {
        expect(source, contains("'$name'"), reason: 'no TourTarget for $name');
      }
    });

    test('back only re-shows explanations on the same screen', () {
      expect(canGoBack(tourSteps, 0), isFalse);
      final pending = tourSteps.indexWhere((s) => s.target == 'dash-pending');
      expect(canGoBack(tourSteps, pending), isTrue);
      final progress = tourSteps.indexWhere((s) => s.target == 'wiz-progress');
      expect(canGoBack(tourSteps, progress), isFalse);
    });

    test('chapter progress counts steps within the chapter', () {
      final first = chapterProgress(tourSteps, 0);
      expect(first.chapter, 0);
      expect(first.chapterStep, 1);
      expect(first.chapterSize, tourSteps.where((s) => s.chapter == 0).length);
      final end = chapterProgress(tourSteps, tourSteps.length - 1);
      expect(end.chapter, tourChapters.length - 1);
      expect(end.chapterStep, end.chapterSize);
    });

    test('wizard steps finish once the wizard moves past them', () {
      final source = tourSteps.firstWhere((s) => s.target == 'wiz-source');
      expect(source.done!(const TourEnv(page: TourPage.wizard, wizardStep: StepKey.source)), isFalse);
      expect(source.done!(const TourEnv(page: TourPage.wizard, wizardStep: StepKey.products)), isTrue);

      final submit = tourSteps.firstWhere((s) => s.target == 'wiz-submit');
      const onBill = TourEnv(page: TourPage.orderBill, pageId: 'o9');
      expect(submit.done!(onBill), isTrue);
      expect(submit.capture!(onBill).orderId, 'o9');
    });

    test('delivery steps are skipped for pickup orders', () {
      final copy = tourSteps.firstWhere((s) => s.target == 'copy-driver');
      TourEnv env(bool pickup) => TourEnv(
        page: TourPage.order,
        order: TourOrder(id: 'o1', paid: false, delivery: DeliveryStatus.waiting, pickup: pickup, cancelled: false),
        vars: const TourVars(orderId: 'o1'),
      );
      expect(copy.skip!(env(true)), isTrue);
      expect(copy.skip!(env(false)), isFalse);
    });
  });

  test('demo credit draft is a credit pickup for two units', () {
    const product = Product(
      id: 'p1',
      name: 'ทรายหยาบ',
      category: ProductCategory.sand,
      unit: 'คิว',
      pricePerUnit: 450,
      sortOrder: 0,
      active: true,
    );
    const customer = Customer(id: 'c1', name: demoCustomerName);
    final d = demoCreditDraft(customer, product, OrderSource.shop);
    expect(d.paymentMethod, PaymentMethod.credit);
    expect(d.fulfillment, Fulfillment.pickup);
    expect(d.items.single.quantity, 2);
    expect(d.items.single.amount, 900);
  });

  testWidgets('overlay follows markers across screens', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    saveSession(
      StoneSandSession(
        id: 'u1',
        username: 'admin',
        displayName: 'แอดมิน',
        role: 'Admin',
        orderSource: null,
        loginAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    startDemoSession();
    final kpis = tourSteps.indexWhere((s) => s.target == 'dash-kpis');
    saveTourState(
      TourState(
        step: kpis,
        vars: const TourVars(customerId: 'c1'),
      ),
    );

    final auth = AuthController();
    final catalog = CatalogController()..loading = false;
    final shell = ShellController();
    final navigator = GlobalKey<NavigatorState>();
    final tour = TourController(auth: auth, catalog: catalog, shell: shell, navigatorKey: navigator);
    expect(tour.active, isTrue);

    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: CatalogScope(
          controller: catalog,
          child: ShellScope(
            controller: shell,
            child: TourScope(
              controller: tour,
              child: MaterialApp(
                navigatorKey: navigator,
                navigatorObservers: [tour.observer],
                builder: (context, child) => TourOverlayHost(child: child!),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TourMarker(
                      page: TourPage.home,
                      child: Column(
                        children: [
                          const TourTarget('dash-kpis', child: SizedBox(width: 200, height: 80)),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const TourMarker(
                                  page: TourPage.wizard,
                                  wizardStep: StepKey.products,
                                  child: Scaffold(body: Text('wizard')),
                                ),
                              ),
                            ),
                            child: const Text('open'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ตัวเลขของวัน'), findsOneWidget);
    expect(find.text('บทที่ 1/${tourChapters.length} · ${tourChapters[0]}'), findsOneWidget);
    expect(find.text('ขั้น ${kpis + 1}/${tourSteps.length}'), findsOneWidget);
    var env = tour.env();
    expect(env.page, TourPage.home);
    expect(env.has('dash-kpis'), isTrue);

    await tester.tap(find.text('ถัดไป'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(tour.state!.step, kpis + 1);
    expect(find.text('งานค้าง'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('wizard'), findsOneWidget);
    env = tour.env();
    expect(env.page, TourPage.wizard);
    expect(env.wizardStep, StepKey.products);
    expect(env.has('dash-kpis'), isFalse);
    expect(find.text('ขั้นนี้อยู่อีกหน้าหนึ่ง'), findsOneWidget);

    tour.pause();
    await tester.pump();
    expect(find.text('งานค้าง'), findsNothing);
    expect(loadTourState()!.paused, isTrue);

    await tester.pumpWidget(const SizedBox());
    tour.dispose();
  });
}
