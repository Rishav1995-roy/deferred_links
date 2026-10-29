/// The pieces our server puts into the Play Store `referrer` parameter.
class ParsedReferrer {
  /// Creates a parsed referrer.
  const ParsedReferrer({this.clickId, this.deepLink});

  /// The click id recorded by the server (`dl_click`).
  final String? clickId;

  /// The deep link embedded for offline resolution (`dl_link`).
  final Uri? deepLink;

  /// Whether the referrer carries nothing we issued.
  bool get isEmpty => clickId == null && deepLink == null;
}

/// Parses an Install Referrer string such as
/// `dl_click=abc123&dl_link=https%3A%2F%2Fexample.com%2Fp%2F1`.
///
/// Organic installs (`utm_source=google-play&utm_medium=organic`) and
/// referrers from other tools return an empty [ParsedReferrer]. Never throws.
ParsedReferrer parseInstallReferrer(String? referrer) {
  if (referrer == null || referrer.isEmpty) return const ParsedReferrer();
  final Map<String, String> params;
  try {
    params = Uri.splitQueryString(referrer);
  } on ArgumentError {
    // Malformed %-escapes splitQueryString throws ArgumentError, other parsers FormatException.
    return const ParsedReferrer();
  } on FormatException {
    return const ParsedReferrer();
  }
  final click = params['dl_click'];
  final rawLink = params['dl_link'];
  Uri? link;
  if (rawLink != null && rawLink.isNotEmpty) {
    final parsed = Uri.tryParse(rawLink);
    if (parsed != null && parsed.hasScheme) link = parsed;
  }
  final validClick =
      click != null && RegExp(r'^[A-Za-z0-9_-]{4,64}$').hasMatch(click);
  return ParsedReferrer(clickId: validClick ? click : null, deepLink: link);
}
