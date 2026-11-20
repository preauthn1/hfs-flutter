part of '../taste_widgets.dart';

class _ChartPoint {
  final ExamRecord exam;
  final double value;
  final String displayValue;
  final String subtitle;

  const _ChartPoint({
    required this.exam,
    required this.value,
    required this.displayValue,
    required this.subtitle,
  });
}

/// Interactive Score Trend Line Chart + Subject Radar Balance Panel
class ScoreTrendAnalyticsCard extends StatefulWidget {
  final DashboardData dashboard;
  final ExamRecord? selectedExam;
  final String? selectedSubject;
  final void Function(ExamRecord exam, {String? preferredSubject}) onSelectExam;

  const ScoreTrendAnalyticsCard({
    super.key,
    required this.dashboard,
    required this.selectedExam,
    this.selectedSubject,
    required this.onSelectExam,
  });

  @override
  State<ScoreTrendAnalyticsCard> createState() =>
      _ScoreTrendAnalyticsCardState();
}

class _ScoreTrendAnalyticsCardState extends State<ScoreTrendAnalyticsCard> {
  String _metricSubject = '总分';
  bool _usePercentageRatio = false;
  int? _hoveredIndex;

  List<_ChartPoint> _buildPointsForSubject(String subject) {
    // Chronological order (oldest -> newest) by actual exam timestamp.
    // Do NOT rely on the raw list already being newest-first — sort explicitly
    // so the x-axis is always monotonic in time. When a timestamp is missing
    // (time == 0) fall back to reverse source order (reproducing the old
    // newest-first-reversed behaviour) so those points stay stable.
    final src = widget.dashboard.exams;
    final order = <ExamRecord, int>{
      for (var i = 0; i < src.length; i++) src[i]: i,
    };
    final chronological = src.toList()
      ..sort((a, b) {
        if (a.time != 0 && b.time != 0 && a.time != b.time) {
          return a.time.compareTo(b.time);
        }
        return (order[b] ?? 0).compareTo(order[a] ?? 0);
      });
    final pts = <_ChartPoint>[];
    for (final ex in chronological) {
      if (subject == '总分') {
        if (ex.score <= 0 && ex.papers.isEmpty) continue;
        final val = _usePercentageRatio
            ? (ex.ratio ??
                (ex.manfen > 0 ? round1((ex.score / ex.manfen) * 100) : 0))
            : ex.score;
        pts.add(
          _ChartPoint(
            exam: ex,
            value: val,
            displayValue: _usePercentageRatio ? '$val%' : ex.scoreS,
            subtitle: ex.manfen > 0
                ? '${ex.scoreS}/${round1(ex.manfen)} (${ex.ratio ?? 0}%)'
                : ex.scoreS,
          ),
        );
      } else {
        PaperScore? match;
        for (final p in ex.papers) {
          if (p.subject == subject) {
            match = p;
            break;
          }
        }
        if (match == null) continue;
        final val = _usePercentageRatio
            ? (match.ratio ??
                (match.manfen > 0
                    ? round1((match.score / match.manfen) * 100)
                    : 0))
            : match.score;
        pts.add(
          _ChartPoint(
            exam: ex,
            value: val,
            displayValue: _usePercentageRatio ? '$val%' : match.scoreS,
            subtitle: match.manfen > 0
                ? '${match.scoreS}/${round1(match.manfen)} (${match.ratio ?? 0}%)'
                : match.scoreS,
          ),
        );
      }
    }
    return pts;
  }

  List<_ChartPoint> _buildPoints() => _buildPointsForSubject(_metricSubject);

