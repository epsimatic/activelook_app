/// ActiveLook® command protocol: frame encoding, parsing and command builders.
///
/// Reference: [ActiveLook_API.md](https://github.com/ActiveLook/Activelook-API-Documentation)
///
/// A frame is laid out as:
///
/// ```
/// 0xFF | commandId | format | length | [queryId] | [data] | 0xAA
/// ```
///
/// * `format` bit 5 selects a 2-byte `length` field, bits 4..1 are the queryId size.
/// * `length` counts the whole frame, header and footer included.
/// * All multi-byte values are big-endian.
library;

import 'dart:convert';
import 'dart:typed_data';

/// ActiveLook command identifiers used by this demo.
abstract final class ActiveLookCommandId {
  static const int displayPower = 0x00;
  static const int clear = 0x01;
  static const int grey = 0x02;
  static const int demo = 0x03;
  static const int battery = 0x05;
  static const int vers = 0x06;
  static const int led = 0x08;
  static const int shift = 0x09;
  static const int settings = 0x0A;

  static const int luma = 0x10;

  static const int grayscale = 0x30;
  static const int point = 0x31;
  static const int line = 0x32;
  static const int rect = 0x33;
  static const int rectf = 0x34;
  static const int circ = 0x35;
  static const int circf = 0x36;
  static const int text = 0x37;
  static const int polyline = 0x38;
  static const int holdFlush = 0x39;
  static const int arc = 0x3C;
  static const int color = 0x3D;
  static const int textColor = 0x3E;

  static const int imgSave = 0x41;
  static const int imgDisplay = 0x42;
  static const int imgStream = 0x44;
  static const int imgDelete = 0x46;
  static const int imgList = 0x47;

  static const int fontList = 0x50;
  static const int fontSave = 0x51;
  static const int fontSelect = 0x52;
  static const int fontDelete = 0x53;

  static const int layoutSave = 0x60;
  static const int layoutDelete = 0x61;
  static const int layoutDisplay = 0x62;
  static const int layoutClear = 0x63;
  static const int layoutList = 0x64;
  static const int layoutPosition = 0x65;
  static const int layoutDisplayExtended = 0x66;
  static const int layoutGet = 0x67;
  static const int layoutClearExtended = 0x68;
  static const int layoutClearAndDisplay = 0x69;

  static const int gaugeDisplay = 0x70;
  static const int gaugeSave = 0x71;
  static const int gaugeDelete = 0x72;
  static const int gaugeList = 0x73;

  static const int pageSave = 0x80;
  static const int pageGet = 0x81;
  static const int pageDisplay = 0x83;
  static const int pageClear = 0x84;
  static const int pageList = 0x85;
  static const int pageClearAndDisplay = 0x86;

  static const int cfgWrite = 0xD0;
  static const int cfgRead = 0xD1;
  static const int cfgSet = 0xD2;
  static const int cfgList = 0xD3;
  static const int cfgDeleteLessUsed = 0xD6;
  static const int cfgFreeSpace = 0xD7;
  static const int cfgGetNb = 0xD8;

  static const int shutdown = 0xE0;
  static const int reset = 0xE1;
  static const int error = 0xE2;
  static const int rdDevInfo = 0xE3;
}

/// Text orientation, as documented in section 5.7 of the API spec.
///
/// [topLeftToRight] (0x04) is regular, upright, left-to-right text.
enum TextRotation {
  bottomRightToLeft(0x00),
  bottomLeftToRight(0x01),
  leftBottomToTop(0x02),
  leftTopToBottom(0x03),
  topLeftToRight(0x04),
  topRightToLeft(0x05),
  rightTopToBottom(0x06),
  rightBottomToTop(0x07);

  const TextRotation(this.value);

  final int value;
}

/// A command to send to the glasses, encoded on demand into a BLE frame.
class ActiveLookCommand {
  ActiveLookCommand(this.id, {this.data = const [], this.queryId = const []})
    : assert(id >= 0 && id <= 0xFF, 'command id must fit in one byte'),
      assert(queryId.length <= 15, 'queryId is limited to 15 bytes'),
      assert(data.length <= 512, 'command data is limited to 512 bytes');

  final int id;
  final List<int> data;
  final List<int> queryId;

