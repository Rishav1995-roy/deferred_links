import 'models.dart';

/// Matches a URI path against a pattern such as `/product/:id`.
///
/// `:name` captures one segment, a trailing `*` matches the rest of the path.
/// Matching ignores a trailing slash.
class DeepLinkPattern {
  /// Creates a pattern.
  DeepLinkPattern(this.pattern)
      : _segments = _split(pattern),
        _wildcard = pattern.endsWith('*');

  /// The pattern text.
  final String pattern;

  final List<String> _segments;
  final bool _wildcard;

  static List<String> _split(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList(growable: false);

  /// Returns captured parameters (plus query parameters) or `null` when the
  /// URI does not match. Path captures win over query parameters of the same
  /// name.
  Map<String, String>? match(Uri uri) {
    final parts = _split(uri.path);
    final fixed = _wildcard ? _segments.length - 1 : _segments.length;
    if (_wildcard ? parts.length < fixed : parts.length != fixed) return null;
    final out = <String, String>{...uri.queryParameters};
    for (var i = 0; i < fixed; i++) {
      final seg = _segments[i];
      if (seg.startsWith(':')) {
        out[seg.substring(1)] = parts[i];
      } else if (seg != parts[i]) {
        return null;
      }
    }
    if (_wildcard) out['*'] = parts.skip(fixed).join('/');
    return out;
  }
}

/// Maps deep links to handlers by pattern, first match wins.
///
/// ```dart
/// final router = DeepLinkRouter({
///   '/product/:id': (link, p) => openProduct(p['id']!),
///   '/invite/:code': (link, p) => openInvite(p['code']!),
/// });
/// router.route(link); // returns false when nothing matched
/// ```
class DeepLinkRouter {
  /// Creates a router from ordered pattern/handler pairs.
  DeepLinkRouter(Map<String, DeepLinkHandler> routes)
      : _routes = [
          for (final e in routes.entries) (DeepLinkPattern(e.key), e.value),
        ];

  final List<(DeepLinkPattern, DeepLinkHandler)> _routes;

  /// Calls the first handler whose pattern matches. Returns whether one did.
  bool route(DeepLink link) {
    for (final (pattern, handler) in _routes) {
      final params = pattern.match(link.uri);
      if (params != null) {
        handler(link, params);
        return true;
      }
    }
    return false;
  }
}

/// Handles a routed [DeepLink] with its captured [params].
typedef DeepLinkHandler = void Function(
    DeepLink link, Map<String, String> params);
