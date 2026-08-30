import 'package:flutter/material.dart';

/// Design tokens for the daily-record hub (หน้าบันทึกประจำวัน).
///
/// Static consts remain the **light** defaults (module accents, status, etc.).
/// For surfaces/ink that must adapt, use [DailyPalette.of] / [DailyColors].
abstract final class DailyPalette {
  // ── Surfaces (light defaults) ─────────────────────────────────────────────
  static const surface = Color(0xFFF7F8FA);
  static const card = Color(0xFFFFFFFF);
  static const chipSurface = Color(0xFFF4F6F8);

  // ── Lines & shadows ───────────────────────────────────────────────────────
  static const hairline = Color(0xFFE2E8F0);
  static const shadowCard = Color(0x0D0F172A);
  static const shadowLift = Color(0x140F172A);

  // ── Typography ────────────────────────────────────────────────────────────
  static const ink = Color(0xFF0B1B2B);
  static const inkMuted = Color(0xFF64748B);
  static const inkSubtle = Color(0xFF475569);

  // ── Brand teal ────────────────────────────────────────────────────────────
  static const brand = Color(0xFF0D98A5);
  static const brandDeep = Color(0xFF067A87);
  static const brandGlow = Color(0xFF22D3EE);
  static const brandBorder = Color(0xFFB6E4EA);
  static const brandDateInk = Color(0xFF0A6270);
  static const brandSurface = Color(0xFFF1F5F9);
  static const grabber = Color(0xFFCBD5E1);

  // ── Status (text / dots only) ─────────────────────────────────────────────
  static const statusComplete = Color(0xFF047857);
  static const statusIncomplete = Color(0xFFB45309);
  static const statusIncompleteDot = Color(0xFFF59E0B);
  static const statusPending = Color(0xFF94A3B8);

  // ── Module accents (11 + count/record) — icons only ───────────────────────
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
  static const moduleMaintenance = Color(0xFFB45309);
  static const moduleCountRecord = Color(0xFF1D4ED8);

  // ── Count-record icons ────────────────────────────────────────────────────
  static const countTripIcon = Color(0xFF1D4ED8);
  static const countSandIcon = Color(0xFFBE185D);

  /// Theme-aware surface / ink tokens (registered on [ThemeData.extensions]).
  static DailyColors of(BuildContext context) => DailyColors.of(context);
}

/// Theme-aware daily hub colors — intentional dark surfaces, readable ink,
/// brand teal preserved (slightly lifted on dark for contrast).
@immutable
class DailyColors extends ThemeExtension<DailyColors> {
  const DailyColors({
    required this.surface,
    required this.card,
    required this.chipSurface,
    required this.hairline,
    required this.shadowCard,
    required this.shadowLift,
    required this.ink,
    required this.inkMuted,
    required this.inkSubtle,
    required this.brand,
    required this.brandDeep,
    required this.brandGlow,
    required this.brandBorder,
    required this.brandDateInk,
    required this.brandSurface,
    required this.grabber,
    required this.statusComplete,
    required this.statusIncomplete,
    required this.statusPending,
  });

  final Color surface;
  final Color card;
  final Color chipSurface;
  final Color hairline;
  final Color shadowCard;
  final Color shadowLift;
  final Color ink;
  final Color inkMuted;
  final Color inkSubtle;
  final Color brand;
  final Color brandDeep;
  final Color brandGlow;
  final Color brandBorder;
  final Color brandDateInk;
  final Color brandSurface;
  final Color grabber;
  final Color statusComplete;
  final Color statusIncomplete;
  final Color statusPending;

  static const light = DailyColors(
    surface: DailyPalette.surface,
    card: DailyPalette.card,
    chipSurface: DailyPalette.chipSurface,
    hairline: DailyPalette.hairline,
    shadowCard: DailyPalette.shadowCard,
    shadowLift: DailyPalette.shadowLift,
    ink: DailyPalette.ink,
    inkMuted: DailyPalette.inkMuted,
    inkSubtle: DailyPalette.inkSubtle,
    brand: DailyPalette.brand,
    brandDeep: DailyPalette.brandDeep,
    brandGlow: DailyPalette.brandGlow,
    brandBorder: DailyPalette.brandBorder,
    brandDateInk: DailyPalette.brandDateInk,
    brandSurface: DailyPalette.brandSurface,
    grabber: DailyPalette.grabber,
    statusComplete: DailyPalette.statusComplete,
    statusIncomplete: DailyPalette.statusIncomplete,
    statusPending: DailyPalette.statusPending,
  );