  void _handleSelectSubjectDimension(String newSubject) {
    setState(() {
      _metricSubject = newSubject;
      _hoveredIndex = null;
    });
    final pts = _buildPointsForSubject(newSubject);
    if (pts.isEmpty) return;

    final curId = widget.selectedExam?.examId ?? '';
    final matchInPoints = pts.where((p) => p.exam.examId == curId).toList();
    final targetExam =
        matchInPoints.isNotEmpty ? matchInPoints.first.exam : pts.last.exam;
    widget.onSelectExam(
      targetExam,
      preferredSubject: newSubject == '总分' ? null : newSubject,
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjects = <String>['总分', ...widget.dashboard.discoveredSubjects];
    if (!subjects.contains(_metricSubject)) {
      _metricSubject = '总分';
    }
    final points = _buildPoints();
    final curExam = widget.selectedExam ??
        (widget.dashboard.exams.isNotEmpty
            ? widget.dashboard.exams.first
            : null);

    double maxVal = 0;
    double minVal = 0;
    double avgVal = 0;
    if (points.isNotEmpty) {
      maxVal = points.map((p) => p.value).reduce(math.max);
      minVal = points.map((p) => p.value).reduce(math.min);
      avgVal = round1(
        points.fold<double>(0, (s, p) => s + p.value) / points.length,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Taste.surface,
        borderRadius: BorderRadius.circular(Taste.radiusCard),
        border: Border.all(color: Taste.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header & Subject Metric Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: LayoutBuilder(
              builder: (ctx, box) {
                final title = Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.show_chart, size: 18, color: Taste.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_metricSubject 历次成绩变化趋势折线图与学科均衡度',
                        maxLines: box.maxWidth < 620 ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: Taste.fontFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Taste.text,
                        ),
                      ),
                    ),
                  ],
                );
                final controls = Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (points.isNotEmpty) ...[
                      TastePill(
                        label:
                            '最高 ${round1(maxVal)}${_usePercentageRatio ? "%" : ""}',
                        tone: TastePillTone.positive,
                      ),
                      TastePill(
                        label:
                            '均值 ${round1(avgVal)}${_usePercentageRatio ? "%" : ""}',
                        tone: TastePillTone.blue,
                      ),
                      TastePill(
                        label:
                            '最低 ${round1(minVal)}${_usePercentageRatio ? "%" : ""}',
                        tone: TastePillTone.warning,
                      ),
                    ],
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      selected: !_usePercentageRatio,
                      label: const Text('原始分值', style: TextStyle(fontSize: 11)),
                      onSelected: (_) =>
                          setState(() => _usePercentageRatio = false),
                    ),
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      selected: _usePercentageRatio,
                      label: const Text('标准得分率 (%)',
                          style: TextStyle(fontSize: 11)),
                      onSelected: (_) =>
                          setState(() => _usePercentageRatio = true),
                    ),
                  ],
                );
                if (box.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerLeft, child: controls),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 12),
                    controls,
                  ],
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Taste.raised,
              border: Border(
                top: BorderSide(color: Taste.border),
                bottom: BorderSide(color: Taste.border),
              ),
            ),
            child: IsolatedHorizontalScroll(
              convertVerticalWheelToHorizontal: true,
              child: Row(
                children: [
                  const Text(
                    '趋势维度：',
                    style: TextStyle(fontSize: 12, color: Taste.muted),
                  ),
                  const SizedBox(width: 6),
                  for (final s in subjects)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        selected: _metricSubject == s,
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        onSelected: (_) => _handleSelectSubjectDimension(s),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (ctx, box) {
                final showRadarSideBySide = box.maxWidth >= 820 &&
                    curExam != null &&
                    curExam.papers.length >= 3;
                final lineChartWidget = _buildInteractiveLineChart(
                  points,
                  avgVal,
                  curExam,
                );
                if (!showRadarSideBySide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      lineChartWidget,
                      if (curExam != null && curExam.papers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: Taste.rule),
                        const SizedBox(height: 12),
                        _buildSubjectBalanceBars(curExam),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: lineChartWidget),
                    const SizedBox(width: 16),
                    Container(
                      width: 1,
                      height: 220,
                      color: Taste.border,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: _buildSubjectBalanceBars(curExam),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveLineChart(
    List<_ChartPoint> points,
    double avgVal,
    ExamRecord? selectedExam,
  ) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text(
            '当前维度暂无足够考试数据绘制折线图',
            style: TextStyle(fontSize: 12, color: Taste.muted),
          ),
        ),
      );
    }

    final selectedIdx = points.indexWhere(
      (p) => p.exam.examId == selectedExam?.examId,
    );
    final activeIdx =
        _hoveredIndex ?? (selectedIdx >= 0 ? selectedIdx : points.length - 1);
    final activePt = points[activeIdx.clamp(0, points.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Active point summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Taste.raised,
            borderRadius: BorderRadius.circular(Taste.radiusControl),
            border: Border.all(color: Taste.border),
          ),
          child: LayoutBuilder(
            builder: (ctx, box) {
              final compact = box.maxWidth < 420;
              final activeTitle = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Taste.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${formatDateMs(activePt.exam.time)} · ${activePt.exam.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Taste.text,
                      ),
                    ),
                  ),
                ],
              );
              final summary = Text(
                '$_metricSubject：${activePt.subtitle}（点击折线节点可切换考试与答题卡）',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Taste.numStyle(
                  size: 12,
                  weight: FontWeight.w500,
                  color: Taste.accent,
                ),
              );
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        activeTitle,
                        const SizedBox(height: 4),
                        summary,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: activeTitle),
                        const SizedBox(width: 8),
                        Expanded(child: summary),
                      ],
                    );
            },
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 212,
          child: LayoutBuilder(
            builder: (ctx, box) {
              const leftPad = 44.0;
              const rightPad = 20.0;
              final plotW = math.max(10.0, box.maxWidth - leftPad - rightPad);

              int hitIndexForDx(double dx) {
                if (points.length <= 1) return 0;
                final rel = (dx - leftPad).clamp(0.0, plotW);
                final step = plotW / (points.length - 1);
                return (rel / step).round().clamp(0, points.length - 1);
              }

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onHover: (ev) {
                  final idx = hitIndexForDx(ev.localPosition.dx);
                  if (idx != _hoveredIndex) {
                    setState(() => _hoveredIndex = idx);
                  }
                },
                onExit: (_) => setState(() => _hoveredIndex = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final idx = hitIndexForDx(details.localPosition.dx);
                    setState(() => _hoveredIndex = idx);
                    widget.onSelectExam(
                      points[idx].exam,
                      preferredSubject:
                          _metricSubject == '总分' ? null : _metricSubject,
                    );
                  },
                  child: CustomPaint(
                    size: Size(box.maxWidth, 212),
                    painter: _ScoreLineChartPainter(
                      points: points,
                      avgValue: avgVal,
                      selectedExamId: selectedExam?.examId ?? '',
                      hoveredIndex: _hoveredIndex,
                      isPercentage: _usePercentageRatio,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectBalanceBars(ExamRecord exam) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${exam.name} · 各科得分率均衡度',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Taste.text,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '对比各学科得分率强弱项（≥85% 优秀 / 60-84% 良好 / <60% 待加强）',
          style: TextStyle(fontSize: 11, color: Taste.muted),
        ),
        const SizedBox(height: 10),
        for (final p in exam.papers)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                setState(() {
                  _metricSubject = p.subject;
                  _hoveredIndex = null;
                });
                widget.onSelectExam(exam, preferredSubject: p.subject);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: (_metricSubject == p.subject ||
                                      widget.selectedSubject == p.subject)
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: (_metricSubject == p.subject ||
                                      widget.selectedSubject == p.subject)
                                  ? Taste.accent
                                  : Taste.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${p.scoreS}/${round1(p.manfen)} (${p.ratio ?? 0}%)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: Taste.numStyle(
                              size: 11,
                              weight: FontWeight.w700,
                              color: Taste.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Taste.raised,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: ((p.ratio ?? 0) / 100.0).clamp(0.0, 1.0),
                        child: Container(
                          color: (p.ratio ?? 0) >= 85
                              ? Taste.positive
                              : ((p.ratio ?? 0) >= 60
                                  ? Taste.accent
                                  : Taste.chart3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScoreLineChartPainter extends CustomPainter {
  final List<_ChartPoint> points;
  final double avgValue;
  final String selectedExamId;
  final int? hoveredIndex;
  final bool isPercentage;

  const _ScoreLineChartPainter({
    required this.points,
    required this.avgValue,
    required this.selectedExamId,
    required this.hoveredIndex,
    required this.isPercentage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPad = 44.0;
    const rightPad = 20.0;
    const topPad = 22.0;
    const bottomPad = 42.0; // room for two-line year+MM-DD axis labels
    final plotW = math.max(10.0, size.width - leftPad - rightPad);
    final plotH = math.max(10.0, size.height - topPad - bottomPad);

    double minV = points.map((p) => p.value).reduce(math.min);
    double maxV = points.map((p) => p.value).reduce(math.max);
    if ((maxV - minV).abs() < 4.0) {
      minV = math.max(0.0, minV - 5.0);
      maxV = maxV + 5.0;
    } else {
      final pad = (maxV - minV) * 0.14;
      minV = math.max(0.0, minV - pad);
      maxV = isPercentage ? math.min(100.0, maxV + pad) : maxV + pad;
    }
    final span = math.max(1.0, maxV - minV);

    double xAt(int i) {
      if (points.length == 1) return leftPad + plotW / 2.0;
      return leftPad + (i / (points.length - 1)) * plotW;
    }

    double yAt(double v) {
      return topPad + plotH - ((v - minV) / span).clamp(0.0, 1.0) * plotH;
    }

    // 1. Horizontal grid lines & Y-axis labels
    final gridPaint = Paint()
      ..color = Taste.rule
      ..strokeWidth = 1.0;

    for (var g = 0; g <= 3; g++) {
      final ratio = g / 3.0;
      final gy = topPad + plotH * (1.0 - ratio);
      final gv = minV + span * ratio;
      canvas.drawLine(
        Offset(leftPad, gy),
        Offset(leftPad + plotW, gy),
        gridPaint,
      );
      _drawLabel(
        canvas,
        size,
        isPercentage ? '${gv.round()}%' : '${gv.round()}',
        Offset(2, gy - 7),
        color: Taste.faint,
        fontSize: 10,
        weight: FontWeight.w400,
      );
    }

    // 2. Dashed average reference line
    final avgY = yAt(avgValue);
    final avgPaint = Paint()
      ..color = Taste.chart2.withValues(alpha: 0.45)
      ..strokeWidth = 1.0;
    for (double dx = leftPad; dx < leftPad + plotW; dx += 8) {
      canvas.drawLine(
        Offset(dx, avgY),
        Offset(math.min(dx + 4, leftPad + plotW), avgY),
        avgPaint,
      );
    }

    // 3. Area fill & straight-segment line path.
    // Use straight segments between exams, not a cubic spline: a spline
    // implies continuous change between discrete exams and visually
    // overshoots real values, which misreads the data.
    final linePath = Path();
    final fillPath = Path();
    for (var i = 0; i < points.length; i++) {
      final px = xAt(i);
      final py = yAt(points[i].value);
      if (i == 0) {
        linePath.moveTo(px, py);
        fillPath.moveTo(px, topPad + plotH);
        fillPath.lineTo(px, py);
      } else {
        linePath.lineTo(px, py);
        fillPath.lineTo(px, py);
      }
      if (i == points.length - 1) {
        fillPath.lineTo(px, topPad + plotH);
        fillPath.close();
      }
    }

    if (points.length > 1) {
      final fillShader = ui.Gradient.linear(
        const Offset(0, topPad),
        Offset(0, topPad + plotH),
        <Color>[
          Taste.accent.withValues(alpha: 0.16),
          Taste.accent.withValues(alpha: 0.01),
        ],
      );
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = fillShader
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        linePath,
        Paint()
          ..color = Taste.accent
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // 4. Data nodes, value tags & X-axis dates
    final labelStep = math.max(1, (points.length / 7).ceil());
    String? lastYearShown;
    for (var i = 0; i < points.length; i++) {
      final pt = points[i];
      final px = xAt(i);
      final py = yAt(pt.value);
      final isSel = pt.exam.examId == selectedExamId;
      final isHov = hoveredIndex == i;

      if (isSel || isHov) {
        canvas.drawLine(
          Offset(px, topPad),
          Offset(px, topPad + plotH),
          Paint()
            ..color = Taste.accent.withValues(alpha: 0.25)
            ..strokeWidth = 1.2,
        );
      }

      // Outer halo for active/selected point
      if (isSel || isHov) {
        canvas.drawCircle(
          Offset(px, py),
          7.0,
          Paint()..color = Taste.accent.withValues(alpha: 0.18),
        );
      }
      canvas.drawCircle(
        Offset(px, py),
        isSel || isHov ? 4.5 : 3.4,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(px, py),
        isSel || isHov ? 4.5 : 3.4,
        Paint()
          ..color = isSel || isHov ? Taste.primary : Taste.accent
          ..strokeWidth = isSel || isHov ? 2.4 : 1.8
          ..style = PaintingStyle.stroke,
      );

      // Value label with an opaque background pill, placed above or below the
      // node depending on local slope so it never sits on the stroke. A V
      // (local minimum) pushes the label down; a peak pushes it up.
      if (points.length <= 10 || isSel || isHov || i == points.length - 1) {
        final prevV = i > 0 ? points[i - 1].value : pt.value;
        final nextV = i < points.length - 1 ? points[i + 1].value : pt.value;
        final isLocalMin = pt.value <= prevV && pt.value <= nextV;
        final placeBelow = isLocalMin && !(isSel || isHov);
        final labelY = placeBelow ? py + 9.0 : py - 20.0;
        _drawLabel(
          canvas,
          size,
          pt.displayValue,
          Offset(px - 16, labelY),
          color: isSel || isHov ? Taste.text : Taste.accent,
          fontSize: 10.5,
          weight: isSel || isHov ? FontWeight.w700 : FontWeight.w500,
          background: Taste.surface.withValues(alpha: 0.92),
          centerOnX: px,
        );
      }

      // X-axis date label. Show the year the first time it appears (and on the
      // first labelled point) so the axis is never a yearless MM-DD sequence
      // that reads as non-chronological across semesters.
      final showThis = i % labelStep == 0 || i == points.length - 1 || isSel;
      if (showThis) {
        final dateStr = formatDateMs(pt.exam.time); // YYYY-MM-DD or '—'
        String axisLabel;
        if (dateStr.length >= 10) {
          final year = dateStr.substring(0, 4);
          final mmdd = dateStr.substring(5, 10);
          axisLabel = (year != lastYearShown) ? '$year\n$mmdd' : mmdd;
          lastYearShown = year;
        } else {
          axisLabel = dateStr;
        }
        _drawLabel(
          canvas,
          size,
          axisLabel,
          Offset(px - 16, topPad + plotH + 6),
          color: isSel ? Taste.text : Taste.muted,
          fontSize: 10,
          weight: isSel ? FontWeight.w700 : FontWeight.w400,
          centerOnX: px,
          align: TextAlign.center,
        );
      }
    }
  }

  void _drawLabel(
    Canvas canvas,
    Size canvasSize,
    String text,
    Offset offset, {
    required Color color,
    required double fontSize,
    required FontWeight weight,
    Color? background,
    double? centerOnX,
    TextAlign align = TextAlign.left,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: Taste.fontFamily,
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    final double wantX =
        centerOnX != null ? centerOnX - tp.width / 2.0 : offset.dx;
    final double safeX = wantX
        .clamp(2.0, math.max(2.0, canvasSize.width - tp.width - 2.0))
        .toDouble();
    final double safeY = offset.dy
        .clamp(1.0, math.max(1.0, canvasSize.height - tp.height - 1.0))
        .toDouble();
    if (background != null) {
      final rect = Rect.fromLTWH(
        safeX - 3.0,
        safeY - 1.0,
        tp.width + 6.0,
        tp.height + 2.0,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = background,
      );
    }
    tp.paint(canvas, Offset(safeX, safeY));
  }

  @override
  bool shouldRepaint(covariant _ScoreLineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.avgValue != avgValue ||
        oldDelegate.selectedExamId != selectedExamId ||
        oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.isPercentage != isPercentage;
  }
}
