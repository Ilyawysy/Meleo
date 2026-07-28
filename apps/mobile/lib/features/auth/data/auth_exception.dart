enum AuthErrorKind { generic, emailTaken, invalidCredentials }

class AuthException implements Exception {
  final String message;
  final AuthErrorKind kind;

  AuthException(this.message) : kind = AuthErrorKind.generic;

  AuthException.emailAlreadyRegistered()
      : message = 'This email is already registered',
        kind = AuthErrorKind.emailTaken;

  AuthException.invalidCredentials()
      : message = 'Invalid email or password',
        kind = AuthErrorKind.invalidCredentials;

  @override
  String toString() => message;
}
