import 'package:flutter/foundation.dart';

import '../../../core/api_client.dart';

class OnboardingService {
  static final ApiClient _api = ApiClient();

  /// Marks onboarding as completed on the server.
  /// Returns true if successful, false on failure.
  static Future<bool> markCompletedOnServer() async {
    try {
      final url = _api.uri('/api/v1/users/me/onboarding/complete');
      final response = await _api.send('POST', url);
      return response.statusCode == 204;
    } catch (e) {
      debugPrint('[OnboardingService] markCompletedOnServer failed: $e');
      return false;
    }
  }
}
