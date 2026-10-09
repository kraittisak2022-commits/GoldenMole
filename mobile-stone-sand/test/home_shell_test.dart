import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/routes.dart';
import 'package:mobile_stone_sand/screens/home_shell.dart';

void main() {
  testWidgets('bottom tabs keep their height so the body fills the screen', (tester) async {
    tester.view.physicalSize = const Size(360, 785);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const body = Key('body');
    await tester.pumpWidget(
      ShellScope(
        controller: ShellController(),
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(key: body),
            bottomNavigationBar: BottomTabs(current: Dest.dashboard),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(BottomTabs)).height, 61);
    expect(tester.getSize(find.byKey(body)).height, 785 - 61);
  });
}
