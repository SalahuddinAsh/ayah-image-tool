part of '/quran.dart';

const _kWordHighlightPaletteColors = [
  Color(0xFFFFD354), // yellow
  Color(0xFFF36077), // red
  Color(0xFF00CD00), // green
];

/// Full-screen overlay layer that shows the word-action tooltip and the
/// color-palette tooltip. Rendered outside [SafeArea] so that global
/// positions map directly to [Positioned] coordinates.
class _WordTooltipOverlay extends StatelessWidget {
  const _WordTooltipOverlay({
    required this.isDark,
    required this.parentContext,
    required this.customWordMenuItems,
  });

  final bool isDark;
  final BuildContext parentContext;
  final List<Widget> customWordMenuItems;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ctrl = WordInfoCtrl.instance;
      final showAction = ctrl.showWordActionTooltip.value;
      final showPalette = ctrl.showColorPaletteTooltip.value;

      if (!showAction && !showPalette) return const SizedBox.shrink();

      final position = ctrl.tooltipPosition.value;
      if (position == null) return const SizedBox.shrink();

      final screenSize = MediaQuery.of(context).size;
      final safePadding = MediaQuery.of(context).padding;

      return Stack(
        children: [
          // Transparent barrier — tap outside to dismiss.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: ctrl.dismissAllTooltips,
            child: const SizedBox.expand(),
          ),
          if (showAction)
            _WordActionTooltip(
              position: position,
              screenSize: screenSize,
              safePadding: safePadding,
              isDark: isDark,
              parentContext: parentContext,
              customWordMenuItems: customWordMenuItems,
            ),
          if (showPalette && !showAction)
            _WordColorPaletteTooltip(
              position: position,
              screenSize: screenSize,
              safePadding: safePadding,
              isDark: isDark,
            ),
        ],
      );
    });
  }
}

// ─── Shared positioning helper ───

Offset _tooltipPosition({
  required Offset pressPos,
  required double width,
  required double height,
  required Size screenSize,
  required EdgeInsets safePadding,
}) {
  const gap = 8.0;
  final minX = safePadding.left + 8;
  final maxX = screenSize.width - safePadding.right - width - 8;
  final minY = safePadding.top + 8;
  final maxY = screenSize.height - safePadding.bottom - height - 8;

  double x = (pressPos.dx - width / 2).clamp(minX, maxX);
  double y = pressPos.dy - height - gap;
  if (y < minY) y = pressPos.dy + gap;
  y = y.clamp(minY, maxY);

  return Offset(x, y);
}

// ─── Shared tooltip container style ───

BoxDecoration _tooltipDecoration(bool isDark) => BoxDecoration(
      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 3)),
      ],
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.08),
        width: 1,
      ),
    );

// ─── Action tooltip ───

class _WordActionTooltip extends StatelessWidget {
  const _WordActionTooltip({
    required this.position,
    required this.screenSize,
    required this.safePadding,
    required this.isDark,
    required this.parentContext,
    required this.customWordMenuItems,
  });

  final Offset position;
  final Size screenSize;
  final EdgeInsets safePadding;
  final bool isDark;
  final BuildContext parentContext;
  final List<Widget> customWordMenuItems;

  @override
  Widget build(BuildContext context) {
    final ctrl = WordInfoCtrl.instance;
    final ayah = ctrl.tooltipAyah.value;
    final iconColor = isDark ? Colors.white70 : Colors.black87;
    final highlightColor = ctrl.wordHighlightColor.value;
    final isHighlighted = ctrl.tooltipWordIsHighlighted.value;

    const iconSize = 22.0;
    const itemW = 44.0;
    const tooltipH = 60.0;

    // Count items to compute width.
    final standardCount = (ayah != null ? 2 : 0) + 1; // tafsir+copy + highlight/remove
    final customCount = customWordMenuItems.length;
    final totalItems = standardCount + customCount;
    final tooltipW = (totalItems * itemW + (totalItems - 1) * 1.0 + 16).clamp(80.0, screenSize.width - 32.0);

    final pos = _tooltipPosition(
      pressPos: position,
      width: tooltipW,
      height: tooltipH,
      screenSize: screenSize,
      safePadding: safePadding,
    );

    Widget divider() => Container(
          width: 1,
          height: 32,
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.08),
        );

