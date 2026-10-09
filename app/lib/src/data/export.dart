import 'dart:convert';
import 'dart:typed_data';

// ---------------------------------------------------------------- CSV

/// One CSV cell: quoted when it holds a comma, quote or line break.
String csvCell(Object? v) {
  if (v == null) return '';
  final s = v is double ? _num(v) : v.toString();
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _num(double v) {
  final r = (v * 100).round() / 100;
  return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
}

/// A whole CSV file. Starts with a byte-order mark so Excel reads UTF-8.
String csvFile(List<String> header, Iterable<List<Object?>> rows) {
  final b = StringBuffer('\uFEFF')..write(header.map(csvCell).join(','))..write('\r\n');
  for (final row in rows) {
    b
      ..write(row.map(csvCell).join(','))
      ..write('\r\n');
  }
  return b.toString();
}

// ---------------------------------------------------------------- ZIP

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    t[n] = c;
  }
  return t;
}();

/// Standard CRC-32 (as used by zip).
int crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

class _Le {
  final BytesBuilder b = BytesBuilder();
  void u16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void bytes(List<int> v) => b.add(v);
  int get length => b.length;
  Uint8List take() => b.takeBytes();
}

/// A zip archive of [files] (name -> contents), stored without compression
/// so it needs no extra libraries. Every zip tool and Windows can open it.
Uint8List zipFiles(Map<String, List<int>> files, {DateTime? at}) {
  final t = at ?? DateTime.now();
  final dosTime = (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);
  final dosDate = ((t.year - 1980).clamp(0, 127) << 9) | (t.month << 5) | t.day;

  final out = _Le();
  final central = _Le();
  var count = 0;
  for (final entry in files.entries) {
    final name = utf8.encode(entry.key);
    final data = entry.value;
    final crc = crc32(data);
    final offset = out.length;

    out
      ..u32(0x04034b50)
      ..u16(20) // version needed
      ..u16(0x0800) // names are UTF-8
      ..u16(0) // stored
      ..u16(dosTime)
      ..u16(dosDate)
      ..u32(crc)
      ..u32(data.length)
      ..u32(data.length)
      ..u16(name.length)
      ..u16(0)
      ..bytes(name)
      ..bytes(data);

    central
      ..u32(0x02014b50)
      ..u16(20) // version made by
      ..u16(20) // version needed
      ..u16(0x0800)
      ..u16(0)
      ..u16(dosTime)
      ..u16(dosDate)
      ..u32(crc)
      ..u32(data.length)
      ..u32(data.length)
      ..u16(name.length)
      ..u16(0) // extra
      ..u16(0) // comment
      ..u16(0) // disk
      ..u16(0) // internal attributes
      ..u32(0) // external attributes
      ..u32(offset)
      ..bytes(name);
    count++;
  }
  final centralOffset = out.length;
  final centralBytes = central.take();
  out
    ..bytes(centralBytes)
    ..u32(0x06054b50)
    ..u16(0)
    ..u16(0)
    ..u16(count)
    ..u16(count)
    ..u32(centralBytes.length)
    ..u32(centralOffset)
    ..u16(0);
  return out.take();
}
