/// Application logic for the connected-glasses screen.
///
/// Owns the [GlassesTransport], translates user intent into ActiveLook
/// commands, and exposes everything the UI needs as observable state.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ble/glasses_transport.dart';
import '../../features/compass/compass_source.dart';
import '../../models/color_show.dart';
import '../../models/compass.dart';
import '../../models/discovered_glasses.dart';
import '../../models/transliteration.dart';
import '../../protocol/active_look_compass.dart';
import '../../protocol/active_look_palette.dart';
import '../../protocol/active_look_protocol.dart';

/// Anchor used for the demo text, taken from the API spec example: with
/// [TextRotation.topLeftToRight] the string is centred around this point.
const int _textAnchorX = 152;
const int _textAnchorY = 128;

class GlassesController extends ChangeNotifier {
  GlassesController({required this.transport, CompassSource? compass})
    : compass = compass ?? DeviceCompassSource() {
    _subscription = transport.events.listen(_onEvent);
    _compassSubscription = this.compass.headings.listen(
      _onCompassHeading,
      onError: (Object _) {},
    );
  }

  /// Default frame rate of the animated color demo.
  static const int defaultColorShowFps = 15;

  /// Slider range for the demo speed, in frames per second.
  static const int minColorShowFps = 2;
  static const int maxColorShowFps = 30;

  /// Interval between compass updates sent to the glasses.
  static const Duration compassRefreshInterval = Duration(seconds: 1);

  final GlassesTransport transport;
  final CompassSource compass;
  StreamSubscription<GlassesEvent>? _subscription;
  StreamSubscription<double?>? _compassSubscription;

  GlassesInfo _info = const GlassesInfo();
  bool _connected = false;
  bool _busy = false;
  String? _error;
  int _luma = 8;
  int _textColor = ActiveLookColor.bright;
  String _lastRenderedText = '';
  final List<String> _log = [];

  Timer? _colorShowTimer;
  Timer? _notifyTimer;
  ColorShowMode? _colorShowMode;
  int _colorShowPhase = 0;
  int _colorShowFps = defaultColorShowFps;
  List<GlassesShape> _frameShapes = const [];
  bool _frameInFlight = false;

  /// Incremental state of [ColorShowMode.sweep]: segments already on screen.
  final List<GlassesShape> _sweepScene = [];
  int _sweepStep = 0;

  /// State of [ColorShowMode.counter].
  int _counterValue = 0;
  int? _counterColor;

  int _lastFrameBytes = 0;

  double? _compassHeading;
  bool _compassActive = false;
  Timer? _compassTimer;
  Timer? _compassNotifyTimer;
  double? _compassDisplayHeading;
  bool _compassFrameInFlight = false;

  GlassesInfo get info => _info;
  bool get connected => _connected;
  bool get busy => _busy;
  String? get error => _error;
  int get luma => _luma;
  int get textColor => _textColor;
  String get lastRenderedText => _lastRenderedText;

  /// Animation mode currently playing, or `null` when the display is static.
  ColorShowMode? get colorShowMode => _colorShowMode;
  bool get isAnimating => _colorShowMode != null;

  /// Current frame rate of the demo.
  int get colorShowFps => _colorShowFps;

  /// Frame interval implied by [colorShowFps].
  Duration get colorShowInterval =>
      Duration(milliseconds: (1000 / _colorShowFps).round());

  /// Encoded size of the commands sent in the latest frame, for the BLE load
  /// read-out in the UI.
  int get lastFrameBytes => _lastFrameBytes;

  /// Approximate sustained BLE traffic of the running demo, in bytes/second.
  double get colorShowBytesPerSecond =>
      _lastFrameBytes * _colorShowFps.toDouble();

  /// Color the phone preview should use: the counter's current frame color
  /// while it runs, otherwise the user-selected text color.
  int get displayColor => _colorShowMode == ColorShowMode.counter
      ? (_counterColor ?? _textColor)
      : _textColor;

  /// Shapes of the frame currently on the glasses, for the phone-side preview.
  List<GlassesShape> get frameShapes => _frameShapes;

  /// Most recent protocol lines, newest first.
  List<String> get log => List<String>.unmodifiable(_log.reversed);

  /// True when the glasses report a color display (`MDP08`, i.e. engo3).
  bool get isColorCapable => _info.displayIsColor ?? false;

  String get displayName => transport.displayName;

  /// Latest heading reported by the phone's compass, or `null` while waiting
  /// for a sensor fix.
  double? get compassHeading => _compassHeading;

  /// Whether the current platform has a compass sensor at all.
  bool get compassSupported => compass.isSupported;

