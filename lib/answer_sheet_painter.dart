import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hfs_client.dart';
import 'hfs_models.dart';

/// Shared helper for right-click / long-press / toolbar image copy & export
class HfsImageClipboardAndExporter {
  static String _sanitizeName(String raw) {
    final cleaned =
        raw.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9_-]'), '_');
    return cleaned.isEmpty
        ? 'hfs_sheet'
        : (cleaned.length > 42 ? cleaned.substring(0, 42) : cleaned);
  }

  /// Render [decodedImage] together with [overlay] (when [includeOverlay] is true) into PNG bytes
  static Future<Uint8List> encodeCompositePng({
    required Uint8List rawBytes,
    ui.Image? decodedImage,
    PageOverlayData? overlay,
    bool includeOverlay = true,
    String? highlightedQuestionName,
  }) async {
    if (!includeOverlay || overlay == null || decodedImage == null) {
      return rawBytes;
    }
    final recorder = ui.PictureRecorder();
    final size = Size(
      decodedImage.width.toDouble(),
      decodedImage.height.toDouble(),
    );
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    canvas.drawImage(decodedImage, Offset.zero, Paint());
    final painter = _GradingOverlayPainter(
      imageSize: size,
      overlay: overlay,
      highlightedQuestionName: highlightedQuestionName,
    );
    painter.paint(canvas, size);
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
      decodedImage.width,
      decodedImage.height,
    );
    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    if (byteData == null) return rawBytes;
    return byteData.buffer.asUint8List();
  }

  /// Save image bytes to Downloads / Desktop / temp directory and return absolute path
  static Future<String> saveImageToDisk({
    required Uint8List bytes,
    required String label,
    String ext = 'png',
  }) async {
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final baseName = '${_sanitizeName(label)}_$ts.$ext';
    final env = Platform.environment;
    final candidates = <String>[
      if ((env['USERPROFILE'] ?? '').isNotEmpty)
        '${env['USERPROFILE']}\\Downloads\\$baseName',
      if ((env['USERPROFILE'] ?? '').isNotEmpty)
        '${env['USERPROFILE']}\\Desktop\\$baseName',
      if ((env['HOME'] ?? '').isNotEmpty)
        '${env['HOME']}/Downloads/$baseName',
      if ((env['HOME'] ?? '').isNotEmpty) '${env['HOME']}/Desktop/$baseName',
      if ((env['HOME'] ?? '').isNotEmpty) '${env['HOME']}/$baseName',
      if (Platform.isAndroid) '/sdcard/Download/$baseName',
      if (Platform.isAndroid) '/storage/emulated/0/Download/$baseName',
      '${Directory.current.path}${Platform.pathSeparator}$baseName',
      '${Directory.systemTemp.path}${Platform.pathSeparator}$baseName',
    ];
    for (final p in candidates) {
      try {
        final f = File(p);
        if (await f.parent.exists()) {
          await f.writeAsBytes(bytes);
          return f.path;
        }
      } catch (_) {}
    }
    final fallback = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$baseName',
    );
    await fallback.writeAsBytes(bytes);
    return fallback.path;
  }

  /// Copy image bitmap directly into OS system clipboard (Windows / macOS / Linux X11 & Wayland)
  /// Also copies the saved file path as text fallback.
  static Future<String> copyImageToSystemClipboard({
    required Uint8List bytes,
    required String label,
  }) async {
    final savedPath = await saveImageToDisk(
      bytes: bytes,
      label: label,
      ext: 'png',
    );
    bool bitmapCopied = false;
    try {
      if (Platform.isWindows) {
        final escaped = savedPath.replaceAll("'", "''");
        final res = await Process.run('powershell', <String>[
          '-NoProfile',
          '-NonInteractive',
          '-STA',
          '-Command',
          "Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; \$img = [System.Drawing.Image]::FromFile('$escaped'); [System.Windows.Forms.Clipboard]::SetImage(\$img); \$img.Dispose()",
        ]);
        bitmapCopied = res.exitCode == 0;
      } else if (Platform.isLinux) {
        try {
          final xclip = await Process.run('xclip', <String>[
            '-selection',
            'clipboard',
            '-t',
            'image/png',
            '-i',
            savedPath,
          ]);
          bitmapCopied = xclip.exitCode == 0;
        } catch (_) {}
        if (!bitmapCopied) {
          try {
            final wl = await Process.run(
              'bash',
              <String>['-lc', 'wl-copy --type image/png < "$savedPath"'],
            );
            bitmapCopied = wl.exitCode == 0;
          } catch (_) {}
        }
      } else if (Platform.isMacOS) {
        final escaped = savedPath.replaceAll('"', '\\"');
        final osa = await Process.run('osascript', <String>[
          '-e',
          'set the clipboard to (read (POSIX file "$escaped") as «class PNGf»)',
        ]);
        bitmapCopied = osa.exitCode == 0;
      }
    } catch (_) {}

    if (!bitmapCopied) {
      await Clipboard.setData(ClipboardData(text: savedPath));
    }
    return savedPath;
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
    final hasOverlay = overlay != null && decodedImage != null;
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
          value: 'export_current',
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.download_outlined,
                  size: 16, color: Color(0xFF1B6C80)),
              const SizedBox(width: 8),
              Text(
                hasOverlay && showOverlay ? '导出图片文件（含批改层 .png）' : '导出图片文件 (.png)',
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
            value: 'export_raw',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.file_download_outlined,
                    size: 16, color: Color(0xFF5D5F60)),
                SizedBox(width: 8),
                Text(
                  '导出纯原图文件 (.png)',
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
                  '全屏无损放大阅卷',
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
      final includeOv =
          (selected == 'copy_current' || selected == 'export_current') &&
              showOverlay;
      final pngBytes = await encodeCompositePng(
        rawBytes: rawBytes,
        decodedImage: decodedImage,
        overlay: overlay,
        includeOverlay: includeOv,
        highlightedQuestionName: highlightedQuestionName,
      );
      if (selected.startsWith('copy_')) {
        final path = await copyImageToSystemClipboard(
          bytes: pngBytes,
          label: label,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF131416),
            content: Text(
              '图片已复制到系统剪贴板（同时已存至：$path）',
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      } else if (selected.startsWith('export_')) {
        final path = await saveImageToDisk(
          bytes: pngBytes,
          label: label,
          ext: 'png',
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF131416),
            content: Text(
              '图片已导出至：$path',
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
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

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
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
            onTap: widget.onOpenLightbox,
            onSecondaryTapDown: (details) {
              if (_imageBytes == null) return;
              HfsImageClipboardAndExporter.showImageContextMenu(
                context: context,
                globalPosition: details.globalPosition,
                rawBytes: _imageBytes!,
                label: 'hfs_answer_sheet',
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
                label: 'hfs_answer_sheet',
                decodedImage: _decodedImage,
                overlay: widget.overlay,
                showOverlay: widget.showOverlay,
                highlightedQuestionName: widget.highlightedQuestionName,
                onOpenLightbox: widget.onOpenLightbox,
              );
            },
            onScaleStart: widget.onZoomChanged != null
                ? (_) {
                    _basePinchZoom = widget.zoomScale;
                  }
                : null,
            onScaleUpdate: widget.onZoomChanged != null
                ? (details) {
                    if ((details.scale - 1.0).abs() > 0.01) {
                      widget.onZoomChanged!(
                        (_basePinchZoom * details.scale).clamp(0.6, 2.5),
                      );
                    }
                  }
                : null,
            child: Listener(
              onPointerSignal: (event) {
                if (widget.onZoomChanged == null) return;
                if (event is PointerScaleEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (resolved) {
                      if (resolved is PointerScaleEvent) {
                        widget.onZoomChanged!(
                          (widget.zoomScale * resolved.scale).clamp(0.6, 2.5),
                        );
                      }
                    },
                  );
                }
              },
              child: stage,
            ),
          ),
        );

        if (zoom > 1.01) {
          return IsolatedHorizontalScroll(
            child: stage,
          );
        }
        return stage;
      },
    );
  }
}

