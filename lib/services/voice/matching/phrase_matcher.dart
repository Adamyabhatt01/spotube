// Turns a recognizer transcript into a command + slot, matching user phrase
// lists in the lossy key space of [VoiceTextNormalizer].
import 'dart:math';

import 'text_normalizer.dart';

/// Every command the voice feature can dispatch. Phrase defaults exist for
/// each, per [VoiceLanguage].
enum VoiceCommandId {
  play,
  pause,
  playPause,
  next,
  previous,
  seekForward,
  seekBackward,
  seekTo,
  volumeUp,
  volumeDown,
  setVolume,
  search,
  playPlaylist,
  like,
  unlike,
  addToQueue,
  openQueue,
  stopListening,
}

/// A phrase is written literally; slot commands may embed a `{query}`,
/// `{name}` or `{percent}` placeholder. A slot phrase written without a
/// placeholder is matched as a prefix, with the remainder becoming the slot.
class VoiceMatch {
  final VoiceCommandId id;
  final String? slot;

  /// 0..1 similarity of the matched phrase, for ambiguity decisions.
  final double score;

  /// Literal (non-slot) words consumed; the tie-break that makes
  /// "play playlist {name}" beat the bare "play" prefix at equal similarity.
  final int literalWords;
  const VoiceMatch(
      {required this.id,
      this.slot,
      required this.score,
      this.literalWords = 0});

  @override
  String toString() => 'VoiceMatch($id, slot: $slot, score: $score)';
}

class PhraseMatcher {
  const PhraseMatcher({this.normalizer = const VoiceTextNormalizer()});

  final VoiceTextNormalizer normalizer;

  static final _slotMarker = RegExp(r'\{(query|name|percent)\}');

  /// Best interpretation of [transcript] against [phrases], or null.
  /// The caller treats `ambiguous` results (top two scores within
  /// [_ambiguityMargin] of each other) as a chooser prompt, never a guess.
  VoiceCommandResult matchCommand(
    String transcript,
    Map<VoiceCommandId, List<String>> phrases,
    VoiceLanguage language,
  ) {
    final rawWords = _rawWords(transcript);
    if (rawWords.isEmpty) return const VoiceCommandResult.none();
    final keys = rawWords.map((w) => normalizer.key(w, language)).toList();

    var best = <VoiceMatch>[];
    for (final entry in phrases.entries) {
      for (final phrase in entry.value) {
        final match = _matchPhrase(entry.key, phrase, rawWords, keys, language);
        if (match == null) continue;
        best = [...best, match]..sort((a, b) {
            final byScore = b.score.compareTo(a.score);
            return byScore != 0
                ? byScore
                : b.literalWords.compareTo(a.literalWords);
          });
      }
    }
    if (best.isEmpty) return const VoiceCommandResult.none();
    if (best.length > 1 &&
        best.first.score - best[1].score < _ambiguityMargin &&
        best.first.literalWords == best[1].literalWords &&
        best.first.id != best[1].id) {
      return VoiceCommandResult.ambiguous(best);
    }
    return VoiceCommandResult.matched(best.first);
  }

  /// Wake check on a rolling transcript tail; returns the portion of the
  /// transcript after the wake phrase for same-breath parsing, or null.
  String? wakeRemainder(
    String transcript,
    List<String> wakePhrases,
    VoiceLanguage language,
  ) {
    final rawWords = _rawWords(transcript);
    if (rawWords.isEmpty) return null;
    final keys = rawWords.map((w) => normalizer.key(w, language)).toList();
    for (final phrase in wakePhrases) {
      final pw = normalizer
          .key(phrase, language)
          .split(' ')
          .where((e) => e.isNotEmpty)
          .toList();
      if (pw.isEmpty) continue;
      // Scan windows ending at the transcript tail, newest last words first.
      for (var end = keys.length; end >= pw.length; end--) {
        final start = end - pw.length;
        final window = keys.sublist(start, end);
        final score = _similarity(window, pw);
        if (score >= _threshold(pw.length)) {
          return rawWords.sublist(end).join(' ');
        }
      }
    }
    return null;
  }

