import 'dart:async';
import 'dart:ui' as ui;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:quran_library/quran_library.dart';

@JS('Blob')
extension type _JsBlob._(JSObject _) implements JSObject {
  external factory _JsBlob(JSArray<JSAny> parts, JSObject options);
}

@JS('ClipboardItem')
extension type _JsClipboardItem._(JSObject _) implements JSObject {
  external factory _JsClipboardItem(JSObject items);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await QuranLibrary.init();
  await QuranLibrary().switchFontType(fontIndex: 1);
  runApp(const AyahImageApp());
}

class AyahImageApp extends StatelessWidget {
  const AyahImageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'صورة آية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AyahImageScreen(),
    );
  }
}

// ─── palette colors ───────────────────────────────────────────────────────────
const _palette = <Color>[
  Color(0xFFD2232A),
  Color(0xFF40AD49),
  Color(0xFFEA008B),
  Color(0xFF176E97),
  Color(0xFFC46FAC),
  Color(0xFFEF5A2C),
  Color(0xFFF8B34A),
  Color(0xFF00ADED),
];

// Unique identifier per word: (surahNumber, ayahNumber, wordNumber)
typedef _WordId = (int, int, int);

_WordId _idOf(QpcV4WordSegment s) =>
    (s.surahNumber, s.ayahNumber, s.wordNumber);

// ─── top-level screen ─────────────────────────────────────────────────────────
class AyahImageScreen extends StatefulWidget {
  const AyahImageScreen({super.key});

  @override
  State<AyahImageScreen> createState() => _AyahImageScreenState();
}

class _AyahImageScreenState extends State<AyahImageScreen> {
  int? _selectedSurah;
  final _ayahStartCtrl = TextEditingController();
  final _ayahEndCtrl = TextEditingController();
  _BgColor _bg = _BgColor.none;
  String? _error;

  int? _surah;
  int? _ayahStart;
  int? _ayahEnd;
  List<({int page, QpcV4WordSegment seg})> _segments = [];
  bool _fontsReady = false;

  // search
  final _searchCtrl = TextEditingController();
  List<AyahModel> _searchResults = [];
  Timer? _searchDebounce;

  // font size
  double _fontSize = 40.0;
  final _fontSizeCtrl = TextEditingController(text: '40');

  List<SurahNamesModel> get _surahs => QuranCtrl.instance.surahsList;

