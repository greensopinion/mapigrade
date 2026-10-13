// Designs D80 and D82 of the http-headers-and-assets change.
import 'package:flutter_mapigrade/src/layer/http_header_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rules are equal by URL and headers', () {
    final rule = HttpHeaderRule(
      url: 'https://tiles.example.com/**',
      headers: {'X-Access-Key': 'k1', 'X-Other': 'o'},
    );
    final same = HttpHeaderRule(
      url: 'https://tiles.example.com/**',
      headers: {'X-Other': 'o', 'X-Access-Key': 'k1'},
    );
    expect(rule, same);
    expect(rule.hashCode, same.hashCode);
    expect(
      rule,
      isNot(
        HttpHeaderRule(
          url: 'https://tiles.example.com/v2/**',
          headers: {'X-Access-Key': 'k1', 'X-Other': 'o'},
        ),
      ),
    );
    expect(
      rule,
      isNot(
        HttpHeaderRule(
          url: 'https://tiles.example.com/**',
          headers: {'X-Access-Key': 'k2', 'X-Other': 'o'},
        ),
      ),
    );
    expect(
      rule,
      isNot(
        HttpHeaderRule(
          url: 'https://tiles.example.com/**',
          headers: {'X-Access-Key': 'k1'},
        ),
      ),
    );
  });

  test('a rule keeps a copy of the headers', () {
    final headers = {'X-Access-Key': 'k1'};
    final rule = HttpHeaderRule(url: 'https://a/**', headers: headers);
    headers['X-Access-Key'] = 'k2';
    expect(rule.headers, {'X-Access-Key': 'k1'});
  });

  test('an invalid header name fails the assert', () {
    expect(
      () => HttpHeaderRule(url: 'https://a/**', headers: {'X(Key)': 'k'}),
      throwsA(
        isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('X(Key)'),
        ),
      ),
    );
    expect(
      () => HttpHeaderRule(url: 'https://a/**', headers: {'': 'k'}),
      throwsA(isA<AssertionError>()),
    );
  });

  test('a header name with a space fails the assert', () {
    expect(
      () => HttpHeaderRule(url: 'https://a/**', headers: {'X Key': 'k'}),
      throwsA(isA<AssertionError>()),
    );
  });

  test('a value with a line feed fails the assert without the value', () {
    expect(
      () => HttpHeaderRule(
        url: 'https://a/**',
        headers: {'X-Access-Key': 'secret\nInjected: 1'},
      ),
      throwsA(
        isA<AssertionError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('X-Access-Key'), isNot(contains('secret'))),
        ),
      ),
    );
  });

  test('a value with a horizontal tab passes', () {
    final rule = HttpHeaderRule(
      url: 'https://a/**',
      headers: {"X-Token!#\$%&'*+-.^_`|~9": 'a\tb'},
    );
    expect(rule.headers.values.single, 'a\tb');
  });
}