/// Inline oss crop / stem image viewer with click-to-lightbox
class OssCropImage extends StatefulWidget {
  final HfsUpstreamClient client;
  final String imageUrl;
  final double? maxHeight;
  final String caption;

  const OssCropImage({
    super.key,
    required this.client,
    required this.imageUrl,
    this.maxHeight,
    this.caption = '原图放大查看',
  });

  @override
  State<OssCropImage> createState() => _OssCropImageState();
}

class _OssCropImageState extends State<OssCropImage> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
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
        onTap: () => showOssImageLightbox(
          context: context,
          client: widget.client,
          imageUrl: widget.imageUrl,
          caption: widget.caption,
        ),
        onSecondaryTapDown: (details) {
          if (_bytes == null) return;
          HfsImageClipboardAndExporter.showImageContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            rawBytes: _bytes!,
            label: widget.caption,
            onOpenLightbox: () => showOssImageLightbox(
              context: context,
              client: widget.client,
              imageUrl: widget.imageUrl,
              caption: widget.caption,
            ),
          );
        },
        onLongPressStart: (details) {
          if (_bytes == null) return;
          HfsImageClipboardAndExporter.showImageContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            rawBytes: _bytes!,
            label: widget.caption,
            onOpenLightbox: () => showOssImageLightbox(
              context: context,
              client: widget.client,
              imageUrl: widget.imageUrl,
              caption: widget.caption,
            ),
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

/// Fullscreen interactive Lightbox dialog supporting pinch, drag, wheel zoom and overlay toggle
Future<void> showOssImageLightbox({
  required BuildContext context,
  required HfsUpstreamClient client,
  required String imageUrl,
  required String caption,
  PageOverlayData? overlay,
  bool initialShowOverlay = true,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xF0131416),
    builder: (ctx) => _OssLightboxDialog(
      client: client,
      imageUrl: imageUrl,
      caption: caption,
      overlay: overlay,
      initialShowOverlay: initialShowOverlay,
    ),
  );
}

