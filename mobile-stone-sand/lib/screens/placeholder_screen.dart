import 'package:flutter/material.dart';

import '../widgets/ui.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: EmptyState('กำลังพัฒนา')),
    );
  }
}
