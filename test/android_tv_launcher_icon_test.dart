import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TV launcher icons meet density-specific minimum sizes', () async {
    const expectedSizes = {
      'mdpi': 80,
      'hdpi': 120,
      'xhdpi': 160,
      'xxhdpi': 240,
      'xxxhdpi': 320,
    };

    for (final MapEntry(key: density, value: size) in expectedSizes.entries) {
      final file = File(
        'android/app/src/main/res/'
        'mipmap-television-$density/ic_launcher.webp',
      );
      expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');

      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      expect(
        (frame.image.width, frame.image.height),
        (size, size),
        reason: file.path,
      );
      frame.image.dispose();
      codec.dispose();
    }
  });

  test(
    'TV adaptive FlowCat launcher icon stays within the safe zone',
    () async {
      final adaptiveIcon = File(
        'android/app/src/main/res/mipmap-television-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();
      expect(adaptiveIcon, contains('@drawable/ic_launcher_foreground'));
      expect(adaptiveIcon, contains('@color/ic_launcher_background'));

      final bytes = await File(
        'android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png',
      ).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final width = image.width;
      final height = image.height;
      expect(width, height);
      final r = pixels.getUint8(0);
      final g = pixels.getUint8(1);
      final b = pixels.getUint8(2);
      var left = width, top = height, right = -1, bottom = -1;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final offset = (y * width + x) * 4;
          final contrast = [
            (pixels.getUint8(offset) - r).abs(),
            (pixels.getUint8(offset + 1) - g).abs(),
            (pixels.getUint8(offset + 2) - b).abs(),
          ].reduce((a, b) => a > b ? a : b);
          if (contrast <= 35) continue;
          if (x < left) left = x;
          if (y < top) top = y;
          if (x > right) right = x;
          if (y > bottom) bottom = y;
        }
      }
      expect(right, greaterThan(left));
      expect(bottom, greaterThan(top));
      expect(left / width, greaterThanOrEqualTo(1 / 6));
      expect(top / height, greaterThanOrEqualTo(1 / 6));
      expect((right + 1) / width, lessThanOrEqualTo(5 / 6));
      expect((bottom + 1) / height, lessThanOrEqualTo(5 / 6));
      expect((left + right) / 2 / width, closeTo(0.5, 0.05));
      expect((top + bottom) / 2 / height, closeTo(0.5, 0.05));
      image.dispose();
      codec.dispose();
    },
  );
}
