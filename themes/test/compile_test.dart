import 'package:spotube_themes/compile.dart';
import 'package:test/test.dart';

/// A build has to be a function of its input.
///
/// Hetu stamps the module with the wall clock, which used to make every
/// rebuild of an unchanged theme produce different bytes. The artifacts are
/// committed, so that turned a no-op into a diff and made it impossible to
/// tell a real theme change from a rebuild.
void main() {
  const source = '''
class Repro {
  fun getTheme() {
    return {
      'light': {},
      'dark': {},
    }
  }
}
''';

  test('the same source compiles to the same bytes', () {
    final first = compileThemeSource(source, sourceName: 'repro');
    final second = compileThemeSource(source, sourceName: 'repro');
    expect(first, equals(second));
  });

  test('the compile stamp is the fixed one', () {
    final bytes = compileThemeSource(source, sourceName: 'repro');
    final text = String.fromCharCodes(bytes);
    expect(text, contains('1970-01-01 00:00:00'));
    expect(RegExp(r'20\d\d-\d\d-\d\d \d\d:\d\d:\d\d').hasMatch(text), isFalse);
  });
}
