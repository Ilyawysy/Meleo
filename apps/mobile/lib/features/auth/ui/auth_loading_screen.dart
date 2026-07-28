import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AuthLoadingScreen extends StatelessWidget {
  final String? message;

  const AuthLoadingScreen({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
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
            ),
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
            const SizedBox(height: 32),
            const CircularProgressIndicator(
              color: Color(0xFF2563EB),
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 16),
            Text(
              message ?? 'Загружаем профиль...',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFFA1A1AA),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
