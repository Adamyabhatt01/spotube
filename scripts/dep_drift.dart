// This fork pins its git dependencies to tested SHAs (see the DEP.x comments in
// pubspec.yaml), which is the point: an unpinned floating ref would take
// whatever upstream pushed. The cost is that those pins never move on their
// own, so this reports how far each one has fallen behind its repository.
//
//   dart run scripts/dep_drift.dart [--summary=<file>]
//
// Exit status: 0 = every pin is at or ahead of its default branch, 1 = at least
// one has drifted, 2 = the pins could not be read. Network or rate-limit
// failures are reported as `unknown` and do not fail the run.

import 'dart:convert';
import 'dart:io';

class GitPin {
  final String package;
  final String url;
  final String ref;

  /// A pin repeated across `dependencies:` and `dependency_overrides:`.
  final List<String> packages;

  GitPin._(this.package, this.url, this.ref) : packages = [package];

  String get slug {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    if (!host.endsWith('github.com')) return '';
    final segments = (uri?.pathSegments ?? []).where((s) => s.isNotEmpty);
    if (segments.length < 2) return '';
    final owner = segments.first;
    final name = segments.last.replaceAll('.git', '');
    return '$owner/$name';
  }

  bool get isSha => RegExp(r'^[0-9a-f]{40}$').hasMatch(ref);

  String get shortRef => isSha ? ref.substring(0, 7) : ref;
}

/// Line-oriented scan: pub is indentation-sensitive, and this avoids making
/// `yaml` a direct dependency just to read the file.
List<GitPin> readPins(String pubspecSource) {
  final pins = <GitPin>[];
  final byKey = <String, GitPin>{};

  String? dependency;
  bool inGit = false;
  String? url, ref;

  void flush() {
    final name = dependency, gitUrl = url, gitRef = ref;
    if (inGit && name != null && gitUrl != null && gitRef != null) {
      final pin = GitPin._(name, gitUrl, gitRef);
      final key = '${pin.slug}@${pin.ref}';
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = pin;
        pins.add(pin);
      } else if (!existing.packages.contains(pin.package)) {
        existing.packages.add(pin.package);
      }
    }
    inGit = false;
    url = null;
    ref = null;
  }

  for (final raw in const LineSplitter().convert(pubspecSource)) {
    if (raw.trim().isEmpty || raw.trim().startsWith('#')) continue;
    final indent = raw.length - raw.trimLeft().length;
    final text = raw.trim().replaceFirst('- ', '');

    if (indent == 0) {
      flush();
      dependency = null;
      continue;
    }
    if (indent <= 2) {
      flush();
      dependency = text.split(':').first.trim();
      continue;
    }
    if (text == 'git:') {
      flush();
      inGit = true;
      continue;
    }
    if (!inGit) continue;

    if (text.startsWith('url:')) {
      url = text.substring(4).trim();
    } else if (text.startsWith('ref:')) {
      ref = text.substring(4).trim();
    }
  }
  flush();
  return pins;
}

class DriftReport {
  final GitPin pin;
  final String? headSha;
  final int? commitsBehind;
  final String? note;

  DriftReport(this.pin, {this.headSha, this.commitsBehind, this.note});

  bool get drifted => commitsBehind != null && commitsBehind! > 0;
  bool get unknown => headSha == null && commitsBehind == null;
}

Future<dynamic> _getJson(
  HttpClient client,
  String path, {
  required String? token,
}) async {
  final request = await client.getUrl(
    Uri.parse('https://api.github.com$path'),
  );
  request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
  request.headers.set(HttpHeaders.userAgentHeader, 'spotube-dep-drift');
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }

  final response = await request.close();
  if (response.statusCode != 200) {
    await response.drain<void>();
    return null;
  }
  return jsonDecode(await utf8.decodeStream(response));
}

Future<DriftReport> checkPin(
    HttpClient client, GitPin pin, String? token) async {
  if (pin.slug.isEmpty) {
    return DriftReport(pin, note: 'not a GitHub url');
  }

  final repo = await _getJson(client, '/repos/${pin.slug}', token: token);
  if (repo is! Map) {
    return DriftReport(pin, note: 'repository lookup failed (rate limited?)');
  }
  final branch = repo['default_branch'];
  if (branch is! String) return DriftReport(pin, note: 'no default branch');

  // `compare` accepts a SHA or a tag/branch name on either side.
  final comparison = await _getJson(
    client,
    '/repos/${pin.slug}/compare/${pin.ref}...$branch',
    token: token,
  );
  if (comparison is! Map) {
    return DriftReport(
      pin,
      note: pin.isSha
          ? 'compare failed (pin may predate history)'
          : 'compare failed',
    );
  }

  final commitsBehind = comparison['ahead_by'];
  // /compare has no top-level `commit`: the branch tip is the last listed
  // commit, or the merge base when the pin already sits at the tip.
  final commits = comparison['commits'];
  final head = commits is List && commits.isNotEmpty
      ? (commits.last as Map)['sha']
      : (comparison['merge_base_commit']?['sha']);

  return DriftReport(
    pin,
    headSha: head is String && head.length >= 7 ? head.substring(0, 7) : null,
    commitsBehind: commitsBehind is int ? commitsBehind : null,
    note: comparison['status'] as String?,
  );
}

String render(List<DriftReport> reports) {
  final buffer = StringBuffer()
    ..writeln('| dependency | pinned | behind | head | status |')
    ..writeln('| --- | --- | --- | --- | --- |');

  for (final report in reports) {
    final pin = report.pin;
    final behind = report.commitsBehind != null
        ? '${report.commitsBehind}'
        : (report.unknown ? '?' : '0');
    buffer.writeln(
      '| ${pin.packages.join(', ')} | `${pin.shortRef}` | $behind '
      '| `${report.headSha ?? '?'}` | ${report.note ?? '-'} |',
    );
  }
  return buffer.toString();
}

void main(List<String> arguments) async {
  final summaryIndex = arguments.indexOf('--summary');
  final summaryPath = arguments.length > summaryIndex + 1 && summaryIndex >= 0
      ? arguments[summaryIndex + 1]
      : null;

  final pins = readPins(File('pubspec.yaml').readAsStringSync());
  if (pins.isEmpty) {
    stderr.writeln('no git pins found in pubspec.yaml');
    exit(2);
  }

  final token = Platform.environment['GITHUB_TOKEN'];
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);

  final reports = <DriftReport>[];
  for (final pin in pins) {
    reports.add(await checkPin(client, pin, token));
  }
  client.close();

  reports.sort((a, b) {
    if (a.drifted != b.drifted) return a.drifted ? -1 : 1;
    return a.pin.package.compareTo(b.pin.package);
  });

  final table = render(reports);
  stdout.writeln(table);

  final drifted = reports.where((r) => r.drifted).length;
  final undetermined = reports.where((r) => r.unknown).length;
  final verdict = drifted == 0
      ? 'all ${reports.length} pinned git dependencies are current'
      : '$drifted of ${reports.length} pinned git dependencies have drifted';
  stdout.writeln(
    '$verdict${undetermined == 0 ? '' : ' ($undetermined undetermined)'}',
  );

  if (summaryPath != null) {
    File(summaryPath).writeAsStringSync(
      '## Dependency drift\n\n$table\n$verdict\n',
      mode: FileMode.append,
    );
  }

  exit(drifted > 0 ? 1 : 0);
}
