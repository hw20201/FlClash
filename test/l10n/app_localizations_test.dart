import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  test('load resolves accessors for every supported locale', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final appLocalizations = loadAppLocalizations(locale);

      expect(currentAppLocalizations.localeName, appLocalizations.localeName);
      expect(appLocalizations.dashboard, isNotEmpty);
      expect(appLocalizations.proxies, isNotEmpty);
      expect(appLocalizations.settings, isNotEmpty);
      expect(appLocalizations.secondsCount(30), contains('30'));
      expect(appLocalizations.geoUpdated('geoip'), contains('geoip'));
    }
  });

  test(
    'app initialization prepares diagnostic dates for every locale',
    () async {
      final date = DateTime(2026, 11, 27, 13, 45, 12);
      for (final locale in AppLocalizations.supportedLocales) {
        await initializeAppLocalizations(locale);

        expect(DateFormat.Hm().format(date), isNotEmpty, reason: '$locale');
        expect(
          DateFormat.yMd().add_Hms().format(date),
          isNotEmpty,
          reason: '$locale',
        );
        expect(DateFormat.yMMMd().format(date), isNotEmpty, reason: '$locale');
      }
    },
  );

  test('delegate recognizes only supported locales', () {
    expect(AppLocalizations.delegate.isSupported(const Locale('en')), isTrue);
    expect(AppLocalizations.delegate.isSupported(const Locale('de')), isFalse);
    expect(
      AppLocalizations.delegate.shouldReload(AppLocalizations.delegate),
      isFalse,
    );
  });
}