  /// Whether the compass ribbon is currently being drawn on the glasses.
  bool get compassActive => _compassActive;

  /// Heading shown by the glasses, for the phone-side framebuffer preview.
  double? get compassDisplayHeading => _compassDisplayHeading;

  Future<void> connect(DiscoveredGlasses glasses) async {
    _setBusy(true);
    _error = null;
    try {
      await transport.connect(glasses);
      // Events are delivered asynchronously; mirror the transport state so the
      // caller can decide immediately whether the connection succeeded.
      _connected = transport.isConnected;
      _info = transport.info;
    } catch (error) {
      _connected = false;
      _error = '$error';
    } finally {
      _setBusy(false);
    }
  }

  /// Draws [text] on the glasses, in one held, flicker-free update.
  Future<void> showText(String text) async {
    // The built-in glasses fonts are ASCII-only, so Cyrillic is transliterated.
    final value = toGlassesText(text.trim());
    if (value.isEmpty) return;

    // A running demo or compass would immediately paint over the text.
    await stopColorShow(clearDisplay: false);
    await stopCompass(clearDisplay: false);

    await _run(() async {
      await transport.send(ActiveLookCommands.hold());
      await transport.send(ActiveLookCommands.clear());
      await transport.send(
        isColorCapable
            ? ActiveLookCommands.textColor(
                x: _textAnchorX,
                y: _textAnchorY,
                text: value,
                color: _textColor,
              )
            : ActiveLookCommands.text(
                x: _textAnchorX,
                y: _textAnchorY,
                text: value,
                grey: 15,
              ),
      );
      await transport.send(ActiveLookCommands.flush());
      _lastRenderedText = value;
      _frameShapes = const [];
      notifyListeners();
    });
  }

  Future<void> clearDisplay() async {
    await stopColorShow(clearDisplay: false);
    await stopCompass(clearDisplay: false);
    await _run(() async {
      await transport.send(ActiveLookCommands.hold());
      await transport.send(ActiveLookCommands.clear());
      await transport.send(ActiveLookCommands.flush());
      _lastRenderedText = '';
      _frameShapes = const [];
      notifyListeners();
    });
  }

  /// Starts the full-screen, animated color demo in [mode].
  ///
  /// Each frame is `hold → clear → color/rectf|circf … → flush`, so the panel
  /// refreshes once per frame. Color commands are gated on `MDP08` hardware.
  Future<void> startColorShow(ColorShowMode mode) async {
    if (!_connected || !isColorCapable) return;

    await stopCompass(clearDisplay: false);
    _colorShowTimer?.cancel();
    _colorShowMode = mode;
    _colorShowPhase = 0;
    _sweepStep = 0;
    _sweepScene.clear();
    _counterValue = 0;
    _counterColor = null;
    _lastFrameBytes = 0;
    _lastRenderedText = '';
    _error = null;
    notifyListeners();

    await _renderColorShowFrame();
    if (_colorShowMode != mode || !_connected) return;
    _startColorShowTimer();
  }

  /// Changes the demo frame rate (clamped to the slider range). If the demo is
  /// running, the timer is restarted with the new interval.
  void setColorShowSpeed(int framesPerSecond) {
    final fps = framesPerSecond.clamp(minColorShowFps, maxColorShowFps);
    if (fps == _colorShowFps) return;
    _colorShowFps = fps;
    if (_colorShowMode != null && _connected) {
      _colorShowTimer?.cancel();
      _startColorShowTimer();
    }
    notifyListeners();
  }

  void _startColorShowTimer() {
    _colorShowTimer?.cancel();
    _colorShowTimer = Timer.periodic(
      colorShowInterval,
      (_) => unawaited(_renderColorShowFrame()),
    );
  }

  /// Stops the animation. By default the display is cleared, because a frozen
  /// full-brightness frame otherwise stays drawn (and lit) forever.
  Future<void> stopColorShow({bool clearDisplay = true}) async {
    _colorShowTimer?.cancel();
    _colorShowTimer = null;
    final wasAnimating = _colorShowMode != null;
    _colorShowMode = null;
    _frameShapes = const [];
    _sweepScene.clear();
    _counterColor = null;
    if (wasAnimating) notifyListeners();

    if (!wasAnimating || !_connected) return;
    await _run(() async {
      // A frame can be interrupted mid-hold, so reset the nested hold counter
      // instead of relying on a matching flush.
      await transport.send(ActiveLookCommands.resetAndFlush());
      if (clearDisplay) {
        await transport.send(ActiveLookCommands.clear());
        await transport.send(ActiveLookCommands.flush());
        _lastRenderedText = '';
      }
      notifyListeners();
    });
  }