  /// Encodes the command into a frame ready for the RX characteristic.
  Uint8List encode() {
    final bodyLength = 5 + queryId.length + data.length;
    final useLongLength = bodyLength > 0xFF;
    final totalLength = useLongLength ? bodyLength + 1 : bodyLength;

    final frame = Uint8List(totalLength);
    var offset = 0;
    frame[offset++] = 0xFF;
    frame[offset++] = id;
    frame[offset++] = (useLongLength ? 0x10 : 0x00) | queryId.length;
    if (useLongLength) {
      frame[offset++] = (totalLength >> 8) & 0xFF;
      frame[offset++] = totalLength & 0xFF;
    } else {
      frame[offset++] = totalLength & 0xFF;
    }
    frame.setRange(offset, offset + queryId.length, queryId);
    offset += queryId.length;
    frame.setRange(offset, offset + data.length, data);
    offset += data.length;
    frame[offset] = 0xAA;
    return frame;
  }

  @override
  String toString() =>
      'ActiveLookCommand(0x${id.toRadixString(16).padLeft(2, '0')})';
}

/// A message received from the glasses (TX or control characteristic).
class ActiveLookMessage {
  const ActiveLookMessage({
    required this.id,
    required this.queryId,
    required this.data,
  });

  final int id;
  final List<int> queryId;
  final List<int> data;

  @override
  String toString() =>
      'ActiveLookMessage(0x${id.toRadixString(16).padLeft(2, '0')}, '
      'queryId: ${hex(queryId)}, data: ${hex(data)})';
}

/// Reassembles ActiveLook frames from arbitrary BLE notification chunks.
///
/// A frame can be split across several notifications, so incoming bytes are
/// buffered until a complete frame (matching `length` and the `0xAA` footer) is
/// available.
class ActiveLookFrameParser {
  final List<int> _buffer = [];

  /// Feeds [chunk] and returns every complete message it completes.
  List<ActiveLookMessage> add(List<int> chunk) {
    _buffer.addAll(chunk);
    final messages = <ActiveLookMessage>[];

    while (_buffer.isNotEmpty) {
      if (_buffer[0] != 0xFF) {
        // Resynchronise on the next start byte.
        _buffer.removeAt(0);
        continue;
      }
      if (_buffer.length < 4) break;

      final format = _buffer[2];
      final useLongLength = (format & 0x10) != 0;
      final queryIdLength = format & 0x0F;
      final headerLength = useLongLength ? 5 : 4;
      if (_buffer.length < headerLength) break;

      final totalLength = useLongLength
          ? ((_buffer[3] << 8) | _buffer[4])
          : _buffer[3];
      if (totalLength < headerLength + 1 || totalLength > 533) {
        _buffer.removeAt(0);
        continue;
      }
      if (_buffer.length < totalLength) break;

      if (_buffer[totalLength - 1] != 0xAA) {
        _buffer.removeAt(0);
        continue;
      }

      final queryIdStart = headerLength;
      final dataStart = queryIdStart + queryIdLength;
      messages.add(
        ActiveLookMessage(
          id: _buffer[1],
          queryId: List<int>.unmodifiable(
            _buffer.sublist(queryIdStart, dataStart),
          ),
          data: List<int>.unmodifiable(
            _buffer.sublist(dataStart, totalLength - 1),
          ),
        ),
      );
      _buffer.removeRange(0, totalLength);
    }

    return messages;
  }

  void reset() => _buffer.clear();
}

/// Builders for the commands this demo needs.
///
/// Command IDs and parameter orders come straight from the API spec; see
/// section 4 of `ActiveLook_API.md`.
abstract final class ActiveLookCommands {
  /// `displayPower` (0x00)
  static ActiveLookCommand displayPower({required bool enabled}) =>
      ActiveLookCommand(
        ActiveLookCommandId.displayPower,
        data: [enabled ? 1 : 0],
      );

  /// `clear` (0x01) — fills the display memory with black.
  static ActiveLookCommand clear() =>
      ActiveLookCommand(ActiveLookCommandId.clear);

  /// `grey` (0x02) — fills the whole display with a grey level (0..15).
  static ActiveLookCommand grey(int level) =>
      ActiveLookCommand(ActiveLookCommandId.grey, data: [_u8(level)]);

  /// `demo` (0x03) — built-in demo patterns, handy to check a connection.
  static ActiveLookCommand demo(int pattern) =>
      ActiveLookCommand(ActiveLookCommandId.demo, data: [_u8(pattern)]);

