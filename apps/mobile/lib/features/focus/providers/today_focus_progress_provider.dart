import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../data/focus_db.dart';

final todayFocusProgressProvider = FutureProvider.autoDispose<int>(
  (ref) async {
    ref.watch(domainScopeToken);

    final session = ref.watch(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      return 0;
    }

    return FocusDb().getAlreadyCreditedToday();
  },
  dependencies: [domainScopeToken],
);
