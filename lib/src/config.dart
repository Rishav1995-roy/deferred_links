import 'package:http/http.dart' as http;

import 'models.dart';

/// Configuration for [DeferredLinks].
class DeferredLinksConfig {
  /// Creates a configuration pointing at your `deferred_links` server.
  DeferredLinksConfig({
    required this.serverUrl,
    this.apiKey,
    List<String>? shortLinkHosts,
    this.useClipboard = false,
    this.minConfidence = MatchConfidence.medium,
    this.requestTimeout = const Duration(seconds: 10),
    this.httpClient,
  }) : shortLinkHosts = shortLinkHosts ?? <String>[serverUrl.host];

  /// Base URL of the server, e.g. `https://links.example.com`.
  final Uri serverUrl;

  /// Bearer key for creating links from the app. Anything in the app binary
  /// can be extracted, so prefer creating links from your own backend and
  /// leave this null. If you must create links in-app, give the server a
  /// separate, rate-limited key for that.
  final String? apiKey;

  /// Hosts whose single-segment paths (`https://host/<id>`) are short links
  /// that must be resolved through the server. Defaults to the server host.
  final List<String> shortLinkHosts;

  /// iOS only. When true, the first-launch check reads the clipboard for a
  /// token the landing page copied. This triggers the iOS paste prompt. Off by
  /// default; the package never reads the clipboard otherwise.
  final bool useClipboard;

  /// Deferred matches below this confidence are reported as
  /// [DeferredStatus.noMatch] instead of being returned.
  final MatchConfidence minConfidence;

  /// Per-request timeout.
  final Duration requestTimeout;

  /// Inject your own HTTP client (proxies, tests).
  final http.Client? httpClient;
}
