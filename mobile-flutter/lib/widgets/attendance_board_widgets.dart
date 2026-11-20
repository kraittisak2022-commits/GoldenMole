import 'package:flutter/material.dart';

import '../theme/daily_palette.dart';
import '../utils/app_haptics.dart';
import '../utils/attendance_board_summary.dart';
import 'app_theme_scope.dart';

/// ข้อมูลรายชื่อในพูลรอเช็คชื่อ
class AttendancePoolPerson {
  const AttendancePoolPerson({
    required this.id,
    required this.displayName,
    required this.selected,
    this.placed = false,
  });

  final String id;
  final String displayName;
  final bool selected;
  final bool placed;
}

/// ปุ่มย้ายด่วนในแถบ Selection Bar เมื่อมีการเลือกรายชื่อ
class AttendanceQuickAssignTarget {
  const AttendanceQuickAssignTarget({
    required this.bucketId,
    required this.label,
    required this.color,
    required this.icon,
  });

  final String bucketId;
  final String label;
  final Color color;
  final IconData icon;
}

/// ชิปพนักงานที่อยู่ในช่องดรอป (active)
class AttendancePlacedChipData {
  const AttendancePlacedChipData({
    required this.empId,
    required this.displayName,
    this.timeRange,
    this.isTimedWork = true,
    this.justDropped = false,
  });

  final String empId;
  final String displayName;
  final String? timeRange;
  final bool isTimedWork;
  final bool justDropped;
}

/// ชิปเซสชันเวลาที่ปิดรอบแล้ว (ย้ายออกจากช่องเดิมแล้ว)
class AttendanceClosedSessionChipData {
  const AttendanceClosedSessionChipData({
    required this.sessionIndex,
    required this.displayName,
    required this.timeRange,
  });

  final int sessionIndex;
  final String displayName;
  final String timeRange;
}

/// นิยามช่องดรอปย่อยภายในการ์ดเช็คชื่อ
class AttendanceZoneSlotData {
  const AttendanceZoneSlotData({
    required this.bucketId,
    required this.label,
    required this.emptyHint,
    required this.activeChips,
    required this.closedSessions,
  });

  final String bucketId;
  final String label;
  final String emptyHint;
  final List<AttendancePlacedChipData> activeChips;
  final List<AttendanceClosedSessionChipData> closedSessions;
}

/// แถบหัวกระดานเช็คชื่อแบบเต็มจอ พร้อมแถบความคืบหน้า + ปุ่มสลับกลุ่มใน 1 แตะ
class AttendanceBoardHeader extends StatelessWidget {
  const AttendanceBoardHeader({
    super.key,
    required this.title,
    required this.dateLabel,
    required this.progress,
    required this.switchLabel,
    required this.onBack,
    required this.onSwitchSection,
  });

  final String title;
  final String dateLabel;
  final AttendanceGroupProgress progress;
  final String switchLabel;
  final VoidCallback onBack;
  final VoidCallback onSwitchSection;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final size = MediaQuery.sizeOf(context);
    final phonePortrait = size.shortestSide < 600 && size.height >= size.width;
    final barColor = progress.isComplete ? p.statusComplete : p.brand;

