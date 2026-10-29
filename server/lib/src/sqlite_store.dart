import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'store.dart';

/// SQLite-backed store. Pass `':memory:'` or a file path.
class SqliteStore implements LinkStore {
  SqliteStore(this.path);

  final String path;
  late final Database _db;

  @override
  Future<void> init() async {
    _db = sqlite3.open(path);
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('''
CREATE TABLE IF NOT EXISTS links (
  id TEXT PRIMARY KEY,
  deep_link TEXT NOT NULL,
  data TEXT NOT NULL,
  title TEXT, description TEXT, image_url TEXT, fallback_url TEXT,
  android_store_url TEXT, ios_store_url TEXT,
  created_at INTEGER NOT NULL,
  expires_at INTEGER
);
CREATE TABLE IF NOT EXISTS clicks (
  id TEXT PRIMARY KEY,
  link_id TEXT NOT NULL,
  platform TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  ip_hash TEXT,
  os_major INTEGER,
  language TEXT,
  screen_w INTEGER, screen_h INTEGER,
  tz_offset INTEGER,
  matched_at INTEGER
);
CREATE INDEX IF NOT EXISTS clicks_match ON clicks (ip_hash, platform, created_at);
CREATE INDEX IF NOT EXISTS clicks_expiry ON clicks (expires_at);
CREATE TABLE IF NOT EXISTS counters (
  link_id TEXT PRIMARY KEY,
  clicks INTEGER NOT NULL DEFAULT 0,
  clicks_ios INTEGER NOT NULL DEFAULT 0,
  clicks_android INTEGER NOT NULL DEFAULT 0,
  clicks_other INTEGER NOT NULL DEFAULT 0,
  opens INTEGER NOT NULL DEFAULT 0,
  installs INTEGER NOT NULL DEFAULT 0
);
''');
  }

