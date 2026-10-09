import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const kMaxContentWidth = 1100.0;

/// Pull-to-refresh scroll body centred at [maxWidth].
class PageScroll extends StatelessWidget {
  const PageScroll({
    super.key,
    required this.children,
    this.slivers = const [],
    this.onRefresh,
    this.bottomPadding = 24,
    this.maxWidth = kMaxContentWidth,
  });
  final List<Widget> children;

  /// Lazily built content placed after [children], e.g. a [SliverCardList] of long lists.
  final List<Widget> slivers;
  final Future<void> Function()? onRefresh;
  final double bottomPadding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(16.0, (width - maxWidth) / 2);
    final list = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, 16, side, slivers.isEmpty ? bottomPadding : 0),
          sliver: SliverList.list(children: children),
        ),
        for (final s in slivers) SliverPadding(padding: EdgeInsets.symmetric(horizontal: side), sliver: s),
        if (slivers.isNotEmpty) SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                  ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}

/// Lays out [children] in [columns] equal columns (KPI grids, menu cards).
class GridRows extends StatelessWidget {
  const GridRows({super.key, required this.columns, required this.children, this.gap = 12});
  final int columns;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final cells = <Widget>[];
      for (var j = 0; j < columns; j++) {
        if (j > 0) cells.add(SizedBox(width: gap));
        final k = i + j;
        cells.add(Expanded(child: k < children.length ? children[k] : const SizedBox.shrink()));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}
