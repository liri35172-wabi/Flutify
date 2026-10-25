import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

/// 超过这个大小的 JSON 响应在后台 Isolate 里解码。
///
/// 起一个 Isolate 有约 1~2ms 的固定开销，小响应直接解码更快；主页（最多 99 个分区）、
/// 大歌单分页、专辑 / 艺人页这类几百 KB 到数 MB 的响应，UTF-8 + JSON 解码在主线程上
/// 要花几十毫秒，手机上就是一次明显掉帧。
const int jsonOffMainThreshold = 64 * 1024;

/// 把 UTF-8 编码的 JSON 字节解码为 Dart 对象；大于 [jsonOffMainThreshold] 时放到后台 Isolate。
///
/// 结果经 `Isolate.exit` 转移回来（不逐个复制），主线程只多一次很短的交接。
/// 解码失败与 `jsonDecode(utf8.decode(bytes))` 一样抛 [FormatException]。
Future<Object?> decodeJsonBytes(Uint8List bytes) {
  if (bytes.length < jsonOffMainThreshold) {
    // Future.sync：同步解码，但解析错误也以失败的 Future 交出，与大响应分支一致
    return Future.sync(() => _decode(bytes));
  }
  return Isolate.run(() => _decode(bytes), debugName: 'json-decode');
}

Object? _decode(Uint8List bytes) => jsonDecode(utf8.decode(bytes));
