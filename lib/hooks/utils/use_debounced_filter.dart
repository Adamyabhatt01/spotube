import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:spotube/hooks/utils/use_debounce.dart';

/// The immediate text plus its debounced, empty-fast-path filter value.
typedef DebouncedFilter = ({
  String value,
  void Function(String) onChange,
  String query,
});

/// One keystroke box wired to a fuzzy filter: [value] is what the field echoes
/// (and what "is anything typed?" conditions read), [query] lags it by [delay]
/// so a burst collapses into one pass, and clearing the box cuts to the empty
/// fast path instantly instead of waiting out the timer.
DebouncedFilter useDebouncedFilter({
  Duration delay = const Duration(milliseconds: 200),
}) {
  final state = useState('');
  final debounced = useDebounce(state.value, delay);
  return useMemoized(
    () => (
      value: state.value,
      onChange: (next) => state.value = next,
      query: state.value.isEmpty ? '' : debounced,
    ),
    [state.value, debounced],
  );
}
