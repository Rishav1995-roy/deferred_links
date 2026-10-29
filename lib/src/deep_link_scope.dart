import 'dart:async';

import 'package:flutter/widgets.dart';

import 'deferred_links_base.dart';
import 'models.dart';

/// Wires incoming links and the first-launch deferred check to a callback.
///
/// Place it above your navigator:
///
/// ```dart
/// DeepLinkScope(
///   onLink: (link) => router.go(link.uri.path),
///   child: MaterialApp.router(...),
/// )
/// ```
class DeepLinkScope extends StatefulWidget {
  /// Creates a scope.
  const DeepLinkScope({
    super.key,
    required this.onLink,
    required this.child,
    this.links,
    this.checkDeferred = true,
    this.onDeferredResult,
  });

  /// Called for the launch link, every later link, and an accepted deferred
  /// link (check [DeepLink.isDeferred] and [DeepLink.confidence]).
  final ValueChanged<DeepLink> onLink;

  /// The subtree.
  final Widget child;

  /// Defaults to [DeferredLinks.instance].
  final DeferredLinks? links;

  /// Whether to run [DeferredLinks.checkDeferredLink] at startup.
  final bool checkDeferred;

  /// Observes the deferred check outcome, including errors and no-match, for
  /// logging or analytics.
  final ValueChanged<DeferredLinkResult>? onDeferredResult;

  @override
  State<DeepLinkScope> createState() => _DeepLinkScopeState();
}

class _DeepLinkScopeState extends State<DeepLinkScope> {
  StreamSubscription<DeepLink>? _sub;

  DeferredLinks get _links => widget.links ?? DeferredLinks.instance;

  @override
  void initState() {
    super.initState();
    _sub = _links.linkStream.listen(_emit);
    unawaited(_start());
  }

  Future<void> _start() async {
    final initial = await _links.getInitialLink();
    if (!mounted) return;
    if (initial != null) _emit(initial);
    if (!widget.checkDeferred) return;
    final result = await _links.checkDeferredLink();
    if (!mounted) return;
    widget.onDeferredResult?.call(result);
    // An incoming launch link wins over a deferred one.
    if (result.link != null && initial == null) _emit(result.link!);
  }

  void _emit(DeepLink link) {
    if (mounted) widget.onLink(link);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
