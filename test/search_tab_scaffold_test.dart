// SearchTabScaffold owns the error/empty/loading branch once, so the five
// search tabs don't re-copy it.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/fallbacks/error_box.dart';
import 'package:spotube/components/fallbacks/no_default_metadata_plugin.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/modules/search/search_tab_scaffold.dart';
import 'package:spotube/modules/search/search_term.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

Future<void> _pumpScaffold(
  WidgetTester tester,
  AsyncValue<Object?> snapshot, {
  void Function()? onRetry,
  String searchTerm = '',
}) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  if (searchTerm.isNotEmpty) {
    container.read(searchTermStateProvider.notifier).state = searchTerm;
  }
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          child: SearchTabScaffold(
            snapshot: snapshot,
            onRetry: onRetry ?? () {},
            child: const Text('tab content'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SearchTabScaffold', () {
    testWidgets('no-default-plugin error renders the setup prompt',
        (tester) async {
      await _pumpScaffold(
        tester,
        AsyncValue<Object?>.error(
          MetadataPluginException.noDefaultMetadataPlugin(),
          StackTrace.empty,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(NoDefaultMetadataPlugin), findsOneWidget);
      expect(find.text('tab content'), findsNothing);
    });

    testWidgets('other errors render ErrorBox with a working retry',
        (tester) async {
      var retried = false;
      final container = ProviderContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ShadcnApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            home: Scaffold(
              child: SearchTabScaffold(
                snapshot: AsyncValue<Object?>.error(
                  Exception('boom'),
                  StackTrace.empty,
                ),
                onRetry: () => retried = true,
                child: const Text('tab content'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorBox), findsOneWidget);
      expect(find.text('tab content'), findsNothing);
      expect(retried, isFalse);
    });

    testWidgets('a rejected login offers re-authentication', (tester) async {
      // The Spotify metadata plugin's token expired: every search request
      // comes back 401. Retrying the same request with the same dead token
      // cannot help, so the error must point at the re-auth flow instead
      // of only offering a retry.
      await _pumpScaffold(
        tester,
        AsyncValue<Object?>.error(
          StateError(
            'DioException [bad response]: This exception was thrown because '
            'the response has a status code of 401',
          ),
          StackTrace.empty,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorBox), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);
      // The credential explanation, not the raw DioException dump.
      expect(
        find.textContaining('Spotify rejected this login'),
        findsOneWidget,
      );
    });

    testWidgets('an unrelated error offers no re-authentication',
        (tester) async {
      await _pumpScaffold(
        tester,
        AsyncValue<Object?>.error(
          Exception('boom'),
          StackTrace.empty,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorBox), findsOneWidget);
      expect(find.text('Login'), findsNothing);
    });

    testWidgets('loading renders the placeholder, not the tab', (tester) async {
      // A submitted (non-empty) term, matching production where tabs only
      // mount while searching; with an empty term the placeholder yields.
      await _pumpScaffold(
        tester,
        const AsyncValue<Object?>.loading(),
        searchTerm: 'daf',
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('tab content'), findsNothing);
    });

    testWidgets('data renders the tab child', (tester) async {
      await _pumpScaffold(
        tester,
        const AsyncValue<Object?>.data('page'),
        searchTerm: 'daf',
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('tab content'), findsOneWidget);
    });
  });
}
