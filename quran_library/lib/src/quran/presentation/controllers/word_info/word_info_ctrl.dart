part of '/quran.dart';

class WordInfoCtrl extends GetxController
    with GetSingleTickerProviderStateMixin {
  static WordInfoCtrl get instance =>
      GetInstance().putOrFind(() => WordInfoCtrl());

  WordInfoCtrl({WordInfoRepository? repository})
      : _repository = repository ?? WordInfoRepository();

  final WordInfoRepository _repository;

  final RxBool isPreparingDownload = false.obs;
  final RxBool isDownloading = false.obs;
  final RxDouble downloadProgress = 0.0.obs;
  final Rx<WordInfoKind?> downloadingKind = Rx<WordInfoKind?>(null);

  final Rx<WordInfoKind> selectedKind = WordInfoKind.recitations.obs;

  /// رقم مراجعة (revision) يتغير عند وصول/تغير بيانات القراءات في الذاكرة.
  /// يُستخدم لإبطال كاش عرض سطور QPC v4 عند اكتمال prewarm.
  int recitationsDataRevision = 0;

  final Rx<WordRef?> selectedWordRef = Rx<WordRef?>(null);

  /// End of the word-highlight range (null = single word at [selectedWordRef]).
  final Rx<WordRef?> wordHighlightEndRef = Rx<WordRef?>(null);

  /// Color used to paint the word-highlight background.
  /// Defaults to yellow (matching the first bookmark color).
  final Rx<Color> wordHighlightColor = Rx<Color>(const Color(0xFFFFD354));

  void setWordHighlightColor(Color color) {
    wordHighlightColor.value = color;
    update(['word_info_data']);
  }

  /// Becomes true after auto-saving a word selection; keeps the color picker visible.
  /// @deprecated Use [showColorPaletteTooltip] instead.
  final RxBool wordSelectionComplete = false.obs;

  // ─── Word-action tooltip state ───

  /// Global screen position of the last long-press that started word selection.
  final Rx<Offset?> tooltipPosition = Rx<Offset?>(null);

  /// The ayah that was long-pressed (used for ayah actions in the tooltip).
  final Rx<AyahModel?> tooltipAyah = Rx<AyahModel?>(null);

  /// True while the floating action tooltip (ayah actions + highlight button) is visible.
  final RxBool showWordActionTooltip = false.obs;

  /// True while the color-palette tooltip is visible.
  final RxBool showColorPaletteTooltip = false.obs;

  /// Number of distinct words covered since the current gesture started.
  /// Used to dismiss the action tooltip after a meaningful slide (>2 words).
  int _slideWordCount = 0;

  /// True when the long-pressed word was already saved in [_savedHighlights].
  /// Prevents [notifyWordSelectionComplete] from saving a new highlight on lift.
  bool _isPressingHighlightedWord = false;

  /// Whether the tooltip was opened by long-pressing an already-highlighted word.
  final RxBool tooltipWordIsHighlighted = false.obs;

  /// The [WordRef] of the word that triggered the current tooltip (for removal).
  WordRef? _tooltipPressedWordRef;

  // ─── Persistent word highlights ───

  static const _kHighlightsKey = 'word_highlights_v1';

  final List<_SavedWordHighlight> _savedHighlights = [];

  /// Set of ayah UQ numbers bookmarked exclusively via word highlights.
  /// Used to suppress the full-ayah background color for these ayahs in the renderer.
  Set<int> wordHighlightBookmarkedAyahUqs = {};

  /// Incremented on every save/clear so [_computeFingerprint] can detect changes.
  int savedHighlightsRevision = 0;

  void _loadHighlights() {
    final raw = GetStorage().read<List>(_kHighlightsKey);
    if (raw == null) return;
    for (final item in raw) {
      try {
        _savedHighlights.add(
            _SavedWordHighlight.fromJson(Map<String, dynamic>.from(item as Map)));
      } catch (_) {}
    }
    _rebuildAyahUqsCache();
  }

  void _persistHighlights() {
    GetStorage().write(
        _kHighlightsKey, _savedHighlights.map((h) => h.toJson()).toList());
  }

  void _rebuildAyahUqsCache() {
    wordHighlightBookmarkedAyahUqs = {
      for (final h in _savedHighlights) ...h.bookedAyahUqs,
    };
  }

  /// Save [start]→[end] range to BookmarksCtrl for every ayah it covers.
  /// Returns the list of ayah UQ numbers that were bookmarked.
  Future<List<int>> _saveToBookmarks(WordRef start, WordRef end, Color color) async {
    final quranCtrl = QuranCtrl.instance;
    final bookmarksCtrl = BookmarksCtrl.instance;
    final surahNumber = start.surahNumber;
    final minAyah = math.min(start.ayahNumber, end.ayahNumber);
    final maxAyah = math.max(start.ayahNumber, end.ayahNumber);

    final wordsText = await quranCtrl.getHighlightedWordsText(start, end);

    final booked = <int>[];
    for (var ayahNum = minAyah; ayahNum <= maxAyah; ayahNum++) {
      final uq = quranCtrl.resolveAyahUq(
          surahNumber: surahNumber, ayahNumber: ayahNum);
      if (uq == 0) continue;
      final ayah = quranCtrl.getAyahByUq(uq);
      if (ayah.ayahUQNumber == 0) continue;
      final surahData = quranCtrl.getSurahDataByAyah(ayah);
      final name = wordsText.isNotEmpty
          ? '${surahData.arabicName} • $wordsText'
          : surahData.arabicName;
      bookmarksCtrl.saveBookmark(
        surahName: name,
        ayahId: uq,
        ayahNumber: ayahNum,
        page: ayah.page,
        colorCode: color.toARGB32(),
      );
      booked.add(uq);
    }
    return booked;
  }

  /// Remove bookmarks that were created by a word-highlight (identified by
  /// [bookedAyahUqs] + [colorCode]).
  void _removeFromBookmarks(List<int> bookedAyahUqs, int colorCode) {
    final bookmarksCtrl = BookmarksCtrl.instance;
    final bucket = List<BookmarkModel>.from(
        bookmarksCtrl.bookmarks[colorCode] ?? []);
    for (final uq in bookedAyahUqs) {
      for (final bm in bucket.where((b) => b.ayahId == uq)) {
        bookmarksCtrl.removeBookmark(bm.id);
      }
    }
  }

  /// Auto-save the current temp selection with [wordHighlightColor].
  /// Shows the color palette tooltip only when the action tooltip is not visible.
  Future<void> notifyWordSelectionComplete() async {
    // If the gesture was on an already-highlighted word, the tooltip was shown
    // in "remove" mode — no new highlight should be saved on lift.
    if (_isPressingHighlightedWord) {
      _isPressingHighlightedWord = false;
      // Keep tooltip open; user hasn't acted yet.
      return;
    }

    final start = selectedWordRef.value;
    if (start == null) return;
    final end = wordHighlightEndRef.value ?? start;

    // Clear temp selection immediately — saved highlight will render instead.
    selectedWordRef.value = null;
    wordHighlightEndRef.value = null;
    wordSelectionComplete.value = true;
    update(['word_info_data']);

    // Save word highlight (async: fetches word text on first call).
    final booked = await _saveToBookmarks(start, end, wordHighlightColor.value);
    _savedHighlights.add(_SavedWordHighlight(
      start: start,
      end: end,
      color: wordHighlightColor.value,
      bookedAyahUqs: booked,
    ));
    savedHighlightsRevision++;
    _persistHighlights();
    _rebuildAyahUqsCache();
    update(['word_info_data']);

    // If the action tooltip is visible the user will tap "تظليل" to open the palette.
    // If not (slid >2 words), show the palette immediately near the last press position.
    if (!showWordActionTooltip.value) {
      showColorPaletteTooltip.value = true;
    }
  }

  /// Update the color of the most recently saved highlight (called from color picker).
  Future<void> updateLastHighlightColor(Color color) async {
    if (_savedHighlights.isEmpty) return;
    final last = _savedHighlights.last;

    // Swap bookmarks: remove old, add new.
    _removeFromBookmarks(last.bookedAyahUqs, last.color.toARGB32());
    final newBooked = await _saveToBookmarks(last.start, last.end, color);

    _savedHighlights[_savedHighlights.length - 1] = _SavedWordHighlight(
      start: last.start,
      end: last.end,
      color: color,
      bookedAyahUqs: newBooked,
    );
    wordHighlightColor.value = color;
    savedHighlightsRevision++;
    _persistHighlights();
    _rebuildAyahUqsCache();

    wordSelectionComplete.value = false;
    showColorPaletteTooltip.value = false;
    update(['word_info_data']);
  }

  /// Dismiss the color picker without changing the saved highlight.
  void dismissColorPicker() {
    wordSelectionComplete.value = false;
    showColorPaletteTooltip.value = false;
  }

  /// Returns the saved highlight color for [ref], or null if not highlighted.
  Color? getSavedHighlightColor(WordRef ref) {
    for (final h in _savedHighlights.reversed) {
      if (h.containsWord(ref)) return h.color;
    }
    return null;
  }

  /// Remove every saved highlight that contains [ref] and its associated bookmarks.
  void removeHighlightContaining(WordRef ref) {
    final toRemove = _savedHighlights.where((h) => h.containsWord(ref)).toList();
    if (toRemove.isEmpty) return;
    for (final h in toRemove) {
      _removeFromBookmarks(h.bookedAyahUqs, h.color.toARGB32());
      _savedHighlights.remove(h);
    }
    savedHighlightsRevision++;
    _persistHighlights();
    _rebuildAyahUqsCache();
    update(['word_info_data']);
  }

  // ─────────────────────────────────────

  /// تفعيل/تعطيل تحديد الكلمة وعرض الـ BottomSheet
  /// يُضبط من خلال بارامتر [QuranLibraryScreen.enableWordSelection]
  bool isWordSelectionEnabled = true;

  /// تفعيل/تعطيل عرض نافذة معلومات الكلمة عند الضغط القصير.
  /// يُضبط من خلال بارامتر [QuranLibraryScreen.enableWordInfo]
  bool isWordInfoEnabled = true;
  late TabController tabController;
  VoidCallback? _tabControllerListener;
  int _lastTabIndexNotified = 0;

  bool get isTenRecitations => tabController.index == 1;

  @override
  void onInit() {
    _loadHighlights();
    tabController = TabController(
        initialIndex:
            GetStorage().read(_StorageConstants().isTenRecitations) ?? 0,
        length: 2,
        vsync: this);

    _lastTabIndexNotified = tabController.index;

    _tabControllerListener = () {
      // حدّث مرة واحدة لكل تغيّر فعلي بالـ index.
      final idx = tabController.index;
      if (idx == _lastTabIndexNotified) return;
      _lastTabIndexNotified = idx;
      GetStorage().write(
        _StorageConstants().isTenRecitations,
        idx,
      );
      update(['word_info_data']);
      QuranCtrl.instance.update();
    };
    tabController.addListener(_tabControllerListener!);
    super.onInit();
  }

  @override
  void onClose() {
    final listener = _tabControllerListener;
    if (listener != null) {
      tabController.removeListener(listener);
      _tabControllerListener = null;
    }
    tabController.dispose();
    WordAudioService.instance.stop();
    super.onClose();
  }

  void setSelectedKind(WordInfoKind kind) {
    selectedKind.value = kind;
    update(['word_info_kind']);
  }

  void _bumpRecitationsRevision() {
    recitationsDataRevision++;
  }

  void setSelectedWord(WordRef ref) {
    selectedWordRef.value = ref;
    update(['word_info_data']);
  }

  void clearSelectedWord() {
    if (selectedWordRef.value == null && wordHighlightEndRef.value == null) return;
    selectedWordRef.value = null;
    wordHighlightEndRef.value = null;
    update(['word_info_data']);
  }

  /// Start a word highlight range at [ref].
  /// [globalPosition] and [ayah] are used to position and populate the action tooltip.
  /// If the word already belongs to a saved highlight, shows the tooltip in
  /// "remove" mode without creating a temp selection.
  void startWordHighlight(WordRef ref, {Offset? globalPosition, AyahModel? ayah}) {
    final alreadyHighlighted = getSavedHighlightColor(ref) != null;
    _isPressingHighlightedWord = alreadyHighlighted;
    tooltipWordIsHighlighted.value = alreadyHighlighted;
    _tooltipPressedWordRef = ref;

    if (!alreadyHighlighted) {
      selectedWordRef.value = ref;
      wordHighlightEndRef.value = ref;
      _slideWordCount = 1;
    }
    showColorPaletteTooltip.value = false;
    if (globalPosition != null) {
      tooltipPosition.value = globalPosition;
      tooltipAyah.value = ayah;
      showWordActionTooltip.value = true;
    }
    update(['word_info_data']);
  }

  /// Extend the current word highlight range to [ref].
  /// Dismisses the action tooltip once more than 2 words have been selected.
  void extendWordHighlight(WordRef ref) {
    if (wordHighlightEndRef.value == ref) return;
    wordHighlightEndRef.value = ref;
    _slideWordCount++;
    if (_slideWordCount > 2) {
      showWordActionTooltip.value = false;
    }
    update(['word_info_data']);
  }

  /// Clear all word highlighting (both start and end) and all tooltips.
  void clearWordHighlight() {
    if (selectedWordRef.value == null && wordHighlightEndRef.value == null) return;
    selectedWordRef.value = null;
    wordHighlightEndRef.value = null;
    wordSelectionComplete.value = false;
    showWordActionTooltip.value = false;
    showColorPaletteTooltip.value = false;
    _isPressingHighlightedWord = false;
    tooltipWordIsHighlighted.value = false;
    _tooltipPressedWordRef = null;
    update(['word_info_data']);
  }

  /// Called when user taps the "إزالة التظليل" button while a highlighted word's
  /// tooltip is open. Removes the saved highlight and dismisses all tooltips.
  void removeTooltipWordHighlight() {
    final ref = _tooltipPressedWordRef;
    if (ref != null) removeHighlightContaining(ref);
    _isPressingHighlightedWord = false;
    tooltipWordIsHighlighted.value = false;
    _tooltipPressedWordRef = null;
    showWordActionTooltip.value = false;
    showColorPaletteTooltip.value = false;
  }

  /// Called when user taps the "تظليل" button in the action tooltip.
  /// Expands the highlight to cover the entire ayah, then shows the color palette.
  Future<void> onHighlightButtonTapped() async {
    showWordActionTooltip.value = false;
    final ayah = tooltipAyah.value;
    if (ayah == null || ayah.surahNumber == null) {
      showColorPaletteTooltip.value = true;
      return;
    }

    // Remove the single-word auto-save and replace with a full-ayah highlight.
    _removeLastHighlightSilently();

    final surah = ayah.surahNumber!;
    final ayahNum = ayah.ayahNumber;
    final wordCount = await QuranCtrl.instance.getAyahWordCount(surah, ayahNum);
    if (wordCount == 0) {
      showColorPaletteTooltip.value = true;
      return;
    }

    final start = WordRef(surahNumber: surah, ayahNumber: ayahNum, wordNumber: 1);
    final end = WordRef(surahNumber: surah, ayahNumber: ayahNum, wordNumber: wordCount);

    final booked = await _saveToBookmarks(start, end, wordHighlightColor.value);
    _savedHighlights.add(_SavedWordHighlight(
      start: start,
      end: end,
      color: wordHighlightColor.value,
      bookedAyahUqs: booked,
    ));
    savedHighlightsRevision++;
    _persistHighlights();
    _rebuildAyahUqsCache();
    update(['word_info_data']);

    showColorPaletteTooltip.value = true;
  }

  /// Called when user taps a non-highlight action in the tooltip (tafsir, copy, etc.).
  /// If the tooltip was opened on a fresh word, removes the auto-saved temp highlight.
  /// If it was opened on an already-highlighted word, leaves the saved highlight intact.
  void onActionTappedWithoutHighlight() {
    showWordActionTooltip.value = false;
    showColorPaletteTooltip.value = false;
    if (!tooltipWordIsHighlighted.value) {
      _removeLastHighlightSilently();
    }
    tooltipWordIsHighlighted.value = false;
    _isPressingHighlightedWord = false;
    _tooltipPressedWordRef = null;
  }

  void _removeLastHighlightSilently() {
    if (_savedHighlights.isEmpty) return;
    final last = _savedHighlights.last;
    _removeFromBookmarks(last.bookedAyahUqs, last.color.toARGB32());
    _savedHighlights.removeLast();
    savedHighlightsRevision++;
    _persistHighlights();
    _rebuildAyahUqsCache();
    update(['word_info_data']);
  }

  /// Remove the last saved highlight and hide the color palette (X button action).
  void removeLastHighlight() {
    _removeLastHighlightSilently();
    showColorPaletteTooltip.value = false;
  }

  /// Dismiss all tooltips without changing the saved highlight.
  void dismissAllTooltips() {
    showWordActionTooltip.value = false;
    showColorPaletteTooltip.value = false;
  }

  bool isKindAvailable(WordInfoKind kind) => _repository.isKindDownloaded(kind);

  QiraatWordInfo? getRecitationsInfoSync(WordRef ref) =>
      _repository.getRecitationWordInfoSync(ref: ref);

  Future<QiraatWordInfo?> getRecitationsInfo(WordRef ref) =>
      _repository.getWordInfo(kind: WordInfoKind.recitations, ref: ref);

  Future<QiraatWordInfo?> getWordInfo({
    required WordInfoKind kind,
    required WordRef ref,
  }) =>
      _repository.getWordInfo(kind: kind, ref: ref);

  Future<void> downloadKind(WordInfoKind kind) async {
    if (isDownloading.value) return;

    try {
      downloadingKind.value = kind;
      isPreparingDownload.value = true;
      isDownloading.value = true;
      downloadProgress.value = 0.0;
      update(['word_info_download']);

      await _repository.downloadKind(
        kind: kind,
        onProgress: (p) {
          isPreparingDownload.value = false;
          downloadProgress.value = p;
          update(['word_info_download']);
        },
      );

      if (kind == WordInfoKind.recitations) {
        _bumpRecitationsRevision();
      }

      isPreparingDownload.value = false;
      isDownloading.value = false;
      downloadingKind.value = null;
      downloadProgress.value = 100.0;
      update(['word_info_download', 'word_info_data']);
    } catch (e) {
      isPreparingDownload.value = false;
      isDownloading.value = false;
      downloadingKind.value = null;
      downloadProgress.value = 0.0;
      update(['word_info_download']);
      rethrow;
    }
  }

  Future<void> prewarmRecitationsSurah(int surahNumber) async {
    final didLoad = await _repository.prewarmRecitationsSurah(surahNumber);
    if (!didLoad) return;
    _bumpRecitationsRevision();
    update(['word_info_data']);
  }

  Future<void> prewarmRecitationsSurahs(Iterable<int> surahNumbers) async {
    final unique = surahNumbers.toSet();
    var didPrewarmAny = false;
    for (final s in unique) {
      final didLoad = await _repository.prewarmRecitationsSurah(s);
      if (didLoad) didPrewarmAny = true;
    }
    if (didPrewarmAny) {
      log('Prewarming recitations for surahs: $unique', name: 'WordInfoCtrl');
      _bumpRecitationsRevision();
      update(['word_info_data']);
    }
  }

  // ─── صوت الكلمات ───

  /// هل تمت تهيئة خدمة صوت الكلمات (OAuth2 credentials)؟
  bool get isWordAudioInitialized => WordAudioService.instance.isInitialized;

  /// تشغيل صوت كلمة واحدة.
  Future<void> playWordAudio(WordRef ref) async {
    final svc = WordAudioService.instance;

    // إذا كانت نفس الكلمة تُشغّل، أوقف
    if (svc.isPlaying.value &&
        !svc.isPlayingAyahWords.value &&
        svc.currentPlayingRef.value == ref) {
      await stopWordAudio();
      return;
    }

    await svc.playWord(ref);
    update(['word_info_audio']);
  }

  /// تشغيل كل كلمات الآية بالتسلسل.
  Future<void> playAyahWordsAudio(WordRef ref) async {
    final svc = WordAudioService.instance;

    // إذا كانت نفس الآية تُشغّل، أوقف
    if (svc.isPlaying.value &&
        svc.isPlayingAyahWords.value &&
        svc.currentPlayingRef.value?.surahNumber == ref.surahNumber &&
        svc.currentPlayingRef.value?.ayahNumber == ref.ayahNumber) {
      await stopWordAudio();
      return;
    }

    await svc.playAyahWords(
      surahNumber: ref.surahNumber,
      ayahNumber: ref.ayahNumber,
    );
    update(['word_info_audio']);
  }

  /// إيقاف صوت الكلمات.
  Future<void> stopWordAudio() async {
    await WordAudioService.instance.stop();
    update(['word_info_audio']);
  }
}

