import 'dart:convert';
import 'dart:typed_data';

import 'package:spotube_themes/compile.dart';
import 'package:test/test.dart';

/// The `theme.json` entry the host reads without booting the VM.
///
/// Its contract is small and exact: the `getTheme()` map with the `getUi()`
/// document merged inline only when the payload carries no tree of its own
/// (an inline tree always wins, matching the host), the optional methods the
/// theme implements, and a format version. The bytes are sorted so a rebuild
/// of unchanged source is byte-identical.
void main() {
  group('staticThemePayload', () {
    test('merges a getUi document into a payload without a tree', () {
      final payload = staticThemePayload(
        CompiledTheme(
          byteCode: Uint8List(0),
          payload: {
            'specVersion': 4,
            'light': {},
            'dark': {},
          },
          warning: null,
          uiSpec: {
            'specVersion': 2,
            'slots': {'home.content': {}},
          },
          optionalMethods: ['getUi'],
        ),
      );

      expect(payload['formatVersion'], staticThemeFormatVersion);
      expect(payload['optionalMethods'], ['getUi']);
      final theme = payload['theme'] as Map<String, dynamic>;
      expect(theme['ui'], {
        'specVersion': 2,
        'slots': {'home.content': {}},
      });
    });

    test('an inline ui always wins over getUi', () {
      final payload = staticThemePayload(
        CompiledTheme(
          byteCode: Uint8List(0),
          payload: {
            'specVersion': 4,
            'light': {},
            'dark': {},
            'ui': {
              'slots': {'inline': {}},
            },
          },
          warning: null,
          uiSpec: {
            'slots': {'from-get-ui': {}},
          },
          optionalMethods: ['getUi'],
        ),
      );

      final theme = payload['theme'] as Map<String, dynamic>;
      expect(
        (theme['ui'] as Map<String, dynamic>)['slots'],
        {'inline': {}},
      );
    });
  });

  group('staticThemeBytes', () {
    test('the same payload is byte-identical in any map order', () {
      CompiledTheme withOrder(Map<String, dynamic> payload) => CompiledTheme(
            byteCode: Uint8List(0),
            payload: payload,
            warning: null,
          );

      final forward = withOrder({
        'specVersion': 4,
        'light': {'background': '#fff', 'foreground': '#000'},
        'dark': {},
      });
      final shuffled = withOrder({
        'dark': {},
        'light': {'foreground': '#000', 'background': '#fff'},
        'specVersion': 4,
      });

      expect(staticThemeBytes(forward), equals(staticThemeBytes(shuffled)));
    });

    test('decodes back to the same envelope', () {
      final bytes = staticThemeBytes(
        CompiledTheme(
          byteCode: Uint8List(0),
          payload: {'specVersion': 4, 'light': {}, 'dark': {}},
          warning: null,
          uiSpec: {'slots': {}},
          optionalMethods: ['getUi'],
        ),
      );

      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(decoded['formatVersion'], staticThemeFormatVersion);
      expect(decoded['optionalMethods'], ['getUi']);
      final theme = decoded['theme'] as Map<String, dynamic>;
      expect(theme['ui'], {'slots': {}});
    });
  });
}
