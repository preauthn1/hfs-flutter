part of '../main.dart';

/// Right Answer Sheet & Original Paper Inspector Pane (#inspector-drawer)
/// Supports 3 Sub-Tabs:
/// 0 = 批改合成与答题卡 (Overlay + Answer Sheet Gallery + Lost-point Jump)
/// 1 = 原卷与题块 (Full Original Paper Pages + Per-Question Origin Stem Crops + Student Answer Crops + Xueba Answers)
/// 2 = 得分明细 (Full Question Score Table with Knowledge Tags & Crops)
class PaperInspectionPane extends StatefulWidget {
  final HfsUpstreamClient client;
  final HfsAccount account;
  final ExamRecord exam;
  final PaperScore paper;
  final bool defaultShowOverlay;
  final ValueChanged<PaperScore>? onSelectPaper;
  final VoidCallback onClose;

  const PaperInspectionPane({
    super.key,
    required this.client,
    required this.account,
    required this.exam,
    required this.paper,
    this.defaultShowOverlay = true,
    this.onSelectPaper,
    required this.onClose,
  });

  @override
  State<PaperInspectionPane> createState() => _PaperInspectionPaneState();
}

class _PaperInspectionPaneState extends State<PaperInspectionPane> {
  final ScrollController _inspectorScrollCtrl = ScrollController();
  final Map<String, GlobalKey> _questionKeys = <String, GlobalKey>{};
  final Map<int, GlobalKey> _pageKeys = <int, GlobalKey>{};

  PaperInspectionData? _data;
  String? _error;
  bool _loading = true;
  late bool _showGradingOverlay;
  int _subTab = 0; // 0 = 批改合成与答题卡, 1 = 原卷与题块, 2 = 得分明细
  double _zoomScale = 1.0;
  String? _highlightedQName;
  int _activePageIndex = 0;
  bool _singlePageView = true;

