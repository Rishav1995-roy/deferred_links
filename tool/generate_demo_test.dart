// Generates doc/demo.gif and the screenshots WITHOUT a device.
//
//   flutter test tool/generate_demo_test.dart --tags demo
//
// The walkthrough is an ILLUSTRATION: the chat and store screens are drawn
// stand-ins, and the last scene is the real example app driven by a fake
// platform that delivers the deferred link. It is not a device capture.
// ignore_for_file: avoid_relative_lib_imports
@Tags(['demo'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:deferred_links/deferred_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../example/lib/app.dart';
import '../test/support.dart';

const _size = Size(390, 760);
final _frames = Directory('build/demo_frames');
final _key = GlobalKey();
var _n = 0;

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT']!;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String f) async =>
      ByteData.sublistView(await File('$dir/$f').readAsBytes());
  final roboto = FontLoader('Roboto')
    ..addFont(read('Roboto-Regular.ttf'))
    ..addFont(read('Roboto-Medium.ttf'))
    ..addFont(read('Roboto-Bold.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> _capture(WidgetTester t, {String? name}) async {
  await t.runAsync(() async {
    final boundary =
        _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = name != null
        ? File('doc/$name.png')
        : File('build/demo_frames/f${(_n++).toString().padLeft(3, '0')}.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
  });
}

Widget _shell(Widget body, String caption, {Brightness b = Brightness.light}) {
  final dark = b == Brightness.dark;
  return Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: _key,
      child: Column(children: [
        Expanded(child: body),
        Container(
          width: double.infinity,
          color: const Color(0xFF1B1E2B),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(caption,
                style: const TextStyle(
                    fontFamily: 'Roboto',
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none)),
            const SizedBox(height: 2),
            Text('Illustrative walkthrough, not a device capture',
                style: TextStyle(
                    fontFamily: 'Roboto',
                    color: dark ? Colors.white60 : Colors.white54,
                    fontSize: 10,
                    decoration: TextDecoration.none)),
          ]),
        ),
      ]),
    ),
  );
}

Widget _chat({required bool pressed}) => Material(
      color: const Color(0xFFEFF1F7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          height: 76,
          color: Colors.white,
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.all(14),
          child: const Row(children: [
            CircleAvatar(
                backgroundColor: Color(0xFF8E24AA),
                child: Text('A', style: TextStyle(color: Colors.white))),
            SizedBox(width: 10),
            Text('Alex (sample contact)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
          ]),
        ),
        const SizedBox(height: 24),
        _bubble('Found the chair you wanted'),
        _bubble('https://go.example.com/aB3dEf9h',
            link: true, pressed: pressed),
      ]),
    );

Widget _bubble(String text, {bool link = false, bool pressed = false}) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 60, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: pressed ? const Color(0xFFD5DCF7) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(text,
              style: TextStyle(
                  fontSize: 15,
                  color: link ? const Color(0xFF1A56DB) : Colors.black87,
                  decoration: link ? TextDecoration.underline : null)),
        ),
      ),
    );

Widget _store({required double? progress, required bool done}) => Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                    colors: [Color(0xFF3F51B5), Color(0xFF00897B)]),
              ),
              child: const Icon(Icons.chair_outlined,
                  color: Colors.white, size: 44),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Linen Home (sample app)',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w500)),
                    SizedBox(height: 4),
                    Text('Example Studio',
                        style: TextStyle(color: Colors.black54)),
                  ]),
            ),
          ]),
          const SizedBox(height: 28),
          if (progress == null || done)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                onPressed: () {},
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF01875F)),
                child: Text(done ? 'Open' : 'Install'),
              ),
            )
          else
            Column(children: [
              LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  color: const Color(0xFF01875F)),
              const SizedBox(height: 8),
              Text('Installing... ${(progress * 100).round()}%',
                  style: const TextStyle(color: Colors.black54)),
            ]),
          const SizedBox(height: 28),
          const Text(
              'The link you tapped will be waiting when you open the app.',
              style: TextStyle(color: Colors.black54, height: 1.4)),
        ]),
      ),
    );

void main() {
  setUpAll(() async {
    if (_frames.existsSync()) _frames.deleteSync(recursive: true);
    _frames.createSync(recursive: true);
    await _loadFonts();
  });

  testWidgets('render demo frames and screenshots', (t) async {
    t.view
      ..physicalSize = _size * 2
      ..devicePixelRatio = 2;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    ThemeData theme() => ThemeData(fontFamily: 'Roboto', useMaterial3: true);
    Widget wrap(Widget child, String caption,
            {Brightness b = Brightness.light}) =>
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme(),
          home: _shell(child, caption, b: b),
        );

    // Scene 1: tap the link in a chat.
    for (var i = 0; i < 14; i++) {
      await t.pumpWidget(wrap(_chat(pressed: i >= 8), '1. Tap a short link'));
      await _capture(t);
    }
    // Scene 2: the app is not installed, so the link lands on the store.
    for (var i = 0; i < 4; i++) {
      await t.pumpWidget(wrap(_store(progress: null, done: false),
          '2. Not installed: the link sends you to the store'));
      await _capture(t);
    }
    for (var i = 0; i <= 16; i++) {
      await t.pumpWidget(wrap(_store(progress: i / 16, done: false),
          '3. Install (the link travels in the Play referrer)'));
      await _capture(t);
    }
    for (var i = 0; i < 4; i++) {
      await t
          .pumpWidget(wrap(_store(progress: 1, done: true), '4. Open the app'));
      await _capture(t);
    }

    // Scene 3: the real example app, first launch after install.
    final platform = FakePlatform(
      referrer: const InstallReferrerResult('ok',
          referrer: 'dl_click=abcd1234efgh&dl_link='
              'https%3A%2F%2Fgo.example.com%2Fproduct%2F42'),
    );
    final links = DeferredLinks(
        platform: platform, targetPlatform: TargetPlatform.android);
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: _shellApp(links, '5. First launch: opened at the right screen'),
    ));
    await _capture(t);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 60));
      await _capture(t);
    }
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 40));
      await _capture(t);
    }
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 100));
      await _capture(t);
    }
    await _capture(t, name: 'screenshot_light');

    // Dark screenshot: the home screen listing the received deferred link.
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    final platform2 = FakePlatform(
      referrer: const InstallReferrerResult('ok',
          referrer: 'dl_link=https%3A%2F%2Fgo.example.com%2Fproduct%2F42'),
    );
    final links2 = DeferredLinks(
        platform: platform2, targetPlatform: TargetPlatform.android);
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: _shellApp(links2, 'Received links list (dark theme)',
          b: Brightness.dark),
    ));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    Navigator.of(t.element(find.byType(ProductScreen))).pop();
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    await _capture(t, name: 'screenshot_dark');
  });
}

Widget _shellApp(DeferredLinks links, String caption,
    {Brightness b = Brightness.light}) {
  return RepaintBoundary(
    key: _key,
    child: Column(children: [
      Expanded(
          child: ExampleApp(links: links, serverUrl: 'http://127.0.0.1:1')),
      Container(
        width: double.infinity,
        color: const Color(0xFF1B1E2B),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(caption,
              style: const TextStyle(
                  fontFamily: 'Roboto',
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none)),
          const SizedBox(height: 2),
          const Text('Illustrative walkthrough, not a device capture',
              style: TextStyle(
                  fontFamily: 'Roboto',
                  color: Colors.white54,
                  fontSize: 10,
                  decoration: TextDecoration.none)),
        ]),
      ),
    ]),
  );
}
