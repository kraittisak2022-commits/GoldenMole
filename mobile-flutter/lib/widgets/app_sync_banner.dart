import 'package:flutter/material.dart';

/// เดิมเป็นแถบสถานะซิงค์ทับทั้งแอป — ตอนนี้ส่งต่อ [child] อย่างเดียว
/// (ซิงค์ออฟไลน์ยังทำงานเงียบ ๆ ผ่าน CountRecordOfflineSync)
class AppSyncBannerHost extends StatelessWidget {
  const AppSyncBannerHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