  @override
  Future<bool> createLink(StoredLink l) async {
    try {
      _db.execute(
        'INSERT INTO links (id, deep_link, data, title, description, image_url, '
        'fallback_url, android_store_url, ios_store_url, created_at, expires_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        [
          l.id,
          l.deepLink,
          jsonEncode(l.data),
          l.title,
          l.description,
          l.imageUrl,
          l.fallbackUrl,
          l.androidStoreUrl,
          l.iosStoreUrl,
          l.createdAt,
          l.expiresAt,
        ],
      );
      return true;
    } on SqliteException catch (e) {
      if (e.extendedResultCode == 1555 || e.extendedResultCode == 2067) {
        return false; // primary key / unique constraint
      }
      rethrow;
    }
  }

  @override
  Future<StoredLink?> getLink(String id) async {
    final rows = _db.select('SELECT * FROM links WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return StoredLink(
      id: r['id'] as String,
      deepLink: r['deep_link'] as String,
      data: (jsonDecode(r['data'] as String) as Map<String, Object?>)
          .map((k, v) => MapEntry(k, '$v')),
      title: r['title'] as String?,
      description: r['description'] as String?,
      imageUrl: r['image_url'] as String?,
      fallbackUrl: r['fallback_url'] as String?,
      androidStoreUrl: r['android_store_url'] as String?,
      iosStoreUrl: r['ios_store_url'] as String?,
      createdAt: r['created_at'] as int,
      expiresAt: r['expires_at'] as int?,
    );
  }

  @override
  Future<void> recordClick(ClickRecord c) async {
    _db.execute(
      'INSERT INTO clicks (id, link_id, platform, created_at, expires_at, ip_hash, '
      'os_major, language, screen_w, screen_h, tz_offset) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      [
        c.id,
        c.linkId,
        c.platform,
        c.createdAt,
        c.expiresAt,
        c.ipHash,
        c.osMajor,
        c.language,
        c.screenWidth,
        c.screenHeight,
        c.timezoneOffsetMinutes,
      ],
    );
    final col = switch (c.platform) {
      'ios' => 'clicks_ios',
      'android' => 'clicks_android',
      _ => 'clicks_other',
    };
    _db.execute('INSERT OR IGNORE INTO counters (link_id) VALUES (?)', [c.linkId]);
    _db.execute(
      'UPDATE counters SET clicks = clicks + 1, $col = $col + 1 WHERE link_id = ?',
      [c.linkId],
    );
  }

  ClickRecord _click(Row r) => ClickRecord(
        id: r['id'] as String,
        linkId: r['link_id'] as String,
        platform: r['platform'] as String,
        createdAt: r['created_at'] as int,
        expiresAt: r['expires_at'] as int,
        ipHash: r['ip_hash'] as String?,
        osMajor: r['os_major'] as int?,
        language: r['language'] as String?,
        screenWidth: r['screen_w'] as int?,
        screenHeight: r['screen_h'] as int?,
        timezoneOffsetMinutes: r['tz_offset'] as int?,
        matchedAt: r['matched_at'] as int?,
      );

  @override
  Future<ClickRecord?> getClick(String id) async {
    final rows = _db.select('SELECT * FROM clicks WHERE id = ?', [id]);
    return rows.isEmpty ? null : _click(rows.first);
  }

  @override
  Future<void> updateClickSignals(
    String clickId, {
    int? screenWidth,
    int? screenHeight,
    int? timezoneOffsetMinutes,
    String? language,
  }) async {
    _db.execute(
      'UPDATE clicks SET screen_w = COALESCE(?, screen_w), screen_h = COALESCE(?, screen_h), '
      'tz_offset = COALESCE(?, tz_offset), language = COALESCE(?, language) '
      'WHERE id = ? AND matched_at IS NULL',
      [screenWidth, screenHeight, timezoneOffsetMinutes, language, clickId],
    );
  }

  @override
  Future<List<ClickRecord>> candidateClicks({
    required String ipHash,
    required String platform,
    required int since,
    required int now,
  }) async =>
      _db
          .select(
            'SELECT * FROM clicks WHERE ip_hash = ? AND platform = ? AND matched_at IS NULL '
            'AND created_at >= ? AND expires_at > ?',
            [ipHash, platform, since, now],
          )
          .map(_click)
          .toList();

  @override
  Future<bool> markMatched(String clickId, int now) async {
    _db.execute(
      'UPDATE clicks SET matched_at = ? WHERE id = ? AND matched_at IS NULL AND expires_at > ?',
      [now, clickId, now],
    );
    if (_db.updatedRows != 1) return false;
    final linkId = _db.select('SELECT link_id FROM clicks WHERE id = ?', [clickId]).first['link_id'];
    _db.execute('INSERT OR IGNORE INTO counters (link_id) VALUES (?)', [linkId]);
    _db.execute('UPDATE counters SET installs = installs + 1 WHERE link_id = ?', [linkId]);
    return true;
  }

  @override
  Future<void> incrementOpens(String linkId) async {
    _db.execute('INSERT OR IGNORE INTO counters (link_id) VALUES (?)', [linkId]);
    _db.execute('UPDATE counters SET opens = opens + 1 WHERE link_id = ?', [linkId]);
  }

  @override
  Future<LinkStats> stats(String linkId) async {
    final rows = _db.select('SELECT * FROM counters WHERE link_id = ?', [linkId]);
    if (rows.isEmpty) return const LinkStats();
    final r = rows.first;
    return LinkStats(
      clicks: r['clicks'] as int,
      clicksIos: r['clicks_ios'] as int,
      clicksAndroid: r['clicks_android'] as int,
      clicksOther: r['clicks_other'] as int,
      opens: r['opens'] as int,
      installs: r['installs'] as int,
    );
  }

  @override
  Future<int> purgeExpired(int now) async {
    _db.execute('DELETE FROM clicks WHERE expires_at <= ?', [now]);
    var n = _db.updatedRows;
    _db.execute('DELETE FROM links WHERE expires_at IS NOT NULL AND expires_at <= ?', [now]);
    n += _db.updatedRows;
    return n;
  }

  @override
  Future<void> close() async => _db.dispose();
}
