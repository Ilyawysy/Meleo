import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/auth_service.dart';
import '../data/models/token_response.dart';

class RegisterVerifyCodeScreen extends StatefulWidget {
  final String email;
  final Function(TokenResponse tokenResponse) onOtpVerified;
  final VoidCallback? onBack;

  const RegisterVerifyCodeScreen({
    super.key,
    required this.email,
    required this.onOtpVerified,
    this.onBack,
  });

  @override
  State<RegisterVerifyCodeScreen> createState() =>
      _RegisterVerifyCodeScreenState();
}

class _RegisterVerifyCodeScreenState extends State<RegisterVerifyCodeScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  bool _isResending = false;
  String? _error;

  // Resend countdown
  Timer? _resendTimer;
  int _resendCountdown = 60;
  bool get _canResend => _resendCountdown <= 0 && !_isResending && !_isLoading;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    // Auto-focus first field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (var c in _controllers) {
      c.dispose();
    }
    for (var n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _resendCountdown = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) {
          timer.cancel();
        }
      });
    });
  }

  void _onCodeChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    // Auto-verify when all 6 digits entered
    if (_controllers.every((c) => c.text.isNotEmpty)) {
      _verifyCode();
    }
  }

  Future<void> _verifyCode() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length != 6) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      debugPrint('[OTP] Verifying OTP...');
      final authService = AuthService();
      final tokenResponse = await authService.verifySignupOtp(
        email: widget.email,
        token: code,
      );
      debugPrint('[OTP] OTP verified');
      final session = Supabase.instance.client.auth.currentSession;
      debugPrint('expiresAt: ${session?.expiresAt}');

      if (mounted) {
        widget.onOtpVerified(tokenResponse);
      }
    } catch (e) {
      debugPrint('[OTP] Verification failed: $e');
      if (mounted) {
        setState(() {
          _error = 'Incorrect code. Please try again.';
          for (var c in _controllers) {
            c.clear();
          }
          _focusNodes[0].requestFocus();
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;

    setState(() {
      _isResending = true;
      _error = null;
    });

    try {
      debugPrint('[OTP] Resending OTP...');
      final authService = AuthService();
      await authService.resendSignupOtp(email: widget.email);
      debugPrint('[OTP] OTP resent');

      if (mounted) {
        _startResendTimer();
        for (var c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
      }
    } catch (e) {
      debugPrint('[OTP] Resend failed: $e');
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('AuthException: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // --- Back Button ---
              _buildBackButton(),

              const SizedBox(height: 36),

              // --- Header ---
              Text(
                'Check your email',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF18181B),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: const Color(0xFFA1A1AA),
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'We sent a verification code to\n'),
                    TextSpan(
                      text: widget.email,
                      style: const TextStyle(color: Color(0xFF71717A)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // --- Code Input ---
              _buildCodeInput(),

              const SizedBox(height: 24),

              // --- Error ---
              if (_error != null)
                Center(
                  child: Text(
                    _error!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFEF4444),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              if (_error != null) const SizedBox(height: 24),

              // --- Loading indicator ---
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),

              // --- Resend Row ---
              _buildResendRow(),

              const SizedBox(height: 24),

              // --- Auto verify note ---
              Center(
                child: Text(
                  'Code will verify automatically when complete',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFFA1A1AA),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () {
        if (widget.onBack != null) {
          widget.onBack!();
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFE4E4E7),
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.arrow_back,
            size: 20,
            color: Color(0xFF18181B),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeInput() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final hasValue = _controllers[index].text.isNotEmpty;
        return Container(
          width: 50,
          height: 60,
          margin: EdgeInsets.only(right: index < 5 ? 12 : 0),
          child: TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            enabled: !_isLoading,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF18181B),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              counterText: '',
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: hasValue
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFE4E4E7),
                  width: hasValue ? 2 : 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: hasValue
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFE4E4E7),
                  width: hasValue ? 2 : 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF2563EB),
                  width: 2,
                ),
              ),
            ),
            onChanged: (value) => _onCodeChanged(index, value),
          ),
        );
      }),
    );
  }

  Widget _buildResendRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Didn't receive the code?",
          style: GoogleFonts.inter(
            fontSize: 14,
            color: const Color(0xFF71717A),
          ),
        ),
        const SizedBox(width: 4),
        if (_canResend)
          GestureDetector(
            onTap: _resendCode,
            child: Text(
              'Resend',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF2563EB),
              ),
            ),
          )
        else
          Text(
            'Resend in ${_resendCountdown}s',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFA1A1AA),
            ),
          ),
      ],
    );
  }
}
