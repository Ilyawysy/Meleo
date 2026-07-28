import 'package:flutter/material.dart';
import 'register_credentials_screen.dart';
import 'register_verify_code_screen.dart';
import 'login_screen.dart';
import '../data/models/token_response.dart';

enum _Step { register, verify, login }

class AuthFlow extends StatefulWidget {
  const AuthFlow({super.key});

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  _Step _step = _Step.register;
  String? _email;
  String? _loginMessage;

  void _onRegistered({required String email, required bool needsOtp}) {
    setState(() {
      _email = email;
      _step = needsOtp ? _Step.verify : _Step.login;
      _loginMessage = needsOtp ? null : 'Введите свой пароль для входа';
    });
  }

  void _onEmailAlreadyRegistered(String email) {
    setState(() {
      _email = email;
      _step = _Step.login;
      _loginMessage = 'Этот email уже зарегистрирован, войдите со своим паролем';
    });
  }

  void _onSwitchToLogin() {
    setState(() {
      _step = _Step.login;
      _loginMessage = null;
    });
  }

  void _onSwitchToRegister() {
    setState(() {
      _step = _Step.register;
      _loginMessage = null;
    });
  }

  void _onBackFromVerify() {
    setState(() => _step = _Step.register);
  }

  void _onOtpVerified(TokenResponse tokenResponse) {
    debugPrint('[AuthFlow] OTP flow complete');
    // Navigation is handled by AuthGate: onAuthStateChange(signedIn) sets
    // _isAuthenticated=true → AuthGate.build() returns ShellScaffold.
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.register:
        return RegisterCredentialsScreen(
          onRegistered: _onRegistered,
          onEmailAlreadyRegistered: _onEmailAlreadyRegistered,
          onSwitchToLogin: _onSwitchToLogin,
        );
      case _Step.verify:
        return RegisterVerifyCodeScreen(
          email: _email!,
          onOtpVerified: _onOtpVerified,
          onBack: _onBackFromVerify,
        );
      case _Step.login:
        return LoginScreen(
          initialEmail: _email,
          initialMessage: _loginMessage,
          onSwitchToRegister: _onSwitchToRegister,
        );
    }
  }
}
