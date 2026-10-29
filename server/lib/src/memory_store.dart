import 'store.dart';

/// In-memory store for tests and quick trials. Data is lost on restart.
class MemoryStore implements LinkStore {
  final Map<String, StoredLink> _links = {};
  final Map<String, ClickRecord> _clicks = {};
  final Map<String, List<int>> _counters = {}; // clicks,ios,android,other,opens,installs

  List<int> _c(String id) => _counters.putIfAbsent(id, () => List.filled(6, 0));

  @override
  Future<void> init() async {}

  @override
  Future<bool> createLink(StoredLink link) async {
    if (_links.containsKey(link.id)) return false;
    _links[link.id] = link;
    return true;
  }

  @override
  Future<StoredLink?> getLink(String id) async => _links[id];

  @override
  Future<void> recordClick(ClickRecord click) async {
    _clicks[click.id] = click;
    final c = _c(click.linkId);
    c[0]++;
    switch (click.platform) {
      case 'ios':
        c[1]++;
      case 'android':
        c[2]++;
      default:
        c[3]++;
    }
  }

  @override
  Future<ClickRecord?> getClick(String id) async => _clicks[id];

  @override
  Future<void> updateClickSignals(
    String clickId, {
    int? screenWidth,
    int? screenHeight,
    int? timezoneOffsetMinutes,
    String? language,
  }) async {
    final c = _clicks[clickId];
    if (c == null || c.matchedAt != null) return;
    _clicks[clickId] = c.copyWith(
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
      language: language,
    );
  }

  @override
  Future<List<ClickRecord>> candidateClicks({
    required String ipHash,
    required String platform,
    required int since,
    required int now,
  }) async =>
      _clicks.values
          .where((c) =>
              c.ipHash == ipHash &&
              c.platform == platform &&
              c.matchedAt == null &&
              c.createdAt >= since &&
              c.expiresAt > now)
          .toList();

  @override
  Future<bool> markMatched(String clickId, int now) async {
    final c = _clicks[clickId];
    if (c == null || c.matchedAt != null || c.expiresAt <= now) return false;
    _clicks[clickId] = c.copyWith(matchedAt: now);
    _c(c.linkId)[5]++;
    return true;
  }

  @override
  Future<void> incrementOpens(String linkId) async => _c(linkId)[4]++;

  @override
  Future<LinkStats> stats(String linkId) async {
    final c = _c(linkId);
    return LinkStats(
      clicks: c[0],
      clicksIos: c[1],
      clicksAndroid: c[2],
      clicksOther: c[3],
      opens: c[4],
      installs: c[5],
    );
  }

  @override
  Future<int> purgeExpired(int now) async {
    final before = _clicks.length + _links.length;
    _clicks.removeWhere((_, c) => c.expiresAt <= now);
    _links.removeWhere((_, l) => l.isExpired(now));
    return before - _clicks.length - _links.length;
  }

  @override
  Future<void> close() async {}
}
