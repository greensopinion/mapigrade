/// HTTP headers that `MapigradeLayer` adds to requests whose URL matches
/// [url]. Each HTTP request that the map sends gets the headers of the first
/// rule whose [url] matches the request's complete URL, and no headers when no
/// rule matches. Requests that the map serves from its cache or from assets
/// don't get the headers.
///
/// [url] is a glob, compared with the URL byte for byte and case-sensitively,
/// after tile URL templates are filled in:
///
/// - `*` matches any characters except `/`, so `https://*.example.com/**`
///   matches `https://a.example.com/x` but not
///   `https://attacker.example/x.example.com/x`.
/// - `**` matches any characters.
/// - `?` matches one character except `/`.
/// - `\` makes the next character literal.
///
/// MapLibre or the platform HTTP client manages these headers, and a rule
/// can't set them: `Accept-Encoding`, `Connection`, `Content-Length`, `Host`,
/// `If-Modified-Since`, `If-None-Match`, `Keep-Alive`, `Proxy-Authorization`,
/// `Proxy-Connection`, `Range`, `TE`, `Trailer`, `Transfer-Encoding`,
/// `Upgrade` and `User-Agent`. A rule with one of them, an invalid header
/// name, or a value with a control character other than horizontal tab makes
/// the layer report a `LayerCreateException`, whose message names the header
/// and doesn't contain its value.
final class HttpHeaderRule {
  /// A rule that keeps a copy of [headers]. In debug builds, asserts that each
  /// header name is valid and that no value contains a control character
  /// other than horizontal tab.
  HttpHeaderRule({required this.url, required Map<String, String> headers})
    : headers = Map.unmodifiable(headers) {
    assert(_checkHeaders(this.headers));
  }

  /// The glob that a request URL must match.
  final String url;

  /// Header names and values.
  final Map<String, String> headers;

  @override
  bool operator ==(Object other) =>
      other is HttpHeaderRule &&
      other.url == url &&
      other.headers.length == headers.length &&
      headers.entries.every((e) => other.headers[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    url,
    Object.hashAllUnordered(
      headers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => 'HttpHeaderRule($url, ${headers.keys.toList()})';
}

// The messages omit the values, which can be secret.
bool _checkHeaders(Map<String, String> headers) {
  for (final MapEntry(key: name, :value) in headers.entries) {
    assert(
      name.isNotEmpty && name.codeUnits.every(_isTokenChar),
      'invalid HTTP header name "$name"',
    );
    assert(
      !value.codeUnits.any((c) => (c < 0x20 && c != 0x09) || c == 0x7f),
      'the value of HTTP header "$name" contains a control character',
    );
  }
  return true;
}

bool _isTokenChar(int c) =>
    (c >= 0x30 && c <= 0x39) || // 0-9
    (c >= 0x41 && c <= 0x5a) || // A-Z
    (c >= 0x61 && c <= 0x7a) || // a-z
    "!#\$%&'*+-.^_`|~".codeUnits.contains(c);