  /// `battery` (0x05) — asks the glasses for their battery level.
  static ActiveLookCommand battery({List<int> queryId = const [0x01]}) =>
      ActiveLookCommand(ActiveLookCommandId.battery, queryId: queryId);

  /// `vers` (0x06) — asks the glasses for their firmware version.
  static ActiveLookCommand vers({List<int> queryId = const [0x02]}) =>
      ActiveLookCommand(ActiveLookCommandId.vers, queryId: queryId);

  /// `shift` (0x09)
  static ActiveLookCommand shift({required int x, required int y}) =>
      ActiveLookCommand(
        ActiveLookCommandId.shift,
        data: [..._s16(x), ..._s16(y)],
      );

  /// `luma` (0x10) — display luminance (0..15), persisted by the glasses.
  static ActiveLookCommand luma(int level) =>
      ActiveLookCommand(ActiveLookCommandId.luma, data: [_u8(level)]);

  /// `sensor` (0x20) — auto-brightness and gesture detection.
  static ActiveLookCommand sensor({required bool enabled}) =>
      ActiveLookCommand(0x20, data: [enabled ? 1 : 0]);

  /// `gesture` (0x21)
  static ActiveLookCommand gesture({required bool enabled}) =>
      ActiveLookCommand(0x21, data: [enabled ? 1 : 0]);

  /// `als` (0x22) — optical sensor auto-brightness.
  static ActiveLookCommand als({required bool enabled}) =>
      ActiveLookCommand(0x22, data: [enabled ? 1 : 0]);

  /// `grayscale` (0x30) — grey level used by the next graphical element.
  static ActiveLookCommand grayscale(int level) =>
      ActiveLookCommand(ActiveLookCommandId.grayscale, data: [_u8(level)]);

  /// `color` (0x3D) — RG color used by the next graphical element.
  ///
  /// Only available on color glasses (`MDP08`).
  static ActiveLookCommand color(int value) =>
      ActiveLookCommand(ActiveLookCommandId.color, data: [_u8(value)]);

  /// `line` (0x32) — straight line between ([x0], [y0]) and ([x1], [y1]).
  ///
  /// Uses the color set by the last [color] or [grayscale] command.
  static ActiveLookCommand line({
    required int x0,
    required int y0,
    required int x1,
    required int y1,
  }) => ActiveLookCommand(
    ActiveLookCommandId.line,
    data: [..._s16(x0), ..._s16(y0), ..._s16(x1), ..._s16(y1)],
  );

  /// `rectf` (0x34) — filled rectangle between ([x0], [y0]) and ([x1], [y1]).
  ///
  /// Uses the color set by the last [color] or [grayscale] command.
  static ActiveLookCommand rectf({
    required int x0,
    required int y0,
    required int x1,
    required int y1,
  }) => ActiveLookCommand(
    ActiveLookCommandId.rectf,
    data: [..._s16(x0), ..._s16(y0), ..._s16(x1), ..._s16(y1)],
  );

  /// `circf` (0x36) — filled circle centred on ([x], [y]).
  ///
  /// The radius is an unsigned byte, so it is limited to 255 px.
  static ActiveLookCommand circf({
    required int x,
    required int y,
    required int radius,
  }) => ActiveLookCommand(
    ActiveLookCommandId.circf,
    data: [..._s16(x), ..._s16(y), _u8(radius)],
  );

  /// `arc` (0x3C) — circular arc of [thickness] px.
  ///
  /// Angles are in degrees, 0° at 3 o'clock, increasing clockwise.
  static ActiveLookCommand arc({
    required int x,
    required int y,
    required int radius,
    required int startAngle,
    required int endAngle,
    required int thickness,
  }) => ActiveLookCommand(
    ActiveLookCommandId.arc,
    data: [
      ..._s16(x),
      ..._s16(y),
      _u8(radius),
      ..._s16(startAngle),
      ..._s16(endAngle),
      _u8(thickness),
    ],
  );

  /// `txt` (0x37) — draws [text] at ([x], [y]).
  ///
  /// Built-in fonts: 0/1 = 24 px, 2 = 35 px, 3 = 49 px (largest). Defaults to
  /// the biggest one so demo text fills the panel. [grey] is 0..15, and
  /// [rotation] defaults to regular upright text.
  static ActiveLookCommand text({
    required int x,
    required int y,
    required String text,
    TextRotation rotation = TextRotation.topLeftToRight,
    int font = 3,
    int grey = 15,
  }) => ActiveLookCommand(
    ActiveLookCommandId.text,
    data: [
      ..._s16(x),
      ..._s16(y),
      rotation.value,
      _u8(font),
      _u8(grey),
      ..._cString(text),
    ],
  );