/// Represents a saved (persisted) word-highlight range with a color.
class _SavedWordHighlight {
  final WordRef start;
  final WordRef end;
  final Color color;
  /// UQ ayah numbers that were bookmarked in BookmarksCtrl for this highlight.
  final List<int> bookedAyahUqs;

  const _SavedWordHighlight({
    required this.start,
    required this.end,
    required this.color,
    this.bookedAyahUqs = const [],
  });

  static int _encode(WordRef r) =>
      r.surahNumber * 10000000 + r.ayahNumber * 10000 + r.wordNumber;

  bool containsWord(WordRef ref) {
    final v = _encode(ref);
    final lo = math.min(_encode(start), _encode(end));
    final hi = math.max(_encode(start), _encode(end));
    return v >= lo && v <= hi;
  }

  Map<String, dynamic> toJson() => {
        'ss': start.surahNumber,
        'sa': start.ayahNumber,
        'sw': start.wordNumber,
        'es': end.surahNumber,
        'ea': end.ayahNumber,
        'ew': end.wordNumber,
        'c': color.toARGB32(),
        'bq': bookedAyahUqs,
      };

  factory _SavedWordHighlight.fromJson(Map<String, dynamic> j) =>
      _SavedWordHighlight(
        start: WordRef(
            surahNumber: j['ss'] as int,
            ayahNumber: j['sa'] as int,
            wordNumber: j['sw'] as int),
        end: WordRef(
            surahNumber: j['es'] as int,
            ayahNumber: j['ea'] as int,
            wordNumber: j['ew'] as int),
        color: Color(j['c'] as int),
        bookedAyahUqs: (j['bq'] as List?)?.cast<int>() ?? [],
      );
}
