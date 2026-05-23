part of '/quran.dart';

/// Recognizer يدعم ضغط مطوّل قصير (للكلمة) وضغط مطوّل أطول (للآية)
/// داخل TextSpan.
///
/// نستخدمه لأن TextSpan لا يدعم أكثر من recognizer واحد.
class TapLongPressRecognizer extends TapGestureRecognizer {
  TapLongPressRecognizer({
    this.shortHoldDuration = const Duration(milliseconds: 250),
    this.longHoldDuration = const Duration(milliseconds: 500),
  }) {
    onTapDown = _handleTapDown;
    onTapUp = _handleTapUp;
    onTapCancel = _handleTapCancel;
  }

  final Duration shortHoldDuration;
  final Duration longHoldDuration;

  VoidCallback? onShortHoldStartCallback;
  VoidCallback? onShortHoldCompleteCallback;
  void Function(LongPressStartDetails details)? onLongHoldStartCallback;

  /// Called on every pointer move while the long hold is active (for slide-to-extend).
  void Function(Offset globalPosition)? onLongHoldMoveCallback;

  /// Called when the pointer is lifted after a long hold (selection complete).
  void Function(Offset globalPosition)? onLongHoldEndCallback;

  /// يُستدعى عند الضغط السريع العادي (بدون ضغط مطوّل).
  /// إذا لم يُعيَّن، يتم استدعاء [QuranCtrl.instance.showControlToggle] كسلوك افتراضي.
  VoidCallback? onQuickTapCallback;

  Timer? _shortTimer;
  Timer? _longTimer;
  bool _didShortHold = false;
  bool _didLongHold = false;
  TapDownDetails? _lastTapDown;

  void _handleTapDown(TapDownDetails details) {
    _lastTapDown = details;
    _didShortHold = false;
    _didLongHold = false;

    _shortTimer?.cancel();
    _longTimer?.cancel();

    _shortTimer = Timer(shortHoldDuration, () {
      _didShortHold = true;
      onShortHoldStartCallback?.call();
    });

    _longTimer = Timer(longHoldDuration, () {
      _didLongHold = true;
      // Accept the arena so the surrounding InkWell/PageView cannot fire after
      // a long hold — this also enables receiving pointer-move events below.
      resolve(GestureDisposition.accepted);
      final d = _lastTapDown;
      if (d == null) return;
      onLongHoldStartCallback?.call(
        LongPressStartDetails(
          globalPosition: d.globalPosition,
          localPosition: d.localPosition,
        ),
      );
    });
  }

  void _handleTapCancel() {
    _shortTimer?.cancel();
    _shortTimer = null;
    _longTimer?.cancel();
    _longTimer = null;
    _lastTapDown = null;
    _didShortHold = false;
    _didLongHold = false;
  }

  void _handleTapUp(TapUpDetails details) {
    _shortTimer?.cancel();
    _shortTimer = null;
    _longTimer?.cancel();
    _longTimer = null;

    final wasLongHold = _didLongHold;

    if (_didShortHold && !_didLongHold) {
      onShortHoldCompleteCallback?.call();
    }

    _lastTapDown = null;
    _didShortHold = false;
    _didLongHold = false;

    if (wasLongHold) {
      onLongHoldEndCallback?.call(details.globalPosition);
    }

    // بعد الضغط المطوّل لا نمسح التحديد — toggleAyahSelection عمل update بالفعل
    if (!wasLongHold) {
      // أثناء السكرول التلقائي: إيقاف/استئناف مع إظهار/إخفاء عناصر التحكم
      final autoScroll = AutoScrollCtrl.instance;
      if (autoScroll.state.isActive.value) {
        autoScroll.togglePause();
        return;
      }

      if (onQuickTapCallback != null) {
        onQuickTapCallback!();
      } else {
        QuranCtrl.instance.showControlToggle();
      }
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (_didLongHold && event is PointerMoveEvent) {
      // Fire the slide callback without forwarding to super: TapGestureRecognizer
      // rejects on move past its 18px tolerance which resets _didLongHold and kills
      // the slide. We handle up/cancel through the normal tap callbacks instead.
      onLongHoldMoveCallback?.call(event.position);
      return;
    }
    super.handleEvent(event);
  }

  @override
  void dispose() {
    _shortTimer?.cancel();
    _longTimer?.cancel();
    super.dispose();
  }
}
