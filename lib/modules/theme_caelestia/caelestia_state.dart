import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the Caelestia state directory.
///
/// Overrideable for tests. Defaults to `$XDG_STATE_HOME/caelestia`
/// (falling back to `$HOME/.local/state/caelestia`). Returns null when
/// neither variable yields a usable base — callers treat null as
/// "no shell state" rather than building a relative path.
String? caelestiaStateDir([String? override]) {
  if (override != null) return override;
  final env = Platform.environment;
  final stateHome = env['XDG_STATE_HOME'] ??
      (env['HOME'] == null ? null : p.join(env['HOME']!, '.local', 'state'));
  if (stateHome == null) return null;
  return p.join(stateHome, 'caelestia');
}
