import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/database/database.dart';

void main() {
  const c = StringListConverter();
  test('comma-joined round trip', () {
    expect(c.fromSql('theme,radio'), ['theme', 'radio']);
    expect(c.toSql(['theme', 'radio']), 'theme,radio');
  });
  test('legacy JSON-array form decodes', () {
    expect(c.fromSql('["theme"]'), ['theme']);
    expect(
        c.fromSql('["webview","localstorage"]'), ['webview', 'localstorage']);
  });
  test('empty stays empty', () {
    expect(c.fromSql(''), isEmpty);
  });
}
