part 'exit_map_geo_data.dart';

class ExitMapPlace {
  const ExitMapPlace({
    required this.country,
    required this.city,
    required this.latitude,
    required this.longitude,
    this.approximate = false,
  });

  final String country;
  final String city;
  final double latitude;
  final double longitude;
  final bool approximate;

  String get flag {
    final letters = country.toUpperCase().codeUnits;
    if (letters.length != 2 || letters.any((unit) => unit < 65 || unit > 90)) {
      return '';
    }
    return String.fromCharCodes(letters.map((unit) => unit + 0x1f1a5));
  }

  @override
  bool operator ==(Object other) =>
      other is ExitMapPlace &&
      country == other.country &&
      city == other.city &&
      latitude == other.latitude &&
      longitude == other.longitude &&
      approximate == other.approximate;

  @override
  int get hashCode =>
      Object.hash(country, city, latitude, longitude, approximate);
}

ExitMapPlace? exitMapCountry(String code) =>
    _index.countries[code.trim().toUpperCase()];

ExitMapPlace? locateExit(String name) => _index.lookup(name);

final _index = _PlaceIndex();

class _PlaceIndex {
  _PlaceIndex() {
    final cities = <(String, String), ExitMapPlace>{};
    final cityNames = <String, ExitMapPlace>{};
    for (final (country, city, lat, lon, aliases) in _cities) {
      final place = ExitMapPlace(
        country: country,
        city: city,
        latitude: lat,
        longitude: lon,
      );
      cities[(country, city)] = place;
      for (final alias in aliases) {
        cityNames[alias] = place;
      }
    }
    final regionNames = <String, ExitMapPlace>{};
    final codes = <String, ExitMapPlace>{};
    final shortCodes = <String, ExitMapPlace>{};
    for (final (code, city, aliases) in _countries) {
      final representative = cities[(code, city)]!;
      final place = ExitMapPlace(
        country: code,
        city: city,
        latitude: representative.latitude,
        longitude: representative.longitude,
        approximate: true,
      );
      countries[code] = place;
      for (final alias in aliases) {
        regionNames[alias] = place;
      }
      regionNames[place.flag] = place;
      final target = _ambiguousCodes.contains(code) ? shortCodes : codes;
      target[code] = place;
    }
    _names = _PlaceAliases({...regionNames, ...cityNames});
    _codes = _PlaceAliases(codes);
    _shortCodes = _PlaceAliases(shortCodes, caseSensitive: true);
  }

  final countries = <String, ExitMapPlace>{};
  late final _PlaceAliases _names;
  late final _PlaceAliases _codes;
  late final _PlaceAliases _shortCodes;

  ExitMapPlace? lookup(String name) {
    ExitMapPlace? relay;
    ExitMapPlace? city;
    ExitMapPlace? region;
    for (final (_, place) in _names.matches(name)) {
      if (place.country == 'CN') {
        if (relay == null || relay.approximate) relay = place;
      } else if (place.approximate) {
        region = place;
      } else {
        city = place;
      }
    }
    if ((city ?? region) case final place?) return place;

    for (final index in [_codes, _shortCodes]) {
      ExitMapPlace? exit;
      for (final (start, place) in index.matches(name)) {
        if (place.country == 'GB' &&
            start > 0 &&
            _digit(name.codeUnitAt(start - 1))) {
          continue;
        }
        if (place.country == 'CN') {
          relay ??= place;
        } else {
          exit = place;
        }
      }
      if (exit != null) return exit;
    }
    return relay;
  }

  static bool _digit(int code) => code >= 48 && code <= 57;
}

const _ambiguousCodes = {'AT', 'BE', 'CO', 'EG', 'IN', 'IT', 'MY', 'NO'};
final _asciiName = RegExp(r'^[A-Za-z0-9 ]+$');
final _separators = RegExp(r'[ _-]+');

class _PlaceAliases {
  _PlaceAliases(Map<String, ExitMapPlace> aliases, {bool caseSensitive = false})
    : _places = {
        for (final entry in aliases.entries) _key(entry.key): entry.value,
      },
      _pattern = RegExp(
        _alternatives(aliases.keys),
        caseSensitive: caseSensitive,
      );

  final Map<String, ExitMapPlace> _places;
  final RegExp _pattern;

  Iterable<(int, ExitMapPlace)> matches(String text) sync* {
    for (final match in _pattern.allMatches(text)) {
      final place = _places[_key(match.group(0)!)];
      if (place != null) yield (match.start, place);
    }
  }

  static String _key(String name) =>
      name.replaceAll(_separators, '').toUpperCase();

  static String _alternatives(Iterable<String> names) {
    final ordered = names.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final ascii = <String>[];
    final literal = <String>[];
    for (final name in ordered) {
      if (_asciiName.hasMatch(name)) {
        ascii.add(name.split(' ').map(RegExp.escape).join('[ _-]*'));
      } else {
        literal.add(RegExp.escape(name));
      }
    }
    return [
      if (ascii.isNotEmpty) '(?<![A-Za-z])(?:${ascii.join('|')})(?![A-Za-z])',
      ...literal,
    ].join('|');
  }
}