  @override
  void dispose() {
    _ayahStartCtrl.dispose();
    _ayahEndCtrl.dispose();
    _searchCtrl.dispose();
    _fontSizeCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final results = QuranLibrary().search(trimmed);
      if (mounted) setState(() => _searchResults = results.take(40).toList());
    });
  }

  void _selectSearchResult(AyahModel result) {
    setState(() {
      _selectedSurah = result.surahNumber;
      _ayahStartCtrl.text = result.ayahNumber.toString();
      _ayahEndCtrl.clear();
      _searchCtrl.clear();
      _searchResults = [];
      _error = null;
    });
    _preview();
  }

  String _arabic(int n) => n.toString().replaceAllMapped(
      RegExp(r'\d'), (m) => String.fromCharCode(0x0660 + int.parse(m[0]!)));

  Future<void> _preview() async {
    final aStart = int.tryParse(_ayahStartCtrl.text.trim());
    final endText = _ayahEndCtrl.text.trim();
    final aEnd = endText.isEmpty ? aStart : int.tryParse(endText);

    String? err;
    if (_selectedSurah == null) {
      err = 'اختر السورة';
    } else if (aStart == null) {
      err = 'أدخل رقم الآية الأولى';
    } else {
      final max = _surahs[_selectedSurah! - 1].ayahsNumber;
      if (aStart < 1 || aStart > max) {
        err = 'رقم الآية يجب أن يكون بين ١ و $max';
      } else if (aEnd == null || aEnd < aStart || aEnd > max) {
        err = 'آية النهاية غير صالحة';
      }
    }

    if (err != null) {
      setState(() => _error = err);
      return;
    }

    final surah = _selectedSurah!;

    setState(() {
      _error = null;
      _surah = surah;
      _ayahStart = aStart!;
      _ayahEnd = aEnd!;
      _segments = [];
      _fontsReady = false;
    });

    // Collect unique pages for the ayah range
    final pageNums = <int>{};
    for (int a = aStart!; a <= aEnd!; a++) {
      pageNums.add(
          QuranCtrl.instance.getPageNumberByAyahAndSurahNumber(a, surah));
    }

    for (final p in pageNums) {
      await QuranFontsService.ensurePagesLoaded(p, radius: 0);
      await QuranCtrl.instance.prewarmQpcV4Pages(p - 1);
    }
    if (!mounted) return;

    final segs = <({int page, QpcV4WordSegment seg})>[];
    for (final p in pageNums.toList()..sort()) {
      final blocks = QuranCtrl.instance.getQpcLayoutBlocksForPageSync(p);
      for (final block in blocks) {
        if (block is QpcV4AyahLineBlock) {
          for (final seg in block.segments) {
            if (seg.surahNumber == surah &&
                seg.ayahNumber >= aStart &&
                seg.ayahNumber <= aEnd) {
              segs.add((page: p, seg: seg));
            }
          }
        }
      }
    }
    segs.sort((a, b) {
      final c = a.seg.ayahNumber.compareTo(b.seg.ayahNumber);
      return c != 0 ? c : a.seg.wordNumber.compareTo(b.seg.wordNumber);
    });

    setState(() {
      _segments = segs;
      _fontsReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final maxAyah =
        _selectedSurah != null ? _surahs[_selectedSurah! - 1].ayahsNumber : null;

    return Scaffold(
      appBar: AppBar(title: const Text('صورة آية'), centerTitle: true),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── search ────────────────────────────────────────────────────
              TextField(
                controller: _searchCtrl,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  labelText: 'بحث في القرآن',
                  hintText: 'ابحث بنص الآية أو اسم السورة...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchResults.isNotEmpty || _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchResults = []);
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
                onChanged: _onSearchChanged,
              ),
              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                    color: theme.colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = _searchResults[i];
                      return InkWell(
                        onTap: () => _selectSearchResult(r),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                r.ayaTextEmlaey,
                                style: theme.textTheme.bodyMedium,
                                textDirection: TextDirection.rtl,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${r.arabicName}  ﴿${_arabic(r.ayahNumber)}﴾',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant),
                                textDirection: TextDirection.rtl,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // ── inputs ────────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<int>(
                      initialValue: _selectedSurah,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'السورة',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                      ),
                      hint: const Text('اختر السورة'),
                      items: List.generate(_surahs.length, (i) {
                        final s = _surahs[i];
                        return DropdownMenuItem<int>(
                          value: s.number,
                          child: Text('${_arabic(s.number)}. ${s.name}',
                              textDirection: TextDirection.rtl),
                        );
                      }),
                      onChanged: (v) => setState(() {
                        _selectedSurah = v;
                        _ayahStartCtrl.clear();
                        _ayahEndCtrl.clear();
                        _surah = null;
                        _segments = [];
                        _fontsReady = false;
                        _error = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _ayahStartCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'من',
                        hintText: maxAyah != null ? '١' : '',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 14),
                      ),
                      onSubmitted: (_) => _preview(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _ayahEndCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'إلى',
                        hintText: maxAyah != null ? _arabic(maxAyah) : '',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 14),
                      ),
                      onSubmitted: (_) => _preview(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: FilledButton(
                      onPressed: _preview,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                      ),
                      child: const Text('عرض'),
                    ),
                  ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(
                        color: theme.colorScheme.error, fontSize: 13)),
              ],

              const SizedBox(height: 20),

              // ── background selector ───────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── background chips ────────────────────────────────────
                  Text('الخلفية: ', style: theme.textTheme.bodyMedium),
                  const SizedBox(width: 6),
                  ..._BgColor.values.map((c) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(c.label),
                          selected: _bg == c,
                          avatar: c == _BgColor.none
                              ? ClipOval(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CustomPaint(
                                        painter: _CheckerboardPainter()),
                                  ),
                                )
                              : Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: c.color(false),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.black26, width: 0.5),
                                  ),
                                ),
                          onSelected: (_) => setState(() => _bg = c),
                        ),
                      )),

                  // ── divider ──────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: SizedBox(
                      height: 32,
                      child: VerticalDivider(
                          color: theme.colorScheme.outlineVariant, width: 1),
                    ),
                  ),

                  // ── font size ────────────────────────────────────────────
                  Text('الحجم: ', style: theme.textTheme.bodyMedium),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 58,
                    height: 40,
                    child: TextField(
                      controller: _fontSizeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodyMedium,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        final d = double.tryParse(v);
                        if (d != null && d >= 10 && d <= 100) {
                          setState(() => _fontSize = d);
                        }
                      },
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      min: 10,
                      max: 100,
                      value: _fontSize.clamp(10.0, 100.0),
                      onChanged: (v) {
                        setState(() => _fontSize = v);
                        _fontSizeCtrl.text = v.round().toString();
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── ayah coloring section ─────────────────────────────────────
              if (_surah != null)
                _AyahColoringSection(
                  key: ValueKey('$_surah-$_ayahStart-$_ayahEnd'),
                  segments: _segments,
                  fontsReady: _fontsReady,
                  bg: _bg,
                  isDark: isDark,
                  surah: _surah!,
                  ayahStart: _ayahStart!,
                  ayahEnd: _ayahEnd!,
                  surahName: _surahs[_surah! - 1].name,
                  fontSize: _fontSize,
                )
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Text(
                      'اختر السورة وأدخل رقم الآية ثم اضغط "عرض"',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: theme.colorScheme.outline),
                      textAlign: TextAlign.center,
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

// ─── coloring section — owns word colors, selection, and export ───────────────
class _AyahColoringSection extends StatefulWidget {
  final List<({int page, QpcV4WordSegment seg})> segments;
  final bool fontsReady;
  final _BgColor bg;
  final bool isDark;
  final int surah;
  final int ayahStart;
  final int ayahEnd;
  final String surahName;
  final double fontSize;

  const _AyahColoringSection({
    super.key,
    required this.segments,
    required this.fontsReady,
    required this.bg,
    required this.isDark,
    required this.surah,
    required this.ayahStart,
    required this.ayahEnd,
    required this.surahName,
    required this.fontSize,
  });

  @override
  State<_AyahColoringSection> createState() => _AyahColoringSectionState();
}

class _AyahColoringSectionState extends State<_AyahColoringSection> {
  final _repaintKey = GlobalKey();
  final Map<_WordId, Color> _wordColors = {};
  final Set<_WordId> _selectedWords = {};
  bool _isSelecting = false;
  _WordId? _anchorWord;
  final Map<_WordId, GlobalKey> _wordKeys = {};
  bool _capturing = false;
  final List<Color> _extraColors = [];

  String _arabic(int n) => n.toString().replaceAllMapped(
      RegExp(r'\d'), (m) => String.fromCharCode(0x0660 + int.parse(m[0]!)));

  Color get _defaultTextColor =>
      widget.bg == _BgColor.dark ? Colors.white : const Color(0xFF1A1A1A);

  GlobalKey _keyFor(_WordId id) =>
      _wordKeys.putIfAbsent(id, () => GlobalKey());

  _WordId? _wordAtGlobalPos(Offset globalPos) {
    for (final entry in _wordKeys.entries) {
      final box =
          entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      if ((box.localToGlobal(Offset.zero) & box.size).contains(globalPos)) {
        return entry.key;
      }
    }
    return null;
  }

  void _updateDragSelection(Offset globalPos) {
    final current = _wordAtGlobalPos(globalPos);
    if (current == null || _anchorWord == null) return;
    final ids = widget.segments.map((e) => _idOf(e.seg)).toList();
    final ai = ids.indexOf(_anchorWord!);
    final ci = ids.indexOf(current);
    if (ai < 0 || ci < 0) return;
    final lo = ai < ci ? ai : ci;
    final hi = ai < ci ? ci : ai;
    setState(() {
      _selectedWords
        ..clear()
        ..addAll(ids.sublist(lo, hi + 1));
    });
  }

  void _selectColor(Color? color) {
    if (_selectedWords.isEmpty) return;
    setState(() {
      for (final w in _selectedWords) {
        if (color == null) {
          _wordColors.remove(w);
        } else {
          _wordColors[w] = color;
        }
      }
    });
  }

  Future<void> _copyImage() async {
    setState(() {
      _capturing = true;
      _selectedWords.clear();
    });
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      if (!mounted) return;

      final blobOptions = JSObject();
      blobOptions['type'] = 'image/png'.toJS;
      final jsBlob = _JsBlob([bytes.toJS as JSAny].toJS, blobOptions);

      final clipInit = JSObject();
      clipInit['image/png'] = jsBlob;
      final clipItem = _JsClipboardItem(clipInit);

      final nav = globalContext['navigator'] as JSObject;
      final clipboard = nav['clipboard'] as JSObject;
      await clipboard.callMethodVarArgs<JSPromise<JSAny?>>(
        'write'.toJS,
        [[clipItem as JSAny].toJS],
      ).toDart;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم نسخ الصورة إلى الحافظة'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر النسخ — جرب Chrome أو حدّث المتصفح'),
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final cardContent = Container(
      color: widget.bg.color(widget.isDark),
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
      child: _buildWords(primary),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── capture area ─────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: widget.bg == _BgColor.none
              ? Stack(children: [
                  Positioned.fill(
                      child: CustomPaint(painter: _CheckerboardPainter())),
                  RepaintBoundary(key: _repaintKey, child: cardContent),
                ])
              : RepaintBoundary(key: _repaintKey, child: cardContent),
        ),

        // ── color palette ─────────────────────────────────────────────────
        if (_selectedWords.isNotEmpty && !_isSelecting) ...[
          const SizedBox(height: 12),
          _ColorPaletteBar(
            colors: [..._palette, ..._extraColors],
            currentColor: _selectedWords.length == 1
                ? _wordColors[_selectedWords.first]
                : null,
            onColor: _selectColor,
            onDismiss: () => setState(() => _selectedWords.clear()),
            onAddColor: (c) => setState(() => _extraColors.add(c)),
          ),
        ] else if (!_isSelecting &&
            widget.fontsReady &&
            widget.segments.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'اضغط على كلمة • اضغط مطولاً واسحب لتحديد عدة كلمات',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],

        if (_wordColors.isNotEmpty) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => setState(() => _wordColors.clear()),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('إعادة تعيين الألوان'),
          ),
        ],

        const SizedBox(height: 12),

        FilledButton.icon(
          onPressed: _capturing ? null : _copyImage,
          icon: _capturing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.content_copy_rounded, size: 18),
          label: const Text('نسخ الصورة'),
        ),
      ],
    );
  }

  Widget _buildWords(Color primary) {
    if (!widget.fontsReady || widget.segments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator.adaptive(),
      );
    }

    final wordWidgets = <Widget>[];
    for (final e in widget.segments) {
      final pageIdx = e.page - 1;
      final fontFamily = QuranCtrl.instance
          .getFontPath(pageIdx, isDark: widget.bg == _BgColor.dark);
      final fontSize = widget.fontSize;
      final seg = e.seg;
      final id = _idOf(seg);

      final isSelected = _selectedWords.contains(id);
      final wordColor = _wordColors[id];

      // ColorFiltered + BlendMode.srcIn overrides the COLR embedded glyph
      // colors in the QPC font by replacing pixel color at the GPU layer.
      final textWidget = Text(
        seg.glyphs,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          height: 1.8,
          color: wordColor != null ? Colors.white : _defaultTextColor,
        ),
        textDirection: TextDirection.rtl,
      );

      wordWidgets.add(
        GestureDetector(
          key: _keyFor(id),
          onTap: () {
            if (_isSelecting) return;
            setState(() {
              if (_selectedWords.contains(id)) {
                _selectedWords.clear();
              } else {
                _selectedWords
                  ..clear()
                  ..add(id);
              }
            });
          },
          onLongPressStart: (d) => setState(() {
            _isSelecting = true;
            _anchorWord = id;
            _selectedWords
              ..clear()
              ..add(id);
          }),
          onLongPressMoveUpdate: (d) =>
              _updateDragSelection(d.globalPosition),
          onLongPressEnd: (_) => setState(() => _isSelecting = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              decoration: isSelected && !_capturing
                  ? BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _isSelecting
                              ? primary.withValues(alpha: 0.5)
                              : primary,
                          width: 2.5,
                        ),
                      ),
                    )
                  : null,
              child: wordColor != null
                  ? ColorFiltered(
                      colorFilter:
                          ColorFilter.mode(wordColor, BlendMode.srcIn),
                      child: textWidget,
                    )
                  : textWidget,
            ),
          ),
        ),
      );

      if (seg.isAyahEnd) {
        wordWidgets.add(Text(
          ' ${_arabic(seg.ayahNumber)} ',
          style: TextStyle(
            fontFamily: 'ayahNumber',
            package: 'quran_library',
            fontSize: fontSize + 4,
            height: 1.5,
            color: _defaultTextColor.withValues(alpha: 0.6),
          ),
        ));
      }
    }

    return Wrap(
      textDirection: TextDirection.rtl,
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: wordWidgets,
    );
  }
}

