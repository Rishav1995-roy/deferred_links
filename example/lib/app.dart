import 'package:deferred_links/deferred_links.dart';
import 'package:flutter/material.dart';

/// Example app for `deferred_links`.
///
/// It demonstrates: DeepLinkScope (cold start, stream, deferred), routing with
/// DeepLinkRouter to the right screen, short link creation, and a settings
/// screen that changes the theme and the matching policy.
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key, DeferredLinks? links, this.serverUrl})
      : _links = links;

  final DeferredLinks? _links;
  final String? serverUrl;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final _nav = GlobalKey<NavigatorState>();
  final _events = ValueNotifier<List<DeepLink>>(const []);
  Color _seed = const Color(0xFF3F51B5);
  ThemeMode _mode = ThemeMode.system;
  late String _serverUrl = widget.serverUrl ?? 'http://10.0.2.2:8080';
  bool _clipboard = false;
  MatchConfidence _minConfidence = MatchConfidence.medium;

  DeferredLinks get _links => widget._links ?? DeferredLinks.instance;

  @override
  void initState() {
    super.initState();
    _apply();
  }

  void _apply() {
    _links.configure(DeferredLinksConfig(
      serverUrl: Uri.parse(_serverUrl),
      useClipboard: _clipboard,
      minConfidence: _minConfidence,
    ));
  }

  late final DeepLinkRouter _router = DeepLinkRouter({
    '/product/:id': (link, p) =>
        _nav.currentState?.push(MaterialPageRoute<void>(
          builder: (_) => ProductScreen(id: p['id']!, link: link),
        )),
    '/invite/:code': (link, p) =>
        _nav.currentState?.push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Invitation')),
            body: Center(child: Text('Invite code ${p['code']}')),
          ),
        )),
  });

  void _onLink(DeepLink link) {
    _events.value = [link, ..._events.value];
    _router.route(link);
  }

  @override
  Widget build(BuildContext context) {
    return DeepLinkScope(
      links: _links,
      onLink: _onLink,
      child: MaterialApp(
        navigatorKey: _nav,
        title: 'deferred_links example',
        debugShowCheckedModeBanner: false,
        themeMode: _mode,
        theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: _seed,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: HomeScreen(
          events: _events,
          links: _links,
          onSettings: () => _nav.currentState?.push(MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(
              seed: _seed,
              mode: _mode,
              serverUrl: _serverUrl,
              clipboard: _clipboard,
              minConfidence: _minConfidence,
              onChanged: (seed, mode, url, clip, conf) {
                setState(() {
                  _seed = seed;
                  _mode = mode;
                  _serverUrl = url;
                  _clipboard = clip;
                  _minConfidence = conf;
                });
                _apply();
              },
            ),
          )),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.events,
    required this.links,
    required this.onSettings,
  });

  final ValueNotifier<List<DeepLink>> events;
  final DeferredLinks links;
  final VoidCallback onSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _path = TextEditingController(text: '/product/42');
  String? _created;
  String? _error;

  Future<void> _create() async {
    setState(() {
      _created = null;
      _error = null;
    });
    try {
      final host = widget.links.config!.serverUrl.host;
      final link = await widget.links.createShortLink(ShortLinkRequest(
        deepLink: Uri.parse('https://$host${_path.text}'),
        title: 'Shared from the example app',
        ttl: const Duration(days: 30),
      ));
      setState(() => _created = link.shortUrl.toString());
    } on Object catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deferred links'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune),
            onPressed: widget.onSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Create a short link',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _path,
                    decoration: const InputDecoration(
                      labelText: 'In-app path',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.link),
                    label: const Text('Create'),
                  ),
                  if (_created != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(_created!,
                        style: TextStyle(color: scheme.primary)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: scheme.error)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Received links',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ValueListenableBuilder<List<DeepLink>>(
            valueListenable: widget.events,
            builder: (context, links, _) {
              if (links.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nothing yet. Open a link on this device.'),
                );
              }
              return Column(
                children: [
                  for (final l in links)
                    Card(
                      child: ListTile(
                        leading: Icon(l.isDeferred
                            ? Icons.download_done
                            : Icons.open_in_new),
                        title: Text(l.uri.path.isEmpty ? '/' : l.uri.path),
                        subtitle: Text(l.isDeferred
                            ? 'Deferred via ${l.method?.name}, '
                                'confidence ${l.confidence?.name}'
                            : 'Opened directly'),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class ProductScreen extends StatelessWidget {
  const ProductScreen({super.key, required this.id, required this.link});

  final String id;
  final DeepLink link;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Product #$id')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [scheme.primaryContainer, scheme.tertiaryContainer],
                ),
              ),
              child: Icon(Icons.chair_outlined,
                  size: 96, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 16),
          Text('Linen Lounge Chair',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Opened from a ${link.isDeferred ? 'deferred ' : ''}link',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          if (link.data['promo'] != null)
            Chip(
              avatar: const Icon(Icons.sell_outlined, size: 18),
              label: Text('Promo ${link.data['promo']}'),
            ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.seed,
    required this.mode,
    required this.serverUrl,
    required this.clipboard,
    required this.minConfidence,
    required this.onChanged,
  });

  final Color seed;
  final ThemeMode mode;
  final String serverUrl;
  final bool clipboard;
  final MatchConfidence minConfidence;
  final void Function(Color, ThemeMode, String, bool, MatchConfidence)
      onChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Color seed = widget.seed;
  late ThemeMode mode = widget.mode;
  late bool clipboard = widget.clipboard;
  late MatchConfidence conf = widget.minConfidence;
  late final url = TextEditingController(text: widget.serverUrl);

  void _push() => widget.onChanged(seed, mode, url.text, clipboard, conf);

  @override
  Widget build(BuildContext context) {
    const seeds = [
      Color(0xFF3F51B5),
      Color(0xFF00897B),
      Color(0xFFE64A19),
      Color(0xFF8E24AA),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: url,
            decoration: const InputDecoration(
                labelText: 'Server URL', border: OutlineInputBorder()),
            onSubmitted: (_) => _push(),
          ),
          const SizedBox(height: 16),
          const Text('Accent'),
          Wrap(spacing: 8, children: [
            for (final c in seeds)
              ChoiceChip(
                label: const SizedBox(width: 20),
                avatar: CircleAvatar(backgroundColor: c),
                selected: seed == c,
                onSelected: (_) {
                  setState(() => seed = c);
                  _push();
                },
              ),
          ]),
          const SizedBox(height: 16),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {mode},
            onSelectionChanged: (s) {
              setState(() => mode = s.first);
              _push();
            },
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('iOS clipboard matching'),
            subtitle: const Text('Reads a token the landing page copied. '
                'Shows the iOS paste prompt.'),
            value: clipboard,
            onChanged: (v) {
              setState(() => clipboard = v);
              _push();
            },
          ),
          const SizedBox(height: 8),
          const Text('Minimum deferred confidence'),
          SegmentedButton<MatchConfidence>(
            segments: [
              for (final c in MatchConfidence.values)
                ButtonSegment(value: c, label: Text(c.name)),
            ],
            selected: {conf},
            onSelectionChanged: (s) {
              setState(() => conf = s.first);
              _push();
            },
          ),
        ],
      ),
    );
  }
}