  /// Starts mirroring the phone's compass on the glasses as a HUD ribbon.
  ///
  /// The ribbon is redrawn at most once per [compassRefreshInterval]; the
  /// phone-side widget still follows the sensor at full rate.
  Future<void> startCompass() async {
    if (!_connected || !compass.isSupported) return;

    await stopColorShow(clearDisplay: false);
    _compassActive = true;
    _compassDisplayHeading = null;
    _lastRenderedText = '';
    _frameShapes = const [];
    _error = null;
    notifyListeners();

    await _renderCompassFrame();
    _compassTimer?.cancel();
    _compassTimer = Timer.periodic(
      compassRefreshInterval,
      (_) => unawaited(_renderCompassFrame()),
    );
  }

  /// Stops the on-glasses compass. By default the display is cleared so the
  /// last ribbon does not stay lit.
  Future<void> stopCompass({bool clearDisplay = true}) async {
    _compassTimer?.cancel();
    _compassTimer = null;
    final wasActive = _compassActive;
    _compassActive = false;
    _compassDisplayHeading = null;
    if (wasActive) notifyListeners();

    if (!wasActive || !_connected) return;
    await _run(() async {
      // A frame can be interrupted mid-hold, so reset the hold counter.
      await transport.send(ActiveLookCommands.resetAndFlush());
      if (clearDisplay) {
        await transport.send(ActiveLookCommands.clear());
        await transport.send(ActiveLookCommands.flush());
      }
      notifyListeners();
    });
  }

  Future<void> _renderCompassFrame() async {
    if (!_compassActive || !_connected || _compassFrameInFlight) return;
    _compassFrameInFlight = true;

    final heading = _compassHeading;
    final commands = heading == null
        ? CompassRibbon.waitingFrame(colorCapable: isColorCapable)
        : CompassRibbon.frame(heading: heading, colorCapable: isColorCapable);

    _compassDisplayHeading = heading == null ? null : normalizeHeading(heading);
    _lastRenderedText = '';
    _frameShapes = const [];
    _lastFrameBytes = _encodedSize(commands);
    notifyListeners();

    try {
      for (final command in commands) {
        if (!_compassActive || !_connected) return;
        await transport.send(command);
      }
    } catch (error) {
      _error = '$error';
      await stopCompass(clearDisplay: false);
    } finally {
      _compassFrameInFlight = false;
    }
  }

  void _onCompassHeading(double? heading) {
    if (heading == null || heading.isNaN || !_connected) return;
    _compassHeading = normalizeHeading(heading);
    // Sensors can emit tens of values per second; coalesce UI rebuilds.
    _compassNotifyTimer ??= Timer(const Duration(milliseconds: 100), () {
      _compassNotifyTimer = null;
      notifyListeners();
    });
  }

  Future<void> _renderColorShowFrame() async {
    final mode = _colorShowMode;
    if (mode == null || !_connected || _frameInFlight) return;

    _frameInFlight = true;
    try {
      switch (mode) {
        case ColorShowMode.pulse:
          await _renderPulseFrame();
        case ColorShowMode.sweep:
          await _renderSweepStep();
        case ColorShowMode.counter:
          await _renderCounterFrame();
      }
    } catch (error) {
      _error = '$error';
      await stopColorShow();
    } finally {
      _frameInFlight = false;
    }
  }

  /// Full-screen redraw of the concentric rings: one hold/flush cycle.
  Future<void> _renderPulseFrame() async {
    _colorShowPhase = (_colorShowPhase + 1) % ColorShow.ramp.length;
    final shapes = ColorShow.frame(ColorShowMode.pulse, _colorShowPhase);
    final commands = [
      ActiveLookCommands.hold(),
      ActiveLookCommands.clear(),
      ...ColorShow.drawCommands(shapes),
      ActiveLookCommands.flush(),
    ];

    _frameShapes = shapes;
    _lastFrameBytes = _encodedSize(commands);
    notifyListeners();

    for (final command in commands) {
      if (_colorShowMode != ColorShowMode.pulse) return;
      await transport.send(command);
    }
  }

