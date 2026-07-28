import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

abstract final class AppTypography {
  // --- Plus Jakarta Sans (headings) ---

  static TextStyle heading30({Color color = AppColors.textDark}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.8,
      );

  static TextStyle heading22({Color color = AppColors.textDark}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: color,
      );

  static TextStyle heading18({Color color = AppColors.textDark}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: color,
      );

  static TextStyle heading16({Color color = AppColors.textDark}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: color,
      );

  static TextStyle heading15({Color color = AppColors.textDark}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle heading20({Color color = AppColors.textDark}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: color,
      );

  // --- Inter (body / UI) ---

  static TextStyle body17({
    Color color = AppColors.textDark,
    FontWeight fontWeight = FontWeight.w500,
  }) =>
      GoogleFonts.inter(
        fontSize: 17,
        fontWeight: fontWeight,
        color: color,
      );

  static TextStyle body15({
    Color color = AppColors.textDark,
    FontWeight fontWeight = FontWeight.w400,
  }) =>
      GoogleFonts.inter(
        fontSize: 15,
        fontWeight: fontWeight,
        color: color,
      );

  static TextStyle body14({
    Color color = AppColors.textDark,
    FontWeight fontWeight = FontWeight.w400,
  }) =>
      GoogleFonts.inter(
        fontSize: 14,
        fontWeight: fontWeight,
        color: color,
      );

  static TextStyle body13({
    Color color = AppColors.textMedium,
    FontWeight fontWeight = FontWeight.w500,
  }) =>
      GoogleFonts.inter(
        fontSize: 13,
        fontWeight: fontWeight,
        color: color,
      );

  static TextStyle caption12({Color color = AppColors.textLight}) =>
      GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle caption11({Color color = AppColors.textLight}) =>
      GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle label10({Color color = AppColors.textLight}) =>
      GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.5,
      );

  static TextStyle sectionTitle({Color color = AppColors.textDark}) =>
      GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: color,
      );
}
