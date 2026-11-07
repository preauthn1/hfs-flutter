import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hfs_client.dart';
import 'hfs_models.dart';
import 'win32_native.dart';

/// Gallery item descriptor for multi-image Lightbox navigation (`←` / `→` keyboard switching)
class LightboxGalleryItem {
  final String imageUrl;
  final String caption;
  final PageOverlayData? overlay;
  final bool initialShowOverlay;
  final String? highlightedQuestionName;

  const LightboxGalleryItem({
    required this.imageUrl,
    required this.caption,
    this.overlay,
    this.initialShowOverlay = true,
    this.highlightedQuestionName,
  });
}

/// Shared helper for right-click / long-press / toolbar image copy & export
class HfsImageClipboardAndExporter {
  static String _sanitizeName(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    if (cleaned.isEmpty) return '好分数试卷';
    return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
  }

  /// Render [decodedImage] (or decode [rawBytes] if null) together with [overlay]
  /// (when [includeOverlay] is true) into a `ui.Image`.
  /// Note: caller must dispose the returned `ui.Image` ONLY if [ownsReturnedImage] is true.
  static Future<({ui.Image image, bool shouldDispose})> _prepareTargetImage({
    required Uint8List rawBytes,
    ui.Image? decodedImage,
    PageOverlayData? overlay,
    bool includeOverlay = true,
    String? highlightedQuestionName,
  }) async {
    ui.Image baseImg;
    bool decodedHere = false;
    if (decodedImage != null) {
      baseImg = decodedImage;
    } else {
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      baseImg = frame.image;
      decodedHere = true;
    }

    if (!includeOverlay || overlay == null) {
      return (image: baseImg, shouldDispose: decodedHere);
    }

    final recorder = ui.PictureRecorder();
    final size = Size(
      baseImg.width.toDouble(),
      baseImg.height.toDouble(),
    );
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawImage(baseImg, Offset.zero, Paint());
    final painter = _GradingOverlayPainter(
      imageSize: size,
      overlay: overlay,
      highlightedQuestionName: highlightedQuestionName,
    );
    painter.paint(canvas, size);
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(baseImg.width, baseImg.height);
    if (decodedHere) {
      baseImg.dispose();
    }
    return (image: rendered, shouldDispose: true);
  }

  /// Encode genuine PNG bytes (converting JPEG/GIF raw bytes into real PNG even when overlay is off)
  static Future<Uint8List> encodeCompositePng({
    required Uint8List rawBytes,
    ui.Image? decodedImage,
    PageOverlayData? overlay,
    bool includeOverlay = true,
    String? highlightedQuestionName,
  }) async {
    // Fast path: if no overlay is requested and rawBytes is already a valid PNG header, return directly
    if ((!includeOverlay || overlay == null) &&
        rawBytes.length > 8 &&
        rawBytes[0] == 0x89 &&
        rawBytes[1] == 0x50 &&
        rawBytes[2] == 0x4E &&
        rawBytes[3] == 0x47) {
      return rawBytes;
    }

    final prep = await _prepareTargetImage(
      rawBytes: rawBytes,
      decodedImage: decodedImage,
      overlay: overlay,
      includeOverlay: includeOverlay,
      highlightedQuestionName: highlightedQuestionName,
    );
    try {
      final byteData =
          await prep.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return rawBytes;
      return byteData.buffer.asUint8List();
    } finally {
      if (prep.shouldDispose) {
        prep.image.dispose();
      }
    }
  }

  /// Copy image bitmap directly into OS system clipboard in < 10ms on Windows (`CF_DIB` via Dart FFI).
  /// NEVER writes any file to the user's Downloads or Desktop directory!
  static Future<bool> copyImageFastToClipboard({
    required Uint8List rawBytes,
    ui.Image? decodedImage,
    PageOverlayData? overlay,
    bool includeOverlay = true,
    String? highlightedQuestionName,
  }) async {
    if (Platform.isWindows) {
      final prep = await _prepareTargetImage(
        rawBytes: rawBytes,
        decodedImage: decodedImage,
        overlay: overlay,
        includeOverlay: includeOverlay,
        highlightedQuestionName: highlightedQuestionName,
      );
      try {
        final w = prep.image.width;
        final h = prep.image.height;
        final rawRgba =
            await prep.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (rawRgba != null) {
          final ok = Win32NativeBridge.copyRgbaToClipboard(
            width: w,
            height: h,
            rgbaBytes: rawRgba.buffer.asUint8List(),
          );
          if (ok) return true;
        }
      } finally {
        if (prep.shouldDispose) {
          prep.image.dispose();
        }
      }
    }

    // Fallback for Linux / macOS: use a temporary file in systemTemp and delete it immediately after copying
    final pngBytes = await encodeCompositePng(
      rawBytes: rawBytes,
      decodedImage: decodedImage,
      overlay: overlay,
      includeOverlay: includeOverlay,
      highlightedQuestionName: highlightedQuestionName,
    );
    return copyImageToSystemClipboard(bytes: pngBytes, label: 'clipboard_tmp');
  }

  /// Copy pre-encoded PNG bytes to system clipboard WITHOUT saving anything to Downloads!
  static Future<bool> copyImageToSystemClipboard({
    required Uint8List bytes,
    required String label,
  }) async {
    if (Platform.isWindows) {
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        codec.dispose();
        final img = frame.image;
        final rgba = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        final w = img.width;
        final h = img.height;
        img.dispose();
        if (rgba != null) {
          final ok = Win32NativeBridge.copyRgbaToClipboard(
            width: w,
            height: h,
            rgbaBytes: rgba.buffer.asUint8List(),
          );
          if (ok) return true;
        }
      } catch (_) {}
    }

    File? tmpFile;
    try {
      final sep = Platform.pathSeparator;
      tmpFile = File(
        '${Directory.systemTemp.path}${sep}hfs_clip_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await tmpFile.writeAsBytes(bytes, flush: true);
      final tmpPath = tmpFile.path;

      if (Platform.isLinux) {
        try {
          final xclip = await Process.run('xclip', <String>[
            '-selection',
            'clipboard',
            '-t',
            'image/png',
            '-i',
            tmpPath,
          ]);
          if (xclip.exitCode == 0) return true;
        } catch (_) {}
        try {
          final wl = await Process.run(
            'bash',
            <String>['-lc', 'wl-copy --type image/png < "$tmpPath"'],
          );
          if (wl.exitCode == 0) return true;
        } catch (_) {}
      } else if (Platform.isMacOS) {
        final escaped = tmpPath.replaceAll('"', '\\"');
        final osa = await Process.run('osascript', <String>[
          '-e',
          'set the clipboard to (read (POSIX file "$escaped") as «class PNGf»)',
        ]);
        if (osa.exitCode == 0) return true;
      }
    } catch (_) {
    } finally {
      if (tmpFile != null) {
        unawaited(tmpFile.delete().catchError((_) => tmpFile!));
      }
    }
    return false;
  }

  /// Resolve the user's real OS Downloads folder (respecting Windows `FOLDERID_Downloads` on D:/E: drives)
  static Future<Directory> resolveDownloadsDirectory() async {
    final sep = Platform.pathSeparator;
    final candidates = <String>[
      if (Platform.isWindows)
        Win32NativeBridge.getWindowsKnownDownloadsPath() ?? '',
      if ((Platform.environment['USERPROFILE'] ?? '').isNotEmpty)
        '${Platform.environment['USERPROFILE']}${sep}Downloads',
      if ((Platform.environment['HOME'] ?? '').isNotEmpty)
        '${Platform.environment['HOME']}${sep}Downloads',
      if (Platform.isAndroid) '/storage/emulated/0/Download',
      if (Platform.isAndroid) '/sdcard/Download',
      if ((Platform.environment['USERPROFILE'] ?? '').isNotEmpty)
        '${Platform.environment['USERPROFILE']}${sep}Desktop',
      if ((Platform.environment['HOME'] ?? '').isNotEmpty)
        '${Platform.environment['HOME']}${sep}Desktop',
    ];
    for (final raw in candidates) {
      final path = raw.trim();
      if (path.isEmpty) continue;
      final dir = Directory(path);
      if (await dir.exists()) {
        return dir;
      }
    }
    return Directory.systemTemp;
  }

