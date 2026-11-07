// Frame-time bench: what scrolling a frosted theme list costs on the real
// engine, and whether the scroll-freeze takes that cost away.
//
// Schedule: 3 rounds of 8 flings down a 200-panel list; sag for settling;
// measure from `FrameTiming` callbacks only (build + raster + total).
// Report avg / p95 build+paint and the share of frames over 16.7ms (jank
// at 60Hz vsync). Values are host-relative — llvmpipe raster on CI-like
// hardware is not a phone's GPU, so this answers "frost scrolls badly
// here, and the freeze fixes it here" — not an absolute claim about any
// device. Both modes run in the same binary (two calls to the bench).
//
// Run:  fvm flutter test integration_test/theme_frame_bench_test.dart -d linux --profile
// Facts go to stdout (and .ai/PERFORMANCE.md), never asserted: a percent
// and per-build jitter table is a measurement, not a budget.

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

ThemeUiRuntime _runtime() {
  return ThemeUiRuntime(
    theme: ThemeDefinition(
      specVersion: 4,
      light: builtInLightThemeColors(),
      dark: builtInDarkThemeColors(),
    ),
    bindings: const ThemeUiBindings({}),
    assets: const ThemeUiAssets(),
    templates: const {},
    specVersion: 4,
    onAction: (_) {},
  );
}

/// A v4-shaped collection content: header box, then 200 frosted rows.
Map<String, dynamic> _benchTree({required bool frosted}) {
  return {
    'type': 'column',
    'gap': 8,
    'children': [
      for (var i = 0; i < 200; i++)
        {
          'type': 'box',
          'height': 64,
          'radius': 16,
          'background': '@card',
          if (frosted) ...{
            'blur': 12,
            'blurTint': '#0ea5e9',
          },
          'children': [
            {'type': 'text', 'text': 'row $i'},
          ],
        },
    ],
  };
}

/// Drains at least [ms] ms of frames while allowing scheduled work.
Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

class _FrameStats {
  final List<Duration> buildPaint = [];
  final List<Duration> total = [];

  int get frames => total.length;

  double _percentile(List<Duration> values, double p) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort((a, b) => a.inMicroseconds.compareTo(b.inMicroseconds));
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx].inMicroseconds / 1000;
  }

  int get jank => total.where((t) => t > const Duration(milliseconds: 16)).length;

  double get jankShare => frames == 0 ? 0 : jank / frames;

  double get p50BuildPaint => _percentile(buildPaint, 0.50);
  double get p95BuildPaint => _percentile(buildPaint, 0.95);
  double get p50Total => _percentile(total, 0.50);
  double get p95Total => _percentile(total, 0.95);
}

Future<_FrameStats> _runRound(
  WidgetTester tester, {
  required bool frosted,
  required bool frozen,
}) async {
  final stats = _FrameStats();
  void callback(List<FrameTiming> timings) {
    for (final t in timings) {
      stats.buildPaint.add(t.buildDuration + t.rasterDuration);
      stats.total.add(t.totalSpan);
    }
  }
  SchedulerBinding.instance.addTimingsCallback(callback);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chromeBlurFrozen.overrideWith((ref) => frozen),
      ],
      child: ShadcnApp(
        home: Scaffold(
          child: SingleChildScrollView(
            child: ThemeUiNodeView(
              node: _benchTree(frosted: frosted),
              runtime: _runtime(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // The drive: 8 flings plus settle time per round.
  for (var i = 0; i < 8; i++) {
    await tester.fling(find.byType(SingleChildScrollView), const Offset(0, -1400), 2200);
    await _pumpFor(tester, const Duration(milliseconds: 350));
  }
  await tester.pumpAndSettle();
  // Flush drained frames into the callback count (timings arrive next frame).
  await tester.pump(const Duration(milliseconds: 100));

  SchedulerBinding.instance.removeTimingsCallback(callback);
  return stats;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('frame-time bench: frosted shelf scrolling', (tester) async {
    // Cheap sane window first.

    for (final frozen in [false, true]) {
      final rounds = <_FrameStats>[];
      for (var r = 0; r < 3; r++) {
        rounds.add(await _runRound(tester, frosted: true, frozen: frozen));
      }
      final combined = _FrameStats()
        ..buildPaint.addAll(rounds.expand((s) => s.buildPaint))
        ..total.addAll(rounds.expand((s) => s.total));

      // ignore: avoid_print
      print(
        '[frame-bench] frozen=$frozen run-runs '
        '${rounds.map((s) => 'p95bp=${s.p95BuildPaint.toStringAsFixed(2)}ms/jank=${s.jank}/${s.frames}').join(' ')} | '
        'combined p50-bp=${combined.p50BuildPaint.toStringAsFixed(2)}ms '
        'p95-bp=${combined.p95BuildPaint.toStringAsFixed(2)}ms '
        'p50-total=${combined.p50Total.toStringAsFixed(2)}ms '
        'p95-total=${combined.p95Total.toStringAsFixed(2)}ms '
        'jank=${combined.jank}/${combined.frames} (${(combined.jankShare * 100).toStringAsFixed(1)}%)',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
