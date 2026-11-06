import 'package:flutter_test/flutter_test.dart';

import 'package:susometer/main.dart';

void main() {
  testWidgets('app shell shows the title and disclaimer', (tester) async {
    await tester.pumpWidget(const SusApp());
    expect(find.text('Sus-o-meter'), findsOneWidget);
    expect(
      find.text('For fun only. Measures stress reactions, not truth.'),
      findsOneWidget,
    );
  });
}
