part of '../taste_widgets.dart';

class WrongNotebookPanel extends StatefulWidget {
  final HfsUpstreamClient client;
  final HfsAccount account;
  final DashboardData dashboard;
  final void Function(String examId, String paperId, String subject)
      onOpenPaperByIds;

  const WrongNotebookPanel({
    super.key,
    required this.client,
    required this.account,
    required this.dashboard,
    required this.onOpenPaperByIds,
  });

  @override
  State<WrongNotebookPanel> createState() => _WrongNotebookPanelState();
}

class _WrongNotebookPanelState extends State<WrongNotebookPanel> {
  String _selectedSubject = '';
  int _filterMode = 0; // 0 = 按考试场次, 1 = 按学期筛选
  String _selectedExamId = '';
  int _selectedSemesterIndex = 0;
  List<WrongQuestionItem> _items = const [];
  bool _loadingItems = false;
  String? _error;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _initSelection();
  }

  @override
  void didUpdateWidget(covariant WrongNotebookPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dashboard != widget.dashboard) {
      _initSelection();
    }
  }

  void _initSelection() {
    final list = widget.dashboard.wrongOverview;
    if (list.isEmpty) return;
    if (!list.any((s) => s.subject == _selectedSubject)) {
      _selectedSubject = list.first.subject;
    }
    final curSubj = list.firstWhere(
      (s) => s.subject == _selectedSubject,
      orElse: () => list.first,
    );
    if (curSubj.exams.isNotEmpty &&
        !curSubj.exams.any((e) => e.examId == _selectedExamId)) {
      _selectedExamId = curSubj.exams.first.examId;
    }
    if (_selectedSemesterIndex >= curSubj.semesters.length) {
      _selectedSemesterIndex = 0;
    }
    _loadWrongItems();
  }

  Future<void> _loadWrongItems({bool allowCache = true}) async {
    final list = widget.dashboard.wrongOverview;
    if (list.isEmpty || _selectedSubject.isEmpty) {
      return;
    }
    final curSubj = list.firstWhere(
      (s) => s.subject == _selectedSubject,
      orElse: () => list.first,
    );
    final reqToken = ++_requestToken;
    final reqSubject = _selectedSubject;
    final reqMode = _filterMode;
    final reqExamId = _selectedExamId;
    final reqSemIdx = _selectedSemesterIndex;
    final stuId = widget.dashboard.currentStudent?.studentId ??
        widget.account.activeStudentId;

    setState(() {
      _loadingItems = true;
      _error = null;
    });

    try {
      List<WrongQuestionItem> res = const [];
      if (reqMode == 1 && curSubj.semesters.isNotEmpty) {
        final sem =
            curSubj.semesters[reqSemIdx.clamp(0, curSubj.semesters.length - 1)];
        if (sem.startMs > 0 && sem.endMs > 0) {
          res = await widget.client.fetchWrongSemesterItems(
            account: widget.account,
            studentId: stuId,
            subject: reqSubject,
            startMs: sem.startMs,
            endMs: sem.endMs,
            allowCache: allowCache,
          );
        } else {
          // Fallback: aggregate exams belonging to this subject
          final matchingExams = curSubj.exams.take(3);
          final agg = <WrongQuestionItem>[];
          for (final ex in matchingExams) {
            final subRes = await widget.client.fetchWrongExamItems(
              account: widget.account,
              studentId: stuId,
              subject: reqSubject,
              examId: ex.examId,
              allowCache: allowCache,
            );
            agg.addAll(subRes);
          }
          res = agg;
        }
      } else if (reqExamId.isNotEmpty) {
        res = await widget.client.fetchWrongExamItems(
          account: widget.account,
          studentId: stuId,
          subject: reqSubject,
          examId: reqExamId,
          allowCache: allowCache,
        );
      }

      if (!mounted ||
          reqToken != _requestToken ||
          _selectedSubject != reqSubject ||
          _filterMode != reqMode ||
          (reqMode == 0 && _selectedExamId != reqExamId) ||
          (reqMode == 1 && _selectedSemesterIndex != reqSemIdx)) {
        return;
      }
      setState(() {
        _items = res;
        _loadingItems = false;
      });
    } catch (e) {
      if (!mounted || reqToken != _requestToken) return;
      setState(() {
        _loadingItems = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dash = widget.dashboard;
    final overviews = dash.wrongOverview;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Subject & Exam Selector Panel
        Container(
          decoration: BoxDecoration(
            color: Taste.surface,
            borderRadius: BorderRadius.circular(Taste.radiusCard),
            border: Border.all(color: Taste.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Text(
                      '错题本深度复盘 · 待复习总计 ${dash.totalWrong} 题',
                      style: const TextStyle(
                        fontFamily: Taste.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Taste.text,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TastePill(
                          label:
                              '已解锁 ${dash.unlockedSubjects}/${dash.totalSubjects} 科',
                          tone: TastePillTone.positive,
                        ),
                        OutlinedButton.icon(
                          onPressed: _loadingItems
                              ? null
                              : () => _loadWrongItems(allowCache: false),
                          icon: const Icon(Icons.refresh, size: 14),
                          label: const Text('刷新错题',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Taste.border),
              if (overviews.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            'assets/images/empty_wrong_book.png',
                            width: 136,
                            height: 136,
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, st) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '当前学生暂无错题本记录',
                          style: TextStyle(color: Taste.muted),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '选择科目：',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Taste.muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in overviews)
                            ChoiceChip(
                              selected: s.subject == _selectedSubject,
                              label: Text(
                                '${s.subject} (${s.noReview}题 · ${s.examCount}场)',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onSelected: (_) {
                                setState(() {
                                  _selectedSubject = s.subject;
                                  if (s.exams.isNotEmpty) {
                                    _selectedExamId = s.exams.first.examId;
                                  }
                                });
                                _loadWrongItems();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            '筛选维度：',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Taste.muted,
                            ),
                          ),
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            selected: _filterMode == 0,
                            label: const Text('按考试场次',
                                style: TextStyle(fontSize: 12)),
                            onSelected: (_) {
                              setState(() => _filterMode = 0);
                              _loadWrongItems();
                            },
                          ),
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            selected: _filterMode == 1,
                            label: const Text('按学期汇总',
                                style: TextStyle(fontSize: 12)),
                            onSelected: (_) {
                              setState(() => _filterMode = 1);
                              _loadWrongItems();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (ctx) {
                          final curSubj = overviews.firstWhere(
                            (s) => s.subject == _selectedSubject,
                            orElse: () => overviews.first,
                          );
                          if (_filterMode == 1) {
                            if (curSubj.semesters.isEmpty) {
                              return const Text(
                                '该科目暂无学期汇总段',
                                style:
                                    TextStyle(fontSize: 12, color: Taste.muted),
                              );
                            }
                            return IsolatedHorizontalScroll(
                              child: Row(
                                children: [
                                  for (var sIdx = 0;
                                      sIdx < curSubj.semesters.length;
                                      sIdx++)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        selected:
                                            sIdx == _selectedSemesterIndex,
                                        label: Text(
                                          '${curSubj.semesters[sIdx].name} (错${curSubj.semesters[sIdx].wrongNum}题)',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        onSelected: (_) {
                                          setState(() =>
                                              _selectedSemesterIndex = sIdx);
                                          _loadWrongItems();
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }
                          return IsolatedHorizontalScroll(
                            child: Row(
                              children: [
                                for (final ex in curSubj.exams)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      selected: ex.examId == _selectedExamId,
                                      label: Text(
                                        '${ex.examName} (错${ex.wrongNum}题)',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      onSelected: (_) {
                                        setState(
                                            () => _selectedExamId = ex.examId);
                                        _loadWrongItems();
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Wrong Question Cards Stream
        if (_loadingItems)
          Container(
            padding: const EdgeInsets.all(36),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Taste.surface,
              borderRadius: BorderRadius.circular(Taste.radiusCard),
              border: Border.all(color: Taste.border),
            ),
            child: const Column(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Taste.accent,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '正在拉取该场考试的错题原卷题干与作答图片…',
                  style: TextStyle(fontSize: 13, color: Taste.muted),
                ),
              ],
            ),
          )
        else if (_error != null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Taste.pillNegBg,
              borderRadius: BorderRadius.circular(Taste.radiusCard),
            ),
            child: Text(
              _error!,
              style: const TextStyle(color: Taste.pillNegInk),
            ),
          )
        else if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Taste.surface,
              borderRadius: BorderRadius.circular(Taste.radiusCard),
              border: Border.all(color: Taste.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/empty_wrong_book.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '本场考试该科目暂无错题明细',
                  style: TextStyle(color: Taste.muted),
                ),
              ],
            ),
          )
        else ...[
          (() {
            final gallery = <LightboxGalleryItem>[];
            final indexMap = <String, int>{};
            for (final it in _items) {
              for (final u in it.stemPictures) {
                indexMap.putIfAbsent('${it.id}:stem:$u', () => gallery.length);
                gallery.add(
                  LightboxGalleryItem(
                    imageUrl: u,
                    caption:
                        '${it.examName} · $_selectedSubject 第${it.shortName}题 原卷题干',
                  ),
                );
              }
              for (final u in it.myAnswerPictures) {
                indexMap.putIfAbsent('${it.id}:ans:$u', () => gallery.length);
                gallery.add(
                  LightboxGalleryItem(
                    imageUrl: u,
                    caption:
                        '${it.examName} · $_selectedSubject 第${it.shortName}题 我的作答',
                  ),
                );
              }
              for (final u in it.xbAnswerPictures) {
                indexMap.putIfAbsent('${it.id}:xb:$u', () => gallery.length);
                gallery.add(
                  LightboxGalleryItem(
                    imageUrl: u,
                    caption:
                        '${it.examName} · $_selectedSubject 第${it.shortName}题 优秀解答',
                  ),
                );
              }
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _items.length; i++)
                  _buildWrongQuestionCard(
                    i + 1,
                    _items[i],
                    gallery: gallery,
                    indexMap: indexMap,
                  ),
              ],
            );
          })(),
        ],

        const SizedBox(height: 16),
        // 3. Account & Upstream Diagnostics Details
        _buildAccountDiagnosticsPanel(dash),
      ],
    );
  }

  Widget _buildWrongQuestionCard(
    int idx,
    WrongQuestionItem item, {
    required List<LightboxGalleryItem> gallery,
    required Map<String, int> indexMap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Taste.surface,
        borderRadius: BorderRadius.circular(Taste.radiusCard),
        border: Border.all(color: Taste.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TastePill(
                      label: '#$idx · 第 ${item.shortName} 题',
                      tone: TastePillTone.negative,
                    ),
                    TastePill(
                      label: item.style,
                      tone: TastePillTone.neutral,
                    ),
                    Text(
                      item.examName,
                      style: const TextStyle(fontSize: 12, color: Taste.muted),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '得分 ${round1(item.myScore)} / ${round1(item.score)}分',
                      style: Taste.numStyle(
                        size: 13,
                        weight: FontWeight.w700,
                        color: Taste.negative,
                      ),
                    ),
                    if (item.classAvgScore > 0)
                      Text(
                        '(班均 ${round2(item.classAvgScore)}分)',
                        style: Taste.numStyle(size: 12, color: Taste.muted),
                      ),
                    if (item.paperId.isNotEmpty)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => widget.onOpenPaperByIds(
                          item.examId,
                          item.paperId,
                          _selectedSubject,
                        ),
                        icon: const Icon(Icons.description_outlined, size: 14),
                        label: const Text('调阅整卷答题卡',
                            style: TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.knowledges.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      const Text(
                        '考查知识点：',
                        style: TextStyle(fontSize: 12, color: Taste.muted),
                      ),
                      for (final k in item.knowledges)
                        TastePill(label: k, tone: TastePillTone.blue),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (item.myAnswer.isNotEmpty || item.answer.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Taste.raised,
                      borderRadius: BorderRadius.circular(Taste.radiusControl),
                    ),
                    child: Wrap(
                      spacing: 20,
                      runSpacing: 6,
                      children: [
                        Text(
                          '我的作答：${item.myAnswer.isEmpty ? "未填/见下图" : item.myAnswer}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Taste.negative,
                          ),
                        ),
                        if (item.answer.isNotEmpty)
                          Text(
                            '标准答案：${item.answer}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Taste.positive,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (item.stemPictures.isNotEmpty) ...[
                  const Text(
                    '原卷题干扫描（点击图片可全屏无损放大）：',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Taste.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final u in item.stemPictures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OssCropImage(
                        client: widget.client,
                        imageUrl: u,
                        maxHeight: 220,
                        caption:
                            '${item.examName} · $_selectedSubject 第${item.shortName}题 原卷题干',
                        galleryItems: gallery,
                        galleryIndex: indexMap['${item.id}:stem:$u'] ?? 0,
                      ),
                    ),
                ],
                if (item.myAnswerPictures.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '我的答题卡作答裁切：',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Taste.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final u in item.myAnswerPictures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OssCropImage(
                        client: widget.client,
                        imageUrl: u,
                        maxHeight: 180,
                        caption:
                            '${item.examName} · $_selectedSubject 第${item.shortName}题 我的作答',
                        galleryItems: gallery,
                        galleryIndex: indexMap['${item.id}:ans:$u'] ?? 0,
                      ),
                    ),
                ],
                if (item.xbAnswerPictures.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '优秀作答 / 参考解析示例：',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Taste.accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final u in item.xbAnswerPictures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OssCropImage(
                        client: widget.client,
                        imageUrl: u,
                        maxHeight: 180,
                        caption:
                            '${item.examName} · $_selectedSubject 第${item.shortName}题 优秀解答',
                        galleryItems: gallery,
                        galleryIndex: indexMap['${item.id}:xb:$u'] ?? 0,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountDiagnosticsPanel(DashboardData dash) {
    return Container(
      decoration: BoxDecoration(
        color: Taste.surface,
        borderRadius: BorderRadius.circular(Taste.radiusCard),
        border: Border.all(color: Taste.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          title: const Text(
            '好分数账号权益与学校门禁配置明细',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Taste.text,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                TastePill(
                  label: '会员状态: ${dash.isMember ? "VIP会员" : "普通账号"}',
                  tone: dash.isMember
                      ? TastePillTone.positive
                      : TastePillTone.neutral,
                ),
                TastePill(
                  label: '单次考试会员: ${dash.isExamMember ? "是" : "否"}',
                  tone: TastePillTone.neutral,
                ),
                TastePill(
                  label:
                      '错题解锁科目: ${dash.unlockedSubjects}/${dash.totalSubjects}',
                  tone: TastePillTone.blue,
                ),
                TastePill(
                  label: '剩余拍照上传额度: ${dash.uploadRemain}',
                  tone: TastePillTone.neutral,
                ),
                TastePill(
                  label: '剩余错题导出额度: ${dash.exportRemain}',
                  tone: TastePillTone.neutral,
                ),
              ],
            ),
            if (dash.rawSchoolHidden.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Taste.raised,
                  borderRadius: BorderRadius.circular(Taste.radiusControl),
                ),
                child: Text(
                  '学校隐藏策略配置 (/v2/config/school/hidden-config)：\n${const JsonEncoder.withIndent("  ").convert(dash.rawSchoolHidden)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Taste.muted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Classmates Roster + Direct StudentId Bind Dialog
/// Combines `GET /v2/students/classmates` and `POST /v2/native-users/bind-students`