  /// `txtColor` (0x3E) — color-glasses counterpart of [text].
  static ActiveLookCommand textColor({
    required int x,
    required int y,
    required String text,
    TextRotation rotation = TextRotation.topLeftToRight,
    int font = 3,
    int color = 0xFF,
  }) => ActiveLookCommand(
    ActiveLookCommandId.textColor,
    data: [
      ..._s16(x),
      ..._s16(y),
      rotation.value,
      _u8(font),
      _u8(color),
      ..._cString(text),
    ],
  );

  /// `holdFlush` (0x39) — hold drawing (0), flush (1) or reset all holds (0xFF).
  ///
  /// Wrapping a group of drawing commands between [hold] and [flush] makes the
  /// panel refresh once, avoiding flicker and saving power.
  static ActiveLookCommand holdFlush(int action) =>
      ActiveLookCommand(ActiveLookCommandId.holdFlush, data: [action]);

  static ActiveLookCommand hold() => holdFlush(0x00);

  static ActiveLookCommand flush() => holdFlush(0x01);

  static ActiveLookCommand resetAndFlush() => holdFlush(0xFF);

  /// `fontSelect` (0x52)
  static ActiveLookCommand fontSelect(int font) =>
      ActiveLookCommand(ActiveLookCommandId.fontSelect, data: [_u8(font)]);

  /// `fontList` (0x50)
  static ActiveLookCommand fontList({List<int> queryId = const [0x03]}) =>
      ActiveLookCommand(ActiveLookCommandId.fontList, queryId: queryId);

  /// `layoutDisplay` (0x62)
  static ActiveLookCommand layoutDisplay({
    required int id,
    required String text,
  }) => ActiveLookCommand(
    ActiveLookCommandId.layoutDisplay,
    data: [_u8(id), ..._cString(text)],
  );

  /// `layoutClearAndDisplay` (0x69)
  static ActiveLookCommand layoutClearAndDisplay({
    required int id,
    required String text,
  }) => ActiveLookCommand(
    ActiveLookCommandId.layoutClearAndDisplay,
    data: [_u8(id), ..._cString(text)],
  );

  /// `pageDisplay` (0x83)
  static ActiveLookCommand pageDisplay({
    required int id,
    required List<String> texts,
  }) => ActiveLookCommand(
    ActiveLookCommandId.pageDisplay,
    data: [_u8(id), for (final text in texts) ..._cString(text)],
  );

  /// `gaugeDisplay` (0x70)
  static ActiveLookCommand gaugeDisplay({
    required int id,
    required int value,
  }) => ActiveLookCommand(
    ActiveLookCommandId.gaugeDisplay,
    data: [_u8(id), _u8(value)],
  );

  /// `rdDevInfo` (0xE3)
  static ActiveLookCommand readDeviceInfo(
    int parameter, {
    List<int> queryId = const [0x04],
  }) => ActiveLookCommand(
    ActiveLookCommandId.rdDevInfo,
    data: [_u8(parameter)],
    queryId: queryId,
  );
}

/// Formats bytes as an uppercase hex string (`FF 39 00 06 00 AA`).
String hex(Iterable<int> bytes) => bytes
    .map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

/// Decodes the `vers` (0x06) response payload into a human readable version.
String decodeFirmwareVersion(List<int> data) {
  if (data.length < 4) return 'неизвестно';
  final suffix = data[3] == 0 ? '' : String.fromCharCode(data[3]);
  return '${data[0]}.${data[1]}.${data[2]}$suffix';
}

int _u8(int value) {
  if (value < 0 || value > 0xFF) {
    throw RangeError.range(value, 0, 0xFF, 'value', 'must fit in one byte');
  }
  return value;
}

List<int> _s16(int value) {
  if (value < -32768 || value > 32767) {
    throw RangeError.range(
      value,
      -32768,
      32767,
      'value',
      'must fit in a signed 16-bit integer',
    );
  }
  final v = value & 0xFFFF;
  return [(v >> 8) & 0xFF, v & 0xFF];
}

List<int> _cString(String value) {
  final bytes = utf8.encode(value);
  final truncated = bytes.length > 254 ? bytes.sublist(0, 254) : bytes;
  return [...truncated, 0x00];
}
