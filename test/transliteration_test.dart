import 'package:activelook_app/models/transliteration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cyrillic is transliterated to ASCII', () {
    expect(toGlassesText('Привет'), 'Privet');
    expect(toGlassesText('ПРИВЕТ'), 'PRIVET');
    expect(toGlassesText('Ёж, щука, Юля и Яна'), 'Ezh, shchuka, Yulya i Yana');
    expect(
      toGlassesText('съешь ещё этих мягких булок'),
      'sesh eshche etikh myagkikh bulok',
    );
  });

  test('ASCII, digits and punctuation pass through unchanged', () {
    expect(toGlassesText('Hi 42!'), 'Hi 42!');
    expect(toGlassesText('— «Ёлка» …'), '— «Elka» …');
    expect(toGlassesText(''), '');
  });
}