// ─── color palette bar ────────────────────────────────────────────────────────
class _ColorPaletteBar extends StatelessWidget {
  final List<Color> colors;
  final void Function(Color? color) onColor;
  final VoidCallback onDismiss;
  final void Function(Color) onAddColor;
  final Color? currentColor;

  const _ColorPaletteBar({
    required this.colors,
    required this.onColor,
    required this.onDismiss,
    required this.onAddColor,
    this.currentColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 0,
        runSpacing: 6,
        children: [
          // reset button
          Tooltip(
            message: 'إزالة اللون',
            child: GestureDetector(
              onTap: () => onColor(null),
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(left: 8, right: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black26),
                ),
                child: const Icon(Icons.format_color_reset_rounded,
                    size: 16, color: Colors.black54),
              ),
            ),
          ),
          // color swatches
          ...colors.map((c) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: c,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(32, 32),
                      maximumSize: const Size(32, 32),
                      shape: CircleBorder(
                        side: BorderSide(
                          color: currentColor == c
                              ? Colors.white
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    onPressed: () => onColor(c),
                    child: currentColor == c
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : const SizedBox.shrink(),
                  ),
                ),
              )),
          // + button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: 32,
              height: 32,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerHigh,
                  foregroundColor: scheme.onSurface,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(32, 32),
                  maximumSize: const Size(32, 32),
                  shape: CircleBorder(
                    side: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
                  ),
                ),
                onPressed: () async {
                  final color = await _showAddColorDialog(context);
                  if (color != null) onAddColor(color);
                },
                child: const Icon(Icons.add_rounded, size: 18),
              ),
            ),
          ),
          // dismiss
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

