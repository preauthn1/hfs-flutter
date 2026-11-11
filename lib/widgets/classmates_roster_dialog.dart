part of '../taste_widgets.dart';

class ClassmatesRosterDialog extends StatefulWidget {
  final HfsUpstreamClient client;
  final HfsAccount account;
  final List<HfsAccount> accounts;
  final StudentInfo? currentStudent;
  final Future<void> Function(HfsAccount targetAccount, DashboardData dash)?
      onBound;
  final void Function(HfsAccount account, StudentInfo student)? onSwitchStudent;

  const ClassmatesRosterDialog({
    super.key,
    required this.client,
    required this.account,
    this.accounts = const [],
    this.currentStudent,
    this.onBound,
    this.onSwitchStudent,
  });

  @override
  State<ClassmatesRosterDialog> createState() => _ClassmatesRosterDialogState();
}

class _ClassmatesRosterDialogState extends State<ClassmatesRosterDialog> {
  late HfsAccount _selectedAccount;
  late StudentInfo? _selectedStudent;
  late HfsAccount _bindTargetAccount;
  // '' = 新增直绑 (`POST /v2/native-users/bind-students`); non-empty = 换绑替换源学生 (`PATCH /v2/native-users/bind-student`)
  String _replaceStudentId = '';
  List<ClassmateBindEntry> _roster = const [];
  String _search = '';
  bool _onlyUnboundInTarget = false;
  bool _loading = true;
  String? _error;
  String? _bindingStudentId;
  String? _bindSuccessMsg;
  String? _bindErrorMsg;

  List<HfsAccount> get _availableAccounts => widget.accounts.isNotEmpty
      ? widget.accounts
      : <HfsAccount>[widget.account];

