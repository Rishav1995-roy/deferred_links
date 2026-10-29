import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'landing.dart';
import 'matcher.dart';
import 'store.dart';

final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{4,64}$');
const _reserved = {'healthz', 'apple-app-site-association', 'assetlinks'};
final RegExp _bots = RegExp(
  r'facebookexternalhit|Twitterbot|Slackbot|WhatsApp|TelegramBot|LinkedInBot|Discordbot|'
  r'Googlebot|bingbot|Applebot|Pinterest|SkypeUriPreview|redditbot|embedly',
  caseSensitive: false,
);
const _maxBody = 16 * 1024;

/// The HTTP application. Build it with [DeferredLinksServer.handler].
class DeferredLinksServer {
  DeferredLinksServer(this.config, this.store, {int Function()? clock, Random? random})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _random = random ?? Random.secure(),
        _salt = utf8.encode(config.ipHashSalt ?? _randomSalt());

  final ServerConfig config;
  final LinkStore store;
  final int Function() _clock;
  final Random _random;
  final List<int> _salt;
  final Map<String, (int, int)> _rate = {}; // key -> (window start, count)

  static String _randomSalt() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// Periodic cleanup. Call from `main`.
  Future<int> purge() => store.purgeExpired(_clock());

  Handler get handler {
    final router = Router()
      ..get('/healthz', (Request r) => Response.ok('ok'))
      ..get('/.well-known/assetlinks.json', _assetLinks)
      ..get('/.well-known/apple-app-site-association', _aasa)
      ..get('/apple-app-site-association', _aasa)
      ..post('/v1/links', _createLink)
      ..get('/v1/links/<id>/stats', _stats)
      ..get('/v1/resolve/<id>', _resolve)
      ..post('/v1/match', _match)
      ..post('/v1/clicks/<id>/install', _install)
      ..post('/c/<id>/fp', _fingerprint)
      ..get('/<id>', _shortLink);
    return const Pipeline()
        .addMiddleware(_securityHeaders)
        .addHandler(router.call);
  }

  Handler _securityHeaders(Handler inner) => (request) async {
        final res = await inner(request);
        return res.change(headers: {
          'x-content-type-options': 'nosniff',
          'referrer-policy': 'no-referrer',
          ...res.headers,
        });
      };

  // ---- helpers -------------------------------------------------------------

