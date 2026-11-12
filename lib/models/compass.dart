/// Compass helpers shared by the phone-side HUD ribbon and the glasses
/// renderer.
///
/// The heading follows the device's magnetometer/rotation-vector sensor:
/// 0° is north, values increase clockwise.
library;

/// Eight-point compass labels, clockwise from north.
///
/// The glasses draw the same letters along the ribbon, so this list is the
/// single source of truth for both.
const List<String> compassLabels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

/// Wraps [degrees] into the `0 <= value < 360` range.
double normalizeHeading(double degrees) {
  final value = degrees % 360;
  return value < 0 ? value + 360 : value;
}

/// Index into [compassLabels] of the 45° sector that contains [degrees].
int compassLabelIndex(double degrees) =>
    ((normalizeHeading(degrees) + 22.5) ~/ 45) % compassLabels.length;

/// Cardinal or intercardinal label for [degrees], e.g. `N`, `NE`, `SW`.
String compassLabel(double degrees) =>
    compassLabels[compassLabelIndex(degrees)];

/// Heading rounded to a whole degree in `0..359`.
int compassDegrees(double degrees) => normalizeHeading(degrees).round() % 360;