  /// Save image bytes directly to the user's OS Downloads directory with browser-style collision numbering
  static Future<String> saveImageToDisk({
    required Uint8List bytes,
    required String label,
    String ext = 'png',
  }) async {
    final dir = await resolveDownloadsDirectory();
    final sep = Platform.pathSeparator;
    final stem = _sanitizeName(label);
    var candidate = File('${dir.path}$sep$stem.$ext');
    var suffix = 1;
    while (await candidate.exists() && suffix < 999) {
      candidate = File('${dir.path}$sep$stem ($suffix).$ext');
      suffix++;
    }
    await candidate.writeAsBytes(bytes, flush: true);
    return candidate.path;
  }

  /// Open native Save-As file dialog on Windows (or fall back to Downloads directory on other platforms)
  static Future<String?> saveImageWithNativeDialog({
    required Uint8List bytes,
    required String label,
    String ext = 'png',
  }) async {
    final stem = _sanitizeName(label);
    if (Platform.isWindows) {
      final dlDir = await resolveDownloadsDirectory();
      final chosen = Win32NativeBridge.showWindowsSaveFileDialog(
        suggestedFileName: '$stem.$ext',
        initialDirectory: dlDir.path,
      );
      if (chosen == null || chosen.isEmpty) {
        return null; // User cancelled dialog
      }
      final outPath =
          chosen.toLowerCase().endsWith('.$ext') ? chosen : '$chosen.$ext';
      final f = File(outPath);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    }
    return saveImageToDisk(bytes: bytes, label: label, ext: ext);
  }

