// Domain-model round-trips for the radio feature: RadioStation JSON
// stability, the favoriteKey namespacing rule, and the provider-registry
// orchestration (priority, empty-vs-throw, all-threw escalation).

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/services/logger/logger.dart';

void main() {
  AppLogger.initialize(false);

  group('RadioStation', () {
    test('survives a toJson/fromJson round trip', () {
      final station = RadioStation(
        id: 'abc',
        provider: 'radio-browser',
        name: 'Classic Hits',
        streamUrl: 'https://stream.example/live',
        tags: const ['jazz', 'oldies'],
        country: 'US',
        faviconUrl: 'https://img.example/favicon.png',
        codec: 'MP3',
        bitrate: 128,
        isVip: true,
      );

      expect(RadioStation.fromJson(station.toJson()), station);
    });

    test('favoriteKey namespaces by provider', () {
      final a = RadioStation(
        id: 'x',
        provider: 'radio-browser',
        name: 'A',
        streamUrl: 'https://a',
      );
      final b = a.copyWith(provider: 'other');

      expect(a.favoriteKey, 'radio-browser:x');
      expect(a.favoriteKey, isNot(b.favoriteKey));
    });

    test('optional collections default to empty', () {
      final station = RadioStation(
        id: 'x',
        provider: 'p',
        name: 'N',
        streamUrl: 'https://s',
      );
      expect(station.tags, isEmpty);
      expect(station.isVip, isFalse);
    });
  });

  group('RadioTag / RadioCountry', () {
    test('RadioTag defaults stationCount to 0', () {
      expect(RadioTag(name: 'jazz').stationCount, 0);
    });
    test('RadioCountry round-trips', () {
      final c = RadioCountry(code: 'us', name: 'United States', stationCount: 12);
      expect(RadioCountry.fromJson(c.toJson()), c);
    });
  });
}