  Response _json(Object body, [int status = 200]) => Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'},
      );

  Response _err(int status, String code, String message) =>
      _json({'error': code, 'message': message}, status);

  String _clientIp(Request r) {
    if (config.trustProxy) {
      final xff = r.headers['x-forwarded-for'];
      if (xff != null && xff.isNotEmpty) return xff.split(',').first.trim();
    }
    final info = r.context['shelf.io.connection_info'];
    if (info is HttpConnectionInfo) return info.remoteAddress.address;
    return '0.0.0.0';
  }

  /// Salted HMAC of the address; IPv6 is reduced to its /64 prefix first.
  String _ipHash(String ip) {
    var norm = ip;
    final addr = InternetAddress.tryParse(ip);
    if (addr != null && addr.type == InternetAddressType.IPv6) {
      norm = 'v6:${addr.rawAddress.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    }
    return Hmac(sha256, _salt).convert(utf8.encode(norm)).toString().substring(0, 32);
  }

  bool _limited(Request r, String bucket) {
    final now = _clock();
    final key = '$bucket:${_ipHash(_clientIp(r))}';
    final cur = _rate[key];
    if (cur == null || now - cur.$1 >= 60000) {
      if (_rate.length > 50000) _rate.clear();
      _rate[key] = (now, 1);
      return false;
    }
    _rate[key] = (cur.$1, cur.$2 + 1);
    return cur.$2 + 1 > config.rateLimitPerMinute;
  }

  String _newId(int length) {
    const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(length, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  bool _authorized(Request r) {
    if (config.apiKeys.isEmpty) return false;
    final header = r.headers['authorization'] ?? '';
    if (!header.startsWith('Bearer ')) return false;
    final given = utf8.encode(header.substring(7));
    var ok = false;
    for (final key in config.apiKeys) {
      final k = utf8.encode(key);
      var diff = k.length ^ given.length;
      for (var i = 0; i < k.length && i < given.length; i++) {
        diff |= k[i] ^ given[i];
      }
      if (diff == 0) ok = true;
    }
    return ok;
  }

  Future<Map<String, Object?>?> _readJson(Request r) async {
    final len = r.contentLength;
    if (len != null && len > _maxBody) return null;
    final bytes = <int>[];
    await for (final chunk in r.read()) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBody) return null;
    }
    try {
      final v = jsonDecode(utf8.decode(bytes));
      return v is Map<String, Object?> ? v : null;
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> _linkJson(StoredLink l) =>
      {'id': l.id, 'deepLink': l.deepLink, 'data': l.data};

  // ---- verification files --------------------------------------------------

  Response _assetLinks(Request r) {
    if (config.androidPackage == null || config.androidSha256.isEmpty) {
      return Response.notFound('assetlinks not configured');
    }
    return Response.ok(
      jsonEncode([
        {
          'relation': ['delegate_permission/common.handle_all_urls'],
          'target': {
            'namespace': 'android_app',
            'package_name': config.androidPackage,
            'sha256_cert_fingerprints': config.androidSha256,
          },
        }
      ]),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _aasa(Request r) {
    if (config.iosAppIds.isEmpty) return Response.notFound('AASA not configured');
    return Response.ok(
      jsonEncode({
        'applinks': {
          'details': [
            {
              'appIDs': config.iosAppIds,
              'components': [for (final p in config.iosPaths) {'/': p}],
              'paths': config.iosPaths,
            }
          ],
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  // ---- link management -----------------------------------------------------

  Future<Response> _createLink(Request r) async {
    if (!_authorized(r)) return _err(401, 'unauthorized', 'Missing or invalid API key');
    final body = await _readJson(r);
    if (body == null) return _err(400, 'bad_request', 'Expected a JSON object under 16 KB');

    final deep = body['deepLink'];
    final deepUri = deep is String ? Uri.tryParse(deep) : null;
    const blocked = {'javascript', 'data', 'file', 'vbscript', 'blob'};
    if (deepUri == null || !deepUri.hasScheme || blocked.contains(deepUri.scheme.toLowerCase())) {
      return _err(400, 'invalid_deep_link', 'deepLink must be an http(s) or custom-scheme URL');
    }
    for (final k in ['fallbackUrl', 'imageUrl', 'androidStoreUrl', 'iosStoreUrl']) {
      final v = body[k];
      if (v != null && (v is! String || !isHttpUrl(v))) {
        return _err(400, 'invalid_$k', '$k must be an http(s) URL');
      }
    }
    final rawData = body['data'];
    final data = <String, String>{};
    if (rawData != null) {
      if (rawData is! Map || rawData.length > 20) {
        return _err(400, 'invalid_data', 'data must be an object with at most 20 keys');
      }
      for (final e in rawData.entries) {
        data['${e.key}'] = '${e.value}';
      }
    }

    final now = _clock();
    final ttlSeconds = body['ttlSeconds'];
    final ttl = ttlSeconds is num && ttlSeconds > 0
        ? Duration(seconds: ttlSeconds.toInt())
        : config.defaultLinkTtl;
    final alias = body['alias'];
    if (alias != null && (alias is! String || !_idPattern.hasMatch(alias) || _reserved.contains(alias))) {
      return _err(400, 'invalid_alias', 'alias must match [A-Za-z0-9_-]{4,64}');
    }

    String? str(String k) => body[k] is String ? body[k] as String : null;
    StoredLink build(String id) => StoredLink(
          id: id,
          deepLink: deepUri.toString(),
          createdAt: now,
          expiresAt: ttl == null ? null : now + ttl.inMilliseconds,
          data: data,
          title: _clip(str('title'), 120),
          description: _clip(str('description'), 300),
          imageUrl: str('imageUrl'),
          fallbackUrl: str('fallbackUrl'),
          androidStoreUrl: str('androidStoreUrl'),
          iosStoreUrl: str('iosStoreUrl'),
        );

    StoredLink? created;
    if (alias is String) {
      final l = build(alias);
      if (!await store.createLink(l)) return _err(409, 'alias_taken', 'alias already exists');
      created = l;
    } else {
      for (var i = 0; i < 5 && created == null; i++) {
        final l = build(_newId(8));
        if (await store.createLink(l)) created = l;
      }
      if (created == null) return _err(500, 'id_exhausted', 'Could not allocate an id');
    }
    return _json({
      'id': created.id,
      'shortUrl': config.baseUrl.replace(path: '/${created.id}', query: null).toString(),
      'deepLink': created.deepLink,
      if (created.expiresAt != null) 'expiresAt': created.expiresAt,
    }, 201);
  }

  String? _clip(String? s, int n) => s == null ? null : (s.length > n ? s.substring(0, n) : s);

  Future<Response> _stats(Request r, String id) async {
    if (!_authorized(r)) return _err(401, 'unauthorized', 'Missing or invalid API key');
    final link = await store.getLink(id);
    if (link == null) return _err(404, 'not_found', 'Unknown link');
    return _json({'id': id, ...(await store.stats(id)).toJson()});
  }

  Future<Response> _resolve(Request r, String id) async {
    if (_limited(r, 'resolve')) return _err(429, 'rate_limited', 'Too many requests');
    final link = await store.getLink(id);
    if (link == null || link.isExpired(_clock())) return _err(404, 'not_found', 'Unknown link');
    await store.incrementOpens(id);
    return _json(_linkJson(link));
  }

  // ---- short link landing --------------------------------------------------

  Future<Response> _shortLink(Request r, String id) async {
    if (!_idPattern.hasMatch(id) || _reserved.contains(id)) return Response.notFound('');
    if (_limited(r, 'click')) return Response(429, body: 'Too many requests');
    final now = _clock();
    final link = await store.getLink(id);
    if (link == null || link.isExpired(now)) {
      return Response.notFound(notFoundPage(), headers: {'content-type': 'text/html; charset=utf-8'});
    }
    final ua = r.headers['user-agent'] ?? '';
    final nonce = _newId(16);
    final canonical = config.baseUrl.replace(path: '/$id', query: null).toString();
    final htmlHeaders = {
      'content-type': 'text/html; charset=utf-8',
      'content-security-policy':
          "default-src 'none'; style-src 'nonce-$nonce'; script-src 'nonce-$nonce'; "
              "img-src https:; connect-src 'self'; base-uri 'none'; form-action 'none'",
      'cache-control': 'no-store',
    };

    if (_bots.hasMatch(ua)) {
      // Link previews: metadata only, no click, no fingerprint.
      return Response.ok(
        landingPage(link: link, nonce: nonce, canonicalUrl: canonical,
            iosStoreUrl: link.iosStoreUrl ?? config.iosStoreUrl, privacyUrl: config.privacyUrl),
        headers: htmlHeaders,
      );
    }

    final platform = ua.contains(RegExp(r'iPhone|iPad|iPod')) ? 'ios' : ua.contains('Android') ? 'android' : 'other';
    final ttl = platform == 'android' ? config.androidClickTtl : config.iosClickTtl;
    final osMatch = RegExp(r'OS (\d+)[_.]').firstMatch(ua);
    final click = ClickRecord(
      id: _newId(12),
      linkId: id,
      platform: platform,
      createdAt: now,
      expiresAt: now + ttl.inMilliseconds,
      ipHash: platform == 'other' ? null : _ipHash(_clientIp(r)),
      osMajor: osMatch == null ? null : int.tryParse(osMatch.group(1)!),
      language: primaryLanguage(r.headers['accept-language']),
    );
    await store.recordClick(click);

    if (platform == 'android') {
      final play = link.androidStoreUrl ?? config.androidStoreUrl;
      if (isHttpUrl(play)) {
        final referrer = StringBuffer('dl_click=${click.id}');
        if (link.deepLink.length <= 600) {
          referrer.write('&dl_link=${Uri.encodeQueryComponent(link.deepLink)}');
        }
        final base = Uri.parse(play!);
        final target = base.replace(queryParameters: {
          ...base.queryParameters,
          'referrer': referrer.toString(),
        });
        return Response.found(target.toString(), headers: {'cache-control': 'no-store'});
      }
    }
    if (platform == 'ios') {
      return Response.ok(
        landingPage(
          link: link,
          nonce: nonce,
          clickId: click.id,
          iosStoreUrl: link.iosStoreUrl ?? config.iosStoreUrl,
          clipboardToken: config.clipboardTokens,
          privacyUrl: config.privacyUrl,
          canonicalUrl: canonical,
        ),
        headers: htmlHeaders,
      );
    }
    final fallback = link.fallbackUrl ?? config.fallbackUrl;
    if (isHttpUrl(fallback)) {
      return Response.found(fallback!, headers: {'cache-control': 'no-store'});
    }
    return Response.ok(
      landingPage(link: link, nonce: nonce, canonicalUrl: canonical,
          iosStoreUrl: link.iosStoreUrl ?? config.iosStoreUrl, privacyUrl: config.privacyUrl),
      headers: htmlHeaders,
    );
  }

  Future<Response> _fingerprint(Request r, String id) async {
    if (_limited(r, 'fp')) return _err(429, 'rate_limited', 'Too many requests');
    final body = await _readJson(r);
    if (body == null) return _err(400, 'bad_request', 'Invalid body');
    int? clamp(Object? v, int lo, int hi) =>
        v is num && v >= lo && v <= hi ? v.toInt() : null;
    await store.updateClickSignals(
      id,
      screenWidth: clamp(body['screenWidth'], 1, 10000),
      screenHeight: clamp(body['screenHeight'], 1, 10000),
      timezoneOffsetMinutes: clamp(body['timezoneOffsetMinutes'], -840, 840),
      language: body['language'] is String ? primaryLanguage(body['language'] as String) : null,
    );
    return Response(204);
  }

  // ---- matching ------------------------------------------------------------

  Future<Response> _install(Request r, String id) async {
    if (_limited(r, 'install')) return _err(429, 'rate_limited', 'Too many requests');
    final click = await store.getClick(id);
    final now = _clock();
    if (click == null || click.expiresAt <= now) return _err(404, 'not_found', 'Unknown click');
    // Idempotent: a retry after a lost response still gets the link.
    await store.markMatched(id, now);
    final link = await store.getLink(click.linkId);
    if (link == null || link.isExpired(now)) return _err(404, 'not_found', 'Link expired');
    return _json({..._linkJson(link), 'method': 'installReferrer', 'confidence': 'exact'});
  }

  Future<Response> _match(Request r) async {
    if (_limited(r, 'match')) return _err(429, 'rate_limited', 'Too many requests');
    final body = await _readJson(r);
    if (body == null) return _err(400, 'bad_request', 'Invalid body');
    final signalsJson = body['signals'];
    final signals = DeviceSignals.fromJson(
        signalsJson is Map ? signalsJson.cast<String, Object?>() : <String, Object?>{});
    final now = _clock();

    Response matched(ClickRecord c, StoredLink l, String method, Confidence conf, double score) =>
        _json({
          'matched': true,
          'method': method,
          'confidence': conf.name,
          'score': score,
          'link': _linkJson(l),
        });

    // 1. Deterministic: token the landing page put on the clipboard.
    final token = body['clipboard'];
    if (config.clipboardTokens &&
        token is String &&
        token.startsWith('deferredlinks:') &&
        _idPattern.hasMatch(token.substring(14))) {
      final click = await store.getClick(token.substring(14));
      if (click != null && click.platform == 'ios' && await store.markMatched(click.id, now)) {
        final link = await store.getLink(click.linkId);
        if (link != null && !link.isExpired(now)) {
          return matched(click, link, 'clipboard', Confidence.exact, 1.0);
        }
      }
    }

    // 2. Probabilistic: same IP, recent click, consistent device signals.
    if (signals.platform != 'ios') return _json({'matched': false});
    final candidates = await store.candidateClicks(
      ipHash: _ipHash(_clientIp(r)),
      platform: 'ios',
      since: now - config.matchWindow.inMilliseconds,
      now: now,
    );
    final pick = pickMatch(candidates, signals, minScore: config.minMatchScore);
    if (pick == null) return _json({'matched': false});
    if (!await store.markMatched(pick.click.id, now)) return _json({'matched': false});
    final link = await store.getLink(pick.click.linkId);
    if (link == null || link.isExpired(now)) return _json({'matched': false});
    return matched(pick.click, link, 'fingerprint', pick.confidence, pick.score);
  }
}