  static void showSavedSnackBar(BuildContext context, String savedPath) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF131416),
        content: Text(
          '图片已保存至：$savedPath',
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
        action: SnackBarAction(
          label: '在文件夹中显示',
          textColor: const Color(0xFF5CE1E6),
          onPressed: () {
            Win32NativeBridge.revealInFileManager(savedPath);
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  static Future<void> showImageContextMenu({
    required BuildContext context,
    required Offset globalPosition,
    required Uint8List rawBytes,
    required String label,
    ui.Image? decodedImage,
    PageOverlayData? overlay,
    bool showOverlay = true,
    String? highlightedQuestionName,
    VoidCallback? onOpenLightbox,
  }) async {
    final hasOverlay = overlay != null;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE8EAEC)),
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'copy_current',
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.copy_all_outlined,
                  size: 16, color: Color(0xFF131416)),
              const SizedBox(width: 8),
              Text(
                hasOverlay && showOverlay ? '复制图片（含红笔批改层）' : '复制图片到剪贴板',
                style: const TextStyle(fontSize: 12, color: Color(0xFF131416)),
              ),
            ],
          ),
        ),
        if (hasOverlay && showOverlay)
          const PopupMenuItem<String>(
            value: 'copy_raw',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.image_outlined, size: 16, color: Color(0xFF5D5F60)),
                SizedBox(width: 8),
                Text(
                  '复制纯原图（不含批改框）',
                  style: TextStyle(fontSize: 12, color: Color(0xFF131416)),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
          value: 'download_current',
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.download_outlined,
                  size: 16, color: Color(0xFF1B6C80)),
              const SizedBox(width: 8),
              Text(
                hasOverlay && showOverlay
                    ? '保存至下载目录（含批改层 .png）'
                    : '保存图片至下载目录 (.png)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1B6C80),
                ),
              ),
            ],
          ),
        ),
        if (hasOverlay && showOverlay)
          const PopupMenuItem<String>(
            value: 'download_raw',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.file_download_outlined,
                    size: 16, color: Color(0xFF5D5F60)),
                SizedBox(width: 8),
                Text(
                  '保存纯原图至下载目录 (.png)',
                  style: TextStyle(fontSize: 12, color: Color(0xFF131416)),
                ),
              ],
            ),
          ),
        if (Platform.isWindows)
          const PopupMenuItem<String>(
            value: 'save_as_dialog',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.folder_open_outlined,
                    size: 16, color: Color(0xFF131416)),
                SizedBox(width: 8),
                Text(
                  '图片另存为… (选择文件夹)',
                  style: TextStyle(fontSize: 12, color: Color(0xFF131416)),
                ),
              ],
            ),
          ),
        if (onOpenLightbox != null) ...[
          const PopupMenuDivider(height: 6),
          const PopupMenuItem<String>(
            value: 'lightbox',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.zoom_out_map, size: 16, color: Color(0xFF131416)),
                SizedBox(width: 8),
                Text(
                  '全屏无损放大阅卷 (支持 ←/→ 切图)',
                  style: TextStyle(fontSize: 12, color: Color(0xFF131416)),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (selected == null || !context.mounted) return;
    if (selected == 'lightbox') {
      onOpenLightbox?.call();
      return;
    }

    try {
      final includeOv = (selected == 'copy_current' ||
              selected == 'download_current' ||
              selected == 'save_as_dialog') &&
          showOverlay;

      if (selected.startsWith('copy_')) {
        final ok = await copyImageFastToClipboard(
          rawBytes: rawBytes,
          decodedImage: decodedImage,
          overlay: overlay,
          includeOverlay: includeOv,
          highlightedQuestionName: highlightedQuestionName,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF131416),
            content: Text(
              ok ? '图片已复制到系统剪贴板' : '复制图片到剪贴板失败',
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      final pngBytes = await encodeCompositePng(
        rawBytes: rawBytes,
        decodedImage: decodedImage,
        overlay: overlay,
        includeOverlay: includeOv,
        highlightedQuestionName: highlightedQuestionName,
      );
      if (selected == 'save_as_dialog') {
        final path = await saveImageWithNativeDialog(
          bytes: pngBytes,
          label: label,
          ext: 'png',
        );
        if (path != null && context.mounted) {
          showSavedSnackBar(context, path);
        }
      } else {
        final path = await saveImageToDisk(
          bytes: pngBytes,
          label: label,
          ext: 'png',
        );
        if (context.mounted) {
          showSavedSnackBar(context, path);
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFC4242A),
          content: Text(
            '操作失败：$e',
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
      );
    }
  }
}

class AnswerSheetCanvas extends StatefulWidget {
  final HfsUpstreamClient client;
  final String imageUrl;
  final String caption;
  final PageOverlayData? overlay;
  final bool showOverlay;
  final double zoomScale;
  final ValueChanged<double>? onZoomChanged;
  final String? highlightedQuestionName;
  final VoidCallback? onOpenLightbox;

  const AnswerSheetCanvas({
    super.key,
    required this.client,
    required this.imageUrl,
    this.caption = '好分数答题卡',
    this.overlay,
    this.showOverlay = true,
    this.zoomScale = 1.0,
    this.onZoomChanged,
    this.highlightedQuestionName,
    this.onOpenLightbox,
  });

  @override
  State<AnswerSheetCanvas> createState() => _AnswerSheetCanvasState();
}

class _AnswerSheetCanvasState extends State<AnswerSheetCanvas> {
  ui.Image? _decodedImage;
  Uint8List? _imageBytes;
  String? _error;
  bool _loading = true;
  int _loadEpoch = 0;
  double _basePinchZoom = 1.0;
  double _baseScrollOffsetX = 0.0;
  Offset _baseLocalFocal = Offset.zero;
  bool _isTrackpadPinching = false;
  final ScrollController _hScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _hScrollCtrl.dispose();
    _decodedImage?.dispose();
    _decodedImage = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AnswerSheetCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final epoch = ++_loadEpoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.client.fetchOssImageBytes(widget.imageUrl);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || epoch != _loadEpoch) {
        frame.image.dispose();
        return;
      }
      final prevImg = _decodedImage;
      setState(() {
        _imageBytes = bytes;
        _decodedImage = frame.image;
        _loading = false;
      });
      prevImg?.dispose();
    } catch (e) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _applyFocalHorizontalScroll({
    required double focalX,
    required double oldScrollX,
    required double ratio,
    double extraPanX = 0.0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hScrollCtrl.hasClients) return;
      final maxX = _hScrollCtrl.position.maxScrollExtent;
      if (maxX > 0) {
        final newScrollX = (focalX * ratio) - (focalX - oldScrollX) - extraPanX;
        _hScrollCtrl.jumpTo(newScrollX.clamp(0.0, maxX));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 280,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF1B6C80),
                ),
              ),
              SizedBox(height: 10),
              Text(
                '正在加载高清扫描件…',
                style: TextStyle(fontSize: 12, color: Color(0xFF5D5F60)),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null || _decodedImage == null || _imageBytes == null) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              size: 32,
              color: Color(0xFFC4242A),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '图片加载失败',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFFC4242A)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loadImage,
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final img = _decodedImage!;
    final aspect = img.width / math.max(1, img.height);
    final zoom = widget.zoomScale.clamp(0.5, 3.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : img.width.toDouble();
        final displayW = maxW * zoom;
        final displayH = displayW / aspect;

        Widget stage = SizedBox(
          width: displayW,
          height: displayH,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                _imageBytes!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
              if (widget.showOverlay && widget.overlay != null)
                CustomPaint(
                  painter: _GradingOverlayPainter(
                    imageSize: Size(
                      img.width.toDouble(),
                      img.height.toDouble(),
                    ),
                    overlay: widget.overlay!,
                    highlightedQuestionName: widget.highlightedQuestionName,
                  ),
                ),
            ],
          ),
        );

        stage = MouseRegion(
          cursor: widget.onOpenLightbox != null
              ? SystemMouseCursors.zoomIn
              : MouseCursor.defer,
          child: GestureDetector(
            supportedDevices: const <PointerDeviceKind>{
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
            },
            onTap: widget.onOpenLightbox,
            onSecondaryTapDown: (details) {
              if (_imageBytes == null) return;
              HfsImageClipboardAndExporter.showImageContextMenu(
                context: context,
                globalPosition: details.globalPosition,
                rawBytes: _imageBytes!,
                label: widget.caption,
                decodedImage: _decodedImage,
                overlay: widget.overlay,
                showOverlay: widget.showOverlay,
                highlightedQuestionName: widget.highlightedQuestionName,
                onOpenLightbox: widget.onOpenLightbox,
              );
            },
            onLongPressStart: (details) {
              if (_imageBytes == null) return;
              HfsImageClipboardAndExporter.showImageContextMenu(
                context: context,
                globalPosition: details.globalPosition,
                rawBytes: _imageBytes!,
                label: widget.caption,
                decodedImage: _decodedImage,
                overlay: widget.overlay,
                showOverlay: widget.showOverlay,
                highlightedQuestionName: widget.highlightedQuestionName,
                onOpenLightbox: widget.onOpenLightbox,
              );
            },
            child: Listener(
              onPointerPanZoomStart: (event) {
                _basePinchZoom = widget.zoomScale.clamp(0.6, 2.5);
                _baseLocalFocal = event.localPosition;
                _baseScrollOffsetX =
                    _hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0;
                _isTrackpadPinching = false;
              },
              onPointerPanZoomUpdate: (event) {
                if ((event.scale - 1.0).abs() > 0.022) {
                  _isTrackpadPinching = true;
                }
                if (_isTrackpadPinching && widget.onZoomChanged != null) {
                  final targetZoom =
                      (_basePinchZoom * event.scale).clamp(0.6, 2.5);
                  final ratio = targetZoom / _basePinchZoom;
                  widget.onZoomChanged!(targetZoom);
                  _applyFocalHorizontalScroll(
                    focalX: _baseLocalFocal.dx,
                    oldScrollX: _baseScrollOffsetX,
                    ratio: ratio,
                    extraPanX: event.localPan.dx,
                  );
                }
              },
              onPointerPanZoomEnd: (_) {
                _isTrackpadPinching = false;
              },
              onPointerSignal: (event) {
                if (widget.onZoomChanged == null) return;
                if (event is PointerScaleEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (resolved) {
                      if (resolved is PointerScaleEvent) {
                        final oldZ = widget.zoomScale.clamp(0.6, 2.5);
                        final newZ = (oldZ * resolved.scale).clamp(0.6, 2.5);
                        final ratio = newZ / oldZ;
                        final oldX =
                            _hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0;
                        widget.onZoomChanged!(newZ);
                        _applyFocalHorizontalScroll(
                          focalX: resolved.localPosition.dx,
                          oldScrollX: oldX,
                          ratio: ratio,
                        );
                      }
                    },
                  );
                } else if (event is PointerScrollEvent) {
                  final pressed =
                      HardwareKeyboard.instance.logicalKeysPressed;
                  final isCtrlOrMeta =
                      pressed.contains(LogicalKeyboardKey.controlLeft) ||
                      pressed.contains(LogicalKeyboardKey.controlRight) ||
                      pressed.contains(LogicalKeyboardKey.metaLeft) ||
                      pressed.contains(LogicalKeyboardKey.metaRight);
                  if (isCtrlOrMeta && event.scrollDelta.dy != 0) {
                    GestureBinding.instance.pointerSignalResolver.register(
                      event,
                      (resolved) {
                        if (resolved is PointerScrollEvent) {
                          final factor = math
                              .exp(-resolved.scrollDelta.dy / 280.0)
                              .clamp(0.75, 1.35);
                          final oldZ = widget.zoomScale.clamp(0.6, 2.5);
                          final newZ = (oldZ * factor).clamp(0.6, 2.5);
                          final ratio = newZ / oldZ;
                          final oldX = _hScrollCtrl.hasClients
                              ? _hScrollCtrl.offset
                              : 0.0;
                          widget.onZoomChanged!(newZ);
                          _applyFocalHorizontalScroll(
                            focalX: resolved.localPosition.dx,
                            oldScrollX: oldX,
                            ratio: ratio,
                          );
                        }
                      },
                    );
                  }
                }
              },
              child: stage,
            ),
          ),
        );

        return IsolatedHorizontalScroll(
          controller: _hScrollCtrl,
          convertVerticalWheelToHorizontal: false,
          child: stage,
        );
      },
    );
  }
}

/// Inline oss crop / stem image viewer with click-to-lightbox & gallery navigation
class OssCropImage extends StatefulWidget {
  final HfsUpstreamClient client;
  final String imageUrl;
  final double? maxHeight;
  final String caption;
  final List<LightboxGalleryItem>? galleryItems;
  final int galleryIndex;

  const OssCropImage({
    super.key,
    required this.client,
    required this.imageUrl,
    this.maxHeight,
    this.caption = '原图放大查看',
    this.galleryItems,
    this.galleryIndex = 0,
  });

  @override
  State<OssCropImage> createState() => _OssCropImageState();
}