  /// Incremental sweep: one new arc segment per frame — `color` + `arc`, 2
  /// commands and ~21 bytes. The panel keeps the previous segments, so no
  /// full-screen redraw is needed and the link stays almost idle.
  Future<void> _renderSweepStep() async {
    final commands = <ActiveLookCommand>[];

    if (_sweepStep == 0) {
      // New revolution: wipe the panel once (3 commands per ~2.5 s).
      _sweepScene.clear();
      commands.addAll([
        ActiveLookCommands.hold(),
        ActiveLookCommands.clear(),
        ActiveLookCommands.flush(),
      ]);
    }

    final segment = ColorShow.sweepSegment(_sweepStep);
    commands.addAll([
      ActiveLookCommands.color(segment.color),
      ActiveLookCommands.arc(
        x: segment.x,
        y: segment.y,
        radius: segment.radius,
        startAngle: segment.startAngle,
        endAngle: segment.endAngle,
        thickness: segment.thickness,
      ),
    ]);

    _frameShapes = List<GlassesShape>.unmodifiable([..._sweepScene, segment]);
    _sweepScene.add(segment);
    _sweepStep = (_sweepStep + 1) % ColorShow.sweepSteps;
    _lastFrameBytes = _encodedSize(commands);
    notifyListeners();

    for (final command in commands) {
      if (_colorShowMode != ColorShowMode.sweep) return;
      await transport.send(command);
    }
  }

  int _encodedSize(List<ActiveLookCommand> commands) =>
      commands.fold(0, (sum, command) => sum + command.encode().length);

  /// One short `txtColor` per frame: the fastest readable update with the
  /// smallest possible payload (4 commands, ~30–35 bytes, no graphics).
  Future<void> _renderCounterFrame() async {
    _counterValue++;
    final color = ColorShow.ramp[_counterValue % ColorShow.ramp.length];
    final text = '$_counterValue';
    final commands = [
      ActiveLookCommands.hold(),
      ActiveLookCommands.clear(),
      ActiveLookCommands.textColor(
        x: _textAnchorX,
        y: _textAnchorY,
        text: text,
        color: color,
      ),
      ActiveLookCommands.flush(),
    ];

    _counterColor = color;
    _lastRenderedText = text;
    _frameShapes = const [];
    _lastFrameBytes = _encodedSize(commands);
    notifyListeners();

    for (final command in commands) {
      if (_colorShowMode != ColorShowMode.counter) return;
      await transport.send(command);
    }
  }

  /// Sets the display luminance (0..15). The value is stored by the glasses.
  Future<void> setLuma(int level) async {
    _luma = level.clamp(0, 15);
    notifyListeners();
    await _run(() => transport.send(ActiveLookCommands.luma(_luma)));
  }

  void setTextColor(int color) {
    _textColor = color;
    notifyListeners();
  }

  /// Plays a built-in demo pattern (0: fill, 1: rectangle with a cross…).
  Future<void> showDemoPattern(int pattern) =>
      _run(() => transport.send(ActiveLookCommands.demo(pattern)));

  Future<void> refreshBattery() => _run(
    () => transport.send(ActiveLookCommands.battery(queryId: const [0x11])),
  );

  Future<void> disconnect() async {
    await transport.disconnect();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!_connected) return;
    _setBusy(true);
    _error = null;
    try {
      await action();
    } catch (error) {
      _error = '$error';
    } finally {
      _setBusy(false);
    }
  }

  void _onEvent(GlassesEvent event) {
    switch (event) {
      case GlassesConnectionChanged(:final connected, :final reason):
        _connected = connected;
        if (reason != null) _error = reason;
        if (!connected) {
          _colorShowTimer?.cancel();
          _colorShowTimer = null;
          _colorShowMode = null;
          _frameShapes = const [];
          _compassTimer?.cancel();
          _compassTimer = null;
          _compassActive = false;
          _compassDisplayHeading = null;
        }
      case GlassesInfoChanged(:final info):
        _info = info;
      case GlassesMessageReceived(:final message):
        _append(
          'разобрано ${message.id.toRadixString(16)} → ${hex(message.data)}',
        );
      case GlassesControlReceived(:final value):
        _append('управление 0x${value.toRadixString(16).padLeft(2, '0')}');
      case GlassesLog(:final text):
        _append(text);
      case GlassesError(:final message):
        _error = message;
        _append('ОШИБКА $message');
    }
    _notifySoon();
  }

  /// Coalesces BLE events into one rebuild per ~100 ms.
  ///
  /// An animation frame produces a dozen log events plus its own update; a
  /// notification per event would rebuild the whole screen needlessly.
  void _notifySoon() {
    if (_notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 100), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  void _append(String line) {
    _log.add(line);
    if (_log.length > 300) _log.removeAt(0);
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _colorShowTimer?.cancel();
    _notifyTimer?.cancel();
    _compassTimer?.cancel();
    _compassNotifyTimer?.cancel();
    _subscription?.cancel();
    _compassSubscription?.cancel();
    compass.dispose();
    transport.dispose();
    super.dispose();
  }
}
