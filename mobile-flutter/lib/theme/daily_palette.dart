import 'package:flutter/material.dart';

/// Design tokens for the daily-record hub (หน้าบันทึกประจำวัน).
abstract final class DailyPalette {
  // ── Surfaces ──────────────────────────────────────────────────────────────
  static const surfaceTop = Color(0xFFF8FBFD);
  static const surfaceBottom = Color(0xFFEDF3F7);
  static const cardTop = Color(0xFFFFFFFF);
  static const cardBottom = Color(0xFFF7FAFC);
  static const cardSubtle = Color(0xFFF1F7FA);

  // ── Lines & shadows ───────────────────────────────────────────────────────
  static const hairline = Color(0xFFE2E8F0);
  static const shadowSoft = Color(0x0F0F172A);
  static const shadowTight = Color(0x0A0F172A);

  // ── Typography ────────────────────────────────────────────────────────────
  static const ink = Color(0xFF0B1B2B);
  static const inkMuted = Color(0xFF64748B);
  static const inkSubtle = Color(0xFF475569);

  // ── Brand teal ────────────────────────────────────────────────────────────
  static const brand = Color(0xFF0D98A5);
  static const brandDeep = Color(0xFF067A87);
  static const brandGlow = Color(0xFF22D3EE);
  static const brandBorder = Color(0xFFB6E4EA);
  static const brandChipTop = Color(0xFFF0FDFA);
  static const brandChipBottom = Color(0xFFFFFFFF);
  static const brandDateInk = Color(0xFF0A6270);
  static const brandSurface = Color(0xFFF1F5F9);
  static const grabber = Color(0xFFCBD5E1);

  // ── Status ────────────────────────────────────────────────────────────────
  static const statusComplete = Color(0xFF047857);
  static const statusCompleteBg = Color(0xFFECFDF5);
  static const statusCompleteBorder = Color(0xFFA7F3D0);
  static const statusIncomplete = Color(0xFFB45309);
  static const statusIncompleteBorder = Color(0xFFFDE68A);
  static const statusIncompleteDot = Color(0xFFF59E0B);
  static const statusPending = Color(0xFF94A3B8);
  static const statusPendingDot = Color(0xFFCBD5E1);

  // ── Module accents (11 + count/record) ────────────────────────────────────
  static const moduleAttendance = Color(0xFF0D9488);
  static const moduleSandSieve = Color(0xFFDB2777);
  static const moduleTrip = Color(0xFF0284C7);
  static const moduleMacro = Color(0xFFF59E0B);
  static const moduleFuel = Color(0xFFEA580C);
  static const moduleEvent = Color(0xFFDC2626);
  static const moduleLabor = Color(0xFF7C3AED);
  static const moduleOt = Color(0xFFE11D48);
  static const moduleLeave = Color(0xFF0891B2);
  static const moduleAdvance = Color(0xFF16A34A);
  static const moduleIncomeExpense = Color(0xFF4F46E5);
  static const moduleCountRecord = Color(0xFF1D4ED8);

  // ── Count-record panels ───────────────────────────────────────────────────
  static const countTripIcon = Color(0xFF1D4ED8);
  static const countTripBg = Color(0xFFEFF6FF);
  static const countTripBorder = Color(0xFFBFDBFE);
  static const countSandIcon = Color(0xFFBE185D);
  static const countSandBg = Color(0xFFFDF2F8);
  static const countSandBorder = Color(0xFFFBCFE8);
  static const countBothIconTile = Color(0xFFE0F7FA);

  /// Pending card border tinted with module accent.
  static Color moduleBorder(Color accent) {
    return Color.lerp(hairline, accent, 0.28)!;
  }

  /// Icon halo background behind module icons.
  static Color iconHaloFill(Color accent) {
    return accent.withValues(alpha: 0.10);
  }

  /// Icon halo border.
  static Color iconHaloBorder(Color accent) {
    return accent.withValues(alpha: 0.18);
  }

  static const surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [surfaceTop, surfaceBottom],
  );

  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cardTop, cardBottom],
  );

  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cardTop, cardSubtle],
  );

  static const brandAccentBar = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [brandGlow, brand, brandDeep],
  );

  static const dateChipGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandChipTop, brandChipBottom],
  );

  static const brandIconGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand, brandDeep],
  );
}