    return Material(
      color: p.card,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              phonePortrait ? 4 : 10,
              phonePortrait ? 4 : 6,
              phonePortrait ? 10 : 14,
              phonePortrait ? 6 : 8,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  tooltip: 'ย้อนกลับ',
                  iconSize: phonePortrait ? 22 : 26,
                  style: IconButton.styleFrom(
                    minimumSize: Size(
                      phonePortrait ? 44 : 48,
                      phonePortrait ? 44 : 48,
                    ),
                    padding: EdgeInsets.all(phonePortrait ? 8 : 10),
                  ),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  color: p.ink,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: phonePortrait ? 17.5 : 21,
                          fontWeight: FontWeight.w800,
                          color: p.ink,
                          height: 1.15,
                          letterSpacing: -0.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: p.inkMuted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              progress.totalCount > 0
                                  ? '$dateLabel · เช็คแล้ว ${progress.checkedCount}/${progress.totalCount} คน'
                                  : dateLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: phonePortrait ? 12 : 13.5,
                                fontWeight: FontWeight.w600,
                                color: progress.isComplete
                                    ? p.statusComplete
                                    : p.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  color: p.brandSurface,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onSwitchSection,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: phonePortrait ? 10 : 12,
                        vertical: phonePortrait ? 7 : 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: p.brandBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: 16,
                            color: p.brandDateInk,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            switchLabel,
                            style: TextStyle(
                              fontSize: phonePortrait ? 12 : 13,
                              fontWeight: FontWeight.w700,
                              color: p.brandDateInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (progress.totalCount > 0)
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: progress.ratio),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              builder: (context, val, _) => LinearProgressIndicator(
                value: val,
                minHeight: 3,
                backgroundColor: isDark
                    ? const Color(0xFF1F2E3D)
                    : const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            )
          else
            Divider(height: 1, color: p.hairline),
        ],
      ),
    );
  }
}

/// แถบคำสั่งด่วนเมื่อแตะเลือกรายชื่อ 1 คนขึ้นไป — ย้ายลงกล่องได้ใน 1 แตะ
class AttendanceSelectionBar extends StatelessWidget {
  const AttendanceSelectionBar({
    super.key,
    required this.selectedCount,
    required this.targets,
    required this.onAssignToBucket,
    required this.onClearSelection,
  });