    Widget iconBtn({
      required IconData icon,
      required VoidCallback onTap,
      Color? color,
      String? label,
    }) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: itemW,
          height: tooltipH,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: iconSize, color: color ?? iconColor),
              if (label != null) ...[
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    color: color ?? iconColor,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    final items = <Widget>[];

    // Custom items (app-provided — e.g. "إنشاء بطاقة", "إزالة العلامة").
    for (final item in customWordMenuItems) {
      if (items.isNotEmpty) items.add(divider());
      items.add(SizedBox(width: itemW, height: tooltipH, child: item));
    }

    // Tafsir.
    if (ayah != null) {
      if (items.isNotEmpty) items.add(divider());
      items.add(iconBtn(
        icon: Icons.menu_book_outlined,
        onTap: () {
          ctrl.onActionTappedWithoutHighlight();
          showTafsirOnTap(
            context: parentContext,
            isDark: isDark,
            ayahNum: ayah.ayahNumber,
            pageIndex: ayah.page - 1,
            ayahUQNum: ayah.ayahUQNumber,
            ayahNumber: ayah.ayahNumber,
          );
        },
      ));
    }

    // Copy.
    if (ayah != null) {
      items.add(divider());
      items.add(iconBtn(
        icon: Icons.copy_rounded,
        onTap: () {
          ctrl.onActionTappedWithoutHighlight();
          Clipboard.setData(ClipboardData(text: ayah.text));
        },
      ));
    }

    // Highlight or remove-highlight button.
    if (items.isNotEmpty) items.add(divider());
    if (isHighlighted) {
      items.add(iconBtn(
        icon: Icons.highlight_remove_rounded,
        color: Colors.redAccent,
        label: 'إزالة',
        onTap: ctrl.removeTooltipWordHighlight,
      ));
    } else {
      items.add(iconBtn(
        icon: Icons.highlight,
        color: highlightColor,
        label: 'تظليل',
        onTap: () => ctrl.onHighlightButtonTapped(),
      ));
    }

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: tooltipW,
          height: tooltipH,
          decoration: _tooltipDecoration(isDark),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: items,
          ),
        ),
      ),
    );
  }
}

// ─── Color palette tooltip ───

class _WordColorPaletteTooltip extends StatelessWidget {
  const _WordColorPaletteTooltip({
    required this.position,
    required this.screenSize,
    required this.safePadding,
    required this.isDark,
  });

  final Offset position;
  final Size screenSize;
  final EdgeInsets safePadding;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ctrl = WordInfoCtrl.instance;
    const circleSize = 30.0;
    const itemW = 46.0;
    const closeW = 36.0;
    const tooltipH = 56.0;
    final tooltipW = _kWordHighlightPaletteColors.length * itemW + closeW + 16.0;

    final pos = _tooltipPosition(
      pressPos: position,
      width: tooltipW,
      height: tooltipH,
      screenSize: screenSize,
      safePadding: safePadding,
    );

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: tooltipW,
          height: tooltipH,
          decoration: _tooltipDecoration(isDark),
          child: Obx(() {
            final selected = ctrl.wordHighlightColor.value;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Color circles.
                ..._kWordHighlightPaletteColors.map((color) {
                  final isSelected = color.toARGB32() == selected.toARGB32();
                  return GestureDetector(
                    onTap: () => ctrl.updateLastHighlightColor(color),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Container(
                        width: circleSize,
                        height: circleSize,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.black54, width: 2.5)
                              : null,
                        ),
                      ),
                    ),
                  );
                }),
                // Remove / close button.
                GestureDetector(
                  onTap: ctrl.removeLastHighlight,
                  child: SizedBox(
                    width: closeW,
                    height: tooltipH,
                    child: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
