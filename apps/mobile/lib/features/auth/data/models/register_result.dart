class RegisterResult {
  final bool emailVerificationRequired;

  RegisterResult({required this.emailVerificationRequired});

  factory RegisterResult.fromJson(Map<String, dynamic> j) => RegisterResult(
        emailVerificationRequired:
            j['email_verification_required'] as bool? ?? false,
      );
}