Future<Color?> _showAddColorDialog(BuildContext context) {
  final ctrl = TextEditingController();
  Color? preview;

  return showDialog<Color>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('إضافة لون'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'hex color',
                  hintText: 'RRGGBB',
                  prefixText: '#',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final hex = v.replaceAll('#', '').trim();
                  final parsed = hex.length == 6
                      ? int.tryParse('FF$hex', radix: 16)
                      : null;
                  setS(() => preview = parsed != null ? Color(parsed) : null);
                },
              ),
            ),
            const SizedBox(height: 16),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: preview ?? Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: preview != null ? Colors.black26 : Colors.transparent,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed:
                preview != null ? () => Navigator.pop(ctx, preview) : null,
            child: const Text('إضافة'),
          ),
        ],
      ),
    ),
  );
}

// ─── background color ─────────────────────────────────────────────────────────
enum _BgColor {
  none('شفاف'),
  white('أبيض'),
  cream('كريمي'),
  dark('داكن');

  final String label;
  const _BgColor(this.label);

  Color color(bool isDark) => switch (this) {
        _BgColor.none => Colors.transparent,
        _BgColor.white => Colors.white,
        _BgColor.cream => const Color(0xFFFAF7F3),
        _BgColor.dark => const Color(0xFF1E1E1E),
      };
}

// ─── checkerboard painter (indicates transparency on screen) ──────────────────
class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 8.0;
    final p1 = Paint()..color = const Color(0xFFCBCBCB);
    final p2 = Paint()..color = const Color(0xFFEEEEEE);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final even = ((x / cell).floor() + (y / cell).floor()) % 2 == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), even ? p1 : p2);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter old) => false;
}
