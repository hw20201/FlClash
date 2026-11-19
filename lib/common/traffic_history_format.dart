import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

String trafficHistoryDuration(BuildContext context, Duration value) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final format = NumberFormat('00', locale);
  return [
    value.inHours,
    value.inMinutes.remainder(60),
    value.inSeconds.remainder(60),
  ].map(format.format).join(':');
}