class _OssCropImageState extends State<OssCropImage> {
  Uint8List? _bytes;
  ui.Image? _decoded;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _decoded?.dispose();
    _decoded = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OssCropImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await widget.client.fetchOssImageBytes(widget.imageUrl);
      final codec = await ui.instantiateImageCodec(b);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      final prev = _decoded;
      setState(() {
        _bytes = b;
        _decoded = frame.image;
        _loading = false;
      });
      prev?.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _openLightbox() {
    showOssImageLightbox(
      context: context,
      client: widget.client,
      imageUrl: widget.imageUrl,
      caption: widget.caption,
      galleryItems: widget.galleryItems,
      initialIndex: widget.galleryIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 76,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6F8),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE8EAEC)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: Color(0xFF1B6C80),
              ),
            ),
            SizedBox(width: 8),
            Text(
              '加载题图…',
              style: TextStyle(fontSize: 12, color: Color(0xFF5D5F60)),
            ),
          ],
        ),
      );
    }
    if (_error != null || _bytes == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEDEA),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 14, color: Color(0xFFC4242A)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _error ?? '题图加载失败',
                style: const TextStyle(fontSize: 12, color: Color(0xFF831C1E)),
              ),
            ),
            TextButton(
              onPressed: _load,
              child: const Text('重试', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    Widget imgWidget = Image.memory(
      _bytes!,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      gaplessPlayback: true,
    );
    if (widget.maxHeight != null) {
      imgWidget = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight!),
        child: imgWidget,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.zoomIn,
      child: GestureDetector(
        onTap: _openLightbox,
        onSecondaryTapDown: (details) {
          if (_bytes == null) return;
          HfsImageClipboardAndExporter.showImageContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            rawBytes: _bytes!,
            decodedImage: _decoded,
            label: widget.caption,
            onOpenLightbox: _openLightbox,
          );
        },
        onLongPressStart: (details) {
          if (_bytes == null) return;
          HfsImageClipboardAndExporter.showImageContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            rawBytes: _bytes!,
            decodedImage: _decoded,
            label: widget.caption,
            onOpenLightbox: _openLightbox,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE8EAEC)),
          ),
          child: imgWidget,
        ),
      ),
    );
  }
}

/// Fullscreen interactive Lightbox dialog supporting:
/// - Trackpad 2-finger pan (`PointerPanZoomUpdateEvent.localPanDelta`) & focal-anchored pinch zoom (`event.scale`) with zero drift
/// - Keyboard `←` / `→` / `PageUp` / `PageDown` / `A` / `D` image switching across `galleryItems`
/// - Instant `<10ms` Win32 `CF_DIB` clipboard copy (`Ctrl+C`) & Save to Downloads (`Ctrl+S`)
Future<void> showOssImageLightbox({
  required BuildContext context,
  required HfsUpstreamClient client,
  required String imageUrl,
  required String caption,
  PageOverlayData? overlay,
  bool initialShowOverlay = true,
  String? highlightedQuestionName,
  List<LightboxGalleryItem>? galleryItems,
  int initialIndex = 0,
}) {
  final items = (galleryItems != null && galleryItems.isNotEmpty)
      ? galleryItems
      : <LightboxGalleryItem>[
          LightboxGalleryItem(
            imageUrl: imageUrl,
            caption: caption,
            overlay: overlay,
            initialShowOverlay: initialShowOverlay,
            highlightedQuestionName: highlightedQuestionName,
          ),
        ];
  final safeIdx = initialIndex.clamp(0, items.length - 1);
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xF0131416),
    builder: (ctx) => _OssLightboxDialog(
      client: client,
      items: items,
      initialIndex: safeIdx,
    ),
  );
}

class _OssLightboxDialog extends StatefulWidget {
  final HfsUpstreamClient client;
  final List<LightboxGalleryItem> items;
  final int initialIndex;

  const _OssLightboxDialog({
    required this.client,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<_OssLightboxDialog> createState() => _OssLightboxDialogState();
}

class _OssLightboxDialogState extends State<_OssLightboxDialog> {
  late int _currentIndex;
  Size _viewportSize = const Size(1280, 800);
  Size _fittedImageSize = const Size(800, 600);
  ui.Image? _decoded;
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;
  int _loadToken = 0;
  late bool _showOverlay;

  // Deterministic center-relative transform state (replaces buggy InteractiveViewer)
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _panZoomBaseScale = 1.0;
  double _touchPinchBaseScale = 1.0;
  Offset _touchLastFocal = Offset.zero;

  LightboxGalleryItem get _currentItem => widget.items[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _showOverlay = _currentItem.initialShowOverlay;
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _loadCurrentImage();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _decoded?.dispose();
    _decoded = null;
    super.dispose();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final key = event.logicalKey;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final isCtrlOrMeta = pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);

    if (isCtrlOrMeta) {
      if (key == LogicalKeyboardKey.keyC && _bytes != null) {
        _copyCurrentToClipboard();
        return true;
      }
      if (key == LogicalKeyboardKey.keyS && _bytes != null) {
        _saveCurrentToDownloads();
        return true;
      }
      return false;
    }

    // Left / PageUp / A -> Previous image
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.keyA ||
        key == LogicalKeyboardKey.bracketLeft) {
      if (widget.items.length > 1) {
        _switchGalleryIndex(_currentIndex - 1);
        return true;
      }
    }

    // Right / PageDown / D / Space -> Next image
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.keyD ||
        key == LogicalKeyboardKey.bracketRight ||
        key == LogicalKeyboardKey.space) {
      if (widget.items.length > 1) {
        _switchGalleryIndex(_currentIndex + 1);
        return true;
      }
    }

