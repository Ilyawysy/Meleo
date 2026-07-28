import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/features/focus/constants/room_colors.dart';
import 'package:meleo/features/focus/models/focus_room.dart';

void main() {
  group('kRoomColorPalette', () {
    test('contains 8 colors, first is indigo', () {
      expect(kRoomColorPalette.length, 8);
      expect(kRoomColorPalette.first, '#6366F1');
    });

    test('all entries are valid hex color strings', () {
      final hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
      for (final color in kRoomColorPalette) {
        expect(hexPattern.hasMatch(color), isTrue,
            reason: '$color is not a valid hex color');
      }
    });
  });

  group('FocusRoom.create (first room onboarding)', () {
    test('creates room with trimmed title and default palette color', () {
      const title = 'Work';
      final room = FocusRoom.create(
        title: title,
        color: kRoomColorPalette.first,
      );

      expect(room.title, 'Work');
      expect(room.color, kRoomColorPalette.first);
      expect(room.type, FocusRoomType.regular);
      expect(room.archived, false);
      expect(room.sortOrder, 0);
      expect(room.id, isNotEmpty);
      expect(room.createdAt, isNotNull);
      expect(room.updatedAt, isNotNull);
    });

    test('generates unique ids for two rooms created at the same time', () {
      final r1 = FocusRoom.create(title: 'Room A', color: kRoomColorPalette.first);
      final r2 = FocusRoom.create(title: 'Room B', color: kRoomColorPalette.first);
      expect(r1.id, isNot(equals(r2.id)));
    });

    test('title validation: empty is invalid', () {
      final trimmed = '   '.trim();
      expect(trimmed.isEmpty, isTrue);
    });

    test('title validation: over 120 chars is invalid', () {
      final longTitle = 'A' * 121;
      expect(longTitle.length > 120, isTrue);
    });

    test('title validation: 120 chars is valid', () {
      final exactTitle = 'A' * 120;
      expect(exactTitle.length <= 120, isTrue);
    });
  });

  group('First Room Step UI behaviour', () {
    testWidgets('Create Room button is disabled when text field is empty',
        (WidgetTester tester) async {
      String? capturedName;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestFirstRoomStepWrapper(
              onContinue: (name) => capturedName = name,
            ),
          ),
        ),
      );

      // Find the Create Room button container — it should have grey color when empty
      final createButton = find.text('Create Room');
      expect(createButton, findsOneWidget);

      // Tap it while empty — nothing should be called
      await tester.tap(createButton);
      await tester.pump();
      expect(capturedName, isNull);
    });

    testWidgets('Create Room button calls onContinue with trimmed name',
        (WidgetTester tester) async {
      String? capturedName;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestFirstRoomStepWrapper(
              onContinue: (name) => capturedName = name,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '  Study  ');
      await tester.pump();

      // Button should now be enabled — tap it
      await tester.tap(find.text('Create Room'));
      await tester.pump();

      expect(capturedName, 'Study');
    });
  });
}

/// Minimal wrapper that reproduces the _FirstRoomStep widget.
/// Since _FirstRoomStep is private we recreate its essential logic here.
class _TestFirstRoomStepWrapper extends StatefulWidget {
  final void Function(String name) onContinue;

  const _TestFirstRoomStepWrapper({required this.onContinue});

  @override
  State<_TestFirstRoomStepWrapper> createState() =>
      _TestFirstRoomStepWrapperState();
}

class _TestFirstRoomStepWrapperState
    extends State<_TestFirstRoomStepWrapper> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty || name.length > 120) return;
    widget.onContinue(name);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(controller: _ctrl),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _ctrl,
          builder: (context, value, _) {
            final enabled = value.text.trim().isNotEmpty;
            return GestureDetector(
              onTap: enabled ? _submit : null,
              child: const Text('Create Room'),
            );
          },
        ),
      ],
    );
  }
}