class _OssLightboxDialog extends StatefulWidget {
  final HfsUpstreamClient client;
  final String imageUrl;
  final String caption;
  final PageOverlayData? overlay;
  final bool initialShowOverlay;

  const _OssLightboxDialog({
    required this.client,
    required this.imageUrl,
    required this.caption,
    this.overlay,
    this.initialShowOverlay = true,
  });

  @override
  State<_OssLightboxDialog> createState() => _OssLightboxDialogState();
}

class _OssLightboxDialogState extends State<_OssLightboxDialog> {
  final TransformationController _ctrl = TransformationController();
  Size _viewportSize = const Size(960, 720);
  ui.Image? _decoded;
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;
  late bool _showOverlay;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _showOverlay = widget.initialShowOverlay;
    _ctrl.addListener(_onMatrix);
    _load();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onMatrix);
    _ctrl.dispose();
    _decoded?.dispose();
    _decoded = null;
    super.dispose();
  }

  void _onMatrix() {
    final s = _ctrl.value.getMaxScaleOnAxis();
    if ((s - _scale).abs() > 0.03 && mounted) {
      setState(() => _scale = s);
    }
  }

  /// Zoom smoothly around [focalPoint] (or viewport center) so the image never drifts to the bottom-right corner!
  void _setScale(double target, {Offset? focalPoint}) {
    final c = target.clamp(0.5, 5.0);
    if ((c - 1.0).abs() < 0.04) {
      _ctrl.value = Matrix4.identity();
      return;
    }
    final oldScale = _ctrl.value.getMaxScaleOnAxis();
    if (oldScale <= 0) {
      _ctrl.value = Matrix4.diagonal3Values(c, c, 1.0);
      return;
    }
    final anchor = focalPoint ??
        Offset(_viewportSize.width / 2.0, _viewportSize.height / 2.0);
    final oldTx = _ctrl.value.storage[12];
    final oldTy = _ctrl.value.storage[13];
    // Preserve scene point under anchor: scenePt = (anchor - oldT) / oldScale, newT = anchor - scenePt * c
    final ratio = c / oldScale;
    final newTx = anchor.dx - (anchor.dx - oldTx) * ratio;
    final newTy = anchor.dy - (anchor.dy - oldTy) * ratio;
    final m = Matrix4.diagonal3Values(c, c, 1.0);
    m.setTranslationRaw(newTx, newTy, 0.0);
    _ctrl.value = m;
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

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: const Color(0xF2131416),
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF131416),
              border: Border(bottom: BorderSide(color: Color(0xFF2E3033))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.overlay != null) ...[
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
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (_bytes != null) ...[
                  TextButton.icon(
                    onPressed: () async {
                      final png = await HfsImageClipboardAndExporter
                          .encodeCompositePng(
                        rawBytes: _bytes!,
                        decodedImage: _decoded,
                        overlay: widget.overlay,
                        includeOverlay: _showOverlay,
                      );
                      final saved = await HfsImageClipboardAndExporter
                          .copyImageToSystemClipboard(
                        bytes: png,
                        label: widget.caption,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已复制图片到剪贴板（同时存至：$saved）'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 15, color: Colors.white),
                    label: const Text(
                      '复制图片',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final png = await HfsImageClipboardAndExporter
                          .encodeCompositePng(
                        rawBytes: _bytes!,
                        decodedImage: _decoded,
                        overlay: widget.overlay,
                        includeOverlay: _showOverlay,
                      );
                      final saved =
                          await HfsImageClipboardAndExporter.saveImageToDisk(
                        bytes: png,
                        label: widget.caption,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('图片已导出至：$saved'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.download_outlined,
                        size: 16, color: Colors.white),
                    label: const Text(
                      '导出图片',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                IconButton(
                  tooltip: '缩小',
                  onPressed: () => _setScale(_scale - 0.35),
                  icon: const Icon(Icons.remove, color: Colors.white, size: 18),
                ),
                InkWell(
                  onTap: () => _setScale(1.0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
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
                  tooltip: '放大',
                  onPressed: () => _setScale(_scale + 0.35),
                  icon: const Icon(Icons.add, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '关闭 (Esc)',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
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
                          final aspect = img.width / math.max(1, img.height);
                          final fitW = math.min(box.maxWidth - 32, 1100.0);
                          final fitH = fitW / aspect;
                          return Listener(
                            onPointerSignal: (event) {
                              if (event is PointerScaleEvent) {
                                GestureBinding.instance.pointerSignalResolver
                                    .register(event, (resolved) {
                                  if (resolved is PointerScaleEvent) {
                                    _setScale(
                                      _scale * resolved.scale,
                                      focalPoint: resolved.localPosition,
                                    );
                                  }
                                });
                              } else if (event is PointerScrollEvent) {
                                GestureBinding.instance.pointerSignalResolver
                                    .register(event, (resolved) {
                                  if (resolved is PointerScrollEvent) {
                                    final dy = resolved.scrollDelta.dy;
                                    if (dy != 0) {
                                      final factor =
                                          math.exp(-dy / 280.0).clamp(0.75, 1.35);
                                      _setScale(
                                        _scale * factor,
                                        focalPoint: resolved.localPosition,
                                      );
                                    }
                                  }
                                });
                              }
                            },
                            child: InteractiveViewer(
                              transformationController: _ctrl,
                              trackpadScrollCausesScale: false,
                              minScale: 0.5,
                              maxScale: 5.0,
                              boundaryMargin: const EdgeInsets.all(240),
                              child: Center(
                              child: SizedBox(
                                width: fitW,
                                height: fitH,
                                child: GestureDetector(
                                  onSecondaryTapDown: (details) {
                                    if (_bytes == null) return;
                                    HfsImageClipboardAndExporter
                                        .showImageContextMenu(
                                      context: context,
                                      globalPosition: details.globalPosition,
                                      rawBytes: _bytes!,
                                      label: widget.caption,
                                      decodedImage: _decoded,
                                      overlay: widget.overlay,
                                      showOverlay: _showOverlay,
                                    );
                                  },
                                  child: Container(
                                    color: Colors.white,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.memory(
                                          _bytes!,
                                          fit: BoxFit.contain,
                                        ),
                                        if (_showOverlay &&
                                            widget.overlay != null)
                                          CustomPaint(
                                            painter: _GradingOverlayPainter(
                                              imageSize: Size(
                                                img.width.toDouble(),
                                                img.height.toDouble(),
                                              ),
                                              overlay: widget.overlay!,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
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

  static final RegExp _pathTagRe = RegExp(r'<path\b([^>]*)/?>', caseSensitive: false);
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

/// Pure Flutter horizontal scroll wrapper that prevents mouse-wheel events from
/// bubbling up to the vertical parent Scrollable when hovering a horizontal strip.
class IsolatedHorizontalScroll extends StatefulWidget {
  final Widget child;
  final ScrollController? controller;

  const IsolatedHorizontalScroll({
    super.key,
    required this.child,
    this.controller,
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
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver.register(
            event,
            (PointerSignalEvent resolved) {
              if (resolved is PointerScrollEvent && ctrl.hasClients) {
                final delta = resolved.scrollDelta.dy != 0
                    ? resolved.scrollDelta.dy
                    : resolved.scrollDelta.dx;
                final maxExt = ctrl.position.maxScrollExtent;
                if (maxExt > 0) {
                  final target = (ctrl.offset + delta).clamp(0.0, maxExt);
                  ctrl.jumpTo(target);
                }
              }
            },
          );
        }
      },
      child: SingleChildScrollView(
        controller: ctrl,
        primary: false,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: widget.child,
      ),
    );
  }
}
