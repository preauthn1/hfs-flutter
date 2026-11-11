part of '../main.dart';

extension _HfsHomeGradesStageExt on _HfsHomeScreenState {
  /// Main Grades & Subject Papers Workbench (#tab-grades)
  Widget _buildGradesStage(bool isDesktop) {
    final dash = _dashboard;
    if (dash == null) {
      return const Center(
        child: Text('请在左侧选择账号与学生', style: TextStyle(color: Taste.muted)),
      );
    }

    final stu = dash.currentStudent ?? dash.account.activeStudent;
    final exams = dash.exams;
    final curExam = _selectedExam;
    final prevExam = (curExam != null && exams.length > 1)
        ? (() {
            final idx = exams.indexWhere((e) => e.examId == curExam.examId);
            return (idx >= 0 && idx + 1 < exams.length) ? exams[idx + 1] : null;
          })()
        : null;

    final filteredExams = exams.where((ex) {
      if (_examFilterQuery.trim().isEmpty) return true;
      return ex.name.toLowerCase().contains(_examFilterQuery.toLowerCase());
    }).toList();

    final allSubjects = dash.discoveredSubjects;
    final visibleSubjects =
        allSubjects.where((s) => !_hiddenSubjects.contains(s)).toList();

    return ListView(
      controller: _centerScrollCtrl,
      primary: false,
      padding: EdgeInsets.all(isDesktop ? 20 : 12),
      children: [
        // 1. Student Banner & 5-Cell Divided KPI Strip
        Container(
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
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  color: Taste.surface,
                  border: Border(bottom: BorderSide(color: Taste.border)),
                ),
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    final compact = box.maxWidth < 420;
                    final studentHeader = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                'assets/images/student_medallion.png',
                                width: 32,
                                height: 32,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, st) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: compact ? box.maxWidth - 44 : 300,
                              ),
                              child: Text(
                                stu?.studentName ?? dash.account.displayLabel,
                                maxLines: compact ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Taste.text,
                                ),
                              ),
                            ),
                            if (stu != null &&
                                (stu.grade.isNotEmpty ||
                                    stu.className.isNotEmpty))
                              TastePill(
                                label: '${stu.grade}${stu.className}',
                                tone: TastePillTone.positive,
                              ),
                            TastePill(
                              label: dash.isMember ? 'VIP已开通' : '普通用户',
                              tone: dash.isMember
                                  ? TastePillTone.warning
                                  : TastePillTone.neutral,
                            ),
                            if (curExam != null && curExam.isPartial)
                              TastePill(
                                label:
                                    '部分科目已出分（${curExam.reportedPaperCount}科）',
                                tone: TastePillTone.warning,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (stu != null && stu.schoolName.isNotEmpty)
                              stu.schoolName,
                            if (stu != null && stu.xuehao.isNotEmpty)
                              '准考证/考号 ${stu.xuehao}',
                            '归属账号 ${dash.account.displayLabel}',
                          ].join(' · '),
                          maxLines: compact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontSize: 12, color: Taste.muted),
                        ),
                      ],
                    );
                    final headerActions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (exams.isNotEmpty)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: compact ? box.maxWidth : 280,
                            ),
                            child: SizedBox(
                              height: compact ? 38 : 34,
                              child: DropdownButtonFormField2<String>(
                                key: ValueKey(
                                  'top_exam_sel_${curExam?.examId ?? exams.first.examId}',
                                ),
                                value:
                                    curExam?.examId ?? exams.first.examId,
                                isExpanded: true,
                                isDense: true,
                                iconStyleData: Taste.dropdownIconStyle,
                                dropdownStyleData: Taste.dropdownStyle(
                                  ctx,
                                  maxHeight: 340,
                                  dropdownWidth: Taste.resolveDropdownMenuWidth(
                                    ctx,
                                    preferredWidth:
                                        compact ? math.max(250.0, box.maxWidth) : 340,
                                  ),
                                ),
                                menuItemStyleData: Taste.menuItemStyle(ctx),
                                dropdownSearchData: DropdownSearchData<String>(
                                  searchController: _examDropdownSearchCtrl,
                                  searchInnerWidgetHeight: 46,
                                  searchInnerWidget: Container(
                                    height: 46,
                                    padding:
                                        const EdgeInsets.fromLTRB(8, 8, 8, 4),
                                    child: TextField(
                                      controller: _examDropdownSearchCtrl,
                                      style: const TextStyle(fontSize: 12),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: '搜索考试名称或日期…',
                                        prefixIcon: const Icon(Icons.search,
                                            size: 15),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              Taste.radiusControl),
                                        ),
                                      ),
                                    ),
                                  ),
                                  searchMatchFn: (item, searchValue) {
                                    final q = searchValue.trim().toLowerCase();
                                    if (q.isEmpty) return true;
                                    final matchEx = exams
                                        .where((e) => e.examId == item.value)
                                        .toList();
                                    if (matchEx.isEmpty) return false;
                                    final ex = matchEx.first;
                                    final label =
                                        '${formatDateMs(ex.time)} ${ex.name} ${ex.scoreS}'
                                            .toLowerCase();
                                    return label.contains(q);
                                  },
                                ),
                                onMenuStateChange: (isOpen) {
                                  if (!isOpen) {
                                    _examDropdownSearchCtrl.clear();
                                  }
                                },
                                selectedItemBuilder: (context) => [
                                  for (final ex in exams)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '${formatDateMs(ex.time)} · ${ex.name} (${ex.scoreS}分)',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Taste.text,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        Taste.radiusControl),
                                  ),
                                ),
                                items: [
                                  for (final ex in exams)
                                    DropdownMenuItem(
                                      value: ex.examId,
                                      child: Text(
                                        '${formatDateMs(ex.time)} · ${ex.name} (${ex.scoreS}分)',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          height: 1.25,
                                          color: Taste.text,
                                        ),
                                      ),
                                    ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    _setHomeState(() {
                                      _selectedExamId = val;
                                      final ex = exams.firstWhere(
                                        (e) => e.examId == val,
                                        orElse: () => exams.first,
                                      );
                                      _inspectingExam = ex;
                                      if (ex.papers.isNotEmpty) {
                                        final prevSubj =
                                            _inspectingPaper?.subject ?? '';
                                        _inspectingPaper = ex.papers.firstWhere(
                                          (p) =>
                                              prevSubj.isNotEmpty &&
                                              p.subject == prevSubj,
                                          orElse: () => ex.papers.first,
                                        );
                                        _inspectorCollapsed = false;
                                      }
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        _buildTopBarBtn(
                          label: '同班名册与直绑',
                          icon: Icons.people_outline,
                          onTap: _openClassmatesRosterModal,
                        ),
                      ],
                    );
                    return compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              studentHeader,
                              const SizedBox(height: 10),
                              headerActions,
                            ],
                          )
                        : Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 10,
                            children: [studentHeader, headerActions],
                          );
                  },
                ),
              ),
              _buildDividedKpiStrip(dash, curExam, prevExam, isDesktop),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 1.5 Interactive Score Trend Line Chart & Subject Balance Analytics
        if (exams.isNotEmpty) ...[
          ScoreTrendAnalyticsCard(
            dashboard: dash,
            selectedExam: curExam,
            selectedSubject: _inspectingPaper?.subject,
            onSelectExam: _selectExamRow,
          ),
          const SizedBox(height: 20),
        ],

        // 2. Score Matrix Table Panel (Sticky Date/Name/Total + 2px Ratio Bar + Subject Filter)
        Container(
          decoration: BoxDecoration(
            color: Taste.surface,
            borderRadius: BorderRadius.circular(Taste.radiusCard),
            border: Border.all(color: Taste.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    final search = SizedBox(
                      width: box.maxWidth < 420 ? double.infinity : 200,
                      height: 30,
                      child: TextField(
                        onChanged: (v) => _setHomeState(() => _examFilterQuery = v),
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: '筛选考试名称…',
                          prefixIcon: const Icon(Icons.search, size: 14),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(Taste.radiusControl),
                          ),
                        ),
                      ),
                    );
                    final heading = Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          '历次考试总分与单科矩阵',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Taste.text,
                          ),
                        ),
                        Text(
                          isDesktop
                              ? '点击任意单科分数立即在右侧调阅高清答题卡'
                              : '点击任意单科分数立即调阅高清答题卡（可左右滑动表格）',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Taste.muted,
                          ),
                        ),
                      ],
                    );
                    if (box.maxWidth < 420) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          heading,
                          const SizedBox(height: 8),
                          search,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 12),
                        search,
                      ],
                    );
                  },
                ),
              ),
              if (allSubjects.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Taste.raised,
                    border: Border(
                      top: BorderSide(color: Taste.border),
                      bottom: BorderSide(color: Taste.border),
                    ),
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        '显示科目列：',
                        style: TextStyle(fontSize: 12, color: Taste.muted),
                      ),
                      for (final subj in allSubjects)
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          label:
                              Text(subj, style: const TextStyle(fontSize: 11)),
                          selected: !_hiddenSubjects.contains(subj),
                          onSelected: (v) {
                            _setHomeState(() {
                              if (v) {
                                _hiddenSubjects.remove(subj);
                              } else {
                                _hiddenSubjects.add(subj);
                              }
                            });
                          },
                        ),
                      if (_hiddenSubjects.isNotEmpty)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: const Text('恢复全部',
                              style: TextStyle(fontSize: 11)),
                          onPressed: () =>
                              _setHomeState(() => _hiddenSubjects.clear()),
                        ),
                    ],
                  ),
                )
              else
                const Divider(height: 1, color: Taste.border),
              _buildScoreMatrixTable(
                filteredExams,
                visibleSubjects,
                curExam,
                isDesktop: isDesktop,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 3. Selected Exam Subject Detail Cards Grid (.papers-grid -> .paper-tile)
        if (curExam != null)
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
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        '${curExam.name} · 各科试卷与答题卡调阅',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Taste.text,
                        ),
                      ),
                      Text(
                        '考试时间：${formatDateMs(curExam.time)} · 已出分科目：${curExam.papers.length} 科',
                        style:
                            const TextStyle(fontSize: 12, color: Taste.muted),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Taste.border),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (ctx, box) {
                      final cols = (box.maxWidth / 220).floor().clamp(1, 5);
                      final tileW = (box.maxWidth - (cols - 1) * 12) / cols;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final p in curExam.papers)
                            SizedBox(
                              width: tileW,
                              child: _buildSubjectPaperTile(curExam, p),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDividedKpiStrip(
    DashboardData dash,
    ExamRecord? curExam,
    ExamRecord? prevExam,
    bool isDesktop,
  ) {
    final scoreStr = curExam?.scoreS ?? '—';
    final manfenStr = (curExam != null && curExam.manfen > 0)
        ? '/ ${round1(curExam.manfen)}'
        : '';
    String deltaText = curExam != null ? curExam.name : '暂无考试';
    Color deltaColor = Taste.muted;
    if (curExam != null &&
        prevExam != null &&
        !curExam.isPartial &&
        !prevExam.isPartial &&
        curExam.manfen > 0 &&
        prevExam.manfen > 0) {
      final diff = round1(curExam.score - prevExam.score);
      if (diff > 0) {
        deltaText = '较上次 +$diff 分';
        deltaColor = Taste.positive;
      } else if (diff < 0) {
        deltaText = '较上次 $diff 分';
        deltaColor = Taste.negative;
      } else {
        deltaText = '与上次持平';
      }
    }

    final ratioVal = curExam?.ratio != null ? '${curExam!.ratio}%' : '—';
    final rankVal = curExam != null && curExam.classRankS.isNotEmpty
        ? curExam.classRankS
        : (curExam != null && curExam.gradeRankS.isNotEmpty
            ? '年排 ${curExam.gradeRankS}'
            : '学校已隐藏');

    final cells = <Widget>[
      _buildKpiCell(
        label: '所选考试总分',
        value: scoreStr,
        subValue: manfenStr,
        delta: deltaText,
        deltaColor: deltaColor,
        isPrimary: true,
      ),
      _buildKpiCell(
        label: '总得分率',
        value: ratioVal,
        subValue: '',
        delta: curExam != null ? '已出卷 ${curExam.reportedPaperCount} 科' : '—',
      ),
      _buildKpiCell(
        label: '班级 / 年级参考名次',
        value: rankVal,
        subValue: '',
        delta: curExam != null && curExam.gradeRankS.isNotEmpty
            ? '年级名次 ${curExam.gradeRankS}'
            : '学校关闭排名时按卷面核对',
      ),
      _buildKpiCell(
        label: '累计采集考试',
        value: '${dash.exams.length}',
        subValue: '场',
        delta: '支持全部历史归档调阅',
      ),
      _buildKpiCell(
        label: '错题本待复习',
        value: '${dash.totalWrong}',
        subValue: '题',
        delta: '覆盖 ${dash.wrongOverview.length} 个学科',
      ),
    ];

    if (!isDesktop) {
      return Column(
        children: [
          for (var r = 0; r < cells.length; r += 2) ...[
            if (r > 0) const Divider(height: 1, color: Taste.border),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cells[r]),
                  if (r + 1 < cells.length) ...[
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Taste.border,
                    ),
                    Expanded(child: cells[r + 1]),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0)
              const VerticalDivider(
                  width: 1, thickness: 1, color: Taste.border),
            Expanded(child: cells[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildKpiCell({
    required String label,
    required String value,
    required String subValue,
    required String delta,
    Color deltaColor = Taste.muted,
    bool isPrimary = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Taste.muted,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: Taste.numStyle(
                    size: 24,
                    weight: FontWeight.w500,
                    color: isPrimary ? Taste.accent : Taste.text,
                  ),
                ),
                if (subValue.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    subValue,
                    style: Taste.numStyle(
                      size: 13,
                      weight: FontWeight.w400,
                      color: Taste.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            delta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight:
                  deltaColor == Taste.muted ? FontWeight.w400 : FontWeight.w500,
              color: deltaColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreMatrixTable(
    List<ExamRecord> exams,
    List<String> subjects,
    ExamRecord? selectedExam, {
    required bool isDesktop,
  }) {
    if (exams.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text('无匹配的考试记录', style: TextStyle(color: Taste.muted)),
        ),
      );
    }

    final double dateColW = isDesktop ? 112 : 84;
    final double nameColW = isDesktop ? 210 : 126;
    final double totalColW = isDesktop ? 148 : 88;
    final double subjColW = isDesktop ? 136 : 92;
    final double wrongColW = isDesktop ? 84 : 62;
    final double minTableW = dateColW +
        nameColW +
        totalColW +
        subjects.length * subjColW +
        wrongColW;

    final showMobile = MediaQuery.sizeOf(context).width < 860;
    final narrow = MediaQuery.sizeOf(context).width < 420;
    if (showMobile && narrow) {
      return _buildMobileScoreCards(exams, subjects, selectedExam);
    }
    return IsolatedHorizontalScroll(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: math.max(isDesktop ? 780 : 320, minTableW),
        ),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: <int, TableColumnWidth>{
            0: FixedColumnWidth(dateColW), // 日期
            1: FixedColumnWidth(nameColW), // 考试名称
            2: FixedColumnWidth(totalColW), // 总分
            for (var i = 0; i < subjects.length; i++)
              i + 3: FixedColumnWidth(subjColW),
            subjects.length + 3: FixedColumnWidth(wrongColW), // 错题数
          },
          border: const TableBorder(
            horizontalInside: BorderSide(color: Taste.rule),
          ),
          children: [
            TableRow(
              decoration: const BoxDecoration(
                color: Taste.surface,
                border: Border(bottom: BorderSide(color: Taste.border)),
              ),
              children: [
                _matrixHeaderCell('日期', compact: !isDesktop),
                _matrixHeaderCell('考试名称', compact: !isDesktop),
                _matrixHeaderCell(
                  '总分',
                  alignRight: true,
                  rightBorder: true,
                  compact: !isDesktop,
                ),
                for (final subj in subjects)
                  _matrixHeaderCell(
                    subj,
                    alignRight: true,
                    compact: !isDesktop,
                  ),
                _matrixHeaderCell(
                  '错题',
                  alignRight: true,
                  compact: !isDesktop,
                ),
              ],
            ),
            for (var rIdx = 0; rIdx < exams.length; rIdx++)
              _buildScoreMatrixRow(
                exams[rIdx],
                rIdx + 1 < exams.length ? exams[rIdx + 1] : null,
                subjects,
                isSelectedExam: exams[rIdx].examId == selectedExam?.examId,
                compact: !isDesktop,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileScoreCards(
    List<ExamRecord> exams,
    List<String> subjects,
    ExamRecord? selectedExam,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < exams.length; index++)
          _buildMobileScoreCard(
            exams[index],
            index + 1 < exams.length ? exams[index + 1] : null,
            subjects,
            selected: exams[index].examId == selectedExam?.examId,
          ),
      ],
    );
  }

  Widget _buildMobileScoreCard(
    ExamRecord exam,
    ExamRecord? olderExam,
    List<String> subjects, {
    required bool selected,
  }) {
    final paperBySubject = <String, PaperScore>{
      for (final paper in exam.papers) paper.subject: paper,
    };
    String trend = '';
    Color trendColor = Taste.muted;
    if (olderExam != null &&
        !exam.isPartial &&
        !olderExam.isPartial &&
        exam.score != olderExam.score) {
      if (exam.score > olderExam.score) {
        trend = '↑ 较上场上升';
        trendColor = Taste.positive;
      } else {
        trend = '↓ 较上场下降';
        trendColor = Taste.negative;
      }
    }
    return InkWell(
      onTap: () => _selectExamRow(exam),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? Taste.raised : Taste.surface,
          borderRadius: BorderRadius.circular(Taste.radiusControl),
          border: Border.all(
            color: selected ? Taste.accent : Taste.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    exam.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Taste.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatDateMs(exam.time),
                  style: Taste.numStyle(size: 11, color: Taste.muted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  '${exam.scoreS}${exam.manfen > 0 ? '/${round1(exam.manfen)}' : ''}',
                  style: Taste.numStyle(
                    size: 20,
                    weight: FontWeight.w700,
                    color: Taste.text,
                  ),
                ),
                if (trend.isNotEmpty)
                  Text(
                    trend,
                    style: TextStyle(fontSize: 11, color: trendColor),
                  ),
                Text(
                  '错题 ${exam.totalWrong}',
                  style: const TextStyle(fontSize: 11, color: Taste.muted),
                ),
              ],
            ),
            if (subjects.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final subject in subjects.take(6))
                    _buildMobileSubjectScoreChip(
                      subject,
                      paperBySubject[subject],
                    ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            const Text(
              '点击查看考试详情与答题卡',
              style: TextStyle(fontSize: 11, color: Taste.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileSubjectScoreChip(String subject, PaperScore? paper) {
    final value = paper == null
        ? '未出分'
        : '${paper.scoreS}${paper.manfen > 0 ? '/${round1(paper.manfen)}' : ''}';
    return Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Taste.raised,
        borderRadius: BorderRadius.circular(Taste.radiusControl),
        border: Border.all(color: Taste.border),
      ),
      child: Text(
        '$subject $value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: Taste.text),
      ),
    );
  }

  Widget _matrixHeaderCell(
    String text, {
    bool alignRight = false,
    bool rightBorder = false,
    bool compact = false,
  }) {
    return Container(
      height: 36,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      decoration: rightBorder
          ? const BoxDecoration(
              border: Border(right: BorderSide(color: Taste.border)),
            )
          : null,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Taste.muted,
        ),
      ),
    );
  }

  void _selectExamRow(ExamRecord exam, {String? preferredSubject}) {
    _setHomeState(() {
      _selectedExamId = exam.examId;
      _inspectingExam = exam;
      if (exam.papers.isNotEmpty) {
        final wantSubj = (preferredSubject != null &&
                preferredSubject.isNotEmpty &&
                preferredSubject != '总分')
            ? preferredSubject
            : (_inspectingPaper?.subject ?? '');
        _inspectingPaper = exam.papers.firstWhere(
          (p) => wantSubj.isNotEmpty && p.subject == wantSubj,
          orElse: () => exam.papers.first,
        );
        _inspectorCollapsed = false;
      }
    });
  }

  TableRow _buildScoreMatrixRow(
    ExamRecord exam,
    ExamRecord? olderExam,
    List<String> subjects, {
    required bool isSelectedExam,
    bool compact = false,
  }) {
    final paperBySubj = <String, PaperScore>{};
    for (final p in exam.papers) {
      paperBySubj[p.subject] = p;
    }

    String? trendArrow;
    Color trendColor = Taste.muted;
    if (olderExam != null &&
        !exam.isPartial &&
        !olderExam.isPartial &&
        exam.manfen > 0 &&
        olderExam.manfen > 0) {
      if (exam.score > olderExam.score + 0.05) {
        trendArrow = '↑';
        trendColor = Taste.positive;
      } else if (exam.score < olderExam.score - 0.05) {
        trendArrow = '↓';
        trendColor = Taste.negative;
      }
    }

    return TableRow(
      decoration: BoxDecoration(
        color: isSelectedExam ? Taste.raised : Taste.surface,
      ),
      children: [
        // Date cell
        InkWell(
          onTap: () => _selectExamRow(exam),
          child: Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
            alignment: Alignment.centerLeft,
            child: Text(
              formatDateMs(exam.time),
              style:
                  Taste.numStyle(size: compact ? 11 : 12, color: Taste.muted),
            ),
          ),
        ),
        // Exam name cell
        InkWell(
          onTap: () => _selectExamRow(exam),
          child: Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
            alignment: Alignment.centerLeft,
            child: Text(
              exam.name,
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w500,
                color: Taste.text,
              ),
            ),
          ),
        ),
        // Total score cell
        Container(
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
          alignment: Alignment.centerRight,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Taste.border)),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  exam.scoreS,
                  style: Taste.numStyle(
                    size: 14,
                    weight: FontWeight.w700,
                    color: Taste.text,
                  ),
                ),
                if (exam.manfen > 0)
                  Text(
                    '/${round1(exam.manfen)}',
                    style: Taste.numStyle(size: 11, color: Taste.muted),
                  ),
                if (trendArrow != null) ...[
                  const SizedBox(width: 3),
                  Text(
                    trendArrow,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: trendColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Subject cells with ScoreLink Button & 2px Bottom Ratio Bar
        for (final subj in subjects)
          Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 8),
            alignment: Alignment.centerRight,
            child: paperBySubj[subj] == null
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Taste.raised,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '未出分',
                      style: TextStyle(fontSize: 11, color: Taste.faint),
                    ),
                  )
                : _buildScoreLinkButton(exam, paperBySubj[subj]!),
          ),
        // Wrong count cell
        Container(
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
          alignment: Alignment.centerRight,
          child: Text(
            exam.totalWrong > 0 ? '${exam.totalWrong}题' : '—',
            style: Taste.numStyle(
              size: 12,
              color: exam.totalWrong > 0 ? Taste.warning : Taste.muted,
            ),
          ),
        ),
      ],
    );
  }

  /// Score Link Button with Micro Paper Icon & 2px Bottom Ratio Bar (mirrors .score-link)
  Widget _buildScoreLinkButton(ExamRecord exam, PaperScore paper) {
    final isSelectedCell = !_inspectorCollapsed &&
        _inspectingExam?.examId == exam.examId &&
        _inspectingPaper?.paperId == paper.paperId;
    final ratio = paper.ratio ?? 0;
    final Color barColor = ratio >= 85
        ? Taste.positive
        : (ratio >= 60 ? Taste.chart2 : Taste.chart3);

    return InkWell(
      borderRadius: BorderRadius.circular(Taste.radiusControl),
      onTap: () => _openPaperInspection(exam, paper),
      child: Container(
        decoration: BoxDecoration(
          color: isSelectedCell ? Taste.text : Taste.surface,
          borderRadius: BorderRadius.circular(Taste.radiusControl),
          border: Border.all(
            color: isSelectedCell ? Taste.text : Taste.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 4, 7, 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      paper.scoreS,
                      style: Taste.numStyle(
                        size: 12,
                        weight: FontWeight.w700,
                        color: isSelectedCell ? Taste.surface : Taste.text,
                      ),
                    ),
                    if (paper.manfen > 0)
                      Text(
                        '/${round1(paper.manfen)}',
                        style: Taste.numStyle(
                          size: 10,
                          color: isSelectedCell
                              ? const Color(0xFFD1D5DB)
                              : Taste.muted,
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.description_outlined,
                      size: 11,
                      color: isSelectedCell
                          ? const Color(0xFFD1D5DB)
                          : Taste.muted,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              right: 0,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (ratio / 100.0).clamp(0.0, 1.0),
                child: Container(
                  height: 2,
                  color: barColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectPaperTile(ExamRecord exam, PaperScore paper) {
    final isActive = !_inspectorCollapsed &&
        _inspectingExam?.examId == exam.examId &&
        _inspectingPaper?.paperId == paper.paperId;
    final ratio = paper.ratio ?? 0;
    final Color barColor = ratio >= 85
        ? Taste.positive
        : (ratio >= 60 ? Taste.chart2 : Taste.chart3);

    return InkWell(
      borderRadius: BorderRadius.circular(Taste.radiusCard),
      onTap: () => _openPaperInspection(exam, paper),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isActive ? Taste.raised : Taste.surface,
          borderRadius: BorderRadius.circular(Taste.radiusCard),
          border: Border.all(
            color: isActive ? Taste.accent : Taste.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (ctx, box) {
                final compact = box.maxWidth < 420;
                final subject = Text(
                  paper.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Taste.text,
                  ),
                );
                final ratioPill = TastePill(
                  label: paper.ratio != null ? '${paper.ratio}%' : '已出分',
                  tone: ratio >= 85
                      ? TastePillTone.positive
                      : (ratio >= 60
                          ? TastePillTone.blue
                          : TastePillTone.warning),
                );
                return compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          subject,
                          const SizedBox(height: 4),
                          ratioPill
                        ],
                      )
                    : Row(
                        children: [Expanded(child: subject), ratioPill],
                      );
              },
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: Taste.numStyle(
                        size: 20,
                        weight: FontWeight.w500,
                        color: Taste.text,
                      ),
                      children: [
                        TextSpan(text: paper.scoreS),
                        TextSpan(
                          text: ' / ${round1(paper.manfen)}分',
                          style: Taste.numStyle(size: 12, color: Taste.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                if (paper.wrongNum != null && paper.wrongNum! > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '错 ${paper.wrongNum} 题',
                    style: Taste.numStyle(size: 11, color: Taste.negative),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: Taste.raised,
                borderRadius: BorderRadius.circular(999),
              ),
              clipBehavior: Clip.antiAlias,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (ratio / 100.0).clamp(0.0, 1.0),
                child: Container(color: barColor),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Taste.rule)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      '含涂卡/批改/原卷',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Taste.muted),
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '调阅答题卡 →',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Taste.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}
