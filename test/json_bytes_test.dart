import 'dart:convert';
import 'dart:typed_data';

import 'package:flutify_app/core/utils/json_bytes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List bytesOf(Object value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));

  test('小响应：当前线程解码，结果与 jsonDecode 一致', () async {
    final value = {
      'a': 1,
      'b': '中文',
      'c': [true, null],
    };
    expect(await decodeJsonBytes(bytesOf(value)), value);
  });

  test('大响应：后台 Isolate 解码，结果一致', () async {
    final value = {
      'items': [
        for (var i = 0; i < 5000; i++)
          {'uri': 'spotify:track:$i', 'name': '歌曲 $i'},
      ],
    };
    final bytes = bytesOf(value);
    expect(bytes.length, greaterThan(jsonOffMainThreshold));
    expect(await decodeJsonBytes(bytes), value);
  });

  test('非法 JSON：大小响应都抛 FormatException', () async {
    final small = Uint8List.fromList(utf8.encode('{"a":'));
    final large = Uint8List.fromList([
      ...utf8.encode('{"a":"'),
      ...List.filled(jsonOffMainThreshold, 0x61),
    ]);
    await expectLater(decodeJsonBytes(small), throwsFormatException);
    await expectLater(decodeJsonBytes(large), throwsFormatException);
  });
}
