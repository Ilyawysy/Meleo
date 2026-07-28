import 'package:flutter/material.dart';

abstract final class AppColors {
  // Primary
  static const primaryBlue = Color(0xFF2563EB);
  static const primaryBlueLight = Color(0xFF3B82F6);

  // Gradient
  static const gradientStart = Color(0xFF2563EB);
  static const gradientEnd = Color(0xFF3B82F6);
  static const gradientLogo = [Color(0xFF2563EB), Color(0xFF7C3AED)];

  // Backgrounds
  static const white = Color(0xFFFFFFFF);
  static const greyBg = Color(0xFFF8F8FA);
  static const greyBgDarker = Color(0xFFF4F4F5);
  static const dayStatusBg = Color(0xFFEFF6FF);
  static const overlay = Color(0x66000000);

  // Borders & dividers
  static const border = Color(0xFFE4E4E7);
  static const divider = Color(0xFFEBEBEF);

  // Text
  static const textDark = Color(0xFF18181B);
  static const textMedium = Color(0xFF71717A);
  static const textLight = Color(0xFFA1A1AA);
  static const textSlate = Color(0xFF64748B);
  static const textSlateLight = Color(0xFF94A3B8);

  // Error / destructive
  static const error = Color(0xFFEF4444);
  static const errorDark = Color(0xFFDC2626);

  // Priority — High
  static const priorityHighBg = Color(0xFFFEF2F2);
  static const priorityHighText = Color(0xFFDC2626);

  // Priority — Medium
  static const priorityMedBg = Color(0xFFFEF3C7);
  static const priorityMedText = Color(0xFFD97706);

  // Priority — Low
  static const priorityLowBg = Color(0xFFF0FDF4);
  static const priorityLowText = Color(0xFF16A34A);

  // FAB
  static const fabAi = Color(0xFF7C3AED);
}
