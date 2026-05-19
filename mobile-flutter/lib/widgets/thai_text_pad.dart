import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// เปิดแป้นพิมพ์ภาษาไทย (ใช้ IME ระบบใน locale ไทย) — รูปแบบเดียวกับแป้นตัวเลขในแอป
Future<String?> showThaiTextPad({
  required BuildContext context,
  required String label,
  String initialText = '',
  int minLines = 2,
  int maxLines = 5,
}) async {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x48000000),
    transitionDuration: const Duration(milliseconds: 80),
    pageBuilder: (dialogCtx, animation, _) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Localizations.override(
        context: dialogCtx,
        locale: const Locale('th'),
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curve),
              child: FadeTransition(
                opacity: curve,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    bottom: MediaQuery.viewInsetsOf(dialogCtx).bottom + 14,
                  ),
                  child: _ThaiTextPadPanel(
                    dialogContext: dialogCtx,
                    label: label,
                    initialText: initialText,
                    minLines: minLines,
                    maxLines: maxLines,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ThaiTextPadPanel extends StatefulWidget {
  const _ThaiTextPadPanel({
    required this.dialogContext,
    required this.label,
    required this.initialText,
    required this.minLines,
    required this.maxLines,
  });

  final BuildContext dialogContext;
  final String label;
  final String initialText;
  final int minLines;
  final int maxLines;

  @override
  State<_ThaiTextPadPanel> createState() => _ThaiTextPadPanelState();
}

class _ThaiTextPadPanelState extends State<_ThaiTextPadPanel> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(widget.dialogContext).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = GoogleFonts.kanit(
      fontSize: 17,
      fontWeight: FontWeight.w800,
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F5FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD8E2EE)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: labelStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'ปิด',
                  onPressed: () => Navigator.of(widget.dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              autocorrect: false,
              enableSuggestions: false,
              style: GoogleFonts.kanit(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1D2A3A),
              ),
              decoration: InputDecoration(
                hintText: 'รายละเอียดงานที่ทำ',
                hintStyle: GoogleFonts.kanit(
                  fontSize: 14,
                  color: Colors.black45,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD8E2EE)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD8E2EE)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF1565C0),
                    width: 1.4,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _confirm(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _controller.clear();
                        _focusNode.requestFocus();
                      });
                    },
                    child: Text('ล้าง', style: GoogleFonts.kanit()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                    ),
                    child: Text(
                      'ตกลง',
                      style: GoogleFonts.kanit(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