  StudentInfo? get _selectedReplaceStudent {
    if (_replaceStudentId.isEmpty) return null;
    for (final s in _bindTargetAccount.students) {
      if (s.studentId == _replaceStudentId) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _selectedAccount = widget.account;
    _selectedStudent = widget.currentStudent ?? widget.account.activeStudent;
    _bindTargetAccount = widget.account;
    _load();
    _refreshTargetQuota();
  }

  Future<void> _refreshTargetQuota() async {
    try {
      await widget.client.hydrateAccountStudents(_bindTargetAccount);
      if (!mounted) return;
      setState(() {
        if (_replaceStudentId.isNotEmpty &&
            !_bindTargetAccount.students
                .any((s) => s.studentId == _replaceStudentId)) {
          _replaceStudentId = '';
        }
      });
    } catch (_) {}
  }

  List<({HfsAccount acc, StudentInfo stu})> _allBoundStudents() {
    final out = <({HfsAccount acc, StudentInfo stu})>[];
    for (final a in _availableAccounts) {
      for (final s in a.students) {
        out.add((acc: a, stu: s));
      }
    }
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.client.fetchClassmates(
        _selectedAccount,
        studentId: _selectedStudent?.studentId ?? '',
      );
      if (!mounted) return;
      setState(() {
        _roster = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<bool?> _confirmRosterRebindSafety({
    required StudentInfo sourceStu,
    required String targetName,
    bool? knownTargetHasStudentAccount,
  }) async {
    bool forceAllowStuAcc = false;
    final needsStuAccWarn = knownTargetHasStudentAccount == true;
    final needsMinusOneWarn = sourceStu.isMinusOneSlot;
    if (!needsStuAccWarn && !needsMinusOneWarn) {
      return false;
    }
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: Taste.surface,
          surfaceTintColor: Colors.transparent,
          insetPadding: Taste.dialogInsetPadding(ctx),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          title: Row(
            children: [
              Icon(
                needsStuAccWarn
                    ? Icons.warning_amber_rounded
                    : Icons.swap_horiz_rounded,
                color: needsStuAccWarn ? Taste.negative : Taste.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  needsStuAccWarn ? '高危换绑风控拦截 (4137 删源风险)' : '确认消耗 -1 活名额进行换绑？',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '源学生（将被移除）：${sourceStu.studentName} (${sourceStu.changeBindStatusLabel})\n'
                    '目标新同学：$targetName\n'
                    '目标账号：${_bindTargetAccount.displayLabel}',
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Taste.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (needsMinusOneWarn)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Taste.pillWarnBg,
                        borderRadius:
                            BorderRadius.circular(Taste.radiusControl),
                      ),
                      child: Text(
                        '• 「${sourceStu.studentName}」属于 changeBindTime == -1 的历史活名额（随时可换）。\n'
                        '• 换绑为新同学后，新记录将写入 +180 天学期锁，本账号 -1 活名额将减 1，总容量上限将从 ${_bindTargetAccount.estimatedMaxQuota} 人永久降为 ${math.max(3, _bindTargetAccount.estimatedMaxQuota - 1)} 人。',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Taste.pillWarnInk,
                        ),
                      ),
                    ),
                  if (needsStuAccWarn) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Taste.pillNegBg,
                        borderRadius:
                            BorderRadius.circular(Taste.radiusControl),
                      ),
                      child: const Text(
                        '• 严重警告：该目标同学已激活学生端账号 (bindStudent 非空)！\n'
                        '• 好分数上游 PATCH /v2/native-users/bind-student 存在非原子写缺陷：目标带有学生端账号时会返回 4137 Duplicate links，但会把源学生直接删除、目标却未加入！\n'
                        '• 强烈建议取消本次换绑，改选「无学生号」的同学。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Taste.pillNegInk,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: forceAllowStuAcc,
                      onChanged: (v) =>
                          setModalState(() => forceAllowStuAcc = v ?? false),
                      title: const Text(
                        '我已知晓 4137 删源不加目标风险，仍强制换绑',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Taste.negative,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            Taste.buildDialogFooter(
              padding: const EdgeInsets.only(top: 8),
              children: [
                Taste.dialogCancelButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  label: '取消',
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        needsStuAccWarn ? Taste.negative : Taste.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(112, 38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  onPressed: (needsStuAccWarn && !forceAllowStuAcc)
                      ? null
                      : () => Navigator.of(ctx).pop(forceAllowStuAcc),
                  child: const Text(
                    '确认执行换绑',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBindByStudentId(
    String studentId, {
    String? studentLabel,
    bool? knownTargetHasStudentAccount,
  }) async {
    final cleanId = studentId.trim();
    if (cleanId.isEmpty || _bindingStudentId != null) return;
    final shownName = studentLabel ?? cleanId;
    final replaceStu = _selectedReplaceStudent;
    bool forceAllowStuAcc = false;

    if (replaceStu != null) {
      if (replaceStu.isSemesterLocked) {
        setState(() {
          _bindErrorMsg =
              '源学生「${replaceStu.studentName}」处于学期锁定期（${replaceStu.changeBindStatusLabel}），每学期只能换绑一次 (4137)';
          _bindSuccessMsg = null;
        });
        return;
      }
      bool? knownHasStu = knownTargetHasStudentAccount;
      if (knownHasStu == null) {
        for (final c in _roster) {
          if (c.id == cleanId) {
            knownHasStu = c.hasStudentAccount;
            break;
          }
        }
      }
      final confirmed = await _confirmRosterRebindSafety(
        sourceStu: replaceStu,
        targetName: shownName,
        knownTargetHasStudentAccount: knownHasStu,
      );
      if (confirmed == null) return;
      forceAllowStuAcc = confirmed;
    }

    setState(() {
      _bindingStudentId = cleanId;
      _bindErrorMsg = null;
      _bindSuccessMsg = null;
    });
    try {
      late DashboardData dash;
      if (replaceStu != null) {
        dash = await widget.client.rebindStudent(
          account: _bindTargetAccount,
          selectStudentId: replaceStu.studentId,
          targetStudentId: cleanId,
          knownTargetHasStudentAccount: knownTargetHasStudentAccount,
          forceAllowStudentAccountTarget: forceAllowStuAcc,
        );
      } else {
        dash = await widget.client.bindStudentById(
          account: _bindTargetAccount,
          studentId: cleanId,
        );
      }
      if (widget.onBound != null) {
        await widget.onBound!(_bindTargetAccount, dash);
      }
      if (!mounted) return;
      setState(() {
        _bindingStudentId = null;
        if (replaceStu != null) {
          _replaceStudentId = '';
          _bindSuccessMsg =
              '已通过 PATCH /v2/native-users/bind-student 成功将 [${_bindTargetAccount.displayLabel}] 下的「${replaceStu.studentName}」换绑为「$shownName」';
        } else {
          _bindSuccessMsg =
              '已通过 POST /v2/native-users/bind-students 成功将「$shownName」新增绑定至账号 [${_bindTargetAccount.displayLabel}]';
        }
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bindingStudentId = null;
        _bindErrorMsg =
            '${replaceStu != null ? "换绑" : "直绑"}「$shownName」到 [${_bindTargetAccount.displayLabel}] 失败：${e.toString().replaceFirst("Exception: ", "")}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allAccounts = _availableAccounts;
    if (!allAccounts.any((a) => a.id == _bindTargetAccount.id)) {
      _bindTargetAccount = allAccounts.first;
    }
    final allStudents = _allBoundStudents();
    final filtered = _roster.where((c) {
      if (_onlyUnboundInTarget &&
          _bindTargetAccount.students.any((s) => s.studentId == c.id)) {
        return false;
      }
      if (_search.trim().isEmpty) return true;
      final q = _search.trim();
      return c.name.contains(q) || c.id.contains(q);
    }).toList();
    final stuBoundCnt = _roster.where((c) => c.hasStudentAccount).length;
    final parBoundCnt = _roster.where((c) => c.hasParentAccount).length;
    final resolvedClassName =
        (_roster.isNotEmpty && _roster.first.className.isNotEmpty)
            ? '${_roster.first.grade}${_roster.first.className}'
            : (_selectedStudent?.className.isNotEmpty == true
                ? '${_selectedStudent!.grade}${_selectedStudent!.className}'
                : '当前班级');

    final trimmedSearch = _search.trim();
    final canDirectBindSearchId =
        RegExp(r'^\d{10,32}$').hasMatch(trimmedSearch);
    final replaceStu = _selectedReplaceStudent;
    final isRebindMode = replaceStu != null;

    final maxDialogH = Taste.dialogMaxHeight(context, desktopMax: 720);
    final isCompactHeight = maxDialogH < 560;

    return Dialog(
      backgroundColor: Taste.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: Taste.dialogInsetPadding(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Taste.radiusCard),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: maxDialogH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
              decoration: const BoxDecoration(
                color: Taste.surface,
                border: Border(bottom: BorderSide(color: Taste.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '同班同学名册与直绑/换绑 ($resolvedClassName · 共 ${_roster.length} 人)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '重新拉取同班名册 (GET /v2/students/classmates)',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _loading ? null : _load,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (allStudents.length > 1 && !isCompactHeight) ...[
                      IsolatedHorizontalScroll(
                        convertVerticalWheelToHorizontal: true,
                        child: Row(
                          children: [
                            const Text(
                              '获取班级来源：',
                              style:
                                  TextStyle(fontSize: 12, color: Taste.muted),
                            ),
                            const SizedBox(width: 6),
                            for (final item in allStudents)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  visualDensity: VisualDensity.compact,
                                  selected:
                                      _selectedAccount.id == item.acc.id &&
                                          _selectedStudent?.studentId ==
                                              item.stu.studentId,
                                  label: Text(
                                    '${item.stu.studentName} (${item.stu.grade}${item.stu.className})',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onSelected: (_) {
                                    setState(() {
                                      _selectedAccount = item.acc;
                                      _selectedStudent = item.stu;
                                    });
                                    _load();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Target account & Add/Rebind slot selector
                    if (!isCompactHeight) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isRebindMode ? Taste.pillWarnBg : Taste.raised,
                          borderRadius:
                              BorderRadius.circular(Taste.radiusControl),
                          border: Border.all(
                            color: isRebindMode
                                ? const Color(0xFFFDE68A)
                                : Taste.border,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isRebindMode
                                          ? Icons.swap_horiz
                                          : Icons.link,
                                      size: 15,
                                      color: isRebindMode
                                          ? Taste.warning
                                          : Taste.accent,
                                    ),
                                    const SizedBox(width: 6),
                                    const Flexible(
                                      child: Text(
                                        'POST /v2/native-users/bind-students 挂载到：',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Taste.text,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 280),
                                      child: SizedBox(
                                        height: 36,
                                        child: DropdownButtonFormField2<String>(
                                          key: ValueKey(
                                              'roster_bind_acc_${_bindTargetAccount.id}_${_bindTargetAccount.students.length}'),
                                          value: _bindTargetAccount.id,
                                          isExpanded: true,
                                          isDense: true,
                                          iconStyleData: Taste.dropdownIconStyle,
                                          dropdownStyleData: Taste.dropdownStyle(
                                            context,
                                            maxHeight: 280,
                                            dropdownWidth:
                                                Taste.resolveDropdownMenuWidth(
                                              context,
                                              preferredWidth: 320,
                                            ),
                                          ),
                                          menuItemStyleData:
                                              Taste.menuItemStyle(context),
                                          selectedItemBuilder: (ctx) => [
                                            for (final a in allAccounts)
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  '${a.displayLabel} (${a.roleType == 1 ? "学生端" : "家长端"} · 已绑${a.students.length}/${a.estimatedMaxQuota}人)',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                            filled: true,
                                            fillColor: Taste.surface,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      Taste.radiusControl),
                                            ),
                                          ),
                                          items: [
                                            for (final a in allAccounts)
                                              DropdownMenuItem(
                                                value: a.id,
                                                child: Text(
                                                  '${a.displayLabel} (${a.roleType == 1 ? "学生端" : "家长端"} · 已绑${a.students.length}/${a.estimatedMaxQuota}人)',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    height: 1.25,
                                                    color: Taste.text,
                                                  ),
                                                ),
                                              ),
                                          ],
                                          onChanged: _bindingStudentId != null
                                              ? null
                                              : (val) {
                                                  if (val == null) return;
                                                  final found =
                                                      allAccounts.firstWhere(
                                                          (a) => a.id == val);
                                                  setState(() {
                                                    _bindTargetAccount = found;
                                                    _replaceStudentId = '';
                                                    _bindErrorMsg = null;
                                                    _bindSuccessMsg = null;
                                                  });
                                                  _refreshTargetQuota();
                                                },
                                        ),
                                      ),
                                    ),
                                    FilterChip(
                                      visualDensity: VisualDensity.compact,
                                      selected: _onlyUnboundInTarget,
                                      label: const Text('仅看未绑',
                                          style: TextStyle(fontSize: 11.5)),
                                      onSelected: (v) => setState(
                                          () => _onlyUnboundInTarget = v),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            IsolatedHorizontalScroll(
                              convertVerticalWheelToHorizontal: true,
                              child: Row(
                                children: [
                                  const Text(
                                    '绑定/换绑槽位：',
                                    style: TextStyle(
                                        fontSize: 11.5, color: Taste.muted),
                                  ),
                                  const SizedBox(width: 6),
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      visualDensity: VisualDensity.compact,
                                      selected: _replaceStudentId.isEmpty,
                                      label: Text(
                                        '＋ 新增直绑 (余${_bindTargetAccount.remainingAddQuota}名额)',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      onSelected: _bindingStudentId != null
                                          ? null
                                          : (_) => setState(() {
                                                _replaceStudentId = '';
                                                _bindErrorMsg = null;
                                              }),
                                    ),
                                  ),
                                  for (final s in _bindTargetAccount.students)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ChoiceChip(
                                        visualDensity: VisualDensity.compact,
                                        selected:
                                            _replaceStudentId == s.studentId,
                                        label: Text(
                                          '⇄ 换绑：${s.studentName} (${s.changeBindStatusLabel})',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: s.isSemesterLocked
                                                ? Taste.muted
                                                : null,
                                          ),
                                        ),
                                        onSelected: _bindingStudentId != null
                                            ? null
                                            : (_) => setState(() {
                                                  _replaceStudentId =
                                                      _replaceStudentId ==
                                                              s.studentId
                                                          ? ''
                                                          : s.studentId;
                                                  _bindErrorMsg = null;
                                                }),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_bindSuccessMsg != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Taste.pillPosBg,
                          borderRadius:
                              BorderRadius.circular(Taste.radiusControl),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                size: 15, color: Taste.positive),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _bindSuccessMsg!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: Taste.pillPosInk),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_bindErrorMsg != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Taste.pillNegBg,
                          borderRadius:
                              BorderRadius.circular(Taste.radiusControl),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                size: 15, color: Taste.negative),
                            const SizedBox(width: 6),
                            Expanded(
                              child: SelectableText(
                                _bindErrorMsg!,
                                maxLines: 2,
                                style: const TextStyle(
                                    fontSize: 12, color: Taste.pillNegInk),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (!isCompactHeight) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          TastePill(
                            label: '已激活学生端: $stuBoundCnt 人',
                            tone: TastePillTone.blue,
                          ),
                          TastePill(
                            label: '已绑定家长端: $parBoundCnt 人',
                            tone: TastePillTone.positive,
                          ),
                          TastePill(
                            label: '未绑家长端: ${_roster.length - parBoundCnt} 人',
                            tone: TastePillTone.warning,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    LayoutBuilder(
                      builder: (ctx, box) {
                        final compact = box.maxWidth < 420;
                        final searchField = SizedBox(
                          height: 36,
                          child: TextField(
                            onChanged: (v) => setState(() => _search = v),
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: '搜索同学姓名，或粘贴任意 studentId 直接绑定…',
                              prefixIcon: const Icon(Icons.search, size: 16),
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 0),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(Taste.radiusControl),
                              ),
                            ),
                          ),
                        );
                        final directBind = canDirectBindSearchId
                            ? SizedBox(
                                height: 36,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Taste.primary,
                                    foregroundColor: Taste.primaryInk,
                                  ),
                                  onPressed: _bindingStudentId != null
                                      ? null
                                      : () =>
                                          _handleBindByStudentId(trimmedSearch),
                                  icon: Icon(
                                    isRebindMode
                                        ? Icons.swap_horiz
                                        : Icons.person_add_alt_1,
                                    size: 15,
                                  ),
                                  label: Text(
                                    isRebindMode ? '换绑该 ID' : '直绑该 ID',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              )
                            : null;
                        if (compact && directBind != null) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              searchField,
                              const SizedBox(height: 8),
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: directBind),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: searchField),
                            if (directBind != null) ...[
                              const SizedBox(width: 8),
                              directBind,
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : (_error != null)
                              ? Center(
                                  child: Text(_error!,
                                      style: const TextStyle(
                                          color: Taste.negative)),
                                )
                              : ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (ctx, idx) => const Divider(
                                      height: 1, color: Taste.rule),
                                  itemBuilder: (ctx, i) {
                                    final c = filtered[i];
                                    final alreadyInTarget = _bindTargetAccount
                                        .students
                                        .any((s) => s.studentId == c.id);
                                    final boundMatches = allStudents
                                        .where((x) => x.stu.studentId == c.id)
                                        .toList();
                                    final isBindingThis =
                                        _bindingStudentId == c.id;

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8, horizontal: 4),
                                      child: Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              SizedBox(
                                                width: 28,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 2),
                                                  child: Text(
                                                    '${i + 1}',
                                                    style: Taste.numStyle(
                                                        size: 12,
                                                        color: Taste.muted),
                                                  ),
                                                ),
                                              ),
                                              Flexible(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Wrap(
                                                      spacing: 6,
                                                      runSpacing: 4,
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          c.name,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                        if (c.isMember)
                                                          const TastePill(
                                                            label: 'VIP',
                                                            tone: TastePillTone
                                                                .warning,
                                                          ),
                                                        TastePill(
                                                          label:
                                                              c.hasStudentAccount
                                                                  ? '已绑学生端'
                                                                  : '无学生号',
                                                          tone: c.hasStudentAccount
                                                              ? TastePillTone
                                                                  .blue
                                                              : TastePillTone
                                                                  .neutral,
                                                        ),
                                                        TastePill(
                                                          label:
                                                              c.hasParentAccount
                                                                  ? '已绑家长端'
                                                                  : '无家长号',
                                                          tone: c.hasParentAccount
                                                              ? TastePillTone
                                                                  .positive
                                                              : TastePillTone
                                                                  .warning,
                                                        ),
                                                        if (boundMatches
                                                            .isNotEmpty)
                                                          TastePill(
                                                            label:
                                                                '已在库: ${boundMatches.map((m) => m.acc.displayLabel).toSet().join("/")}',
                                                            tone: TastePillTone
                                                                .positive,
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 3),
                                                    SelectableText(
                                                      'studentId: ${c.id}',
                                                      style: Taste.numStyle(
                                                          size: 11,
                                                          color: Taste.muted),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  padding: const EdgeInsets
                                                      .symmetric(horizontal: 8),
                                                ),
                                                onPressed: () {
                                                  Clipboard.setData(
                                                      ClipboardData(
                                                          text: c.id));
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                          '已复制 ${c.name} 的 studentId: ${c.id}'),
                                                      duration: const Duration(
                                                          seconds: 2),
                                                    ),
                                                  );
                                                },
                                                child: const Text('复制ID',
                                                    style: TextStyle(
                                                        fontSize: 11)),
                                              ),
                                              if (boundMatches.isNotEmpty &&
                                                  widget.onSwitchStudent !=
                                                      null)
                                                OutlinedButton(
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8),
                                                  ),
                                                  onPressed: () =>
                                                      widget.onSwitchStudent!(
                                                    boundMatches.first.acc,
                                                    boundMatches.first.stu,
                                                  ),
                                                  child: const Text('查看成绩',
                                                      style: TextStyle(
                                                          fontSize: 11)),
                                                ),
                                              FilledButton.tonal(
                                                style: FilledButton.styleFrom(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10),
                                                  backgroundColor:
                                                      (isRebindMode &&
                                                              c.hasStudentAccount)
                                                          ? Taste.pillNegBg
                                                          : null,
                                                  foregroundColor:
                                                      (isRebindMode &&
                                                              c.hasStudentAccount)
                                                          ? Taste.negative
                                                          : null,
                                                ),
                                                onPressed: (_bindingStudentId !=
                                                            null ||
                                                        alreadyInTarget)
                                                    ? null
                                                    : () =>
                                                        _handleBindByStudentId(
                                                          c.id,
                                                          studentLabel: c.name,
                                                          knownTargetHasStudentAccount:
                                                              c.hasStudentAccount,
                                                        ),
                                                child: Text(
                                                  isBindingThis
                                                      ? (isRebindMode
                                                          ? '换绑中…'
                                                          : '直绑中…')
                                                      : (alreadyInTarget
                                                          ? '该号已绑'
                                                          : (isRebindMode
                                                              ? (c.hasStudentAccount
                                                                  ? '⚠️ 风险换绑'
                                                                  : '⇄ 换绑此人')
                                                              : '一键直绑')),
                                                  style: const TextStyle(
                                                      fontSize: 11.5),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ),
            Taste.buildDialogFooter(
              children: [
                Taste.dialogCancelButton(
                  onPressed: () => Navigator.of(context).pop(),
                  label: '取消',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings & Upstream Diagnostics Dialog
