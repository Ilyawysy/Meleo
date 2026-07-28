import 'package:flutter/widgets.dart';

/// Observes app lifecycle and triggers a sync callback on foreground resume.
///
/// No periodic timer — pull sync is event-driven:
/// - App start (orchestrator calls syncNow)
/// - Foreground resume (this controller detects it)
class AdaptiveSyncController with WidgetsBindingObserver {
  AdaptiveSyncController._();
  static final AdaptiveSyncController instance = AdaptiveSyncController._();

  VoidCallback? _onResume;

  /// Start observing lifecycle. [onResume] is called when app returns
  /// to foreground.
  void start({required VoidCallback onResume}) {
    _onResume = onResume;
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _onResume = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResume?.call();
    }
  }
}
