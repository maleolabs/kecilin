import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kecilin/ui/app_theme.dart';
import 'package:kecilin/ui/widgets.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Center(child: SizedBox(width: 320, child: child)),
    ),
  );
}

void main() {
  testWidgets('SizeBar splits proportionally to the output size', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const SizeBar(before: 1000, after: 250)));

    final children = tester
        .widgetList<Expanded>(
          find.descendant(
            of: find.byType(SizeBar),
            matching: find.byType(Expanded),
          ),
        )
        .toList();

    expect(children, hasLength(2));
    expect(children.first.flex, 250);
    expect(children.last.flex, 750);
  });

  testWidgets('SizeBar handles a zero byte source', (tester) async {
    await tester.pumpWidget(_host(const SizeBar(before: 0, after: 0)));

    expect(tester.takeException(), isNull);
  });

  testWidgets('ChoicePill reports taps', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _host(
        ChoicePill(
          label: '200 KB',
          selected: false,
          accent: const Color(0xFF0E6B57),
          onTap: () => tapped++,
        ),
      ),
    );

    await tester.tap(find.text('200 KB'));
    await tester.pump();

    expect(tapped, 1);
  });

  testWidgets('ChoicePill stays compact and centers its label vertically', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Row(
          children: [
            ChoicePill(
              label: '200 KB',
              selected: false,
              accent: const Color(0xFF0E6B57),
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    final pill = tester.getRect(find.byType(AnimatedContainer));
    final text = tester.getRect(find.text('200 KB'));

    // Tidak melebar memenuhi host 320px.
    expect(pill.width, lessThan(160));
    // Teks benar-benar di tengah vertikal pill.
    expect((text.center.dy - pill.center.dy).abs(), lessThan(0.5));
  });

  testWidgets('OptionCard shows the selected state', (tester) async {
    await tester.pumpWidget(
      _host(
        OptionCard(
          title: 'Agresif',
          subtitle: 'Halaman dijadikan gambar',
          selected: true,
          onTap: () {},
        ),
      ),
    );

    expect(find.text('Agresif'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
