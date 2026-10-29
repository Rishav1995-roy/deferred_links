import 'dart:convert';

import 'store.dart';

const _esc = HtmlEscape(HtmlEscapeMode.attribute);

String _e(String? s) => _esc.convert(s ?? '');

bool isHttpUrl(String? s) {
  final u = s == null ? null : Uri.tryParse(s);
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
}

/// HTML for social crawlers and iOS visitors. All dynamic values are escaped;
/// the script receives only server-generated ids through JSON.
String landingPage({
  required StoredLink link,
  required String nonce,
  String? clickId,
  String? iosStoreUrl,
  bool clipboardToken = false,
  String? privacyUrl,
  String? canonicalUrl,
}) {
  final title = link.title ?? 'Open in the app';
  final desc = link.description ?? 'Get the app to continue.';
  final image = isHttpUrl(link.imageUrl) ? link.imageUrl : null;
  final store = isHttpUrl(iosStoreUrl) ? iosStoreUrl : null;
  final scriptData = jsonEncode({'click': clickId, 'clipboard': clipboardToken})
      .replaceAll('<', '\\u003c');
  final script = clickId == null
      ? ''
      : '''
<script nonce="${_e(nonce)}">
(function () {
  var d = $scriptData;
  try {
    fetch('/c/' + encodeURIComponent(d.click) + '/fp', {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({
        screenWidth: screen.width, screenHeight: screen.height,
        timezoneOffsetMinutes: -new Date().getTimezoneOffset(),
        language: navigator.language
      }),
      keepalive: true
    });
  } catch (e) {}
  var btn = document.getElementById('get');
  if (btn && d.clipboard) {
    btn.addEventListener('click', function (ev) {
      if (!navigator.clipboard) return;
      ev.preventDefault();
      var go = function () { location.href = btn.href; };
      navigator.clipboard.writeText('deferredlinks:' + d.click).then(go, go);
    });
  }
})();
</script>''';
  return '''<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_e(title)}</title>
<meta property="og:title" content="${_e(title)}">
<meta property="og:description" content="${_e(desc)}">
${image == null ? '' : '<meta property="og:image" content="${_e(image)}">'}
${canonicalUrl == null ? '' : '<meta property="og:url" content="${_e(canonicalUrl)}">'}
<meta name="twitter:card" content="${image == null ? 'summary' : 'summary_large_image'}">
<style nonce="${_e(nonce)}">
body{font-family:system-ui,sans-serif;margin:0;min-height:100vh;display:grid;place-items:center;background:#f6f7fb;color:#1b1e2b}
main{max-width:360px;padding:32px;text-align:center}
a.btn{display:inline-block;margin-top:20px;padding:14px 28px;border-radius:12px;background:#3f51b5;color:#fff;text-decoration:none;font-weight:600}
small{display:block;margin-top:24px;color:#6b7080;line-height:1.4}
@media (prefers-color-scheme:dark){body{background:#13151f;color:#eceef7}}
</style></head><body><main>
<h1>${_e(title)}</h1><p>${_e(desc)}</p>
${store == null ? '<p>Search for the app in your store.</p>' : '<a class="btn" id="get" href="${_e(store)}">Get the app</a>'}
<small>To reopen this link after you install, we keep your approximate device settings (screen size, language, time zone) and a one-way hash of your network address for a short time, then delete them.${privacyUrl == null ? '' : ' <a href="${_e(privacyUrl)}">Privacy</a>'}</small>
</main>$script</body></html>''';
}

String notFoundPage() => '''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Link not found</title></head>
<body style="font-family:system-ui,sans-serif;text-align:center;padding:48px">
<h1>Link not found</h1><p>This link has expired or does not exist.</p></body></html>''';
