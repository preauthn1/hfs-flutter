import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Cross-platform user-visible file storage.
/// Android uses the Storage Access Framework/MediaStore and never writes a
/// guessed public path or asks for broad storage permission.
class HfsAndroidStorage {
  static const MethodChannel _channel = MethodChannel('hfs_storage');

  static bool get isAndroid => Platform.isAndroid;

  static Future<String> saveBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('saveBytes is only the Android bridge');
    }
    final result = await _channel.invokeMethod<String>('saveBytes', <String, dynamic>{
      'fileName': fileName,
      'mimeType': mimeType,
      'bytes': bytes,
    });
    if (result == null || result.isEmpty) {
      throw StateError('Android did not return a saved document URI');
    }
    return result;
  }

  static Future<String> saveText({
    required String text,
    required String fileName,
    String mimeType = 'application/json',
  }) => saveBytes(
        bytes: Uint8List.fromList(utf8.encode(text)),
        fileName: fileName,
        mimeType: mimeType,
      );

  static Future<String> readTextDocument() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('readTextDocument is only the Android bridge');
    }
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('openText');
    if (result == null) throw StateError('未选择文件');
    final rawBytes = result['bytes'];
    if (rawBytes is! List) throw StateError('Android 返回的文件内容无效');
    final bytes = rawBytes is Uint8List
        ? rawBytes
        : Uint8List.fromList(List<int>.from(rawBytes));
    return utf8.decode(bytes, allowMalformed: false);
  }
}
