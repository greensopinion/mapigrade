// Designs D80 and D82 of the http-headers-and-assets change.

/// HTTP headers that `MapigradeLayer` adds to requests whose URL matches
/// [url]. A request gets the headers of the first matching rule, or none.
///
/// [url] is a case-sensitive glob over the complete URL: `*` matches any
/// characters except `/`, `**` any characters, `?` one character except `/`,
/// and `\` escapes the next character.
///
/// A header that MapLibre rejects, such as `Host`, makes the layer report a
/// `LayerCreateException`.
final class HttpHeaderRule {
  /// A rule that keeps a copy of [headers].
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
