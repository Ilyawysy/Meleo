import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;
import '../data/auth_service.dart';
import '../data/auth_exception.dart';

class RegisterCredentialsScreen extends StatefulWidget {
  final void Function({required String email, required bool needsOtp})
      onRegistered;
  final void Function(String email) onEmailAlreadyRegistered;
  final VoidCallback onSwitchToLogin;

  const RegisterCredentialsScreen({
    super.key,
    required this.onRegistered,
    required this.onEmailAlreadyRegistered,
    required this.onSwitchToLogin,
  });

  @override
  State<RegisterCredentialsScreen> createState() =>
      _RegisterCredentialsScreenState();
}

class _RegisterCredentialsScreenState
    extends State<RegisterCredentialsScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  String? _error;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _oauthTimeout;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) async {
        if (!mounted) return;
        if (data.event == AuthChangeEvent.signedIn && _isGoogleLoading) {
          // Keep the in-button spinner visible until AuthGate routes us to
          // Onboarding/Shell (this widget will be disposed then). Cancel only
          // the OAuth-timeout guard since the sign-in actually succeeded.
          _oauthTimeout?.cancel();
        }
        if (data.event == AuthChangeEvent.signedOut && _isGoogleLoading) {
          _oauthTimeout?.cancel();
          setState(() {
            _isGoogleLoading = false;
            _error = 'Google sign-in was cancelled';
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _oauthTimeout?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Введите пароль';
    }
    if (value.length < 8) {
      return 'Пароль должен быть не короче 8 символов';
    }
    if (value.length > 128) {
      return 'Пароль не должен превышать 128 символов';
    }
    if (!RegExp(r'[a-zA-Z]').hasMatch(value)) {
      return 'Пароль должен содержать хотя бы одну букву';
    }
    if (!RegExp(r'[\d\W_]').hasMatch(value)) {
      return 'Пароль должен содержать хотя бы одну цифру или спецсимвол';
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      debugPrint('[RegisterCredentialsScreen] Registering...');
      final result = await _authService.registerWithPassword(
        email: email,
        password: password,
      );

      if (result.emailVerificationRequired) {
        debugPrint('[RegisterCredentialsScreen] OTP required');
        if (mounted) {
          widget.onRegistered(email: email, needsOtp: true);
        }
      } else {
        debugPrint('[RegisterCredentialsScreen] No OTP, signing in directly');
        try {
          await _authService.signInWithPassword(
            email: email,
            password: password,
          );
          // AuthGate handles navigation on signedIn event
        } on AuthException catch (e) {
          if (e.kind == AuthErrorKind.invalidCredentials) {
            if (mounted) {
              widget.onRegistered(email: email, needsOtp: false);
            }
          } else {
            if (mounted) setState(() => _error = e.message);
          }
        }
      }
    } on AuthException catch (e) {
      if (e.kind == AuthErrorKind.emailTaken) {
        if (mounted) {
          widget.onEmailAlreadyRegistered(email);
        }
      } else {
        if (mounted) setState(() => _error = e.message);
      }
    } catch (e) {
      debugPrint('[RegisterCredentialsScreen] Register failed: $e');
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('AuthException: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });
    _oauthTimeout?.cancel();
    _oauthTimeout = Timer(const Duration(seconds: 45), () {
      if (!mounted || !_isGoogleLoading) return;
      setState(() {
        _isGoogleLoading = false;
        _error = 'Google sign-in timed out. Please try again.';
      });
    });
    try {
      await _authService.signInWithGoogleOAuth();
    } catch (e) {
      debugPrint('[RegisterCredentialsScreen] Google OAuth failed: $e');
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('AuthException: ', '');
          _isGoogleLoading = false;
        });
      }
    }
  }

  void _handleAppleSignIn() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Apple sign-in coming soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAnyLoading = _isLoading || _isGoogleLoading;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // --- Logo Section ---
                  _buildLogo(),
                  const SizedBox(height: 12),
                  Text(
                    'Meleo',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF18181B),
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Stay focused. Get things done.',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFFA1A1AA),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --- Email Field ---
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Email',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF71717A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !isAnyLoading,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: const Color(0xFF18181B),
                    ),
                    decoration: _inputDecoration('your@email.com'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@') || !value.contains('.')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // --- Password Field ---
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Пароль',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF71717A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    enabled: !isAnyLoading,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: const Color(0xFF18181B),
                    ),
                    decoration: _inputDecoration('Минимум 8 символов').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: const Color(0xFF71717A),
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    validator: _validatePassword,
                  ),

                  // --- Error ---
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFEF4444),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: 40),

                  // --- Buttons ---
                  _buildContinueButton(isAnyLoading),
                  const SizedBox(height: 14),
                  _buildGoogleButton(isAnyLoading),
                  const SizedBox(height: 14),
                  _buildAppleButton(isAnyLoading),

                  const SizedBox(height: 20),

                  // --- Switch to login ---
                  GestureDetector(
                    onTap: isAnyLoading ? null : widget.onSwitchToLogin,
                    child: Text(
                      'Уже есть аккаунт? Войти',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // --- Terms ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'By continuing, you agree to our Terms of Service\nand Privacy Policy',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFFA1A1AA),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        fontSize: 15,
        color: const Color(0xFFA1A1AA),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.flash_on_rounded,
          color: Colors.white,
          size: 36,
        ),
      ),
    );
  }

  Widget _buildContinueButton(bool isAnyLoading) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
          ),
        ),
        child: ElevatedButton(
          onPressed: isAnyLoading ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'Зарегистрироваться',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton(bool isAnyLoading) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: isAnyLoading ? null : _handleGoogleSignIn,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFE4E4E7), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isGoogleLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.language,
                    size: 20,
                    color: Color(0xFF18181B),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Continue with Google',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF18181B),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAppleButton(bool isAnyLoading) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isAnyLoading ? null : _handleAppleSignIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF18181B),
          disabledBackgroundColor:
              const Color(0xFF18181B).withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.apple,
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Text(
              'Continue with Apple',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