  /// Which of [names] the spoken [heard] slot was most likely asking for.
  ///
  /// A playlist name is not a phrase the user typed into this app, so the
  /// word-for-word windowing [_similarity] needs cannot apply: "the white
  /// stuff" may be heard as two words, "best of 1999" with the year spelled
  /// out. Coverage is therefore measured in both directions — how much of the
  /// heard slot the name explains, and how much of the name the slot
  /// mentions — and combined geometrically so a long name is not punished for
  /// being long. The result stays in the same 0..1 space as a phrase score, so
  /// [_ambiguityMargin] means the same thing here: two names that close are a
  /// question for the user, not a guess by us.
  List<VoiceNameMatch> rankNames(
    String heard,
    List<String> names,
    VoiceLanguage language,
  ) {
    final needle = _keyWords(heard, language);
    if (needle.isEmpty) return const [];

    final ranked = <VoiceNameMatch>[];
    for (var i = 0; i < names.length; i++) {
      final hay = _keyWords(names[i], language);
      if (hay.isEmpty) continue;
      final explained = needle
              .where((word) => _bestWordScore(word, hay) >= _nameWordFloor)
              .length /
          needle.length;
      final mentioned = hay
              .where((word) => _bestWordScore(word, needle) >= _nameWordFloor)
              .length /
          hay.length;
      final score = sqrt(explained * mentioned);
      if (score < _nameAcceptFloor) continue;
      ranked.add(VoiceNameMatch(index: i, score: score));
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked;
  }

  /// Whether the best two ranked names are too close to pick silently.
  ///
  /// Same margin as [matchCommand]: a phrase the matcher would have asked
  /// about is a name the executor must ask about too.
  bool namesAreAmbiguous(double top, double second) =>
      second > top - _ambiguityMargin;

  static const _nameWordFloor = 0.6;

  /// Below this a name is not what was asked for at all. 0.45 keeps
  /// "white stuff" → "The White Stuff" (1.0) and a half-remembered
  /// "whit staff tomorrow" (0.7) in, and drops an unrelated short name.
  static const _nameAcceptFloor = 0.45;

  double _bestWordScore(String word, List<String> others) {
    var best = 0.0;
    for (final other in others) {
      final score = _similarity([word], [other]);
      if (score > best) best = score;
    }
    return best;
  }

  static const _ambiguityMargin = 0.08;

  VoiceMatch? _matchPhrase(
    VoiceCommandId id,
    String phrase,
    List<String> rawWords,
    List<String> keys,
    VoiceLanguage language,
  ) {
    final placeholder = _slotMarker.firstMatch(phrase);
    if (placeholder == null) {
      final pw = _keyWords(phrase, language);
      if (pw.isEmpty) return null;
      final isSlotCommand = _slotCommands.contains(id);
      final score = _bestWindowScore(keys, pw);
      if (score == null) return null;
      if (!isSlotCommand) {
        return VoiceMatch(id: id, score: score, literalWords: pw.length);
      }
      // No-placeholder phrase for a slot command: prefix mode, remainder is
      // the slot.
      final slot = _remainderAfterWindow(rawWords, keys, pw);
      if (slot == null || slot.isEmpty) return null;
      return VoiceMatch(
          id: id,
          slot: _finalizeSlot(id, slot, language),
          score: score,
          literalWords: pw.length);
    }

    // A template holds exactly one slot; a second placeholder would split
    // into more than three parts and silently mis-parse the boundaries.
    if (_slotMarker.allMatches(phrase).length > 1) return null;

    // Explicit template: literals around the placeholder must appear in
    // order; the words between are the slot.
    final before = _keyWords(phrase.split(_slotMarker).first, language);
    final after = _keyWords(phrase.split(_slotMarker).last, language);
    if (before.isEmpty && after.isEmpty) return null;
    final bScore = before.isEmpty ? 1.0 : (_bestWindowScore(keys, before) ?? 0);
    final aScore = after.isEmpty ? 1.0 : (_bestWindowScore(keys, after) ?? 0);
    final minLen = (before.length + after.length).clamp(1, 99);
    if (bScore < _threshold(minLen) || aScore < _threshold(minLen)) return null;

    final startIdx =
        before.isEmpty ? 0 : _windowStart(keys, before, requireAfter: true);
    if (startIdx == null) return null;
    var endIdx = rawWords.length;
    if (after.isNotEmpty) {
      final afterStart =
          _windowStart(keys.sublist(startIdx), after, requireAfter: false);
      if (afterStart == null) return null;
      endIdx = startIdx + afterStart;
    }
    final slotWords = rawWords.sublist(startIdx, endIdx);
    if (slotWords.isEmpty) return null;
    final slot = slotWords.join(' ');
    final score = (bScore + aScore) / 2;
    return VoiceMatch(
      id: id,
      slot: _finalizeSlot(id, slot, language),
      score: score,
      literalWords: before.length + after.length,
    );
  }

  static const _slotCommands = {
    VoiceCommandId.search,
    VoiceCommandId.playPlaylist,
    VoiceCommandId.seekTo,
    VoiceCommandId.setVolume,
  };

  String? _finalizeSlot(
      VoiceCommandId id, String slot, VoiceLanguage language) {
    if (id == VoiceCommandId.seekTo || id == VoiceCommandId.setVolume) {
      return normalizer.parseStepPercent(_rawWords(slot), language)?.toString();
    }
    return slot;
  }

  List<String> _keyWords(String s, VoiceLanguage language) => normalizer
      .key(s, language)
      .split(' ')
      .where((e) => e.isNotEmpty)
      .toList();

  double? _bestWindowScore(List<String> keys, List<String> pw) {
    if (pw.length > keys.length) return null;
    var best = 0.0;
    for (var i = 0; i + pw.length <= keys.length; i++) {
      final score = _similarity(keys.sublist(i, i + pw.length), pw);
      if (score > best) best = score;
    }
    return best >= _threshold(pw.length) ? best : null;
  }

  int? _windowStart(List<String> keys, List<String> pw,
      {required bool requireAfter}) {
    for (var i = 0; i + pw.length <= keys.length; i++) {
      if (_similarity(keys.sublist(i, i + pw.length), pw) >=
          _threshold(pw.length)) {
        return requireAfter ? i + pw.length : i;
      }
    }
    return null;
  }

  String? _remainderAfterWindow(
      List<String> rawWords, List<String> keys, List<String> pw) {
    final start = _windowStart(keys, pw, requireAfter: true);
    if (start == null || start >= rawWords.length) return null;
    return rawWords.sublist(start).join(' ');
  }

  /// Length-aware: short phrases must match almost exactly — "next" and
  /// "text" differ by one edit, so ≤4-word-total keys allow zero tolerance
  /// beyond one substitution on longer words.
  double _threshold(int wordCount) {
    if (wordCount <= 1) return 0.86;
    if (wordCount <= 2) return 0.78;
    return 0.7;
  }

  double _similarity(List<String> a, List<String> b) {
    if (a.length != b.length) return 0;
    var totalLen = 0;
    var totalDist = 0;
    for (var i = 0; i < a.length; i++) {
      totalDist += _levenshtein(a[i], b[i]);
      totalLen += a[i].length;
    }
    if (totalLen == 0) return 0;
    return 1 - totalDist / totalLen;
  }

  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    final m = s.length, n = t.length;
    if (m == 0) return n;
    if (n == 0) return m;
    var prev = List<int>.generate(n + 1, (i) => i);
    var cur = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      cur[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
            .reduce((a, b) => a < b ? a : b);
      }
      final tmp = prev;
      prev = cur;
      cur = tmp;
    }
    return prev[n];
  }

  static List<String> _rawWords(String transcript) => transcript
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ')
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
}

/// One ranked name: which entry of the ranked list it was, and how well it fit.
class VoiceNameMatch {
  /// Position in the list that was passed to [PhraseMatcher.rankNames] — the
  /// caller owns the objects behind the names, so nothing here carries them.
  final int index;
  final double score;
  const VoiceNameMatch({required this.index, required this.score});
}

class VoiceCommandResult {
  final VoiceMatch? match;
  final List<VoiceMatch> candidates;
  const VoiceCommandResult._(this.match, this.candidates);
  const VoiceCommandResult.none() : this._(null, const []);
  VoiceCommandResult.matched(VoiceMatch m) : this._(m, [m]);
  VoiceCommandResult.ambiguous(List<VoiceMatch> cs) : this._(null, cs);

  bool get hasMatch => match != null;
  bool get isAmbiguous => match == null && candidates.isNotEmpty;
}
