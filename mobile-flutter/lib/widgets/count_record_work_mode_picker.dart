import 'package:flutter/material.dart';

import '../utils/device_perf.dart';
import 'soft_press_button.dart';

/// โหมดงานในแผง «บันทึกและนับจำนวน»
enum CountRecordWorkMode {
  trip,
  sand,
  both,
}

/// ขั้นเลือกงานก่อนเข้าแผงบันทึกและนับจำนวน — ตัวอักษร/ไอคอนใหญ่ + stagger นุ่ม
class CountRecordWorkModePicker extends StatefulWidget {
  const CountRecordWorkModePicker({super.key, required this.onSelect});

  final ValueChanged<CountRecordWorkMode> onSelect;

  @override
  State<CountRecordWorkModePicker> createState() =>
      _CountRecordWorkModePickerState();
}

class _CountRecordWorkModePickerState extends State<CountRecordWorkModePicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final List<Animation<double>> _staggerAnims;
  late final bool _lite;

  @override
  void initState() {
    super.initState();
    _lite = DevicePerf.isConstrainedDevice;
    _entrance = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _lite ? 300 : 560),
    );
    _staggerAnims = List.generate(4, (index) {
      final start = (0.08 + index * 0.14).clamp(0.0, 0.72);
      final end = (start + (_lite ? 0.22 : 0.32)).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _entrance,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );
    });
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Widget _staggerTile(int index, Widget child) {
    return AnimatedBuilder(
      animation: _staggerAnims[index],
      builder: (context, _) {
        final t = _staggerAnims[index].value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 18),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final titleSize = isTablet ? 28.0 : 25.0;
    final subtitleSize = isTablet ? 16.0 : 14.5;
    final gap = isTablet ? 14.0 : 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _staggerTile(
          0,
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE0F7FA), Color(0xFFE8F4FD)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFB8E4EA)),
                ),
                child: const Text(
                  'เลือกโหมดงานวันนี้',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: Color(0xFF0D98A5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'วันนี้ทำงานอะไร?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                  letterSpacing: -0.4,
                  color: const Color(0xFF1A2433),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'เลือกประเภทงานก่อนเริ่มบันทึก',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: subtitleSize,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: gap + 4),
        Expanded(
          child: _staggerTile(
            1,
            _WorkModeOption(
              title: 'ขนอย่างเดียว',
              subtitle: 'บันทึกจำนวนเที่ยวรถ',
              icon: Icons.fire_truck_rounded,
              accent: const Color(0xFF1565C0),
              accentLight: const Color(0xFF42A5F5),
              gradientColors: const [Color(0xFFE3F2FD), Color(0xFFF5FAFF)],
              borderColor: const Color(0xFF90CAF9),
              onTap: () => widget.onSelect(CountRecordWorkMode.trip),
            ),
          ),
        ),
        SizedBox(height: gap),
        Expanded(
          child: _staggerTile(
            2,
            _WorkModeOption(
              title: 'ร่อนทรายอย่างเดียว',
              subtitle: 'บันทึกการร่อนทราย',
              icon: Icons.water_drop_rounded,
              accent: const Color(0xFFAD1457),
              accentLight: const Color(0xFFEC407A),
              gradientColors: const [Color(0xFFFCE4EC), Color(0xFFFFF5F8)],
              borderColor: const Color(0xFFF48FB1),
              onTap: () => widget.onSelect(CountRecordWorkMode.sand),
            ),
          ),
        ),
        SizedBox(height: gap),
        Expanded(
          child: _staggerTile(
            3,
            _WorkModeOption(
              title: 'ขนและร่อนทราย',
              subtitle: 'ทั้ง 2 อย่าง — แสดงสองการ์ด',
              icon: Icons.layers_rounded,
              accent: const Color(0xFF00695C),
              accentLight: const Color(0xFF26A69A),
              gradientColors: const [Color(0xFFE0F2F1), Color(0xFFF4FBFA)],
              borderColor: const Color(0xFF80CBC4),
              dualAccent: const [
                Color(0xFF1565C0),
                Color(0xFFAD1457),
              ],
              onTap: () => widget.onSelect(CountRecordWorkMode.both),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkModeOption extends StatelessWidget {
  const _WorkModeOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.accentLight,
    required this.gradientColors,
    required this.borderColor,
    required this.onTap,
    this.dualAccent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color accentLight;
  final List<Color> gradientColors;
  final Color borderColor;
  final List<Color>? dualAccent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final iconSize = isTablet ? 44.0 : 40.0;
    final iconBox = isTablet ? 76.0 : 68.0;
    final titleSize = isTablet ? 22.0 : 20.0;
    final subtitleSize = isTablet ? 15.0 : 14.0;

    Widget iconBadge() {
      if (dualAccent != null && dualAccent!.length >= 2) {
        return SizedBox(
          width: iconBox + 8,
          height: iconBox,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 4,
                child: _IconOrb(
                  size: iconBox * 0.72,
                  icon: Icons.fire_truck_rounded,
                  accent: dualAccent![0],
                  accentLight: const Color(0xFF42A5F5),
                  iconSize: iconSize * 0.72,
                ),
              ),
              Positioned(
                right: 4,
                child: _IconOrb(
                  size: iconBox * 0.72,
                  icon: Icons.water_drop_rounded,
                  accent: dualAccent![1],
                  accentLight: const Color(0xFFEC407A),
                  iconSize: iconSize * 0.72,
                ),
              ),
            ],
          ),
        );
      }
      return _IconOrb(
        size: iconBox,
        icon: icon,
        accent: accent,
        accentLight: accentLight,
        iconSize: iconSize,
      );
    }

    return SoftPressButton(
      onTap: onTap,
      size: SoftPressSize.large,
      borderRadius: 24,
      isDarkSurface: false,
      liftWhenIdle: true,
      depthShadow: SoftPressDepthShadow(
        color: accent.withValues(alpha: 0.18),
        blurRadius: 16,
        offsetY: 5,
        pressedBlurRadius: 6,
        pressedOffsetY: 2,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor.withValues(alpha: 0.85)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 22 : 18,
            vertical: isTablet ? 16 : 14,
          ),
          child: Row(
            children: [
              iconBadge(),
              SizedBox(width: isTablet ? 18 : 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                        letterSpacing: -0.25,
                        color: const Color(0xFF1A2433),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: subtitleSize,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: const Color(0xFF5C7088),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.22),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: accent,
                    size: isTablet ? 26 : 24,
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

class _IconOrb extends StatelessWidget {
  const _IconOrb({
    required this.size,
    required this.icon,
    required this.accent,
    required this.accentLight,
    required this.iconSize,
  });

  final double size;
  final IconData icon;
  final Color accent;
  final Color accentLight;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentLight.withValues(alpha: 0.35),
            accent.withValues(alpha: 0.12),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 2,
        ),
      ),
      child: Icon(icon, color: accent, size: iconSize),
    );
  }
}
