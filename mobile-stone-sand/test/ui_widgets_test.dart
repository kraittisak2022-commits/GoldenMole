import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/widgets/page.dart';
import 'package:mobile_stone_sand/widgets/ui.dart';

void main() {
  testWidgets('long card lists only build the rows on screen', (tester) async {
    var built = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageScroll(
          slivers: [
            SliverCardList(
              itemCount: 1000,
              header: const Text('หัวรายการ'),
              itemBuilder: (_, i) {
                built++;
                return ListTile(title: Text('แถว $i'), onTap: () {});
              },
            ),
          ],
          children: const [Text('ด้านบน')],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('หัวรายการ'), findsOneWidget);
    expect(find.text('แถว 0'), findsOneWidget);
    expect(find.text('แถว 999'), findsNothing);
    expect(built, lessThan(40));
  });

  testWidgets('reveal swaps the placeholder for the content', (tester) async {
    Widget app(bool pending) => MaterialApp(
          home: Scaffold(
            body: Reveal(pending: pending, placeholder: const Text('กำลังโหลด'), child: const Text('ข้อมูล')),
          ),
        );
    await tester.pumpWidget(app(true));
    expect(find.text('กำลังโหลด'), findsOneWidget);
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(find.text('กำลังโหลด'), findsNothing);
    expect(find.text('ข้อมูล'), findsOneWidget);
  });
}
