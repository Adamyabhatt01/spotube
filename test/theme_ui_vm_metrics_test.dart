// The debug counters that prove theme VM calls are not on the frame path.
//
// The wiring lives at the plugin endpoint (`getUi`/`onUiAction`), which is the
// only place a theme method crosses into Hetu. The provider layer is
// deliberately not counted: `pluginThemeUiProvider` may rebuild for its own
// reasons without invoking the VM, and a counter there would hide that.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/modules/theme_ui/theme_ui_vm_metrics.dart';

void main() {
  setUp(ThemeUiVmMetrics.reset);

  test('each recorded call increments its own counter', () {
    ThemeUiVmMetrics.recordGetUi();
    ThemeUiVmMetrics.recordGetUi();
    ThemeUiVmMetrics.recordOnUiAction();

    expect(ThemeUiVmMetrics.getUiCalls, 2);
    expect(ThemeUiVmMetrics.onUiActionCalls, 1);
    expect(ThemeUiVmMetrics.summary, 'getUi 2 · onUiAction 1');
  });

  test('reset clears both counters', () {
    ThemeUiVmMetrics.recordGetUi();
    ThemeUiVmMetrics.recordOnUiAction();
    ThemeUiVmMetrics.reset();

    expect(ThemeUiVmMetrics.getUiCalls, 0);
    expect(ThemeUiVmMetrics.onUiActionCalls, 0);
  });
}
