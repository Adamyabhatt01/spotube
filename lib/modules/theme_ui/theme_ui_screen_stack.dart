import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The theme screen stack, pushed by a `navigate` action whose target is
/// `screen:<id>`.
///
/// A stack rather than one id because a theme may nest screens (obsidian's
/// colophon returns to now-playing), and "back" must return to the previous
/// theme screen before it closes the overlay.
final themeUiScreenStackProvider =
    StateProvider<List<String>>((ref) => const <String>[]);

String? currentThemeUiScreen(WidgetRef ref) {
  final stack = ref.watch(themeUiScreenStackProvider);
  return stack.isEmpty ? null : stack.last;
}

void pushThemeUiScreen(WidgetRef ref, String id) {
  final stack = ref.read(themeUiScreenStackProvider);
  if (stack.isNotEmpty && stack.last == id) return;
  ref.read(themeUiScreenStackProvider.notifier).state = [...stack, id];
}

void popThemeUiScreen(WidgetRef ref) {
  final stack = ref.read(themeUiScreenStackProvider);
  if (stack.isEmpty) return;
  ref.read(themeUiScreenStackProvider.notifier).state =
      stack.sublist(0, stack.length - 1);
}

void clearThemeUiScreens(WidgetRef ref) {
  ref.read(themeUiScreenStackProvider.notifier).state = const [];
}

/// Clears the stack from a provider notifier, where only a [Ref] is available.
///
/// `WidgetRef` and `Ref` are unrelated types, so this cannot delegate to
/// [clearThemeUiScreens]; it is the same one-line reset against the other ref.
void clearThemeUiScreensState(Ref ref) {
  ref.read(themeUiScreenStackProvider.notifier).state = const [];
}