  /// Deep slate surfaces — not washed grey; teal/gold accents stay vivid.
  static const dark = DailyColors(
    surface: Color(0xFF0B1219),
    card: Color(0xFF15202B),
    chipSurface: Color(0xFF1C2A38),
    hairline: Color(0xFF2A3A4A),
    shadowCard: Color(0x66000000),
    shadowLift: Color(0x80000000),
    ink: Color(0xFFF1F5F9),
    inkMuted: Color(0xFF94A3B8),
    inkSubtle: Color(0xFFCBD5E1),
    brand: Color(0xFF2EC4D4),
    brandDeep: Color(0xFF11A8BA),
    brandGlow: Color(0xFF22D3EE),
    brandBorder: Color(0xFF1A5A66),
    brandDateInk: Color(0xFF7EE8F0),
    brandSurface: Color(0xFF132A33),
    grabber: Color(0xFF475569),
    statusComplete: Color(0xFF34D399),
    statusIncomplete: Color(0xFFFBBF24),
    statusPending: Color(0xFF64748B),
  );

  static DailyColors of(BuildContext context) {
    return Theme.of(context).extension<DailyColors>() ?? light;
  }

  @override
  DailyColors copyWith({
    Color? surface,
    Color? card,
    Color? chipSurface,
    Color? hairline,
    Color? shadowCard,
    Color? shadowLift,
    Color? ink,
    Color? inkMuted,
    Color? inkSubtle,
    Color? brand,
    Color? brandDeep,
    Color? brandGlow,
    Color? brandBorder,
    Color? brandDateInk,
    Color? brandSurface,
    Color? grabber,
    Color? statusComplete,
    Color? statusIncomplete,
    Color? statusPending,
  }) {
    return DailyColors(
      surface: surface ?? this.surface,
      card: card ?? this.card,
      chipSurface: chipSurface ?? this.chipSurface,
      hairline: hairline ?? this.hairline,
      shadowCard: shadowCard ?? this.shadowCard,
      shadowLift: shadowLift ?? this.shadowLift,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkSubtle: inkSubtle ?? this.inkSubtle,
      brand: brand ?? this.brand,
      brandDeep: brandDeep ?? this.brandDeep,
      brandGlow: brandGlow ?? this.brandGlow,
      brandBorder: brandBorder ?? this.brandBorder,
      brandDateInk: brandDateInk ?? this.brandDateInk,
      brandSurface: brandSurface ?? this.brandSurface,
      grabber: grabber ?? this.grabber,
      statusComplete: statusComplete ?? this.statusComplete,
      statusIncomplete: statusIncomplete ?? this.statusIncomplete,
      statusPending: statusPending ?? this.statusPending,
    );
  }

  @override
  DailyColors lerp(ThemeExtension<DailyColors>? other, double t) {
    if (other is! DailyColors) return this;
    return DailyColors(
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      chipSurface: Color.lerp(chipSurface, other.chipSurface, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      shadowCard: Color.lerp(shadowCard, other.shadowCard, t)!,
      shadowLift: Color.lerp(shadowLift, other.shadowLift, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkSubtle: Color.lerp(inkSubtle, other.inkSubtle, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandDeep: Color.lerp(brandDeep, other.brandDeep, t)!,
      brandGlow: Color.lerp(brandGlow, other.brandGlow, t)!,
      brandBorder: Color.lerp(brandBorder, other.brandBorder, t)!,
      brandDateInk: Color.lerp(brandDateInk, other.brandDateInk, t)!,
      brandSurface: Color.lerp(brandSurface, other.brandSurface, t)!,
      grabber: Color.lerp(grabber, other.grabber, t)!,
      statusComplete: Color.lerp(statusComplete, other.statusComplete, t)!,
      statusIncomplete:
          Color.lerp(statusIncomplete, other.statusIncomplete, t)!,
      statusPending: Color.lerp(statusPending, other.statusPending, t)!,
    );
  }
}
