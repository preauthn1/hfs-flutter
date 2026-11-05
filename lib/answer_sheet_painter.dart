import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'hfs_client.dart';
import 'hfs_models.dart';

class AnswerSheetCanvas extends StatefulWidget {
  final HfsUpstreamClient client;
  final String imageUrl;
  final PageOverlayData? overlay;
  final bool showOverlay;

  const AnswerSheetCanvas({
    super.key,
    required this.client,
    required this.imageUrl,
    this.overlay,
    this.showOverlay = true,
  });

  @override
  State<AnswerSheetCanvas> createState() => _AnswerSheetCanvasState();
}

class _AnswerSheetCanvasState extends State<AnswerSheetCanvas> {
  final TransformationController _transformCtrl = TransformationController();
  ui.Image? _decodedImage;
  Uint8List? _imageBytes;
  String? _error;
  bool _loading = true;
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _transformCtrl.addListener(_onTransformChanged);
    _loadImage();
  }

  @override
  void dispose() {
    _transformCtrl.removeListener(_onTransformChanged);
    _transformCtrl.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final s = _transformCtrl.value.getMaxScaleOnAxis();
    if ((s - _currentScale).abs() > 0.04 && mounted) {
      setState(() => _currentScale = s);
    }
  }

  void _setZoom(double targetScale) {
    final clamped = targetScale.clamp(1.0, 4.0);
    if ((clamped - 1.0).abs() < 0.05) {
      _transformCtrl.value = Matrix4.identity();
    } else {
      _transformCtrl.value = Matrix4.diagonal3Values(clamped, clamped, 1.0);
    }
  }

  @override
  void didUpdateWidget(covariant AnswerSheetCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _transformCtrl.value = Matrix4.identity();
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.client.fetchOssImageBytes(widget.imageUrl);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _decodedImage = frame.image;
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
      return const SizedBox(
        height: 360,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2.4),
              SizedBox(height: 12),
              Text(
                '正在从好分数 OSS 加载高清答题卡…',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null || _decodedImage == null || _imageBytes == null) {
      return Container(
        height: 260,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined,
                size: 36, color: Color(0xFFDC2626)),
            const SizedBox(height: 8),
            Text(
              _error ?? '图片加载失败',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFFDC2626)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadImage,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final img = _decodedImage!;
    final aspect = img.width / math.max(1, img.height);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : img.width.toDouble();
        final displayW = maxW;
        final displayH = displayW / aspect;

        return Stack(
          children: [
            GestureDetector(
              onDoubleTap: () {
                if (_currentScale > 1.2) {
                  _setZoom(1.0);
                } else {
                  _setZoom(2.2);
                }
              },
              child: InteractiveViewer(
                transformationController: _transformCtrl,
                minScale: 1.0,
                maxScale: 4.0,
                child: SizedBox(
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
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '缩小',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove, size: 16),
                      onPressed: _currentScale <= 1.05
                          ? null
                          : () => _setZoom(_currentScale - 0.4),
                    ),
                    InkWell(
                      onTap: () => _setZoom(1.0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '${(_currentScale * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '放大',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add, size: 16),
                      onPressed: _currentScale >= 3.95
                          ? null
                          : () => _setZoom(_currentScale + 0.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GradingOverlayPainter extends CustomPainter {
  final Size imageSize;
  final PageOverlayData overlay;

  const _GradingOverlayPainter({
    required this.imageSize,
    required this.overlay,
  });

  static const Color _green = Color(0xFF16A34A);
  static const Color _red = Color(0xFFDC2626);
  static const Color _amber = Color(0xFFD97706);

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return;
    final sx = size.width / imageSize.width;
    final sy = size.height / imageSize.height;

    // 1. Objective choices
    for (final obj in overlay.objectives) {
      final rect = Rect.fromLTWH(
        obj.x * sx,
        obj.y * sy,
        math.max(18 * sx, obj.w * sx),
        math.max(14 * sy, obj.h * sy),
      );
      if (obj.isRight) {
        final stroke = Paint()
          ..color = _green.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, 2.0 * sx);
        canvas.drawRect(rect, stroke);
      } else {
        final fill = Paint()
          ..color = _red.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill;
        final stroke = Paint()
          ..color = _red.withValues(alpha: 0.92)
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
            fontWeight: FontWeight.w800,
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
      final color = isFull ? _green : (isZero ? _red : _amber);

      final rect = Rect.fromLTWH(bx, by, bw, bh);
      final borderPaint = Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, 2.0 * sx);
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
        Radius.circular(math.max(3.0, 6.0 * sx)),
      );
      canvas.drawRRect(
        rrect,
        Paint()..color = color.withValues(alpha: 0.92),
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
          fontWeight: FontWeight.w900,
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
    return oldDelegate.imageSize != imageSize || oldDelegate.overlay != overlay;
  }
}