    // Up / Down: pan if zoomed in, otherwise switch image!
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_scale > 1.05) {
        setState(() {
          _offset = _clampOffset(_offset + const Offset(0, 72), _scale);
        });
        return true;
      } else if (widget.items.length > 1) {
        _switchGalleryIndex(_currentIndex - 1);
        return true;
      }
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_scale > 1.05) {
        setState(() {
          _offset = _clampOffset(_offset + const Offset(0, -72), _scale);
        });
        return true;
      } else if (widget.items.length > 1) {
        _switchGalleryIndex(_currentIndex + 1);
        return true;
      }
    }

    // + / = -> Zoom in
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _setScale(_scale * 1.25);
      return true;
    }
    // - -> Zoom out
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _setScale(_scale / 1.25);
      return true;
    }
    // 0 -> Reset zoom
    if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      _resetTransform();
      return true;
    }

    return false;
  }

  void _switchGalleryIndex(int newIdx) {
    if (widget.items.length <= 1) return;
    final wrapped = (newIdx % widget.items.length + widget.items.length) %
        widget.items.length;
    if (wrapped == _currentIndex) return;
    setState(() {
      _currentIndex = wrapped;
      _scale = 1.0;
      _offset = Offset.zero;
    });
    _loadCurrentImage();
  }

  void _resetTransform() {
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  Offset _clampOffset(Offset candidate, double scale) {
    final scaledW = _fittedImageSize.width * scale;
    final scaledH = _fittedImageSize.height * scale;
    final maxPanX =
        math.max(_viewportSize.width * 0.35, (scaledW - _viewportSize.width) / 2.0 + 140.0);
    final maxPanY =
        math.max(_viewportSize.height * 0.35, (scaledH - _viewportSize.height) / 2.0 + 140.0);
    return Offset(
      candidate.dx.clamp(-maxPanX, maxPanX),
      candidate.dy.clamp(-maxPanY, maxPanY),
    );
  }

  /// Zoom smoothly around [focalPoint] (in viewport coordinates) with zero drift!
  void _setScale(double target, {Offset? focalPoint}) {
    final newScale = target.clamp(0.4, 6.0);
    if ((newScale - 1.0).abs() < 0.02 && focalPoint == null) {
      _resetTransform();
      return;
    }
    final oldScale = _scale;
    final center = Offset(_viewportSize.width / 2.0, _viewportSize.height / 2.0);
    final anchor = focalPoint ?? center;
    final ratio = newScale / math.max(0.1, oldScale);
    // Exact center-relative focal-point invariance:
    // newOffset = (anchor - center) - (anchor - center - oldOffset) * (newScale / oldScale)
    final relAnchor = anchor - center;
    final rawNewOffset = relAnchor - (relAnchor - _offset) * ratio;
    setState(() {
      _scale = newScale;
      _offset = _clampOffset(rawNewOffset, newScale);
    });
  }

  Future<void> _loadCurrentImage() async {
    final token = ++_loadToken;
    final item = _currentItem;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await widget.client.fetchOssImageBytes(item.imageUrl);
      final codec = await ui.instantiateImageCodec(b);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || token != _loadToken) {
        frame.image.dispose();
        return;
      }
      final prev = _decoded;
      setState(() {
        _bytes = b;
        _decoded = frame.image;
        _loading = false;
      });
      prev?.dispose();

      // Preload adjacent gallery images in background for instant keyboard switching
      if (widget.items.length > 1) {
        final nextIdx = (_currentIndex + 1) % widget.items.length;
        unawaited(
          widget.client
              .fetchOssImageBytes(widget.items[nextIdx].imageUrl)
              .catchError((_) => Uint8List(0)),
        );
      }
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _copyCurrentToClipboard() async {
    if (_bytes == null) return;
    final item = _currentItem;
    final ok = await HfsImageClipboardAndExporter.copyImageFastToClipboard(
      rawBytes: _bytes!,
      decodedImage: _decoded,
      overlay: item.overlay,
      includeOverlay: _showOverlay,
      highlightedQuestionName: item.highlightedQuestionName,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF131416),
        content: Text(
          ok ? '图片已复制到系统剪贴板' : '复制图片失败',
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveCurrentToDownloads({bool useSaveAsDialog = false}) async {
    if (_bytes == null) return;
    final item = _currentItem;
    final png = await HfsImageClipboardAndExporter.encodeCompositePng(
      rawBytes: _bytes!,
      decodedImage: _decoded,
      overlay: item.overlay,
      includeOverlay: _showOverlay,
      highlightedQuestionName: item.highlightedQuestionName,
    );
    final saved = useSaveAsDialog
        ? await HfsImageClipboardAndExporter.saveImageWithNativeDialog(
            bytes: png,
            label: item.caption,
          )
        : await HfsImageClipboardAndExporter.saveImageToDisk(
            bytes: png,
            label: item.caption,
          );
    if (saved != null && mounted) {
      HfsImageClipboardAndExporter.showSavedSnackBar(context, saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _currentItem;
    final totalCount = widget.items.length;
    final screenW = MediaQuery.of(context).size.width;
    final isCompactMobile = screenW < 640;

    return Dialog.fullscreen(
      backgroundColor: const Color(0xF2131416),
      child: SafeArea(
        child: Column(
          children: [
            // Top Toolbar
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompactMobile ? 8 : 16,
                vertical: isCompactMobile ? 4 : 6,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF131416),
                border: Border(bottom: BorderSide(color: Color(0xFF2E3033))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (totalCount > 1) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B6C80),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${_currentIndex + 1}/$totalCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [ui.FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (!isCompactMobile) ...[
                          IconButton(
                            tooltip: '上一张 (键盘 ← / PageUp)',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                _switchGalleryIndex(_currentIndex - 1),
                            icon: const Icon(Icons.chevron_left,
                                color: Colors.white, size: 22),
                          ),
                          IconButton(
                            tooltip: '下一张 (键盘 → / PageDown)',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                _switchGalleryIndex(_currentIndex + 1),
                            icon: const Icon(Icons.chevron_right,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ],
                      Expanded(
                        child: Text(
                          item.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isCompactMobile ? 12.5 : 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!isCompactMobile) ...[
                        if (item.overlay != null) ...[
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _showOverlay = !_showOverlay),
                            icon: Icon(
                              _showOverlay
                                  ? Icons.layers_outlined
                                  : Icons.layers_clear_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                            label: Text(
                              _showOverlay ? '隐藏批改层' : '显示批改层',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (_bytes != null) ...[
                          TextButton.icon(
                            onPressed: _copyCurrentToClipboard,
                            icon: const Icon(Icons.copy,
                                size: 15, color: Colors.white),
                            label: const Text(
                              '复制图片 (Ctrl+C)',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _saveCurrentToDownloads(useSaveAsDialog: false),
                            icon: const Icon(Icons.download_outlined,
                                size: 16, color: Colors.white),
                            label: const Text(
                              '保存至下载 (Ctrl+S)',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                          if (Platform.isWindows)
                            TextButton.icon(
                              onPressed: () => _saveCurrentToDownloads(
                                  useSaveAsDialog: true),
                              icon: const Icon(Icons.folder_open_outlined,
                                  size: 15, color: Colors.white70),
                              label: const Text(
                                '另存为…',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          const SizedBox(width: 4),
                        ],
                        IconButton(
                          tooltip: '缩小 (-)',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _setScale(_scale / 1.25),
                          icon: const Icon(Icons.remove,
                              color: Colors.white, size: 18),
                        ),
                        InkWell(
                          onTap: _resetTransform,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Text(
                              '${(_scale * 100).round()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [ui.FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '放大 (+)',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _setScale(_scale * 1.25),
                          icon: const Icon(Icons.add,
                              color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        tooltip: '关闭 (Esc)',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                  if (isCompactMobile)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: IsolatedHorizontalScroll(
                        child: Row(
                          children: [
                            if (totalCount > 1) ...[
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onPressed: () =>
                                    _switchGalleryIndex(_currentIndex - 1),
                                icon: const Icon(Icons.chevron_left,
                                    size: 16, color: Colors.white),
                                label: const Text('上一张',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 11.5)),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onPressed: () =>
                                    _switchGalleryIndex(_currentIndex + 1),
                                icon: const Icon(Icons.chevron_right,
                                    size: 16, color: Colors.white),
                                label: const Text('下一张',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 11.5)),
                              ),
                            ],
                            if (item.overlay != null)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onPressed: () => setState(
                                    () => _showOverlay = !_showOverlay),
                                icon: Icon(
                                  _showOverlay
                                      ? Icons.layers_outlined
                                      : Icons.layers_clear_outlined,
                                  size: 15,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  _showOverlay ? '隐藏批改' : '显示批改',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11.5),
                                ),
                              ),
                            if (_bytes != null) ...[
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onPressed: _copyCurrentToClipboard,
                                icon: const Icon(Icons.copy,
                                    size: 14, color: Colors.white),
                                label: const Text('复制',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 11.5)),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onPressed: () => _saveCurrentToDownloads(
                                    useSaveAsDialog: false),
                                icon: const Icon(Icons.download_outlined,
                                    size: 15, color: Colors.white),
                                label: const Text('保存图片',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 11.5)),
                              ),
                            ],
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                  minWidth: 30, minHeight: 30),
                              padding: EdgeInsets.zero,
                              onPressed: () => _setScale(_scale / 1.25),
                              icon: const Icon(Icons.remove,
                                  color: Colors.white, size: 16),
                            ),
                            InkWell(
                              onTap: _resetTransform,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  '${(_scale * 100).round()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                  minWidth: 30, minHeight: 30),
                              padding: EdgeInsets.zero,
                              onPressed: () => _setScale(_scale * 1.25),
                              icon: const Icon(Icons.add,
                                  color: Colors.white, size: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Main Interactive Stage
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : (_error != null || _decoded == null || _bytes == null)
                    ? Center(
                        child: Text(
                          _error ?? '加载失败',
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (ctx, box) {
                          _viewportSize = Size(box.maxWidth, box.maxHeight);
                          final img = _decoded!;
                          final aspect =
                              img.width / math.max(1.0, img.height.toDouble());
                          final availW = math.max(120.0, box.maxWidth - 48.0);
                          final availH = math.max(120.0, box.maxHeight - 36.0);
                          double fitW = availW;
                          double fitH = fitW / aspect;
                          if (fitH > availH) {
                            fitH = availH;
                            fitW = fitH * aspect;
                          }
                          _fittedImageSize = Size(fitW, fitH);

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerPanZoomStart: (event) {
                                  _panZoomBaseScale = _scale;
                                },
                                onPointerPanZoomUpdate: (event) {
                                  // 1. Apply 2-finger trackpad pan delta immediately
                                  if (event.localPanDelta != Offset.zero) {
                                    _offset = _clampOffset(
                                      _offset + event.localPanDelta,
                                      _scale,
                                    );
                                  }
                                  // 2. Apply focal-anchored pinch zoom around stationary cursor
                                  if ((event.scale - 1.0).abs() > 0.003) {
                                    _setScale(
                                      _panZoomBaseScale * event.scale,
                                      focalPoint: event.localPosition,
                                    );
                                  } else if (event.localPanDelta !=
                                      Offset.zero) {
                                    setState(() {});
                                  }
                                },
                                onPointerSignal: (event) {
                                  if (event is PointerScaleEvent) {
                                    GestureBinding
                                        .instance.pointerSignalResolver
                                        .register(event, (resolved) {
                                      if (resolved is PointerScaleEvent) {
                                        _setScale(
                                          _scale * resolved.scale,
                                          focalPoint: resolved.localPosition,
                                        );
                                      }
                                    });
                                  } else if (event is PointerScrollEvent) {
                                    GestureBinding
                                        .instance.pointerSignalResolver
                                        .register(event, (resolved) {
                                      if (resolved is PointerScrollEvent) {
                                        final pressed = HardwareKeyboard
                                            .instance.logicalKeysPressed;
                                        final isCtrlOrMeta = pressed.contains(
                                              LogicalKeyboardKey.controlLeft,
                                            ) ||
                                            pressed.contains(
                                              LogicalKeyboardKey.controlRight,
                                            ) ||
                                            pressed.contains(
                                              LogicalKeyboardKey.metaLeft,
                                            ) ||
                                            pressed.contains(
                                              LogicalKeyboardKey.metaRight,
                                            );
                                        if (resolved.kind ==
                                                PointerDeviceKind.trackpad &&
                                            !isCtrlOrMeta) {
                                          // Legacy trackpad scroll -> 2D pan
                                          setState(() {
                                            _offset = _clampOffset(
                                              _offset - resolved.scrollDelta,
                                              _scale,
                                            );
                                          });
                                        } else if (resolved.scrollDelta.dy !=
                                            0) {
                                          final factor = math
                                              .exp(
                                                -resolved.scrollDelta.dy /
                                                    260.0,
                                              )
                                              .clamp(0.75, 1.35);
                                          _setScale(
                                            _scale * factor,
                                            focalPoint: resolved.localPosition,
                                          );
                                        }
                                      }
                                    });
                                  }
                                },
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  supportedDevices: const <PointerDeviceKind>{
                                    PointerDeviceKind.touch,
                                    PointerDeviceKind.mouse,
                                    PointerDeviceKind.stylus,
                                  },
                                  onDoubleTapDown: (details) {
                                    if (_scale > 1.25) {
                                      _resetTransform();
                                    } else {
                                      _setScale(
                                        2.2,
                                        focalPoint: details.localPosition,
                                      );
                                    }
                                  },
                                  onSecondaryTapDown: (details) {
                                    if (_bytes == null) return;
                                    HfsImageClipboardAndExporter
                                        .showImageContextMenu(
                                      context: context,
                                      globalPosition: details.globalPosition,
                                      rawBytes: _bytes!,
                                      label: item.caption,
                                      decodedImage: _decoded,
                                      overlay: item.overlay,
                                      showOverlay: _showOverlay,
                                      highlightedQuestionName:
                                          item.highlightedQuestionName,
                                    );
                                  },
                                  onScaleStart: (details) {
                                    _touchPinchBaseScale = _scale;
                                    _touchLastFocal = details.localFocalPoint;
                                  },
                                  onScaleUpdate: (details) {
                                    final delta =
                                        details.localFocalPoint - _touchLastFocal;
                                    _touchLastFocal = details.localFocalPoint;
                                    if (delta != Offset.zero) {
                                      _offset = _clampOffset(
                                        _offset + delta,
                                        _scale,
                                      );
                                    }
                                    if ((details.scale - 1.0).abs() > 0.01) {
                                      _setScale(
                                        _touchPinchBaseScale * details.scale,
                                        focalPoint: details.localFocalPoint,
                                      );
                                    } else if (delta != Offset.zero) {
                                      setState(() {});
                                    }
                                  },
                                  child: ClipRect(
                                    child: Center(
                                      child: Transform.translate(
                                        offset: _offset,
                                        child: Transform.scale(
                                          scale: _scale,
                                          alignment: Alignment.center,
                                          child: Container(
                                            width: fitW,
                                            height: fitH,
                                            color: Colors.white,
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                Image.memory(
                                                  _bytes!,
                                                  fit: BoxFit.contain,
                                                  gaplessPlayback: true,
                                                ),
                                                if (_showOverlay &&
                                                    item.overlay != null)
                                                  CustomPaint(
                                                    painter:
                                                        _GradingOverlayPainter(
                                                      imageSize: Size(
                                                        img.width.toDouble(),
                                                        img.height.toDouble(),
                                                      ),
                                                      overlay: item.overlay!,
                                                      highlightedQuestionName:
                                                          item.highlightedQuestionName,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Floating Left / Right Gallery Navigation Arrows
                              if (totalCount > 1) ...[
                                Positioned(
                                  left: 16,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: Material(
                                      color: const Color(0xB8131416),
                                      shape: const CircleBorder(
                                        side: BorderSide(
                                          color: Color(0xFF3E4044),
                                        ),
                                      ),
                                      child: IconButton(
                                        tooltip: '上一张 (←)',
                                        onPressed: () => _switchGalleryIndex(
                                            _currentIndex - 1),
                                        icon: const Icon(
                                          Icons.chevron_left,
                                          color: Colors.white,
                                          size: 26,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 16,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: Material(
                                      color: const Color(0xB8131416),
                                      shape: const CircleBorder(
                                        side: BorderSide(
                                          color: Color(0xFF3E4044),
                                        ),
                                      ),
                                      child: IconButton(
                                        tooltip: '下一张 (→)',
                                        onPressed: () => _switchGalleryIndex(
                                            _currentIndex + 1),
                                        icon: const Icon(
                                          Icons.chevron_right,
                                          color: Colors.white,
                                          size: 26,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradingOverlayPainter extends CustomPainter {
  final Size imageSize;
  final PageOverlayData overlay;
  final String? highlightedQuestionName;

  const _GradingOverlayPainter({
    required this.imageSize,
    required this.overlay,
    this.highlightedQuestionName,
  });

  static const Color _green = Color(0xFF1E7B4F);
  static const Color _red = Color(0xFFC4242A);
  static const Color _amber = Color(0xFFA86F0C);
  static const Color _teal = Color(0xFF1B6C80);

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return;
    final sx = size.width / imageSize.width;
    final sy = size.height / imageSize.height;

    // 1. Objective choices
    for (final obj in overlay.objectives) {
      final isHighlighted = highlightedQuestionName != null &&
          obj.qName == highlightedQuestionName;
      final rect = Rect.fromLTWH(
        obj.x * sx,
        obj.y * sy,
        math.max(18 * sx, obj.w * sx),
        math.max(14 * sy, obj.h * sy),
      );
      if (isHighlighted) {
        canvas.drawRect(
          rect.inflate(4 * sx),
          Paint()
            ..color = _teal.withValues(alpha: 0.25)
            ..style = PaintingStyle.fill,
        );
      }
      if (obj.isRight) {
        final stroke = Paint()
          ..color = _green.withValues(alpha: 0.88)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, 2.0 * sx);
        canvas.drawRect(rect, stroke);
      } else {
        final fill = Paint()
          ..color = _red.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill;
        final stroke = Paint()
          ..color = _red.withValues(alpha: 0.94)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.6, 2.4 * sx);
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, stroke);

        if (obj.stdAnswer.isNotEmpty) {
          _drawText(
            canvas,
            '✓${obj.stdAnswer}',
            Offset(rect.right + 3 * sx, rect.top - 1 * sy),
            color: _red,
            fontSize: math.max(9.5, 16 * sx),
            fontWeight: FontWeight.w700,
          );
        }
      }
    }

    // 2. Subjective blocks & teacher remarks
    for (final blk in overlay.blocks) {
      final bx = blk.x * sx;
      final by = blk.y * sy;
      final bw = blk.w * sx;
      final bh = blk.h * sy;
      final isFull =
          blk.manfen > 0 && (blk.score - blk.manfen).abs() < 0.01;
      final isZero = blk.score <= 0.001;
      final isHighlighted = highlightedQuestionName != null &&
          blk.qNames.contains(highlightedQuestionName);
      final color = isHighlighted
          ? _teal
          : (isFull ? _green : (isZero ? _red : _amber));

      final rect = Rect.fromLTWH(bx, by, bw, bh);
      if (isHighlighted) {
        canvas.drawRect(
          rect,
          Paint()
            ..color = _teal.withValues(alpha: 0.08)
            ..style = PaintingStyle.fill,
        );
      }
      final borderPaint = Paint()
        ..color = color.withValues(alpha: isHighlighted ? 0.95 : 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(isHighlighted ? 2.2 : 1.2, 2.0 * sx);
      canvas.drawRect(rect, borderPaint);

      final qLabel = blk.qNames.join('/');
      final detail = blk.itemScores.length > 1
          ? ' (${blk.itemScores.join('+')})'
          : '';
      final badgeText =
          '第$qLabel题: +${round2(blk.score)} / ${round2(blk.manfen)}分$detail';

      final tp = _layoutText(
        badgeText,
        color: Colors.white,
        fontSize: math.max(10.0, 20.0 * sx),
        fontWeight: FontWeight.w700,
      );
      final padX = math.max(5.0, 10.0 * sx);
      final padY = math.max(2.5, 5.0 * sy);
      final boxW = tp.width + padX * 2;
      final boxH = tp.height + padY * 2;
      final badgeTop = math.max(2.0, by - boxH - 2 * sy);
      final badgeLeft = math.min(size.width - boxW - 2, math.max(2.0, bx));

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(badgeLeft, badgeTop, boxW, boxH),
        Radius.circular(math.max(3.0, 5.0 * sx)),
      );
      canvas.drawRRect(
        rrect,
        Paint()..color = color.withValues(alpha: 0.94),
      );
      tp.paint(canvas, Offset(badgeLeft + padX, badgeTop + padY));

      if (blk.drawScore) {
        final stampX = math.min(
          size.width - 70 * sx,
          bx + math.min(bw * 0.72, bw - 80 * sx),
        );
        final stampY = by + math.min(36 * sy, bh * 0.25);
        _drawText(
          canvas,
          '+${round2(blk.score)}',
          Offset(stampX, stampY),
          color: _red.withValues(alpha: 0.85),
          fontSize: math.max(15.0, 44.0 * sx),
          fontWeight: FontWeight.w700,
        );
      }

      for (final rm in blk.remarks) {
        final rx = (blk.x + rm.x) * sx;
        final ry = (blk.y + rm.y) * sy;
        final rw = math.max(20.0 * sx, rm.w * sx);
        final rh = math.max(16.0 * sy, rm.h * sy);
        _drawRemarkMark(canvas, rm.type, rx, ry, rw, rh, rm.content, sx);
      }
    }
  }

  void _drawRemarkMark(
    Canvas canvas,
    int type,
    double x,
    double y,
    double w,
    double h,
    String content,
    double sx,
  ) {
    final stroke = Paint()
      ..color = _red.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, 3.6 * sx)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (type == 1 || type == 2) {
      final p = Path()
        ..moveTo(x, y + h * 0.55)
        ..lineTo(x + w * 0.38, y + h * 0.9)
        ..lineTo(x + w, y + h * 0.12);
      canvas.drawPath(p, stroke);
      if (type == 2) {
        final p2 = Path()
          ..moveTo(x + w * 0.52, y + h * 0.18)
          ..lineTo(x + w * 0.88, y + h * 0.78);
        canvas.drawPath(p2, stroke);
      }
    } else if (type == 3) {
      final p = Path()
        ..moveTo(x, y)
        ..lineTo(x + w, y + h)
        ..moveTo(x + w, y)
        ..lineTo(x, y + h);
      canvas.drawPath(p, stroke);
    } else if (content.isNotEmpty) {
      _drawText(
        canvas,
        content,
        Offset(x, y),
        color: _red.withValues(alpha: 0.9),
        fontSize: math.max(11.0, 24.0 * sx),
        fontWeight: FontWeight.w700,
      );
    }
  }

  TextPainter _layoutText(
    String text, {
    required Color color,
    required double fontSize,
    required FontWeight fontWeight,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'NotoSansSC',
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color color,
    required double fontSize,
    required FontWeight fontWeight,
  }) {
    final tp = _layoutText(
      text,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
    );
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _GradingOverlayPainter oldDelegate) {
    return oldDelegate.imageSize != imageSize ||
        oldDelegate.overlay != overlay ||
        oldDelegate.highlightedQuestionName != highlightedQuestionName;
  }
}

/// Pure Flutter CustomPainter that renders Haofenshu graphical SVG captchas
/// (`<svg width="200" height="80"><path d="M...L...Q...C...Z" fill="#..." stroke="#..."/></svg>`)
class SvgCaptchaView extends StatelessWidget {
  final String svgXml;
  final double width;
  final double height;
  final VoidCallback? onTapRefresh;

  const SvgCaptchaView({
    super.key,
    required this.svgXml,
    this.width = 130,
    this.height = 44,
    this.onTapRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTapRefresh,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6F8),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFCDCED1)),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          size: Size(width, height),
          painter: _SvgCaptchaPainter(svgXml),
        ),
      ),
    );
  }
}

class _SvgCaptchaPainter extends CustomPainter {
  final String svgXml;

  _SvgCaptchaPainter(this.svgXml);

  static final RegExp _pathTagRe =
      RegExp(r'<path\b([^>]*)/?>', caseSensitive: false);
  static final RegExp _attrRe =
      RegExp(r'''([a-zA-Z_-]+)\s*=\s*["']([^"']*)["']''');
  static final RegExp _tokenRe =
      RegExp(r'([MmLlQqCcZzHhVv])|(-?\d+(?:\.\d+)?)');

  @override
  void paint(Canvas canvas, Size size) {
    if (svgXml.isEmpty) return;
    double vbW = 200;
    double vbH = 80;
    final wMatch = RegExp(r'width="(\d+)"').firstMatch(svgXml);
    final hMatch = RegExp(r'height="(\d+)"').firstMatch(svgXml);
    if (wMatch != null) vbW = double.tryParse(wMatch.group(1)!) ?? 200;
    if (hMatch != null) vbH = double.tryParse(hMatch.group(1)!) ?? 80;

    final sx = size.width / math.max(1.0, vbW);
    final sy = size.height / math.max(1.0, vbH);
    canvas.save();
    canvas.scale(sx, sy);

    for (final m in _pathTagRe.allMatches(svgXml)) {
      final attrsRaw = m.group(1) ?? '';
      final attrs = <String, String>{};
      for (final am in _attrRe.allMatches(attrsRaw)) {
        attrs[am.group(1)!.toLowerCase()] = am.group(2)!;
      }
      final d = attrs['d'] ?? '';
      if (d.isEmpty) continue;
      final path = _parseSvgPath(d);
      final fillStr = attrs['fill'] ?? '';
      final strokeStr = attrs['stroke'] ?? '';

      if (fillStr.isNotEmpty && fillStr.toLowerCase() != 'none') {
        final c = _parseHexColor(fillStr);
        if (c != null) {
          canvas.drawPath(
            path,
            Paint()
              ..color = c
              ..style = PaintingStyle.fill,
          );
        }
      }
      if (strokeStr.isNotEmpty && strokeStr.toLowerCase() != 'none') {
        final c = _parseHexColor(strokeStr);
        if (c != null) {
          canvas.drawPath(
            path,
            Paint()
              ..color = c
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6,
          );
        }
      }
    }
    canvas.restore();
  }

  Color? _parseHexColor(String raw) {
    var s = raw.trim().replaceFirst('#', '');
    if (s.length == 3) {
      s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
    }
    if (s.length == 6) {
      final v = int.tryParse('FF$s', radix: 16);
      if (v != null) return Color(v);
    }
    return null;
  }

  Path _parseSvgPath(String d) {
    final path = Path();
    final tokens = <String>[];
    for (final m in _tokenRe.allMatches(d)) {
      tokens.add(m.group(0)!);
    }
    var i = 0;
    var cmd = '';
    double cx = 0;
    double cy = 0;

    double nextNum() {
      if (i >= tokens.length) return 0;
      return double.tryParse(tokens[i++]) ?? 0;
    }

    while (i < tokens.length) {
      final t = tokens[i];
      if (RegExp(r'^[A-Za-z]$').hasMatch(t)) {
        cmd = t;
        i++;
      }
      switch (cmd) {
        case 'M':
          cx = nextNum();
          cy = nextNum();
          path.moveTo(cx, cy);
          cmd = 'L';
          break;
        case 'm':
          cx += nextNum();
          cy += nextNum();
          path.moveTo(cx, cy);
          cmd = 'l';
          break;
        case 'L':
          cx = nextNum();
          cy = nextNum();
          path.lineTo(cx, cy);
          break;
        case 'l':
          cx += nextNum();
          cy += nextNum();
          path.lineTo(cx, cy);
          break;
        case 'H':
          cx = nextNum();
          path.lineTo(cx, cy);
          break;
        case 'h':
          cx += nextNum();
          path.lineTo(cx, cy);
          break;
        case 'V':
          cy = nextNum();
          path.lineTo(cx, cy);
          break;
        case 'v':
          cy += nextNum();
          path.lineTo(cx, cy);
          break;
        case 'Q':
          final x1 = nextNum();
          final y1 = nextNum();
          cx = nextNum();
          cy = nextNum();
          path.quadraticBezierTo(x1, y1, cx, cy);
          break;
        case 'q':
          final x1 = cx + nextNum();
          final y1 = cy + nextNum();
          cx += nextNum();
          cy += nextNum();
          path.quadraticBezierTo(x1, y1, cx, cy);
          break;
        case 'C':
          final x1 = nextNum();
          final y1 = nextNum();
          final x2 = nextNum();
          final y2 = nextNum();
          cx = nextNum();
          cy = nextNum();
          path.cubicTo(x1, y1, x2, y2, cx, cy);
          break;
        case 'c':
          final x1 = cx + nextNum();
          final y1 = cy + nextNum();
          final x2 = cx + nextNum();
          final y2 = cy + nextNum();
          cx += nextNum();
          cy += nextNum();
          path.cubicTo(x1, y1, x2, y2, cx, cy);
          break;
        case 'Z':
        case 'z':
          path.close();
          cmd = '';
          break;
        default:
          i++;
          break;
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _SvgCaptchaPainter oldDelegate) =>
      oldDelegate.svgXml != svgXml;
}

/// Conflict-free horizontal scroll wrapper:
/// - Does NOT register `PointerDeviceKind.trackpad` in `HorizontalDragGestureRecognizer`, so it NEVER steals
///   vertical trackpad two-finger scroll gestures from the parent `ListView`!
/// - Instead, handles horizontal trackpad panning (`event.localPanDelta.dx`) via `Listener.onPointerPanZoomUpdate`,
///   enabling smooth simultaneous 2D diagonal trackpad scrolling!
class IsolatedHorizontalScroll extends StatefulWidget {
  final Widget child;
  final ScrollController? controller;
  final bool convertVerticalWheelToHorizontal;

  const IsolatedHorizontalScroll({
    super.key,
    required this.child,
    this.controller,
    this.convertVerticalWheelToHorizontal = false,
  });

  @override
  State<IsolatedHorizontalScroll> createState() =>
      _IsolatedHorizontalScrollState();
}

class _IsolatedHorizontalScrollState extends State<IsolatedHorizontalScroll> {
  ScrollController? _internalCtrl;

  ScrollController get _effectiveCtrl =>
      widget.controller ?? (_internalCtrl ??= ScrollController());

  @override
  void didUpdateWidget(covariant IsolatedHorizontalScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && _internalCtrl != null) {
      _internalCtrl!.dispose();
      _internalCtrl = null;
    }
  }

  @override
  void dispose() {
    _internalCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _effectiveCtrl;
    return Listener(
      onPointerPanZoomUpdate: (event) {
        if (!ctrl.hasClients) return;
        // When user swipes horizontally on trackpad (and is not pinching), pan horizontally without blocking vertical scroll!
        if ((event.scale - 1.0).abs() < 0.025 &&
            event.localPanDelta.dx != 0.0) {
          final maxExt = ctrl.position.maxScrollExtent;
          if (maxExt > 0) {
            final target =
                (ctrl.offset - event.localPanDelta.dx).clamp(0.0, maxExt);
            if (target != ctrl.offset) {
              ctrl.jumpTo(target);
            }
          }
        }
      },
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && ctrl.hasClients) {
          final maxExt = ctrl.position.maxScrollExtent;
          if (maxExt <= 0) return;

          final pressed = HardwareKeyboard.instance.logicalKeysPressed;
          final isShift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
              pressed.contains(LogicalKeyboardKey.shiftRight);

          double hDelta = 0.0;
          if (event.scrollDelta.dx != 0.0) {
            hDelta = event.scrollDelta.dx;
          } else if (event.scrollDelta.dy != 0.0 &&
              (isShift ||
                  (widget.convertVerticalWheelToHorizontal &&
                      event.kind == PointerDeviceKind.mouse))) {
            hDelta = event.scrollDelta.dy;
          }

          if (hDelta != 0.0) {
            final nextOffset = (ctrl.offset + hDelta).clamp(0.0, maxExt);
            if (nextOffset != ctrl.offset) {
              GestureBinding.instance.pointerSignalResolver.register(
                event,
                (PointerSignalEvent resolved) {
                  if (resolved is PointerScrollEvent && ctrl.hasClients) {
                    final maxE = ctrl.position.maxScrollExtent;
                    if (maxE > 0) {
                      ctrl.jumpTo((ctrl.offset + hDelta).clamp(0.0, maxE));
                    }
                  }
                },
              );
            }
          }
        }
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: const <PointerDeviceKind>{
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.stylus,
          },
        ),
        child: SingleChildScrollView(
          controller: ctrl,
          primary: false,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: widget.child,
        ),
      ),
    );
  }
}
