// The shell toggles are user state, not theme state: the sidebar collapse and
// the aside's open/closed choice survive a restart, so they live in the
// preferences row beside the player dock. This pins the row defaults the
// migration adds and the two setters the sidebar, aside, shortcuts and theme
// actions all funnel through.
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/models/database/database.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

import 'support/common_fakes.dart';

void main() {
  test('a fresh row ships an expanded sidebar and an open aside', () {
    final defaults = PreferencesTable.defaults();
    expect(defaults.sidebarCollapsed, isFalse);
    expect(defaults.asideOpen, isTrue);
  });

  test('both setters write the row the shell reads', () async {
    final db = newMemoryDatabase();
    addTearDown(db.close);
    await db.into(db.preferencesTable).insert(
          PreferencesTableCompanion.insert(id: const Value(0)),
        );

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(userPreferencesProvider.notifier);
    // The notifier loads the row (and starts watching it) asynchronously.
    await pumpEventQueue();

    notifier.setSidebarCollapsed(true);
    notifier.setAsideOpen(false);
    await pumpEventQueue();

    final row = await (db.select(db.preferencesTable)
          ..where((table) => table.id.equals(0)))
        .getSingle();
    expect(row.sidebarCollapsed, isTrue);
    expect(row.asideOpen, isFalse);
  });
}
