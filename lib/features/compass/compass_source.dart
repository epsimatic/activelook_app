/// Source of device heading values for the compass feature.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// Stream of heading updates, in degrees clockwise from north.
///
/// Abstracted so the compass UI and the glasses controller can be tested
/// without a magnetometer, and so desktop builds (macOS in this project) never
/// touch a plugin that only exists on mobile.
abstract class CompassSource {
  /// Whether a compass sensor can be expected on this platform.
  bool get isSupported;

  /// Heading values in degrees, or `null` when the sensor has no fix yet.
  Stream<double?> get headings;

  Future<void> dispose();
}

/// [CompassSource] backed by the `flutter_compass` plugin.
///
/// The plugin only ships Android and iOS implementations, so desktop/web
/// builds report [isSupported] as `false` and never subscribe to the channel
/// (subscribing there throws `MissingPluginException`).
class DeviceCompassSource implements CompassSource {
  @override
  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Stream<double?> get headings {
    if (!isSupported) return const Stream<double?>.empty();
    return FlutterCompass.events!
        .map<double?>((event) => event.heading)
        // A sensor error must not take the screen down; keep the last heading.
        .handleError((Object _) {});
  }

  @override
  Future<void> dispose() async {}
}