  @override
  void initState() {
    super.initState();
    _showGradingOverlay = widget.defaultShowOverlay;
    HardwareKeyboard.instance.addHandler(_handleInspectorKeyEvent);
    _loadInspection();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleInspectorKeyEvent);
    _inspectorScrollCtrl.dispose();
    super.dispose();
  }

  bool _handleInspectorKeyEvent(KeyEvent event) {
    if (!mounted || _loading || _data == null) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    // Do not intercept keys when a modal dialog (e.g. Lightbox / Settings) is on top
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    // Do not intercept keys when user is typing in a text field
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusedWidget is EditableText) return false;

    final key = event.logicalKey;
    final data = _data!;

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      if (_subTab == 0 && data.answerPages.length > 1) {
        _switchPageIndex(
          (_activePageIndex - 1 + data.answerPages.length) %
              data.answerPages.length,
        );
        return true;
      } else if (_subTab == 1 && data.originalPages.length > 1) {
        _switchPageIndex(
          (_activePageIndex - 1 + data.originalPages.length) %
              data.originalPages.length,
        );
        return true;
      } else if (widget.exam.papers.length > 1 &&
          widget.onSelectPaper != null) {
        final curIdx = widget.exam.papers.indexWhere(
          (p) => p.paperId == widget.paper.paperId,
        );
        if (curIdx >= 0) {
          final prevIdx = (curIdx - 1 + widget.exam.papers.length) %
              widget.exam.papers.length;
          widget.onSelectPaper!(widget.exam.papers[prevIdx]);
          return true;
        }
      }
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown) {
      if (_subTab == 0 && data.answerPages.length > 1) {
        _switchPageIndex((_activePageIndex + 1) % data.answerPages.length);
        return true;
      } else if (_subTab == 1 && data.originalPages.length > 1) {
        _switchPageIndex((_activePageIndex + 1) % data.originalPages.length);
        return true;
      } else if (widget.exam.papers.length > 1 &&
          widget.onSelectPaper != null) {
        final curIdx = widget.exam.papers.indexWhere(
          (p) => p.paperId == widget.paper.paperId,
        );
        if (curIdx >= 0) {
          final nextIdx = (curIdx + 1) % widget.exam.papers.length;
          widget.onSelectPaper!(widget.exam.papers[nextIdx]);
          return true;
        }
      }
    }
    return false;
  }

  void _switchPageIndex(int nextIdx) {
    setState(() {
      _activePageIndex = nextIdx;
    });
    if (_singlePageView) {
      if (_inspectorScrollCtrl.hasClients) {
        _inspectorScrollCtrl.jumpTo(0.0);
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final key = _pageKeys[nextIdx];
        if (key?.currentContext != null) {
          Scrollable.ensureVisible(
            key!.currentContext!,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant PaperInspectionPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exam.examId != widget.exam.examId ||
        oldWidget.paper.paperId != widget.paper.paperId ||
        oldWidget.paper.pid != widget.paper.pid ||
        oldWidget.exam.studentId != widget.exam.studentId ||
        oldWidget.account.id != widget.account.id ||
        oldWidget.account.activeStudentId != widget.account.activeStudentId) {
      _highlightedQName = null;
      _activePageIndex = 0;
      _loadInspection();
    }
  }

  Future<void> _loadInspection() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.client.fetchPaperInspection(
        account: widget.account,
        studentId: widget.exam.studentId.isNotEmpty
            ? widget.exam.studentId
            : widget.account.activeStudentId,
        examId: widget.exam.examId,
        paperId: widget.paper.paperId,
        pid: widget.paper.pid,
        subject: widget.paper.subject,
      );
      if (!mounted) return;
      _pageKeys.clear();
      _questionKeys.clear();
      for (var i = 0; i < res.answerPages.length; i++) {
        _pageKeys[i] = GlobalKey();
      }
      for (final q in res.questions) {
        _questionKeys[q.name] = GlobalKey();
      }
      setState(() {
        _data = res;
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

  void _jumpToLostQuestion(QuestionDetailItem q) {
    setState(() {
      _highlightedQName = q.name;
    });
    if (_subTab == 0) {
      // Find which page contains this question's objective mark or subjective block
      final data = _data;
      if (data != null) {
        for (final ov in data.pageOverlays) {
          final hasObj = ov.objectives.any((o) => o.qName == q.name);
          final hasBlk = ov.blocks.any((b) => b.qNames.contains(q.name));
          if (hasObj || hasBlk) {
            _switchPageIndex(
              ov.pageIndex.clamp(0, math.max(0, data.answerPages.length - 1)),
            );
            return;
          }
        }
      }
    } else {
      final key = _questionKeys[q.name];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 220),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final originItemCount = (data?.originalPages.length ?? 0) +
        (data?.questionsWithOriginStems.length ?? 0) +
        (data?.questions.where((q) => q.cropUrls.isNotEmpty).length ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Inspector Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: const BoxDecoration(
            color: Taste.surface,
            border: Border(bottom: BorderSide(color: Taste.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.paper.subject} · 试卷与答题卡调阅',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Taste.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data != null
                          ? '${widget.exam.name} · 总分 ${data.totalScore} (客观 ${data.objectScore} / 主观 ${data.subjectScore})'
                          : widget.exam.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Taste.numStyle(size: 12, color: Taste.muted),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(Taste.radiusControl),
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 52, minHeight: 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Taste.surface,
                    border: Border.all(color: Taste.control),
                    borderRadius: BorderRadius.circular(Taste.radiusControl),
                  ),
                  child: const Text(
                    '收起',
                    style:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. Inspector Zoom & Overlay Tools Bar (#F4F6F8)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: const BoxDecoration(
            color: Taste.raised,
            border: Border(bottom: BorderSide(color: Taste.border)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _toolBtn(
                    '−',
                    onTap: _zoomScale <= 0.65
                        ? null
                        : () => setState(() =>
                            _zoomScale = (_zoomScale - 0.25).clamp(0.6, 2.5)),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(_zoomScale * 100).round()}%',
                      textAlign: TextAlign.center,
                      style: Taste.numStyle(
                        size: 12,
                        weight: FontWeight.w700,
                        color: Taste.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _toolBtn(
                    '＋',
                    onTap: _zoomScale >= 2.45
                        ? null
                        : () => setState(() =>
                            _zoomScale = (_zoomScale + 0.25).clamp(0.6, 2.5)),
                  ),
                  const SizedBox(width: 4),
                  _toolBtn(
                    '适应宽度',
                    onTap: () => setState(() => _zoomScale = 1.0),
                  ),
                ],
              ),
              _toolBtn(
                _showGradingOverlay ? '批改叠加：开' : '批改叠加：关',
                active: _showGradingOverlay,
                onTap: () =>
                    setState(() => _showGradingOverlay = !_showGradingOverlay),
              ),
            ],
          ),
        ),

        // 3. Inspector 3 Sub-Tabs (批改合成与答题卡 | 原卷与题块 | 得分明细)
        Container(
          decoration: const BoxDecoration(
            color: Taste.surface,
            border: Border(bottom: BorderSide(color: Taste.border)),
          ),
          child: Row(
            children: [
              _buildSubTab(
                0,
                '批改合成 (${data?.answerPages.length ?? 0})',
              ),
              _buildSubTab(
                1,
                '原卷与题块 ($originItemCount)',
              ),
              _buildSubTab(
                2,
                '得分明细 (${data?.questions.length ?? 0})',
              ),
            ],
          ),
        ),

        // 4. Lost Points Quick Jump Bar (#lost-points-bar)
        if (data != null && data.lostQuestions.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFAFA),
              border: Border(bottom: BorderSide(color: Taste.border)),
            ),
            child: IsolatedHorizontalScroll(
              child: Row(
                children: [
                  const Text(
                    '失分题定位：',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Taste.negative,
                    ),
                  ),
                  const SizedBox(width: 6),
                  for (final q in data.lostQuestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () => _jumpToLostQuestion(q),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _highlightedQName == q.name
                                ? Taste.negative
                                : Taste.pillNegBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Text(
                            '第${q.name}题 (−${q.lostScore})',
                            style: Taste.numStyle(
                              size: 11,
                              weight: FontWeight.w500,
                              color: _highlightedQName == q.name
                                  ? Colors.white
                                  : Taste.pillNegInk,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

        // 5. Inspector Independent Scrollable Body
        Expanded(
          child: _loading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Taste.accent),
                      SizedBox(height: 12),
                      Text(
                        '正在调阅答题卡、原卷题干与逐题批改坐标…',
                        style: TextStyle(fontSize: 12, color: Taste.muted),
                      ),
                    ],
                  ),
                )
              : (_error != null)
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Taste.negative),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _loadInspection,
                              icon: const Icon(Icons.refresh, size: 15),
                              label: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : (data == null)
                      ? const SizedBox.shrink()
                      : ListView(
                          controller: _inspectorScrollCtrl,
                          primary: false,
                          padding: const EdgeInsets.all(12),
                          children: [
                            if (_subTab == 0)
                              ..._buildAnswerSheetGallery(data)
                            else if (_subTab == 1)
                              ..._buildOriginalPaperAndBlocksView(data)
                            else
                              ..._buildQuestionsScoreTableView(data),
                          ],
                        ),
        ),
      ],
    );
  }

  List<Widget> _buildAnswerSheetGallery(PaperInspectionData data) {
    if (data.answerPages.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/empty_inspector.png',
                    width: 140,
                    height: 140,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '该科目暂无答题卡扫描件',
                  style: TextStyle(color: Taste.muted),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final galleryItems = <LightboxGalleryItem>[
      for (var pIdx = 0; pIdx < data.answerPages.length; pIdx++)
        LightboxGalleryItem(
          imageUrl: data.answerPages[pIdx],
          caption:
              '${widget.exam.name} · ${widget.paper.subject} 答题卡 第 ${pIdx + 1} / ${data.answerPages.length} 页',
          overlay:
              pIdx < data.pageOverlays.length ? data.pageOverlays[pIdx] : null,
          initialShowOverlay: _showGradingOverlay,
          highlightedQuestionName: _highlightedQName,
        ),
    ];

    final safePageIdx = _activePageIndex.clamp(0, data.answerPages.length - 1);
    final visibleIndices = (_singlePageView && data.answerPages.length > 1)
        ? <int>[safePageIdx]
        : List<int>.generate(data.answerPages.length, (idx) => idx);

    return [
      if (data.answerPages.length > 1)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Taste.raised,
            borderRadius: BorderRadius.circular(Taste.radiusControl),
            border: Border.all(color: Taste.border),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _toolBtn(
                    '‹ 上一张',
                    onTap: () => _switchPageIndex(
                      (safePageIdx - 1 + data.answerPages.length) %
                          data.answerPages.length,
                    ),
                  ),
                  for (var pIdx = 0; pIdx < data.answerPages.length; pIdx++)
                    _toolBtn(
                      '第${pIdx + 1}页',
                      active: safePageIdx == pIdx,
                      onTap: () => _switchPageIndex(pIdx),
                    ),
                  _toolBtn(
                    '下一张 ›',
                    onTap: () => _switchPageIndex(
                      (safePageIdx + 1) % data.answerPages.length,
                    ),
                  ),
                ],
              ),
              _toolBtn(
                _singlePageView ? '切换为连续平铺' : '切换为单张翻页',
                active: !_singlePageView,
                onTap: () => setState(() => _singlePageView = !_singlePageView),
              ),
            ],
          ),
        ),
      for (final i in visibleIndices)
        Container(
          key: _pageKeys[i],
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Taste.surface,
            borderRadius: BorderRadius.circular(Taste.radiusCard),
            border: Border.all(color: Taste.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: const BoxDecoration(
                  color: Taste.surface,
                  border: Border(bottom: BorderSide(color: Taste.border)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Text(
                      '答题卡 第 ${i + 1} / ${data.answerPages.length} 页',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Taste.muted,
                      ),
                    ),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _toolBtn(
                          '复制图片',
                          onTap: () async {
                            try {
                              final raw = await widget.client
                                  .fetchOssImageBytes(data.answerPages[i]);
                              final ok = await HfsImageClipboardAndExporter
                                  .copyImageFastToClipboard(
                                rawBytes: raw,
                                overlay: i < data.pageOverlays.length
                                    ? data.pageOverlays[i]
                                    : null,
                                includeOverlay: _showGradingOverlay,
                                highlightedQuestionName: _highlightedQName,
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok ? '图片已复制到系统剪贴板' : '复制图片到剪贴板失败',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('复制失败：$e')),
                              );
                            }
                          },
                        ),
                        _toolBtn(
                          '保存至下载',
                          onTap: () async {
                            try {
                              final raw = await widget.client
                                  .fetchOssImageBytes(data.answerPages[i]);
                              final png = await HfsImageClipboardAndExporter
                                  .encodeCompositePng(
                                rawBytes: raw,
                                overlay: i < data.pageOverlays.length
                                    ? data.pageOverlays[i]
                                    : null,
                                includeOverlay: _showGradingOverlay,
                                highlightedQuestionName: _highlightedQName,
                              );
                              final saved = await HfsImageClipboardAndExporter
                                  .saveImageToDisk(
                                bytes: png,
                                label:
                                    '${widget.exam.name}_${widget.paper.subject}_答题卡_第${i + 1}页',
                              );
                              if (!mounted) return;
                              HfsImageClipboardAndExporter.showSavedSnackBar(
                                context,
                                saved,
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('保存失败：$e')),
                              );
                            }
                          },
                        ),
                        _toolBtn(
                          '全屏放大',
                          onTap: () => showOssImageLightbox(
                            context: context,
                            client: widget.client,
                            imageUrl: data.answerPages[i],
                            caption:
                                '${widget.exam.name} · ${widget.paper.subject} 第 ${i + 1} 页',
                            overlay: i < data.pageOverlays.length
                                ? data.pageOverlays[i]
                                : null,
                            initialShowOverlay: _showGradingOverlay,
                            highlightedQuestionName: _highlightedQName,
                            galleryItems: galleryItems,
                            initialIndex: i,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              AnswerSheetCanvas(
                client: widget.client,
                imageUrl: data.answerPages[i],
                caption:
                    '${widget.exam.name}_${widget.paper.subject}_答题卡_第${i + 1}页',
                overlay:
                    i < data.pageOverlays.length ? data.pageOverlays[i] : null,
                showOverlay: _showGradingOverlay,
                zoomScale: _zoomScale,
                onZoomChanged: (newZoom) {
                  setState(() => _zoomScale = newZoom);
                },
                highlightedQuestionName: _highlightedQName,
                onOpenLightbox: () => showOssImageLightbox(
                  context: context,
                  client: widget.client,
                  imageUrl: data.answerPages[i],
                  caption:
                      '${widget.exam.name} · ${widget.paper.subject} 第 ${i + 1} 页',
                  overlay: i < data.pageOverlays.length
                      ? data.pageOverlays[i]
                      : null,
                  initialShowOverlay: _showGradingOverlay,
                  highlightedQuestionName: _highlightedQName,
                  galleryItems: galleryItems,
                  initialIndex: i,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  /// Sub-Tab 1: Original Paper Pages (`paperPic`) + Per-Question Origin Stem Images (`pictures`) + Student Crop (`url`) + Xueba Answer (`xbAnswerUrls`)
  List<Widget> _buildOriginalPaperAndBlocksView(PaperInspectionData data) {
    final widgets = <Widget>[];
    final gallery = <LightboxGalleryItem>[];
    final indexMap = <String, int>{};

    for (var i = 0; i < data.originalPages.length; i++) {
      final url = data.originalPages[i];
      indexMap.putIfAbsent('orig:$i:$url', () => gallery.length);
      gallery.add(
        LightboxGalleryItem(
          imageUrl: url,
          caption:
              '${widget.exam.name} · ${widget.paper.subject} 原卷第 ${i + 1} / ${data.originalPages.length} 页',
          initialShowOverlay: false,
        ),
      );
    }
    for (final q in data.questions) {
      for (final u in q.stemUrls) {
        indexMap.putIfAbsent('q:${q.name}:stem:$u', () => gallery.length);
        gallery.add(
          LightboxGalleryItem(
            imageUrl: u,
            caption: '${widget.paper.subject} 第${q.name}题 · 原卷题干',
          ),
        );
      }
      for (final u in q.cropUrls) {
        indexMap.putIfAbsent('q:${q.name}:crop:$u', () => gallery.length);
        gallery.add(
          LightboxGalleryItem(
            imageUrl: u,
            caption: '${widget.paper.subject} 第${q.name}题 · 我的作答切块',
          ),
        );
      }
      for (final u in q.xbAnswerUrls) {
        indexMap.putIfAbsent('q:${q.name}:xb:$u', () => gallery.length);
        gallery.add(
          LightboxGalleryItem(
            imageUrl: u,
            caption: '${widget.paper.subject} 第${q.name}题 · 优秀解答',
          ),
        );
      }
    }

    if (data.originalPages.isNotEmpty) {
      for (var i = 0; i < data.originalPages.length; i++) {
        final gIdx = indexMap['orig:$i:${data.originalPages[i]}'] ?? i;
        widgets.add(
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Taste.surface,
              borderRadius: BorderRadius.circular(Taste.radiusCard),
              border: Border.all(color: Taste.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Taste.border)),
                  ),
                  child: Text(
                    '整页原卷扫描 第 ${i + 1} / ${data.originalPages.length} 页',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Taste.text,
                    ),
                  ),
                ),
                AnswerSheetCanvas(
                  client: widget.client,
                  imageUrl: data.originalPages[i],
                  caption:
                      '${widget.exam.name}_${widget.paper.subject}_原卷_第${i + 1}页',
                  showOverlay: false,
                  zoomScale: _zoomScale,
                  onZoomChanged: (newZoom) {
                    setState(() => _zoomScale = newZoom);
                  },
                  onOpenLightbox: () => showOssImageLightbox(
                    context: context,
                    client: widget.client,
                    imageUrl: data.originalPages[i],
                    caption:
                        '${widget.exam.name} · ${widget.paper.subject} 原卷第 ${i + 1} 页',
                    galleryItems: gallery,
                    initialIndex: gIdx,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    for (final q in data.questions) {
      if (q.stemUrls.isEmpty && q.cropUrls.isEmpty && q.xbAnswerUrls.isEmpty) {
        continue;
      }
      final isHighlighted = _highlightedQName == q.name;
      widgets.add(
        Container(
          key: _questionKeys[q.name],
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Taste.surface,
            borderRadius: BorderRadius.circular(Taste.radiusCard),
            border: Border.all(
              color: isHighlighted ? Taste.accent : Taste.border,
              width: isHighlighted ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: Taste.raised,
                  border: Border(bottom: BorderSide(color: Taste.border)),
                ),
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    final compact = box.maxWidth < 420;
                    final title = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '第 ${q.name} 题',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Taste.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TastePill(
                          label: q.type == 2 ? '客观题' : '主观题',
                          tone: TastePillTone.neutral,
                        ),
                      ],
                    );
                    final score = TastePill(
                      label: '${q.scoreS} / ${round1(q.manfen)}分',
                      tone: q.isFullScore
                          ? TastePillTone.positive
                          : (q.isZeroScore
                              ? TastePillTone.negative
                              : TastePillTone.warning),
                    );
                    return compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [title, const SizedBox(height: 4), score],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [Expanded(child: title), score],
                          );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (q.knowledges.isNotEmpty) ...[
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final k in q.knowledges)
                            TastePill(label: k, tone: TastePillTone.blue),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (q.stemUrls.isNotEmpty) ...[
                      const Text(
                        '原卷题干扫描（点击放大，支持 ←/→ 切图）：',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Taste.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final u in q.stemUrls)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: OssCropImage(
                            client: widget.client,
                            imageUrl: u,
                            maxHeight: 200,
                            caption:
                                '${widget.paper.subject} 第${q.name}题 · 原卷题干',
                            galleryItems: gallery,
                            galleryIndex: indexMap['q:${q.name}:stem:$u'] ?? 0,
                          ),
                        ),
                    ],
                    if (q.cropUrls.isNotEmpty) ...[
                      const Text(
                        '我的作答切块（点击放大，支持 ←/→ 切图）：',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Taste.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final u in q.cropUrls)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: OssCropImage(
                            client: widget.client,
                            imageUrl: u,
                            maxHeight: 160,
                            caption:
                                '${widget.paper.subject} 第${q.name}题 · 我的作答切块',
                            galleryItems: gallery,
                            galleryIndex: indexMap['q:${q.name}:crop:$u'] ?? 0,
                          ),
                        ),
                    ],
                    if (q.xbAnswerUrls.isNotEmpty) ...[
                      const Text(
                        '参考 / 优秀解答切块：',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Taste.accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final u in q.xbAnswerUrls)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: OssCropImage(
                            client: widget.client,
                            imageUrl: u,
                            maxHeight: 160,
                            caption:
                                '${widget.paper.subject} 第${q.name}题 · 优秀解答',
                            galleryItems: gallery,
                            galleryIndex: indexMap['q:${q.name}:xb:$u'] ?? 0,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (widgets.isEmpty) {
      widgets.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              '该场考试学校未上传独立原卷切块，请在「批改合成」页查看完整答题卡原图',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Taste.muted),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  /// Sub-Tab 2: Detailed Per-Question Table
  List<Widget> _buildQuestionsScoreTableView(PaperInspectionData data) {
    return [
      for (final q in data.questions)
        Container(
          key: _questionKeys[q.name],
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _highlightedQName == q.name ? Taste.raised : Taste.surface,
            borderRadius: BorderRadius.circular(Taste.radiusControl),
            border: Border.all(
              color: _highlightedQName == q.name ? Taste.accent : Taste.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (ctx, box) {
                  final compact = box.maxWidth < 420;
                  final title = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '第 ${q.name} 题',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Taste.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TastePill(
                        label: q.type == 2 ? '客观题' : '主观题',
                        tone: TastePillTone.neutral,
                      ),
                    ],
                  );
                  final score = TastePill(
                    label: '${q.scoreS} / ${round1(q.manfen)}分',
                    tone: q.isFullScore
                        ? TastePillTone.positive
                        : (q.isZeroScore
                            ? TastePillTone.negative
                            : TastePillTone.warning),
                  );
                  return compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [title, const SizedBox(height: 4), score],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [Expanded(child: title), score],
                        );
                },
              ),
              if (q.type == 2 ||
                  q.myAnswer.isNotEmpty ||
                  q.answer.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '我的作答：${q.myAnswer.isEmpty ? "—" : q.myAnswer}   ·   标准答案：${q.answer.isEmpty ? "—" : q.answer}',
                  style: const TextStyle(fontSize: 12, color: Taste.muted),
                ),
              ],
              if (q.knowledges.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final k in q.knowledges)
                      TastePill(label: k, tone: TastePillTone.blue),
                  ],
                ),
              ],
              if (q.cropUrls.isNotEmpty) ...[
                const SizedBox(height: 6),
                OssCropImage(
                  client: widget.client,
                  imageUrl: q.cropUrls.first,
                  maxHeight: 110,
                  caption: '${widget.paper.subject} 第${q.name}题 作答切块',
                ),
              ],
            ],
          ),
        ),
    ];
  }

  Widget _buildSubTab(int idx, String label) {
    final active = _subTab == idx;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _subTab = idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? Taste.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? Taste.text : Taste.muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolBtn(
    String label, {
    required VoidCallback? onTap,
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Taste.radiusControl),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Taste.pillPosBg : Taste.surface,
          borderRadius: BorderRadius.circular(Taste.radiusControl),
          border: Border.all(
            color: active ? const Color(0xFFA7F3D0) : Taste.control,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: active
                ? Taste.pillPosInk
                : (onTap == null ? Taste.faint : Taste.text),
          ),
        ),
      ),
    );
  }
}
