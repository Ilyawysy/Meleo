import 'package:flutter/foundation.dart';

@immutable
class TokenResponse {
  final String accessToken;
  final String userId;
  final String? refreshToken;

  const TokenResponse({
    required this.accessToken,
    required this.userId,
    this.refreshToken,
  });

  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    return TokenResponse(
      accessToken: json['access_token'] as String,
      userId: json['user_id'] as String? ?? json['sub'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'user_id': userId,
      if (refreshToken != null) 'refresh_token': refreshToken,
    };
  }

  @override
  String toString() {
    final masked = accessToken.length > 10
        ? '${accessToken.substring(0, 10)}...'
        : '***';
    return 'TokenResponse(accessToken: $masked, userId: $userId)';
  }
}
