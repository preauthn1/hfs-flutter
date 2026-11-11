part of '../main.dart';

extension _HfsHomeFleetStageExt on _HfsHomeScreenState {
  /// Tab 1: Fleet & All-Students Overview Stage (1:1 parity with #tab-fleet)
  Widget _buildFleetOverviewStage() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // 1. All-Students Score Comparison Table
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
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '全员学生最新考试成绩对照表',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Taste.text,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '汇总所有已挂载账号下的全体绑定学生最新成绩（按总分降序排列，点击即切换）',
                          style: TextStyle(fontSize: 12, color: Taste.muted),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildTopBarBtn(
                          label: _loadingFleet ? '正在遍历全员…' : '一键遍历同步全员成绩',
                          icon: Icons.sync,
                          onTap: _loadingFleet
                              ? null
                              : _handleProbeAllAccountsFleet,
                        ),
                        _buildTopBarBtn(
                          label: '绑定新学生',
                          icon: Icons.person_add_alt_1_outlined,
                          onTap: () => _openAdvancedBindStudentModal(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Taste.border),
              if (_fleetRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child:
                        Text('暂无已绑定学生', style: TextStyle(color: Taste.muted)),
                  ),
                )
              else
                IsolatedHorizontalScroll(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 780),
                    child: DataTable(
                      headingRowHeight: 38,
                      dataRowMinHeight: 46,
                      dataRowMaxHeight: 48,
                      columns: const [
                        DataColumn(label: Text('排名')),
                        DataColumn(label: Text('学生姓名')),
                        DataColumn(label: Text('学校 / 班级')),
                        DataColumn(label: Text('准考证/考号')),
                        DataColumn(label: Text('最新考试')),
                        DataColumn(label: Text('总分 / 满分'), numeric: true),
                        DataColumn(label: Text('班排 / 年排')),
                        DataColumn(label: Text('归属账号')),
                        DataColumn(label: Text('操作')),
                      ],
                      rows: [
                        for (var i = 0; i < _fleetRows.length; i++)
                          _buildFleetDataRow(i + 1, _fleetRows[i]),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 2. Account Pool Cards Grid (.fleet-card)
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
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      '已连接好分数账号池（共 ${_accounts.length} 个账号）',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Taste.text,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildTopBarBtn(
                          label: '导出凭证文件 (.json)',
                          icon: Icons.download_outlined,
                          onTap: () => _exportCredentialFileDirect(),
                        ),
                        _buildTopBarBtn(
                          label: '＋ 新增 / 注册账号',
                          icon: Icons.add,
                          onTap: () => _openAuthOrRegisterModal(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Taste.border),
              Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    final cols = (box.maxWidth / 300).floor().clamp(1, 4);
                    final cardW = (box.maxWidth - (cols - 1) * 12) / cols;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final acc in _accounts)
                          SizedBox(
                            width: cardW,
                            child: _buildFleetAccountCard(acc),
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

  DataRow _buildFleetDataRow(
    int rank,
    ({HfsAccount account, StudentInfo student, StudentSnapshot? snapshot}) row,
  ) {
    final snap = row.snapshot;
    return DataRow(
      cells: [
        DataCell(
          TastePill(
            label: '#$rank',
            tone: rank <= 3 ? TastePillTone.positive : TastePillTone.neutral,
          ),
        ),
        DataCell(
          Text(
            row.student.studentName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        DataCell(
          Text(
            '${row.student.schoolName} ${row.student.grade}${row.student.className}'
                .trim(),
            style: const TextStyle(fontSize: 12, color: Taste.muted),
          ),
        ),
        DataCell(
          Text(
            row.student.xuehao.isNotEmpty ? row.student.xuehao : '—',
            style: Taste.numStyle(size: 12, color: Taste.muted),
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              snap?.examName ?? '尚未拉取（点击上方遍历）',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        DataCell(
          Text(
            snap != null ? '${snap.scoreS} / ${round1(snap.manfen)}' : '—',
            style: Taste.numStyle(
              size: 13,
              weight: FontWeight.w700,
              color: Taste.accent,
            ),
          ),
        ),
        DataCell(
          Text(
            snap != null &&
                    (snap.classRankS.isNotEmpty || snap.gradeRankS.isNotEmpty)
                ? '班${snap.classRankS.isEmpty ? "-" : snap.classRankS} / 年${snap.gradeRankS.isEmpty ? "-" : snap.gradeRankS}'
                : '—',
            style: Taste.numStyle(size: 12, color: Taste.muted),
          ),
        ),
        DataCell(
          Text(
            row.account.displayLabel,
            style: const TextStyle(fontSize: 12, color: Taste.muted),
          ),
        ),
        DataCell(
          _miniIconBtn(
            label: '查看成绩单',
            active: true,
            onTap: () {
              _setHomeState(() => _activeTabIndex = 0);
              _handleSwitchStudent(row.account, row.student);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFleetAccountCard(HfsAccount acc) {
    final isSelected = acc.id == _selectedAccountId;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Taste.surface,
        borderRadius: BorderRadius.circular(Taste.radiusCard),
        border: Border.all(color: isSelected ? Taste.accent : Taste.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  acc.displayLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Taste.text,
                  ),
                ),
              ),
              TastePill(
                label: acc.roleType == 1 ? '学生端' : '家长端',
                tone: acc.roleType == 1
                    ? TastePillTone.blue
                    : TastePillTone.positive,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${acc.maskedLogin} · 已绑 ${acc.students.length} 名学生',
            style: const TextStyle(fontSize: 12, color: Taste.muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final stu in acc.students)
                InkWell(
                  onTap: () {
                    _setHomeState(() => _activeTabIndex = 0);
                    _handleSwitchStudent(acc, stu);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: acc.activeStudentId == stu.studentId && isSelected
                          ? Taste.active
                          : Taste.raised,
                      borderRadius: BorderRadius.circular(Taste.radiusControl),
                      border: Border.all(
                        color:
                            acc.activeStudentId == stu.studentId && isSelected
                                ? Taste.accent
                                : Taste.border,
                      ),
                    ),
                    child: Text(
                      '${stu.studentName}${acc.studentSnapshots[stu.studentId] != null ? " (${acc.studentSnapshots[stu.studentId]!.scoreS})" : ""}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color:
                            acc.activeStudentId == stu.studentId && isSelected
                                ? Taste.accent
                                : Taste.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniIconBtn({
    required String label,
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
            color: active ? Taste.pillPosInk : Taste.text,
          ),
        ),
      ),
    );
  }

  Widget _svgIconActionBtn({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Taste.radiusControl),
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Taste.surface,
            borderRadius: BorderRadius.circular(Taste.radiusControl),
            border: Border.all(color: Taste.control),
          ),
          child: Icon(
            icon,
            size: 14,
            color: danger ? Taste.negative : Taste.text,
          ),
        ),
      ),
    );
  }

  Widget _compactInput(
    TextEditingController ctrl,
    String hint, {
    bool obscure = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return SizedBox(
      height: 30,
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        onSubmitted: onSubmitted,
        style: const TextStyle(fontSize: 12, color: Taste.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 11, color: Taste.faint),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          filled: true,
          fillColor: Taste.surface,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Taste.radiusControl),
            borderSide: const BorderSide(color: Taste.control),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Taste.radiusControl),
            borderSide: const BorderSide(color: Taste.accent),
          ),
        ),
      ),
    );
  }
}
