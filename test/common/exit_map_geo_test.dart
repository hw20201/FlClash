import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes cities before countries and handles relay names', () {
    for (final (name, country, city) in [
      ('香港 03', 'HK', '香港'),
      ('JP-Tokyo-02', 'JP', '东京'),
      ('🇺🇸 日本 东京 02', 'JP', '东京'),
      ('中国 深圳 → JP-Tokyo-02', 'JP', '东京'),
      ('US New-York 01', 'US', '纽约'),
    ]) {
      final place = locateExit(name);
      expect(place?.country, country, reason: name);
      expect(place?.city, city, reason: name);
      expect(place?.approximate, isFalse, reason: name);
    }
  });

  test('does not mistake country substrings or ordinary words for cities', () {
    expect(locateExit('罗马尼亚 01')?.country, 'RO');
    expect(locateExit('Romania 01')?.country, 'RO');
    expect(locateExit('Indonesia 01')?.country, 'ID');
    expect(locateExit('in my network'), isNull);
    expect(locateExit('流量 100GB'), isNull);
    expect(locateExit('unknown node'), isNull);
    expect(locateExit('IN-02')?.country, 'IN');
    expect(locateExit('🇬🇧 01')?.country, 'GB');
    expect(locateExit('jp-02')?.country, 'JP');
  });

  test(
    'country fallback is marked approximate and ISO flags are validated',
    () {
      final country = exitMapCountry(' us ');
      expect(country?.country, 'US');
      expect(country?.approximate, isTrue);
      expect(country?.flag, '🇺🇸');
      expect(exitMapCountry('ZZ'), isNull);
      const invalid = ExitMapPlace(
        country: '123',
        city: '',
        latitude: 0,
        longitude: 0,
      );
      expect(invalid.flag, isEmpty);
      expect(country, exitMapCountry('US'));
      expect(country.hashCode, exitMapCountry('US').hashCode);
    },
  );
}
