import 'package:flutter/material.dart';

/// Full brand lockup: gold mole + FOR USER / GOLDEN MOLE (`assets/branding/app_logo.png`)
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 88,
    this.semanticLabel = 'โลโก้แอป',
  });

  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Image.asset(
        'assets/branding/app_logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