  final int selectedCount;
  final List<AttendanceQuickAssignTarget> targets;
  final ValueChanged<String> onAssignToBucket;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final size = MediaQuery.sizeOf(context);
    final phonePortrait = size.shortestSide < 600 && size.height >= size.width;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: selectedCount <= 0
          ? const SizedBox.shrink()
          : Container(
              margin: EdgeInsets.only(bottom: phonePortrait ? 6 : 8),
              padding: EdgeInsets.fromLTRB(
                phonePortrait ? 10 : 12,
                phonePortrait ? 8 : 10,
                phonePortrait ? 10 : 12,
                phonePortrait ? 8 : 10,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF132D36)
                    : const Color(0xFFECFEFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: p.brand.withValues(alpha: isDark ? 0.55 : 0.45),
                  width: 1.3,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 17,
                        color: p.brand,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'เลือกอยู่ $selectedCount คน · แตะเลือกช่องปลายทาง',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: phonePortrait ? 12.5 : 13.5,
                            fontWeight: FontWeight.w700,
                            color: p.ink,
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onClearSelection,
                        child: Text(
                          'ยกเลิก',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: p.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < targets.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _QuickTargetButton(
                            target: targets[i],
                            compact: phonePortrait,
                            isDark: isDark,
                            onTap: () => onAssignToBucket(targets[i].bucketId),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _QuickTargetButton extends StatelessWidget {
  const _QuickTargetButton({
    required this.target,
    required this.compact,
    required this.isDark,
    required this.onTap,
  });

  final AttendanceQuickAssignTarget target;
  final bool compact;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = target.color;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 11 : 14,
            vertical: compact ? 8 : 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(target.icon, size: 16, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                target.label,
                style: TextStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// พูลรายชื่อพนักงานที่รอเช็คชื่อ — มีปุ่มเลือกทั้งหมด + ค้นหา + รองรับลากกลับ
class AttendancePoolPanel extends StatelessWidget {
  const AttendancePoolPanel({
    super.key,
    required this.title,
    required this.remainingCount,
    required this.totalGroupCount,
    required this.visiblePeople,
    required this.selectedCount,
    required this.searchOpen,
    required this.searchQuery,
    required this.searchController,
    required this.scrollController,
    required this.accent,
    required this.emptyConfigText,
    required this.onToggleSearch,
    required this.onSearchChanged,
    required this.onSelectAllRemaining,
    required this.onClearSelection,
    required this.onTogglePerson,
    required this.onAcceptDropBack,
    this.dragDelay = const Duration(milliseconds: 120),
  });

  final String title;
  final int remainingCount;
  final int totalGroupCount;
  final List<AttendancePoolPerson> visiblePeople;
  final int selectedCount;
  final bool searchOpen;
  final String searchQuery;
  final TextEditingController searchController;
  final ScrollController scrollController;
  final Color accent;
  final String emptyConfigText;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSelectAllRemaining;
  final VoidCallback onClearSelection;
  final ValueChanged<String> onTogglePerson;
  final ValueChanged<String> onAcceptDropBack;
  final Duration dragDelay;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final size = MediaQuery.sizeOf(context);
    final phonePortrait = size.shortestSide < 600 && size.height >= size.width;
    final allChecked = totalGroupCount > 0 && remainingCount == 0;
    final showSearchToggle = remainingCount >= 4 || searchOpen;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allChecked
              ? p.statusComplete.withValues(alpha: isDark ? 0.5 : 0.4)
              : p.hairline,
          width: allChecked ? 1.3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: p.shadowCard,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: phonePortrait ? 10 : 12,
              vertical: phonePortrait ? 7 : 9,
            ),
            decoration: BoxDecoration(
              color: allChecked
                  ? p.statusComplete.withValues(alpha: isDark ? 0.16 : 0.08)
                  : p.chipSurface,
              border: Border(bottom: BorderSide(color: p.hairline)),
            ),
            child: Row(
              children: [
                Icon(
                  allChecked
                      ? Icons.verified_rounded
                      : Icons.people_alt_rounded,
                  size: phonePortrait ? 17 : 19,
                  color: allChecked ? p.statusComplete : accent,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: phonePortrait ? 14 : 15.5,
                            color: p.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (allChecked ? p.statusComplete : accent)
                              .withValues(alpha: isDark ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          allChecked ? 'ครบแล้ว' : 'เหลือ $remainingCount',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: allChecked ? p.statusComplete : accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showSearchToggle)
                  IconButton(
                    tooltip: searchOpen ? 'ปิดค้นหา' : 'ค้นหาชื่อ',
                    onPressed: onToggleSearch,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(34, 34),
                      padding: const EdgeInsets.all(4),
                    ),
                    icon: Icon(
                      searchOpen ? Icons.close_rounded : Icons.search_rounded,
                      size: 19,
                      color: searchOpen ? accent : p.inkMuted,
                    ),
                  ),
                if (remainingCount > 0) ...[
                  const SizedBox(width: 4),
                  Material(
                    color: selectedCount > 0
                        ? p.card
                        : accent.withValues(alpha: isDark ? 0.2 : 0.11),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: selectedCount > 0
                          ? onClearSelection
                          : onSelectAllRemaining,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selectedCount > 0
                                ? p.hairline
                                : accent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          selectedCount > 0
                              ? 'ล้าง ($selectedCount)'
                              : 'เลือกทั้งหมด',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: selectedCount > 0 ? p.inkMuted : accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'พิมพ์ชื่อเล่นหรือชื่อจริง...',
                  hintStyle: TextStyle(fontSize: 13.5, color: p.inkMuted),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: p.inkMuted,
                  ),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear_rounded,
                            size: 18,
                            color: p.inkMuted,
                          ),
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: p.chipSurface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: p.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: p.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: accent, width: 1.4),
                  ),
                ),
              ),
            ),
          Expanded(
            child: DragTarget<String>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (d) => onAcceptDropBack(d.data),
              builder: (context, cand, _) {
                final hovering = cand.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: double.infinity,
                  padding: EdgeInsets.all(phonePortrait ? 8 : 10),
                  color: hovering
                      ? accent.withValues(alpha: isDark ? 0.14 : 0.08)
                      : p.surface.withValues(alpha: isDark ? 0.55 : 0.65),
                  child: _buildBody(
                    context: context,
                    p: p,
                    isDark: isDark,
                    phonePortrait: phonePortrait,
                    allChecked: allChecked,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required DailyColors p,
    required bool isDark,
    required bool phonePortrait,
    required bool allChecked,
  }) {
    if (totalGroupCount == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            emptyConfigText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: phonePortrait ? 13 : 14,
              fontWeight: FontWeight.w500,
              color: p.inkMuted,
            ),
          ),
        ),
      );
    }

    if (allChecked) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: p.statusComplete.withValues(alpha: isDark ? 0.2 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 22,
                color: p.statusComplete,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'เช็คชื่อครบทั้ง $totalGroupCount คนแล้ว',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: phonePortrait ? 14 : 15.5,
                fontWeight: FontWeight.w800,
                color: p.statusComplete,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'ลากรายชื่อกลับมาวางที่นี่เพื่อนำออก',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: phonePortrait ? 11.5 : 12.5,
                fontWeight: FontWeight.w500,
                color: p.inkMuted,
              ),
            ),
          ],
        ),
      );
    }

    if (visiblePeople.isEmpty && searchQuery.trim().isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ไม่พบชื่อ "$searchQuery"',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: p.inkMuted,
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () {
                searchController.clear();
                onSearchChanged('');
              },
              child: const Text('ล้างคำค้นหา'),
            ),
          ],
        ),
      );
    }

    return Scrollbar(
      controller: scrollController,
      thumbVisibility: !phonePortrait,
      radius: const Radius.circular(8),
      child: SingleChildScrollView(
        controller: scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(right: phonePortrait ? 2 : 6),
        child: Wrap(
          spacing: phonePortrait ? 6 : 8,
          runSpacing: phonePortrait ? 7 : 9,
          children: [
            for (final person in visiblePeople)
              LongPressDraggable<String>(
                data: person.id,
                delay: dragDelay,
                onDragStarted: () => AppHaptics.tap(),
                feedback: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.transparent,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: phonePortrait ? 14 : 16,
                      vertical: phonePortrait ? 10 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.drag_indicator_rounded,
                          size: 18,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          person.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontSize: phonePortrait ? 15.5 : 17.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: _PoolPersonChip(
                    person: person,
                    accent: accent,
                    compact: phonePortrait,
                    isDark: isDark,
                    onTap: null,
                  ),
                ),
                child: _PoolPersonChip(
                  person: person,
                  accent: accent,
                  compact: phonePortrait,
                  isDark: isDark,
                  onTap: () {
                    AppHaptics.tap();
                    onTogglePerson(person.id);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PoolPersonChip extends StatelessWidget {
  const _PoolPersonChip({
    required this.person,
    required this.accent,
    required this.compact,
    required this.isDark,
    required this.onTap,
  });

  final AttendancePoolPerson person;
  final Color accent;
  final bool compact;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final selected = person.selected;
    final initials = attendanceInitialsOf(person.displayName);

    return Material(
      color: selected
          ? accent.withValues(alpha: isDark ? 0.26 : 0.14)
          : p.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.fromLTRB(
            compact ? 6 : 8,
            compact ? 6 : 8,
            compact ? 11 : 13,
            compact ? 6 : 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : p.hairline,
              width: selected ? 1.7 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: compact ? 24 : 28,
                height: compact ? 24 : 28,
                decoration: BoxDecoration(
                  color: selected
                      ? accent
                      : accent.withValues(alpha: isDark ? 0.2 : 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: Colors.white,
                      )
                    : Text(
                        initials,
                        style: TextStyle(
                          fontSize: compact ? 12 : 13.5,
                          fontWeight: FontWeight.w800,
                          color: accent,
                          height: 1,
                        ),
                      ),
              ),
              const SizedBox(width: 7),
              Text(
                person.displayName,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 14.5 : 16.5,
                  color: p.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// การ์ดกลุ่มปลายทาง (มาทำงาน / ขับแม็คโคร / ขับดรัม / ลางาน)
class AttendanceBoardCard extends StatelessWidget {
  const AttendanceBoardCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.zones,
    required this.pickedCount,
    required this.onTapZone,
    required this.onAcceptDrop,
    required this.onRemoveEmp,
    required this.onDeleteClosedSession,
    this.equalHeightZones = false,
    this.dragDelay = const Duration(milliseconds: 120),
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<AttendanceZoneSlotData> zones;
  final int pickedCount;
  final ValueChanged<String> onTapZone;
  final void Function(String bucketId, String empId) onAcceptDrop;
  final void Function(String bucketId, String empId) onRemoveEmp;
  final ValueChanged<int> onDeleteClosedSession;
  final bool equalHeightZones;
  final Duration dragDelay;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final size = MediaQuery.sizeOf(context);
    final phonePortrait = size.shortestSide < 600 && size.height >= size.width;
    final totalInCard = {
      for (final z in zones)
        for (final c in z.activeChips) c.empId,
    }.length;
    final isMultiZone = zones.length > 1;

    final zoneWidgets = <Widget>[];
    for (var i = 0; i < zones.length; i++) {
      if (i > 0) zoneWidgets.add(const SizedBox(height: 8));
      final zoneWidget = _AttendanceDropZone(
        zone: zones[i],
        color: color,
        pickedCount: pickedCount,
        showPersistentHeader: isMultiZone,
        expand: equalHeightZones,
        compact: phonePortrait,
        isDark: isDark,
        dragDelay: dragDelay,
        onTap: () => onTapZone(zones[i].bucketId),
        onAcceptDrop: (empId) => onAcceptDrop(zones[i].bucketId, empId),
        onRemoveEmp: (empId) => onRemoveEmp(zones[i].bucketId, empId),
        onDeleteClosedSession: onDeleteClosedSession,
      );
      zoneWidgets.add(equalHeightZones ? Expanded(child: zoneWidget) : zoneWidget);
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: pickedCount > 0
              ? color.withValues(alpha: isDark ? 0.65 : 0.55)
              : color.withValues(alpha: isDark ? 0.38 : 0.28),
          width: pickedCount > 0 ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 3.5, color: color),
          Padding(
            padding: EdgeInsets.fromLTRB(
              phonePortrait ? 10 : 12,
              phonePortrait ? 8 : 10,
              phonePortrait ? 10 : 12,
              phonePortrait ? 6 : 8,
            ),
            child: Row(
              children: [
                Container(
                  width: phonePortrait ? 28 : 32,
                  height: phonePortrait ? 28 : 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: phonePortrait ? 16 : 18,
                    color: color,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: phonePortrait ? 15.5 : 17.5,
                      color: p.ink,
                      height: 1.15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: totalInCard > 0
                        ? color.withValues(alpha: isDark ? 0.24 : 0.13)
                        : p.chipSurface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$totalInCard คน',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: totalInCard > 0 ? color : p.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                phonePortrait ? 8 : 10,
                0,
                phonePortrait ? 8 : 10,
                phonePortrait ? 8 : 10,
              ),
              child: equalHeightZones
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: zoneWidgets,
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: zoneWidgets,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceDropZone extends StatelessWidget {
  const _AttendanceDropZone({
    required this.zone,
    required this.color,
    required this.pickedCount,
    required this.showPersistentHeader,
    required this.expand,
    required this.compact,
    required this.isDark,
    required this.dragDelay,
    required this.onTap,
    required this.onAcceptDrop,
    required this.onRemoveEmp,
    required this.onDeleteClosedSession,
  });

  final AttendanceZoneSlotData zone;
  final Color color;
  final int pickedCount;
  final bool showPersistentHeader;
  final bool expand;
  final bool compact;
  final bool isDark;
  final Duration dragDelay;
  final VoidCallback onTap;
  final ValueChanged<String> onAcceptDrop;
  final ValueChanged<String> onRemoveEmp;
  final ValueChanged<int> onDeleteClosedSession;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final canMove = pickedCount > 0;
    final hasContent =
        zone.activeChips.isNotEmpty || zone.closedSessions.isNotEmpty;

    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => onAcceptDrop(d.data),
      builder: (context, cand, _) {
        final hovering = cand.isNotEmpty;
        final highlight = hovering || canMove;
        final bg = hovering
            ? color.withValues(alpha: isDark ? 0.22 : 0.14)
            : canMove
                ? color.withValues(alpha: isDark ? 0.09 : 0.05)
                : p.chipSurface;
        final borderColor = hovering
            ? color
            : canMove
                ? color.withValues(alpha: isDark ? 0.6 : 0.5)
                : color.withValues(alpha: isDark ? 0.24 : 0.2);

        final content = Material(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: canMove ? onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: double.infinity,
              constraints: BoxConstraints(minHeight: expand ? 0 : 58),
              padding: EdgeInsets.all(compact ? 8 : 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: borderColor,
                  width: highlight ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showPersistentHeader) ...[
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            zone.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 12.5 : 13.5,
                              fontWeight: FontWeight.w800,
                              color: p.inkSubtle,
                            ),
                          ),
                        ),
                        if (canMove)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '+ วาง $pickedCount คน',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          )
                        else if (zone.activeChips.isNotEmpty)
                          Text(
                            '${zone.activeChips.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (expand)
                    Expanded(
                      child: _buildInner(
                        p: p,
                        hasContent: hasContent,
                        canMove: canMove,
                        hovering: hovering,
                      ),
                    )
                  else
                    _buildInner(
                      p: p,
                      hasContent: hasContent,
                      canMove: canMove,
                      hovering: hovering,
                    ),
                ],
              ),
            ),
          ),
        );

        return expand ? SizedBox.expand(child: content) : content;
      },
    );
  }

  Widget _buildInner({
    required DailyColors p,
    required bool hasContent,
    required bool canMove,
    required bool hovering,
  }) {
    if (!hasContent) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hovering || canMove
                  ? Icons.add_circle_outline_rounded
                  : Icons.touch_app_outlined,
              size: 16,
              color: hovering || canMove ? color : p.inkMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                hovering
                    ? 'ปล่อยเพื่อวางที่นี่'
                    : canMove
                        ? 'แตะวาง $pickedCount คนที่นี่'
                        : zone.emptyHint,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 13 : 14.5,
                  fontWeight: hovering || canMove
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: hovering || canMove ? color : p.inkMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final chips = <Widget>[
      for (final item in zone.activeChips)
        _PlacedActiveChip(
          item: item,
          color: color,
          compact: compact,
          isDark: isDark,
          dragDelay: dragDelay,
          onRemove: () => onRemoveEmp(item.empId),
        ),
      for (final closed in zone.closedSessions)
        _PlacedClosedChip(
          item: closed,
          color: color,
          compact: compact,
          isDark: isDark,
          onDelete: () => onDeleteClosedSession(closed.sessionIndex),
        ),
    ];

    final wrap = Wrap(spacing: 6, runSpacing: 6, children: chips);
    if (!expand) return wrap;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: wrap,
    );
  }
}

class _PlacedActiveChip extends StatelessWidget {
  const _PlacedActiveChip({
    required this.item,
    required this.color,
    required this.compact,
    required this.isDark,
    required this.dragDelay,
    required this.onRemove,
  });

  final AttendancePlacedChipData item;
  final Color color;
  final bool compact;
  final bool isDark;
  final Duration dragDelay;
  final VoidCallback onRemove;

  Widget _pill(DailyColors p, {bool showRemove = true}) {
    final time = item.timeRange?.trim() ?? '';
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 9 : 11,
        compact ? 6 : 7,
        showRemove ? (compact ? 4 : 6) : (compact ? 9 : 11),
        compact ? 6 : 7,
      ),
      decoration: BoxDecoration(
        color: isDark ? p.card : Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.52 : 0.4),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: item.isTimedWork ? p.statusComplete : color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            item.displayName,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: compact ? 14.5 : 16,
              color: p.ink,
            ),
          ),
          if (time.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                time,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
          if (showRemove) ...[
            const SizedBox(width: 4),
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: compact ? 16 : 18,
                    color: p.inkMuted,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final labelWithTime = (item.timeRange?.trim().isNotEmpty ?? false)
        ? '${item.displayName} · ${item.timeRange}'
        : item.displayName;
    return LongPressDraggable<String>(
      data: item.empId,
      delay: dragDelay,
      onDragStarted: () => AppHaptics.tap(),
      feedback: Material(
        color: Colors.transparent,
        elevation: 8,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            labelWithTime,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _pill(p, showRemove: false),
      ),
      child: AnimatedScale(
        scale: item.justDropped ? 1.07 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: _pill(p),
      ),
    );
  }
}

class _PlacedClosedChip extends StatelessWidget {
  const _PlacedClosedChip({
    required this.item,
    required this.color,
    required this.compact,
    required this.isDark,
    required this.onDelete,
  });

  final AttendanceClosedSessionChipData item;
  final Color color;
  final bool compact;
  final bool isDark;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 10,
        compact ? 5 : 6,
        compact ? 4 : 6,
        compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.3 : 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            '${item.displayName} · ${item.timeRange}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: compact ? 13 : 14,
              color: p.inkSubtle,
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: p.inkMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// แถบสรุปและปุ่มบันทึกด้านล่างกระดานเช็คชื่อ
class AttendanceBottomDock extends StatelessWidget {
  const AttendanceBottomDock({
    super.key,
    required this.stats,
    required this.remainingCount,
    required this.hasUnsavedChanges,
    required this.canSave,
    required this.saveLabel,
    required this.onSave,
  });

  final List<AttendanceStatBadgeData> stats;
  final int remainingCount;
  final bool hasUnsavedChanges;
  final bool canSave;
  final String saveLabel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final size = MediaQuery.sizeOf(context);
    final phonePortrait = size.shortestSide < 600 && size.height >= size.width;
    final saveBg = isDark ? p.brand : p.brandDeep;
    final saveFg = isDark ? const Color(0xFF0B1219) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.hairline)),
        boxShadow: [
          BoxShadow(
            color: p.shadowLift,
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            phonePortrait ? 12 : 16,
            phonePortrait ? 8 : 10,
            phonePortrait ? 12 : 16,
            phonePortrait ? 10 : 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: stats.isEmpty
                        ? Text(
                            remainingCount > 0
                                ? 'ยังไม่ลงรายชื่อ · เหลือ $remainingCount คน'
                                : 'ยังไม่มีรายชื่อในกระดาน',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: phonePortrait ? 12.5 : 13.5,
                              fontWeight: FontWeight.w600,
                              color: p.inkMuted,
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (var i = 0; i < stats.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 6),
                                  _DockStatPill(
                                    stat: stats[i],
                                    isDark: isDark,
                                    compact: phonePortrait,
                                  ),
                                ],
                                if (remainingCount > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: p.chipSurface,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: p.hairline),
                                    ),
                                    child: Text(
                                      'เหลือ $remainingCount',
                                      style: TextStyle(
                                        fontSize: phonePortrait ? 11.5 : 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: p.inkMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                  ),
                  if (hasUnsavedChanges) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: p.statusIncomplete.withValues(
                          alpha: isDark ? 0.2 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: p.statusIncomplete,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'ยังไม่บันทึก',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: p.statusIncomplete,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: phonePortrait ? 8 : 10),
              FilledButton.icon(
                onPressed: canSave ? onSave : null,
                icon: Icon(
                  Icons.how_to_reg_rounded,
                  size: phonePortrait ? 20 : 23,
                ),
                label: Text(
                  saveLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: phonePortrait ? 16 : 18.5,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: saveBg,
                  foregroundColor: saveFg,
                  minimumSize: Size.fromHeight(phonePortrait ? 50 : 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockStatPill extends StatelessWidget {
  const _DockStatPill({
    required this.stat,
    required this.isDark,
    required this.compact,
  });

  final AttendanceStatBadgeData stat;
  final bool isDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: stat.color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: stat.color.withValues(alpha: isDark ? 0.45 : 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: stat.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '${stat.label} ${stat.count}',
            style: TextStyle(
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w700,
              color: isDark ? p.ink : stat.color,
            ),
          ),
        ],
      ),
    );
  }
}
