import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/features/auth/ui/auth_loading_screen.dart';

void main() {
  group('AuthLoadingScreen', () {
    testWidgets(
      'renders Scaffold with a CircularProgressIndicator',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: AuthLoadingScreen()),
        );
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets(
      'shows default message when message is null',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: AuthLoadingScreen()),
        );
        expect(find.text('Загружаем профиль...'), findsOneWidget);
      },
    );

    testWidgets(
      'shows custom message when message is provided',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: AuthLoadingScreen(message: 'Пожалуйста, подождите'),
          ),
        );
        expect(find.text('Пожалуйста, подождите'), findsOneWidget);
        // Default message must not appear.
        expect(find.text('Загружаем профиль...'), findsNothing);
      },
    );

    testWidgets(
      'shows Meleo brand label',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: AuthLoadingScreen()),
        );
        expect(find.text('Meleo'), findsOneWidget);
      },
    );

    testWidgets(
      'shows lightning-bolt icon inside a decorated Container',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: AuthLoadingScreen()),
        );
        expect(find.byIcon(Icons.flash_on_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'does not crash when mounted and unmounted immediately',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: AuthLoadingScreen()),
        );
        // Trigger a rebuild / unmount by swapping to an empty scaffold.
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        // No exceptions thrown.
      },
    );

    testWidgets(
      'background colour is white',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: AuthLoadingScreen()),
        );
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.backgroundColor, Colors.white);
      },
    );
  });
}
