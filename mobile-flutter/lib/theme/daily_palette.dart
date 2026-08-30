import 'package:flutter/material.dart';

/// Design tokens for the daily-record hub (หน้าบันทึกประจำวัน) — minimal white.
abstract final class DailyPalette {
  // ── Surfaces ──────────────────────────────────────────────────────────────
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
}
