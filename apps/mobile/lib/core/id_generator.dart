import 'dart:math';

/// Generates a collision-resistant local ID.
///
/// Format: `local-<millisecondsSinceEpoch>-<random 0..999999>`
String generateLocalId() {
  final now = DateTime.now();
  return 'local-${now.millisecondsSinceEpoch}-${Random().nextInt(999999)}';
}
