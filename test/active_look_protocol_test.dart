import 'package:activelook_flutter/protocol/active_look_advertisement.dart';
import 'package:activelook_flutter/protocol/active_look_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('frame encoding', () {
    test('clear matches the spec example', () {
      expect(hex(ActiveLookCommands.clear().encode()), 'FF 01 00 05 AA');
    });

    test('hold and flush set the right action byte', () {
      expect(hex(ActiveLookCommands.hold().encode()), 'FF 39 00 06 00 AA');
      expect(hex(ActiveLookCommands.flush().encode()), 'FF 39 00 06 01 AA');
      expect(
        hex(ActiveLookCommands.resetAndFlush().encode()),
        'FF 39 00 06 FF AA',
      );
    });

    test('txt encodes text with a NUL terminator', () {
      final frame = ActiveLookCommands.text(
        x: 152,
        y: 128,
        text: 'Hi',
        rotation: TextRotation.topLeftToRight,
        font: 2,
        grey: 15,
      ).encode();
      expect(hex(frame), 'FF 37 00 0F 00 98 00 80 04 02 0F 48 69 00 AA');
    });

    test('txtColor uses command 0x3E and the largest built-in font', () {
      final frame = ActiveLookCommands.textColor(
        x: 152,
        y: 128,
        text: 'Hi',
        color: 0xFF,
      ).encode();
      expect(hex(frame), 'FF 3E 00 0F 00 98 00 80 04 03 FF 48 69 00 AA');
    });

    test('rectf encodes the two opposite corners', () {
      final frame = ActiveLookCommands.rectf(
        x0: 0,
        y0: 0,
        x1: 303,
        y1: 255,
      ).encode();
      expect(hex(frame), 'FF 34 00 0D 00 00 00 00 01 2F 00 FF AA');
    });

    test('circf encodes centre and radius', () {
      final frame = ActiveLookCommands.circf(
        x: 152,
        y: 128,
        radius: 199,
      ).encode();
      expect(hex(frame), 'FF 36 00 0A 00 98 00 80 C7 AA');
    });

    test('arc encodes centre, radius, angles and thickness', () {
      final frame = ActiveLookCommands.arc(
        x: 152,
        y: 128,
        radius: 92,
        startAngle: 0,
        endAngle: 12,
        thickness: 20,
      ).encode();
      expect(hex(frame), 'FF 3C 00 0F 00 98 00 80 5C 00 00 00 0C 14 AA');
    });

    test('queryId is included and counted in the format byte', () {
      final frame = ActiveLookCommand(
        0x05,
        queryId: const [0x02, 0x01],
      ).encode();
      expect(hex(frame), 'FF 05 02 07 02 01 AA');
    });

    test('switches to a two byte length above 255 bytes', () {
      final frame = ActiveLookCommands.text(
        x: 0,
        y: 0,
        text: 'x' * 300,
      ).encode();
      // 5 header bytes + 7 parameters + 255 string bytes = 267, plus one byte
      // because the length field itself grows to two bytes → 268 = 0x010C.
      expect(frame[2], 0x10);
      expect(frame[3], 0x01);
      expect(frame[4], 0x0C);
      expect(frame.length, 268);
      expect(frame.last, 0xAA);
    });

    test('rejects values that do not fit', () {
      expect(() => ActiveLookCommands.grayscale(256), throwsRangeError);
      expect(
        () => ActiveLookCommands.text(x: 40000, y: 0, text: 'x'),
        throwsRangeError,
      );
      expect(
        () => ActiveLookCommands.circf(x: 0, y: 0, radius: 256),
        throwsRangeError,
      );
    });
  });

  group('frame parsing', () {
    test('parses one complete message', () {
      final parser = ActiveLookFrameParser();
      final messages = parser.add(hexToBytes('FF 05 01 07 03 50 AA'));
      expect(messages, hasLength(1));
      expect(messages.single.id, 0x05);
      expect(messages.single.queryId, [0x03]);
      expect(messages.single.data, [0x50]);
    });

    test('reassembles a frame split across notifications', () {
      final parser = ActiveLookFrameParser();
      final frame = ActiveLookCommands.text(
        x: 152,
        y: 128,
        text: 'Hi',
      ).encode();

      expect(parser.add(frame.sublist(0, 4)), isEmpty);
      expect(parser.add(frame.sublist(4, 11)), isEmpty);
      final messages = parser.add(frame.sublist(11));
      expect(messages, hasLength(1));
      expect(messages.single.id, ActiveLookCommandId.text);
      expect(String.fromCharCodes(messages.single.data.sublist(7, 9)), 'Hi');
    });

    test('parses several messages from a single chunk', () {
      final parser = ActiveLookFrameParser();
      final chunk = [
        ...ActiveLookCommands.hold().encode(),
        ...ActiveLookCommands.flush().encode(),
      ];
      final messages = parser.add(chunk);
      expect(messages.map((m) => m.id), [
        ActiveLookCommandId.holdFlush,
        ActiveLookCommandId.holdFlush,
      ]);
      expect(messages.first.data, [0x00]);
      expect(messages.last.data, [0x01]);
    });

    test('resynchronises when the stream starts with garbage', () {
      final parser = ActiveLookFrameParser();
      final messages = parser.add([
        0x00,
        0x12,
        ...ActiveLookCommands.clear().encode(),
      ]);
      expect(messages, hasLength(1));
      expect(messages.single.id, ActiveLookCommandId.clear);
    });

    test('drops frames with a bad footer', () {
      final parser = ActiveLookFrameParser();
      expect(
        parser.add([
          0xFF,
          0x01,
          0x00,
          0x05,
          0xBB,
          0xFF,
          0x01,
          0x00,
          0x05,
          0xAA,
        ]),
        hasLength(1),
      );
    });
  });

  group('decoding', () {
    test('formats the firmware version like the spec', () {
      expect(decodeFirmwareVersion([0x03, 0x05, 0x00, 0x62]), '3.5.0b');
      expect(decodeFirmwareVersion([0x04, 0x0E, 0x02, 0x00]), '4.14.2');
      expect(decodeFirmwareVersion([]), 'неизвестно');
    });
  });

  group('advertisement detection', () {
    test('matches the ActiveLook name prefix', () {
      expect(isActiveLookAdvertisement(name: 'A.Look 000128'), isTrue);
      expect(isActiveLookAdvertisement(name: 'A.LooK 000128'), isTrue);
      expect(isActiveLookAdvertisement(name: 'Polar H10'), isFalse);
    });

    test('matches the 0x08F2 manufacturer marker', () {
      expect(
        isActiveLookAdvertisement(
          name: '',
          manufacturerData: [
            [0xDA, 0xFA, 0x08, 0xF2],
          ],
        ),
        isTrue,
      );
      expect(
        isActiveLookAdvertisement(
          name: '',
          manufacturerData: [
            [0x4C, 0x00, 0x02, 0x15],
          ],
        ),
        isFalse,
      );
    });
  });
}

/// Parses a `FF 01 00 05 AA` style string, handy for spec examples.
List<int> hexToBytes(String value) => value
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .map((part) => int.parse(part, radix: 16))
    .toList();
