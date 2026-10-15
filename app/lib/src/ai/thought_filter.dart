/// Hides a model's private reasoning from what the chat shows.
///
/// The on-device runtime streams a thinking model's reasoning on its own
/// channel, wrapped as `<|channel>thought\n...<channel|>`, one wrapper per
/// token. Our AI package only strips the older `<think>...</think>` form for
/// Qwen3, so on iPhone the reasoning leaked into the chat. This drops every
/// `<|channel>...<channel|>` span, even one split across tokens, and passes
/// the rest through unchanged.
class ThoughtFilter {
  static const _open = '<|channel>', _close = '<channel|>';
  var _buf = '';
  var _inside = false;

  /// Feeds one token; returns the text that may be shown (often empty).
  String feed(String token) {
    _buf += token;
    final out = StringBuffer();
    while (_buf.isNotEmpty) {
      if (_inside) {
        final end = _buf.indexOf(_close);
        if (end < 0) {
          // Keep a possible start of the closing tag; drop the rest.
          _buf = _buf.substring(_buf.length - _partialSuffix(_buf, _close));
          break;
        }
        _buf = _buf.substring(end + _close.length);
        _inside = false;
      } else {
        final start = _buf.indexOf(_open);
        if (start < 0) {
          final keep = _partialSuffix(_buf, _open);
          out.write(_buf.substring(0, _buf.length - keep));
          _buf = _buf.substring(_buf.length - keep);
          break;
        }
        out.write(_buf.substring(0, start));
        _buf = _buf.substring(start + _open.length);
        _inside = true;
      }
    }
    return out.toString();
  }

  /// Anything still held back once the answer has ended.
  String flush() {
    final rest = _inside ? '' : _buf;
    _buf = '';
    _inside = false;
    return rest;
  }

  /// How many characters at the end of [s] could be the start of [tag].
  static int _partialSuffix(String s, String tag) {
    for (var n = tag.length - 1; n > 0; n--) {
      if (s.length >= n && s.endsWith(tag.substring(0, n))) return n;
    }
    return 0;
  }
}

/// The same, over a stream of tokens.
Stream<String> hideThoughtChannel(Stream<String> tokens) async* {
  final f = ThoughtFilter();
  await for (final t in tokens) {
    final out = f.feed(t);
    if (out.isNotEmpty) yield out;
  }
  final rest = f.flush();
  if (rest.isNotEmpty) yield rest;
}
