import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';

/// Evaluates a theme condition against a binding snapshot.
///
/// A condition is either:
///
/// - a binding name (`player.playing`): truthy when the binding exists and is
///   not empty/zero/false;
/// - a negated binding name (`!player.playing`): the opposite;
/// - an object form `{bind, equals?, invert?, gt?, gte?, lt?, lte?, allOf?,
///   anyOf?}` (see `uiCondition` in the v4 schema) that composes those:
///   equality/range against the bound value plus `allOf`/`anyOf` lists of
///   nested conditions, `invert` negates the whole result.
///
/// The object form is declarative only — no expressions, no host code. A
/// malformed condition evaluates to false (the same as a truthy check against
/// a missing binding), so an authoring bug cannot hide content or unlock a
/// write by accident.
bool evaluateThemeUiCondition(ThemeUiBindings bindings, Object? condition) {
  if (condition is String) {
    if (condition.startsWith('!')) {
      return !bindings.isTruthy(condition.substring(1));
    }
    return bindings.isTruthy(condition);
  }
  if (condition is Map) {
    return _evaluateObject(bindings, condition.cast<String, dynamic>());
  }
  return false;
}

bool _evaluateObject(ThemeUiBindings bindings, Map<String, dynamic> map) {
  final parts = <bool>[];

  final bind = map['bind'];
  if (bind is String) {
    parts.add(_evaluateBind(bindings, bind, map));
  }

  final allOf = map['allOf'];
  if (allOf is List) {
    parts.add(allOf.every(
      (entry) => evaluateThemeUiCondition(bindings, entry),
    ));
  }

  final anyOf = map['anyOf'];
  if (anyOf is List) {
    parts.add(anyOf.any(
      (entry) => evaluateThemeUiCondition(bindings, entry),
    ));
  }

  if (parts.isEmpty) return false;
  var result = parts.every((part) => part);
  if (map['invert'] == true) result = !result;
  return result;
}

/// The bound-value part of an object condition: equality or a numeric range.
///
/// `equals` uses the same coercion as `ThemeUiBindings.matches` (numeric and
/// string comparisons coerce like `conditional` does). Range keys compare
/// numerically only; a non-numeric bound value fails the part.
bool _evaluateBind(
  ThemeUiBindings bindings,
  String bind,
  Map<String, dynamic> map,
) {
  final equals = map['equals'];
  if (equals != null) return bindings.matches(bind, equals);

  const rangeOps = {'gt', 'gte', 'lt', 'lte'};
  final present = rangeOps.where(map.containsKey);
  if (present.isNotEmpty) {
    final value = bindings.raw(bind);
    if (value is! num) return false;
    for (final op in present) {
      final threshold = map[op];
      if (threshold is! num) return false;
      final pass = switch (op) {
        'gt' => value > threshold,
        'gte' => value >= threshold,
        'lt' => value < threshold,
        'lte' => value <= threshold,
        _ => false,
      };
      if (!pass) return false;
    }
    return true;
  }

  return bindings.isTruthy(bind);
}
