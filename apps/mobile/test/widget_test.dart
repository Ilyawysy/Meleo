import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:meleo/core/providers/inner_scope.dart';
import 'package:meleo/main.dart';

void main() {
  testWidgets('App bootstrap smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: InnerScope(
          child: MyApp(),
        ),
      ),
    );

    expect(find.byType(MyApp), findsOneWidget);
  });
}
