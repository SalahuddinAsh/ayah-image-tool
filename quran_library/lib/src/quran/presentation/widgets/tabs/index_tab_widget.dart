part of '/quran.dart';

class _IndexTab extends StatelessWidget {
  final bool isDark;
  final String languageCode;
  final IndexTabStyle style;
  const _IndexTab(
      {required this.isDark, required this.languageCode, required this.style});

  @override
  Widget build(BuildContext context) {
    final jozzList = QuranLibrary.allJoz;
    final hizbList = QuranLibrary.allHizb;
    final surahs = QuranLibrary.getAllSurahs(isArabic: false);

    final Color textColor = style.textColor ?? AppColors.getTextColor(isDark);
    final Color accentColor =
        style.accentColor ?? Theme.of(context).colorScheme.primary;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            height: style.tabBarHeight ?? 35,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: style.tabBarBgAlpha ?? 0.06),
              borderRadius:
                  BorderRadius.circular((style.tabBarRadius ?? 12).toDouble()),
            ),
            child: TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(
                    (style.indicatorRadius ?? 10).toDouble()),
              ),
              indicatorPadding:
                  style.indicatorPadding ?? const EdgeInsets.all(4),
              padding: EdgeInsets.zero,
              labelColor: style.labelColor ?? Colors.white,
              unselectedLabelColor: style.unselectedLabelColor ??
                  textColor.withValues(alpha: 0.6),
              indicatorColor: accentColor,
              indicatorWeight: .5,
              labelStyle: style.labelStyle ??
                  QuranLibrary().cairoStyle.copyWith(
                      fontSize: 13, fontWeight: FontWeight.w700, height: 1.3),
              unselectedLabelStyle: style.unselectedLabelStyle ??
                  QuranLibrary().cairoStyle.copyWith(fontSize: 13),
              tabs: [
                Tab(text: style.tabSurahsLabel ?? 'السور'),
                Tab(text: style.tabJozzLabel ?? 'الأجزاء'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: [
                _SurahsList(
                    isDark: isDark,
                    languageCode: languageCode,
                    surahs: surahs,
                    style: style),
                _JozzList(
                    isDark: isDark,
                    jozzList: jozzList,
                    hizbList: hizbList,
                    style: style),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ── Surah list item types ────────────────────────────────────────────────────

sealed class _SurahItem {}

class _SurahJuzHeader extends _SurahItem {
  final int juz;
  _SurahJuzHeader(this.juz);
}

class _SurahRowData extends _SurahItem {
  final int surahNumber; // 1..114
  final String arabicName;
  final int startPage;
  final int ayahCount;
  final String revelationType; // 'مكية' or 'مدنية'

  _SurahRowData({
    required this.surahNumber,
    required this.arabicName,
    required this.startPage,
    required this.ayahCount,
    required this.revelationType,
  });
}

// Removes Arabic diacritics and Quranic annotation marks so surah names
// display as clean connected text without floating tashkeel characters.
String _cleanSurahName(String text) {
  final stripped = text.replaceAll(RegExp(r'[\u064B-\u065F\u0610-\u061A\u0670\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED]'), '');
  return stripped.replaceFirst(RegExp(r'^سورة\s*'), '');
}

// ── Surah list widget ─────────────────────────────────────────────────────────

class _SurahsList extends StatefulWidget {
  final bool isDark;
  final String languageCode;
  final List<String> surahs;
  final IndexTabStyle style;

  const _SurahsList({
    required this.isDark,
    required this.languageCode,
    required this.surahs,
    required this.style,
  });

  @override
  State<_SurahsList> createState() => _SurahsListState();
}

class _SurahsListState extends State<_SurahsList> {
  late final ScrollController _scrollCtrl;
  late final List<_SurahItem> _items;
  late final int _currentSurahNumber; // 1..114
  late final int _currentJuz;

  // Maps juz (1..30) → flat item index of its header
  final Map<int, int> _juzHeaderIndex = {};

  static const double _headerH = 38.0; // SizedBox height for juz header in surah list
  static const double _rowH = 72.0;    // SizedBox height for surah row

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();

    final ctrl = QuranCtrl.instance;
    final currentPage = ctrl.state.currentPageNumber.value;

    int surahNum = 1;
    int currentJuz = 1;
    try {
      final sm = ctrl.getCurrentSurahByPageNumber(currentPage);
      surahNum = sm.surahNumber;
      currentJuz = ctrl.getJuzByPage(currentPage).juz;
    } catch (_) {}
    _currentSurahNumber = surahNum;
    _currentJuz = currentJuz;

    // Build flat list: juz header whenever juz changes, then surah row
    _items = [];
    int prevJuz = 0;
    for (final sm in ctrl.surahs) {
      final startJuz =
          sm.ayahs.isNotEmpty ? sm.ayahs.first.juz : prevJuz;
      if (startJuz != prevJuz) {
        _juzHeaderIndex[startJuz] = _items.length;
        _items.add(_SurahJuzHeader(startJuz));
        prevJuz = startJuz;
      }
      String revType = 'مكية';
      try {
        final info = QuranLibrary().getSurahInfo(surahNumber: sm.surahNumber);
        revType = info.revelationType.toLowerCase().contains('medinan')
            ? 'مدنية'
            : 'مكية';
      } catch (_) {}
      _items.add(_SurahRowData(
        surahNumber: sm.surahNumber,
        arabicName: _cleanSurahName(sm.arabicName),
        startPage: sm.ayahs.isNotEmpty ? sm.ayahs.first.page : 0,
        ayahCount: sm.ayahs.length,
        revelationType: revType,
      ));
    }

    // Scroll to current surah after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  double _offsetForItem(int itemIndex) {
    double offset = 0;
    for (int i = 0; i < itemIndex && i < _items.length; i++) {
      offset += _items[i] is _SurahJuzHeader ? _headerH : _rowH;
    }
    return offset;
  }

  void _scrollToCurrent() {
    if (!_scrollCtrl.hasClients) return;
    // Find current surah's item index
    final idx = _items.indexWhere(
      (item) =>
          item is _SurahRowData && item.surahNumber == _currentSurahNumber,
    );
    if (idx < 0) return;
    final target = (_offsetForItem(idx) - _rowH)
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.jumpTo(target);
  }

  void _jumpToJuz(int juz) {
    if (!_scrollCtrl.hasClients) return;
    final idx = _juzHeaderIndex[juz];
    if (idx == null) return;
    final target =
        _offsetForItem(idx).clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color textColor =
        widget.style.textColor ?? AppColors.getTextColor(widget.isDark);
    final Color accentColor =
        widget.style.accentColor ?? Theme.of(context).colorScheme.primary;
    final jozzList = QuranLibrary.allJoz;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      textDirection: TextDirection.ltr, // sidebar always on left
      children: [
        // ── Left sidebar: juz numbers 1-30 ──────────────────────────────
        _JuzSidebar(
          currentJuz: _currentJuz,
          accentColor: accentColor,
          textColor: textColor,
          onJuzTap: _jumpToJuz,
        ),

        // ── Main scrollable surah list ───────────────────────────────────
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];

              if (item is _SurahJuzHeader) {
                // ── Juz header ─────────────────────────────────────────
                return SizedBox(
                  height: _headerH,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerRight,
                    child: Text(
                      jozzList[(item.juz - 1).clamp(0, 29)],
                      textAlign: TextAlign.right,
                      style: QuranLibrary().cairoStyle.copyWith(
                            fontSize: 12,
                            color: accentColor.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                );
              }

              // ── Surah row ──────────────────────────────────────────────
              final row = item as _SurahRowData;
              final isCurrent = row.surahNumber == _currentSurahNumber;

              return SizedBox(
                height: _rowH,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                        (widget.style.listItemRadius ?? 6).toDouble()),
                    onTap: () {
                      Navigator.pop(context);
                      QuranLibrary().jumpToSurah(row.surahNumber);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? accentColor.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                            (widget.style.listItemRadius ?? 6).toDouble()),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Surah number circle (right side in RTL = first child)
                          _SurahCircle(
                            number: row.surahNumber,
                            isCurrent: isCurrent,
                            accentColor: accentColor,
                            isDark: widget.isDark,
                            textColor: textColor,
                          ),
                          const SizedBox(width: 8),
                          // Surah name + info (fills space, text right-aligned)
                          Expanded(
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    row.arabicName,
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: QuranLibrary().cairoStyle.copyWith(
                                          fontSize: 16,
                                          fontWeight: isCurrent
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          color: isCurrent
                                              ? accentColor
                                              : textColor,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'الصفحة ${row.startPage} - ${row.ayahCount} آية - ${row.revelationType}',
                                    textAlign: TextAlign.right,
                                    style: QuranLibrary().cairoStyle.copyWith(
                                          fontSize: 11,
                                          color: textColor.withValues(alpha: 0.5),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Surah number circle ───────────────────────────────────────────────────────

class _SurahCircle extends StatelessWidget {
  final int number;
  final bool isCurrent;
  final Color accentColor;
  final Color textColor;
  final bool isDark;

  const _SurahCircle({
    required this.number,
    required this.isCurrent,
    required this.accentColor,
    required this.textColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCurrent
            ? accentColor
            : (isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.07)),
        border: isCurrent
            ? null
            : Border.all(
                color: accentColor.withValues(alpha: 0.25),
                width: 1,
              ),
      ),
      child: Center(
        child: Text(
          '$number',
          style: QuranLibrary().cairoStyle.copyWith(
                fontSize: number > 99 ? 10 : 12,
                fontWeight: FontWeight.w700,
                color: isCurrent
                    ? Colors.white
                    : textColor.withValues(alpha: 0.6),
              ),
        ),
      ),
    );
  }
}

// ── Data holder for a single rub' entry ──────────────────────────────────────

class _RubEntry {
  final String opening;
  final String surahName;
  final int ayahNumber;
  final int page;

  const _RubEntry({
    required this.opening,
    required this.surahName,
    required this.ayahNumber,
    required this.page,
  });
}

// ── Juz list with rub' breakdown ─────────────────────────────────────────────

class _JozzList extends StatefulWidget {
  final bool isDark;
  final List<String> jozzList;
  final List<String> hizbList;
  final IndexTabStyle style;

  const _JozzList({
    required this.isDark,
    required this.jozzList,
    required this.hizbList,
    required this.style,
  });

  @override
  State<_JozzList> createState() => _JozzListState();
}

class _JozzListState extends State<_JozzList> {
  late final ScrollController _scrollCtrl;
  late final List<_RubEntry> _rubEntries; // 240 entries
  late final int _currentGlobalRub;


  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();

    final ctrl = QuranCtrl.instance;
    final currentPage = ctrl.state.currentPageNumber.value;

    int globalRub = 1;
    try {
      globalRub = QuranLibrary().getRubIndexForPage(currentPage);
    } catch (_) {}
    _currentGlobalRub = globalRub;

    // Pre-compute surah name + ayah for every rub'
    _rubEntries = List.generate(240, (i) {
      final rub = i + 1;
      int page = 1;
      int ayahNum = 1;
      String surahName = '';
      try {
        final ayah = ctrl.getHizbStartPage(rub);
        page = ayah.page > 0 ? ayah.page : 1;
        ayahNum = ayah.ayahNumber;
        surahName = ctrl.getCurrentSurahByPageNumber(page).arabicName;
      } catch (_) {}
      return _RubEntry(
        opening: kRubOpenings[i],
        surahName: surahName,
        ayahNumber: ayahNum,
        page: page,
      );
    });

    // Scroll to current juz after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final juz = ((_currentGlobalRub - 1) ~/ 8) + 1;
      _scrollToJuzOffset(juz, animated: false);
    });
  }

  // Estimated item heights — must match the build output closely enough.
  static const double _headerH = 44.0; // SizedBox height for juz header
  static const double _rubH = 68.0;    // SizedBox height for rub row

  double _offsetForJuz(int juz) {
    // Preceding juzs each contribute 1 header + 8 rub rows
    return (juz - 1) * (_headerH + 8 * _rubH);
  }

  void _scrollToJuzOffset(int juz, {bool animated = true}) {
    if (!_scrollCtrl.hasClients) return;
    final target = _offsetForJuz(juz)
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    if (animated) {
      _scrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      _scrollCtrl.jumpTo(target);
    }
  }

  void _jumpToJuz(int juz) => _scrollToJuzOffset(juz);

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color textColor =
        widget.style.textColor ?? AppColors.getTextColor(widget.isDark);
    final Color accentColor =
        widget.style.accentColor ?? Theme.of(context).colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      textDirection: TextDirection.ltr, // sidebar always on left regardless of locale
      children: [
        // ── Left sidebar: juz numbers 1-30 ───────────────────────────────
        _JuzSidebar(
          currentJuz: ((_currentGlobalRub - 1) ~/ 8) + 1,
          accentColor: accentColor,
          textColor: textColor,
          onJuzTap: _jumpToJuz,
        ),

        // ── Main scrollable list ──────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            itemCount: widget.jozzList.length * 9, // 1 header + 8 rubs per juz
            itemBuilder: (context, index) {
              final juzIndex = index ~/ 9; // 0..29
              final itemInJuz = index % 9; // 0 = header, 1..8 = rubs
              final juz = juzIndex + 1;

              // ── Juz header ──────────────────────────────────────────────
              if (itemInJuz == 0) {
                return SizedBox(
                  height: _headerH,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerRight,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(
                          alpha: (widget.style.jozzAltBgAlpha ?? 0.1)),
                      borderRadius: BorderRadius.circular(
                          (widget.style.listItemRadius ?? 8).toDouble()),
                    ),
                    child: Text(
                      widget.jozzList[juzIndex],
                      textAlign: TextAlign.right,
                      style: QuranLibrary().cairoStyle.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: accentColor.withValues(alpha: 0.8),
                          ),
                    ),
                  ),
                );
              }

              // ── Rub' row ────────────────────────────────────────────────
              final rubInJuz = itemInJuz; // 1..8
              final globalRub = (juz - 1) * 8 + rubInJuz; // 1..240
              final isCurrent = globalRub == _currentGlobalRub;
              final entry = _rubEntries[globalRub - 1];

              // Quarter within hizb (1..4): rubs 1-4 → hizb 1, rubs 5-8 → hizb 2
              final rubInHizb = ((rubInJuz - 1) % 4) + 1;

              return SizedBox(
                height: _rubH,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                        (widget.style.listItemRadius ?? 4).toDouble()),
                    onTap: () {
                      Navigator.pop(context);
                      QuranLibrary().jumpToRub(juz, rubInJuz);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? accentColor.withValues(alpha: 0.13)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                            (widget.style.listItemRadius ?? 4).toDouble()),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Pie circle (right side in RTL = first child)
                          _RubCircle(
                            rubInHizb: rubInHizb,
                            isCurrent: isCurrent,
                            accentColor: accentColor,
                            isDark: widget.isDark,
                          ),
                          const SizedBox(width: 8),
                          // Opening text + surah info (vertically centered)
                          Flexible(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  entry.opening,
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: QuranLibrary().cairoStyle.copyWith(
                                        fontSize: 15,
                                        color: isCurrent
                                            ? accentColor
                                            : textColor,
                                        fontWeight: isCurrent
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${entry.surahName}: ${entry.ayahNumber} - الصفحة ${entry.page}',
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: QuranLibrary().cairoStyle.copyWith(
                                        fontSize: 11,
                                        color:
                                            textColor.withValues(alpha: 0.55),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Narrow left sidebar with juz numbers ─────────────────────────────────────

class _JuzSidebar extends StatelessWidget {
  final int currentJuz;
  final Color accentColor;
  final Color textColor;
  final void Function(int juz) onJuzTap;

  const _JuzSidebar({
    required this.currentJuz,
    required this.accentColor,
    required this.textColor,
    required this.onJuzTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: accentColor.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: List.generate(30, (i) {
          final juz = i + 1;
          final isCurrent = juz == currentJuz;
          return Expanded(
            child: GestureDetector(
              onTap: () => onJuzTap(juz),
              child: Container(
                alignment: Alignment.center,
                decoration: isCurrent
                    ? BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      )
                    : null,
                child: Text(
                  '$juz',
                  style: QuranLibrary().cairoStyle.copyWith(
                        fontSize: 13,
                        color: isCurrent
                            ? accentColor
                            : textColor.withValues(alpha: 0.5),
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w400,
                      ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Rub' circle indicator ────────────────────────────────────────────────────

class _RubCircle extends StatelessWidget {
  final int rubInHizb; // 1..4
  final bool isCurrent;
  final Color accentColor;
  final bool isDark;

  const _RubCircle({
    required this.rubInHizb,
    required this.isCurrent,
    required this.accentColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(26, 26),
      painter: _RubCirclePainter(
        rubInHizb: rubInHizb,
        filledColor:
            isCurrent ? accentColor : accentColor.withValues(alpha: 0.55),
        bgColor: isCurrent
            ? accentColor.withValues(alpha: 0.15)
            : (isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06)),
      ),
    );
  }
}

class _RubCirclePainter extends CustomPainter {
  final int rubInHizb; // 1..4
  final Color filledColor;
  final Color bgColor;

  const _RubCirclePainter({
    required this.rubInHizb,
    required this.filledColor,
    required this.bgColor,
  });

  static const double _pi = 3.14159265358979;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(center, radius, Paint()..color = bgColor);

    // Filled arc from 12 o'clock, clockwise
    canvas.drawArc(
      rect,
      -_pi / 2,
      2 * _pi * rubInHizb / 4,
      true,
      Paint()..color = filledColor,
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = filledColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_RubCirclePainter old) =>
      old.rubInHizb != rubInHizb ||
      old.filledColor != filledColor ||
      old.bgColor != bgColor;
}
