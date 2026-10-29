import 'store.dart';

/// Signals the app sends with `/v1/match`.
class DeviceSignals {
  DeviceSignals({
    this.platform = 'ios',
    this.osVersion,
    this.screenWidth,
    this.screenHeight,
    this.language,
    this.timezoneOffsetMinutes,
  });

  factory DeviceSignals.fromJson(Map<String, Object?> j) => DeviceSignals(
        platform: (j['platform'] as String?) ?? 'ios',
        osVersion: j['osVersion'] as String?,
        screenWidth: (j['screenWidth'] as num?)?.toInt(),
        screenHeight: (j['screenHeight'] as num?)?.toInt(),
        language: j['language'] as String?,
        timezoneOffsetMinutes: (j['timezoneOffsetMinutes'] as num?)?.toInt(),
      );

  final String platform;
  final String? osVersion;
  final int? screenWidth;
  final int? screenHeight;
  final String? language;
  final int? timezoneOffsetMinutes;
}

enum Confidence { low, medium, high, exact }

class MatchOutcome {
  const MatchOutcome(this.click, this.score, this.confidence);
  final ClickRecord click;
  final double score;
  final Confidence confidence;
}

/// Weights. The IP must match (it is the only signal that survives the trip
/// App Store -> first launch for a given user); the rest raise confidence.
const double ipWeight = 0.50;
const double screenWeight = 0.20;
const double timezoneWeight = 0.15;
const double languageWeight = 0.10;
const double osWeight = 0.05;

/// Two candidates whose scores differ by less than this are ambiguous.
const double ambiguityMargin = 0.05;

/// Primary language subtag, lower case (`en-US` -> `en`).
String? primaryLanguage(String? tag) {
  if (tag == null || tag.isEmpty) return null;
  return tag.split(RegExp(r'[-_,;]')).first.trim().toLowerCase();
}

/// First number of an OS version (`17.4.1` -> 17).
int? osMajorOf(String? version) {
  if (version == null) return null;
  final m = RegExp(r'^(\d+)').firstMatch(version.trim());
  return m == null ? null : int.parse(m.group(1)!);
}

/// Scores one candidate against the device signals, or null when a strong
/// signal contradicts (different screen size or time zone).
double? scoreCandidate(ClickRecord click, DeviceSignals s) {
  var score = ipWeight; // caller guarantees the IP hash matched

  if (click.screenWidth != null &&
      click.screenHeight != null &&
      s.screenWidth != null &&
      s.screenHeight != null) {
    final a = [click.screenWidth!, click.screenHeight!]..sort();
    final b = [s.screenWidth!, s.screenHeight!]..sort();
    if (a[0] != b[0] || a[1] != b[1]) return null;
    score += screenWeight;
  }
  if (click.timezoneOffsetMinutes != null && s.timezoneOffsetMinutes != null) {
    if (click.timezoneOffsetMinutes != s.timezoneOffsetMinutes) return null;
    score += timezoneWeight;
  }
  final cl = primaryLanguage(click.language);
  final dl = primaryLanguage(s.language);
  if (cl != null && dl != null && cl == dl) score += languageWeight;
  // Safari freezes its reported OS version on recent iOS, so a mismatch is not
  // evidence; only a match adds a little.
  final dos = osMajorOf(s.osVersion);
  if (click.osMajor != null && dos != null && click.osMajor == dos) {
    score += osWeight;
  }
  return score;
}

Confidence confidenceFor(double score) {
  if (score >= 0.9) return Confidence.high;
  if (score >= 0.75) return Confidence.medium;
  return Confidence.low;
}

/// Picks the best candidate, or null when there is none above [minScore] or
/// the top two are ambiguous. Ambiguity between clicks of the same link is not
/// a conflict (same destination), so the older one is taken.
MatchOutcome? pickMatch(
  List<ClickRecord> candidates,
  DeviceSignals signals, {
  double minScore = 0.6,
}) {
  final scored = <(ClickRecord, double)>[];
  for (final c in candidates) {
    final s = scoreCandidate(c, signals);
    if (s != null && s >= minScore) scored.add((c, s));
  }
  if (scored.isEmpty) return null;
  scored.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    return byScore != 0 ? byScore : b.$1.createdAt.compareTo(a.$1.createdAt);
  });
  final top = scored.first;
  for (final other in scored.skip(1)) {
    if (top.$2 - other.$2 < ambiguityMargin && other.$1.linkId != top.$1.linkId) {
      return null; // two different destinations are equally plausible
    }
  }
  return MatchOutcome(top.$1, top.$2, confidenceFor(top.$2));
}
