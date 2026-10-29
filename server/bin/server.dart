import 'dart:async';
import 'dart:io';

import 'package:deferred_links_server/deferred_links_server.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final env = Platform.environment;
  final config = ServerConfig.fromEnv(env);
  final LinkStore store = (env['STORE'] ?? 'sqlite') == 'memory'
      ? MemoryStore()
      : SqliteStore(env['DB_PATH'] ?? 'deferred_links.db');
  await store.init();

  final app = DeferredLinksServer(config, store);
  Timer.periodic(const Duration(minutes: 10), (_) async {
    final removed = await app.purge();
    if (removed > 0) stdout.writeln('purged $removed expired rows');
  });

  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final server = await io.serve(app.handler, InternetAddress.anyIPv4, port);
  stdout.writeln('deferred_links server on :${server.port} (base ${config.baseUrl})');
  if (config.apiKeys.isEmpty) {
    stdout.writeln('WARNING: API_KEYS is empty, link creation and stats are disabled.');
  }
  for (final sig in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    sig.watch().listen((_) async {
      await server.close(force: true);
      await store.close();
      exit(0);
    });
  }
}
