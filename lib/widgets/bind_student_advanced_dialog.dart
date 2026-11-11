part of '../taste_widgets.dart';

class BindStudentAdvancedDialog extends StatefulWidget {
  final HfsUpstreamClient client;
  final List<HfsAccount> accounts;
  final HfsAccount initialAccount;
  final String? initialReplaceStudentId;
  final Future<void> Function(HfsAccount targetAccount, DashboardData dash)
      onBound;

  const BindStudentAdvancedDialog({
    super.key,
    required this.client,
    required this.accounts,
    required this.initialAccount,
    this.initialReplaceStudentId,
    required this.onBound,
  });

  @override
  State<BindStudentAdvancedDialog> createState() =>
      _BindStudentAdvancedDialogState();
}

class _BindStudentAdvancedDialogState extends State<BindStudentAdvancedDialog> {
  late HfsAccount _targetAccount;
  // '' = 新增绑定模式; non-empty studentId = 换绑替换模式 (`PATCH /v2/native-users/bind-student` selectStudentId)
  String _replaceStudentId = '';
  bool _refreshingQuota = false;
  // 0 = 姓名+学号/考号, 1 = 按学校+年级+姓名查询绑定, 2 = 按学生端账号密码绑定, 3 = 同班名册 + studentId 直绑/换绑
  int _channel = 0;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _authCtrl = TextEditingController();
  final TextEditingController _stuAccCtrl = TextEditingController();
  final TextEditingController _stuPwdCtrl = TextEditingController();
  final TextEditingController _stuIdCtrl = TextEditingController();
  final TextEditingController _schoolIdCtrl = TextEditingController();
  final TextEditingController _gradeCtrl = TextEditingController(text: '初三');

  List<RegionProvinceItem> _provinces = const [];
  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedCounty;
  String? _selectedSchoolId;
  List<RegionSchoolItem> _schools = const [];
  final TextEditingController _regionSearchCtrl = TextEditingController();
  final TextEditingController _schoolSearchCtrl = TextEditingController();
  List<SchoolMatchedStudent> _matchedStudents = const [];
  bool _loadingRegions = false;
  bool _submitting = false;
  String? _error;

  // Channel 3: Combined `GET /v2/students/classmates` + `POST /v2/native-users/bind-students` / `PATCH /v2/native-users/bind-student`
  HfsAccount? _rosterSourceAcc;
  StudentInfo? _rosterSourceStu;
  List<ClassmateBindEntry> _classmates = const [];
  bool _loadingClassmates = false;
  String? _classmatesError;
  String _classmateSearch = '';

  @override
  void initState() {
    super.initState();
    _targetAccount = widget.initialAccount;
    _replaceStudentId = widget.initialReplaceStudentId?.trim() ?? '';
    final all = _allBoundStudents();
    if (all.isNotEmpty) {
      final curMatch = all.where(
        (x) =>
            x.acc.id == widget.initialAccount.id &&
            x.stu.studentId == widget.initialAccount.activeStudentId,
      );
      final chosen = curMatch.isNotEmpty ? curMatch.first : all.first;
      _rosterSourceAcc = chosen.acc;
      _rosterSourceStu = chosen.stu;
    } else {
      _rosterSourceAcc = widget.initialAccount;
    }
    _refreshTargetAccountQuota();
  }

  Future<void> _refreshTargetAccountQuota() async {
    if (_refreshingQuota) return;
    setState(() => _refreshingQuota = true);
    try {
      await widget.client.hydrateAccountStudents(_targetAccount);
      if (!mounted) return;
      setState(() {
        _refreshingQuota = false;
        if (_replaceStudentId.isNotEmpty &&
            !_targetAccount.students
                .any((s) => s.studentId == _replaceStudentId)) {
          _replaceStudentId = '';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _refreshingQuota = false);
    }
  }

  List<({HfsAccount acc, StudentInfo stu})> _allBoundStudents() {
    final out = <({HfsAccount acc, StudentInfo stu})>[];
    for (final a in widget.accounts) {
      for (final s in a.students) {
        out.add((acc: a, stu: s));
      }
    }
    return out;
  }

  Future<void> _loadClassmatesForChannel3() async {
    final acc = _rosterSourceAcc ?? _targetAccount;
    setState(() {
      _loadingClassmates = true;
      _classmatesError = null;
    });
    try {
      final list = await widget.client.fetchClassmates(
        acc,
        studentId: _rosterSourceStu?.studentId ?? '',
      );
      if (!mounted) return;
      setState(() {
        _classmates = list;
        _loadingClassmates = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingClassmates = false;
        _classmatesError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _authCtrl.dispose();
    _stuAccCtrl.dispose();
    _stuPwdCtrl.dispose();
    _stuIdCtrl.dispose();
    _schoolIdCtrl.dispose();
    _gradeCtrl.dispose();
    _regionSearchCtrl.dispose();
    _schoolSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRegionsIfNeeded() async {
    if (_provinces.isNotEmpty || _loadingRegions) return;
    setState(() {
      _loadingRegions = true;
      _error = null;
    });
    try {
      final list = await widget.client.fetchRegions(_targetAccount);
      if (!mounted) return;
      setState(() {
        _provinces = list;
        _loadingRegions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRegions = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadSchools(String prov, String city, String county) async {
    setState(() {
      _loadingRegions = true;
      _error = null;
    });
    try {
      final list = await widget.client.fetchRegionSchools(
        account: _targetAccount,
        province: prov,
        city: city,
        county: county,
      );
      if (!mounted) return;
      setState(() {
        _schools = list;
        if (list.isNotEmpty) {
          _selectedSchoolId = list.first.id;
          _schoolIdCtrl.text = list.first.id;
        } else {
          _selectedSchoolId = null;
        }
        _loadingRegions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRegions = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _querySchoolStudents() async {
    final sid = _schoolIdCtrl.text.trim();
    final sName = _nameCtrl.text.trim();
    if (sid.isEmpty || sName.isEmpty) {
      setState(() => _error = '请填写学校 ID（或从上方省市区选择学校）与学生姓名');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final matches = await widget.client.matchStudentsBySchool(
        account: _targetAccount,
        schoolId: sid,
        studentName: sName,
        grade: _gradeCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _matchedStudents = matches;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  StudentInfo? get _selectedReplaceStudent {
    if (_replaceStudentId.isEmpty) return null;
    for (final s in _targetAccount.students) {
      if (s.studentId == _replaceStudentId) return s;
    }
    return null;
  }

  Future<bool?> _confirmRebindSafety({
    required StudentInfo sourceStu,
    String? targetName,
    bool? knownTargetHasStudentAccount,
  }) async {
    bool forceAllowStuAcc = false;
    final needsStuAccWarn = knownTargetHasStudentAccount == true;
    final needsMinusOneWarn = sourceStu.isMinusOneSlot;
    if (!needsStuAccWarn && !needsMinusOneWarn) {
      return false; // Proceed without needing forceAllowStudentAccountTarget
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
                    '目标新学生：${targetName ?? "所选目标学生"}\n'
                    '挂载账号：${_targetAccount.displayLabel}',
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
                        '• 一旦换绑为新学生，新记录将一律写入 +180 天学期锁，本账号的 -1 活名额将从 ${_targetAccount.minusOneSlotCount} 个减为 ${math.max(0, _targetAccount.minusOneSlotCount - 1)} 个，账号总容量上限将从 ${_targetAccount.estimatedMaxQuota} 人永久降为 ${math.max(3, _targetAccount.estimatedMaxQuota - 1)} 人。',
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
                        '• 严重警告：检测到目标同学已激活学生端账号 (bindStudent 非空)！\n'
                        '• 好分数上游 PATCH /v2/native-users/bind-student 存在非原子写缺陷：当目标带有学生端账号时，服务端会返回 4137 Duplicate links，但会把源学生直接删除、目标学生却未加入（导致白白丢失一名已绑学生）！\n'
                        '• 强烈建议取消本次换绑，改选无学生端账号的目标或使用新增直绑。',
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
                        '我已知晓 4137 删源不加目标风险，仍强制发送换绑请求',
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
                  label: '取消换绑',
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

  Future<void> _submitBind({
    String? directStudentId,
    bool? knownTargetHasStudentAccount,
    String? targetStudentName,
  }) async {
    final replaceStu = _selectedReplaceStudent;
    bool forceAllowStuAcc = false;

    if (replaceStu != null) {
      if (replaceStu.isSemesterLocked) {
        setState(() {
          _error =
              '源学生「${replaceStu.studentName}」处于学期锁定期（${replaceStu.changeBindStatusLabel}），每学期只能换绑一次 (4137)，请更换其他可换绑槽位。';
        });
        return;
      }
      final confirmed = await _confirmRebindSafety(
        sourceStu: replaceStu,
        targetName: targetStudentName ?? directStudentId,
        knownTargetHasStudentAccount: knownTargetHasStudentAccount,
      );
      if (confirmed == null) return; // User cancelled
      forceAllowStuAcc = confirmed;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      late DashboardData dash;
      if (directStudentId != null && directStudentId.isNotEmpty) {
        if (replaceStu != null) {
          dash = await widget.client.rebindStudent(
            account: _targetAccount,
            selectStudentId: replaceStu.studentId,
            targetStudentId: directStudentId,
            schoolAuthCode: _authCtrl.text.trim(),
            knownTargetHasStudentAccount: knownTargetHasStudentAccount,
            forceAllowStudentAccountTarget: forceAllowStuAcc,
          );
        } else {
          dash = await widget.client.bindStudentById(
            account: _targetAccount,
            studentId: directStudentId,
          );
        }
      } else if (_channel == 0) {
        if (_nameCtrl.text.trim().isEmpty || _codeCtrl.text.trim().isEmpty) {
          throw Exception('请填写学生姓名与学号/准考证号');
        }
        dash = await widget.client.bindStudent(
          account: _targetAccount,
          studentName: _nameCtrl.text.trim(),
          identityCode: _codeCtrl.text.trim(),
          schoolAuthCode: _authCtrl.text.trim(),
          replaceStudentId: replaceStu?.studentId ?? '',
        );
      } else if (_channel == 2) {
        if (_stuAccCtrl.text.trim().isEmpty || _stuPwdCtrl.text.isEmpty) {
          throw Exception('请填写好分数学生端账号与密码');
        }
        dash = await widget.client.bindStudentByAccount(
          account: _targetAccount,
          studentAccount: _stuAccCtrl.text.trim(),
          studentPassword: _stuPwdCtrl.text,
          chooseStudentId: replaceStu?.studentId ?? '',
        );
      } else if (_channel == 3) {
        final rawId = _stuIdCtrl.text.trim();
        if (rawId.isEmpty) {
          throw Exception('请填写或从下方同班名册点选内部 studentId');
        }
        // Check if this ID is in loaded classmates to know `hasStudentAccount`
        bool? knownHasStu = knownTargetHasStudentAccount;
        if (knownHasStu == null) {
          for (final c in _classmates) {
            if (c.id == rawId) {
              knownHasStu = c.hasStudentAccount;
              break;
            }
          }
        }
        if (replaceStu != null) {
          dash = await widget.client.rebindStudent(
            account: _targetAccount,
            selectStudentId: replaceStu.studentId,
            targetStudentId: rawId,
            schoolAuthCode: _authCtrl.text.trim(),
            knownTargetHasStudentAccount: knownHasStu,
            forceAllowStudentAccountTarget: forceAllowStuAcc,
          );
        } else {
          dash = await widget.client.bindStudentById(
            account: _targetAccount,
            studentId: rawId,
          );
        }
      } else {
        throw Exception('请先点击“查询学生”，然后点击对应学生的绑定/换绑按钮');
      }

      if (!mounted) return;
      await widget.onBound(_targetAccount, dash);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    RegionProvinceItem? curProv;
    for (final p in _provinces) {
      if (p.name == _selectedProvince) curProv = p;
    }
    RegionCityItem? curCity;
    if (curProv != null) {
      for (final c in curProv.cities) {
        if (c.name == _selectedCity) curCity = c;
      }
    }

    final replaceStu = _selectedReplaceStudent;
    final isRebindMode = replaceStu != null;

    return Dialog(
      backgroundColor: Taste.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: Taste.dialogInsetPadding(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Taste.radiusCard),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: Taste.dialogMaxHeight(context, desktopMax: 700),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                      isRebindMode
                          ? '换绑学生（替换「${replaceStu.studentName}」· PATCH bind-student）'
                          : '多通道绑定与换绑学生',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: Taste.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Taste.text,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (ctx, box) {
                        final compact = box.maxWidth < 420;
                        final accountDropdown = DropdownButtonFormField2<String>(
                          key: ValueKey(
                              'bind_acc_${_targetAccount.id}_${_targetAccount.students.length}'),
                          value: _targetAccount.id,
                          isExpanded: true,
                          isDense: true,
                          iconStyleData: Taste.dropdownIconStyle,
                          dropdownStyleData: Taste.dropdownStyle(
                            ctx,
                            maxHeight: 280,
                            dropdownWidth: Taste.resolveDropdownMenuWidth(
                              ctx,
                              preferredWidth: compact
                                  ? math.max(250.0, box.maxWidth)
                                  : math.max(300.0, box.maxWidth - 76.0),
                            ),
                          ),
                          menuItemStyleData: Taste.menuItemStyle(ctx),
                          selectedItemBuilder: (context) => [
                            for (final a in widget.accounts)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${a.displayLabel} (${a.roleType == 1 ? "学生端" : "家长端"} · 已绑${a.students.length}/${a.estimatedMaxQuota}人)',
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
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(Taste.radiusControl),
                            ),
                          ),
                          items: [
                            for (final a in widget.accounts)
                              DropdownMenuItem(
                                value: a.id,
                                child: Text(
                                  '${a.displayLabel} (${a.roleType == 1 ? "学生端" : "家长端"} · 已绑${a.students.length}/${a.estimatedMaxQuota}人)',
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
                          onChanged: _submitting
                              ? null
                              : (val) {
                                  if (val == null) return;
                                  final found = widget.accounts
                                      .firstWhere((a) => a.id == val);
                                  setState(() {
                                    _targetAccount = found;
                                    _replaceStudentId = '';
                                    _error = null;
                                  });
                                  _refreshTargetAccountQuota();
                                },
                        );
                        final refreshBtn = IconButton(
                          tooltip:
                              '实时刷新该账号关联学生与换绑锁状态 (GET /v2/user-center/related-students)',
                          visualDensity: VisualDensity.compact,
                          onPressed: _refreshingQuota
                              ? null
                              : _refreshTargetAccountQuota,
                          icon: _refreshingQuota
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.8),
                                )
                              : const Icon(Icons.refresh, size: 16),
                        );
                        return compact
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          '目标账号：',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Taste.muted,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      refreshBtn,
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  accountDropdown,
                                ],
                              )
                            : Row(
                                children: [
                                  const Text(
                                    '目标账号：',
                                    style: TextStyle(
                                        fontSize: 12, color: Taste.muted),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: accountDropdown),
                                  const SizedBox(width: 6),
                                  refreshBtn,
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 8),
                    // Quota & Add vs Rebind Slot Selector Box
                    Container(
                      padding: const EdgeInsets.all(10),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TastePill(
                                label:
                                    '已绑 ${_targetAccount.students.length} / 上限 ${_targetAccount.estimatedMaxQuota} 人',
                                tone: _targetAccount.isQuotaFull
                                    ? TastePillTone.warning
                                    : TastePillTone.positive,
                              ),
                              TastePill(
                                label:
                                    '-1活名额: ${_targetAccount.minusOneSlotCount} 个',
                                tone: _targetAccount.minusOneSlotCount > 0
                                    ? TastePillTone.blue
                                    : TastePillTone.neutral,
                              ),
                              TastePill(
                                label: _targetAccount.isQuotaFull
                                    ? '新增配额已满(4010/4025)，请选下方槽位换绑'
                                    : '可新增 ${_targetAccount.remainingAddQuota} 人',
                                tone: _targetAccount.isQuotaFull
                                    ? TastePillTone.warning
                                    : TastePillTone.positive,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '选择绑定模式（新增绑定 或 点击已有学生进行换绑）：',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Taste.text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          IsolatedHorizontalScroll(
                            convertVerticalWheelToHorizontal: true,
                            child: Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    visualDensity: VisualDensity.compact,
                                    selected: _replaceStudentId.isEmpty,
                                    label: const Text(
                                      '＋ 新增绑定 (不替换已有学生)',
                                      style: TextStyle(fontSize: 11.5),
                                    ),
                                    onSelected: _submitting
                                        ? null
                                        : (_) => setState(() {
                                              _replaceStudentId = '';
                                              _error = null;
                                            }),
                                  ),
                                ),
                                for (final s in _targetAccount.students)
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
                                          fontSize: 11.5,
                                          color: s.isSemesterLocked
                                              ? Taste.muted
                                              : null,
                                        ),
                                      ),
                                      onSelected: _submitting
                                          ? null
                                          : (_) => setState(() {
                                                _replaceStudentId =
                                                    _replaceStudentId ==
                                                            s.studentId
                                                        ? ''
                                                        : s.studentId;
                                                _error = null;
                                              }),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (replaceStu != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              replaceStu.isSemesterLocked
                                  ? '⚠️ 「${replaceStu.studentName}」处于180天学期锁定期（${replaceStu.changeBindStatusLabel}），换绑会返回 4137 错误。'
                                  : (replaceStu.isMinusOneSlot
                                      ? '⚠️ 正在使用「${replaceStu.studentName}」(-1活名额) 进行换绑：换绑成功后新学生将写入 +180天锁，本号上限将减 1。'
                                      : '✓ 已选择将「${replaceStu.studentName}」换绑为下方指定的新学生（PATCH /v2/native-users/bind-student）。'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: replaceStu.isSemesterLocked
                                    ? Taste.negative
                                    : Taste.pillWarnInk,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildChannelChip(0, '姓名 + 学号/考号'),
                        _buildChannelChip(1, '学校 + 年级 + 姓名'),
                        _buildChannelChip(2, '学生端账号密码'),
                        _buildChannelChip(3, '同班名册 + studentId 直绑/换绑'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_channel == 0) ...[
                      _inputField('学生姓名', _nameCtrl, '请输入学生真实姓名'),
                      const SizedBox(height: 10),
                      _inputField('学号 / 准考证号 / 考号', _codeCtrl, '请输入学号或考号'),
                      const SizedBox(height: 10),
                      _inputField('学校授权码（选填）', _authCtrl, '无授权码请留空'),
                    ] else if (_channel == 1) ...[
                      LayoutBuilder(
                        builder: (ctx, box) {
                          final compact = box.maxWidth < 420;
                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _inputField(
                                  '学校 ID (如已知可直接填)',
                                  _schoolIdCtrl,
                                  '如 [REDACTED]',
                                ),
                                const SizedBox(height: 8),
                                _inputField(
                                  '年级',
                                  _gradeCtrl,
                                  '如 初三 / 高一',
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                child: _inputField(
                                  '学校 ID (如已知可直接填)',
                                  _schoolIdCtrl,
                                  '如 [REDACTED]',
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 110,
                                child: _inputField(
                                  '年级',
                                  _gradeCtrl,
                                  '如 初三 / 高一',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      if (_provinces.isEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed:
                                _loadingRegions ? null : _loadRegionsIfNeeded,
                            icon: const Icon(Icons.map_outlined, size: 15),
                            label: Text(
                              _loadingRegions
                                  ? '正在加载省市区…'
                                  : '不知道学校 ID？展开省市区检索学校',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                      else ...[
                        LayoutBuilder(
                          builder: (ctx, regionBox) {
                            final regionPopupW = Taste.resolveDropdownMenuWidth(
                              ctx,
                              preferredWidth: math.max(240.0, regionBox.maxWidth),
                            );
                            final schoolPopupW = Taste.resolveDropdownMenuWidth(
                              ctx,
                              preferredWidth: math.max(260.0, regionBox.maxWidth),
                            );
                            DropdownSearchData<String> regionSearch(String hint) {
                              return DropdownSearchData<String>(
                                searchController: _regionSearchCtrl,
                                searchInnerWidgetHeight: 44,
                                searchInnerWidget: Container(
                                  height: 44,
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 8, 8, 4),
                                  child: TextField(
                                    controller: _regionSearchCtrl,
                                    style: const TextStyle(fontSize: 12),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: hint,
                                      prefixIcon:
                                          const Icon(Icons.search, size: 15),
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
                                  return (item.value ?? '')
                                      .toLowerCase()
                                      .contains(q);
                                },
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DropdownButtonFormField2<String>(
                                  key: ValueKey('prov_sel_${_selectedProvince ?? "none"}'),
                                  value: _selectedProvince,
                                  isExpanded: true,
                                  isDense: true,
                                  iconStyleData: Taste.dropdownIconStyle,
                                  dropdownStyleData: Taste.dropdownStyle(
                                    ctx,
                                    maxHeight: 280,
                                    dropdownWidth: regionPopupW,
                                  ),
                                  menuItemStyleData: Taste.menuItemStyle(ctx),
                                  dropdownSearchData:
                                      regionSearch('搜索省份 / 直辖市…'),
                                  onMenuStateChange: (isOpen) {
                                    if (!isOpen) _regionSearchCtrl.clear();
                                  },
                                  selectedItemBuilder: (context) => [
                                    for (final p in _provinces)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          p.name,
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
                                  hint: const Text(
                                    '选择省份 / 直辖市',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: Taste.muted),
                                  ),
                                  decoration: InputDecoration(
                                    labelText: '省份',
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(Taste.radiusControl),
                                    ),
                                  ),
                                  items: [
                                    for (final p in _provinces)
                                      DropdownMenuItem(
                                        value: p.name,
                                        child: Text(
                                          p.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: Taste.text,
                                          ),
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) => setState(() {
                                    _selectedProvince = v;
                                    _selectedCity = null;
                                    _selectedCounty = null;
                                    _selectedSchoolId = null;
                                    _schools = const [];
                                  }),
                                ),
                                if (curProv != null) ...[
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField2<String>(
                                    key: ValueKey(
                                        'city_sel_${_selectedProvince}_${_selectedCity ?? "none"}'),
                                    value: _selectedCity,
                                    isExpanded: true,
                                    isDense: true,
                                    iconStyleData: Taste.dropdownIconStyle,
                                    dropdownStyleData: Taste.dropdownStyle(
                                      ctx,
                                      maxHeight: 280,
                                      dropdownWidth: regionPopupW,
                                    ),
                                    menuItemStyleData: Taste.menuItemStyle(ctx),
                                    dropdownSearchData:
                                        regionSearch('搜索城市 / 地区…'),
                                    onMenuStateChange: (isOpen) {
                                      if (!isOpen) _regionSearchCtrl.clear();
                                    },
                                    selectedItemBuilder: (context) => [
                                      for (final c in curProv!.cities)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            c.name,
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
                                    hint: const Text(
                                      '选择城市 / 地区',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, color: Taste.muted),
                                    ),
                                    decoration: InputDecoration(
                                      labelText: '城市',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(Taste.radiusControl),
                                      ),
                                    ),
                                    items: [
                                      for (final c in curProv.cities)
                                        DropdownMenuItem(
                                          value: c.name,
                                          child: Text(
                                            c.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              color: Taste.text,
                                            ),
                                          ),
                                        ),
                                    ],
                                    onChanged: (v) => setState(() {
                                      _selectedCity = v;
                                      _selectedCounty = null;
                                      _selectedSchoolId = null;
                                      _schools = const [];
                                    }),
                                  ),
                                ],
                                if (curCity != null) ...[
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField2<String>(
                                    key: ValueKey(
                                        'county_sel_${_selectedCity}_${_selectedCounty ?? "none"}'),
                                    value: _selectedCounty,
                                    isExpanded: true,
                                    isDense: true,
                                    iconStyleData: Taste.dropdownIconStyle,
                                    dropdownStyleData: Taste.dropdownStyle(
                                      ctx,
                                      maxHeight: 280,
                                      dropdownWidth: regionPopupW,
                                    ),
                                    menuItemStyleData: Taste.menuItemStyle(ctx),
                                    dropdownSearchData:
                                        regionSearch('搜索区县名称…'),
                                    onMenuStateChange: (isOpen) {
                                      if (!isOpen) _regionSearchCtrl.clear();
                                    },
                                    selectedItemBuilder: (context) => [
                                      for (final co in curCity!.counties)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            co,
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
                                    hint: const Text(
                                      '选择区县（自动拉取该区县学校列表）',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, color: Taste.muted),
                                    ),
                                    decoration: InputDecoration(
                                      labelText: '区县',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(Taste.radiusControl),
                                      ),
                                    ),
                                    items: [
                                      for (final co in curCity.counties)
                                        DropdownMenuItem(
                                          value: co,
                                          child: Text(
                                            co,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              color: Taste.text,
                                            ),
                                          ),
                                        ),
                                    ],
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setState(() => _selectedCounty = v);
                                      _loadSchools(
                                          _selectedProvince!, _selectedCity!, v);
                                    },
                                  ),
                                ],
                                if (_schools.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField2<String>(
                                    key: ValueKey(
                                      'school_sel_${_schools.first.id}_${_selectedSchoolId ?? _schools.first.id}',
                                    ),
                                    value: _schools.any((s) => s.id == _selectedSchoolId)
                                        ? _selectedSchoolId
                                        : _schools.first.id,
                                    isExpanded: true,
                                    isDense: true,
                                    iconStyleData: Taste.dropdownIconStyle,
                                    dropdownStyleData: Taste.dropdownStyle(
                                      ctx,
                                      maxHeight: 340,
                                      dropdownWidth: schoolPopupW,
                                    ),
                                    menuItemStyleData: Taste.menuItemStyle(ctx),
                                    dropdownSearchData: DropdownSearchData<String>(
                                      searchController: _schoolSearchCtrl,
                                      searchInnerWidgetHeight: 46,
                                      searchInnerWidget: Container(
                                        height: 46,
                                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                                        child: TextField(
                                          controller: _schoolSearchCtrl,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            hintText: '搜索学校名称或学校 ID…',
                                            prefixIcon: const Icon(Icons.search, size: 15),
                                            contentPadding: const EdgeInsets.symmetric(
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
                                        final val = (item.value ?? '').toLowerCase();
                                        final matchSchool = _schools
                                            .where((s) => s.id == item.value)
                                            .toList();
                                        final name = matchSchool.isNotEmpty
                                            ? matchSchool.first.name.toLowerCase()
                                            : '';
                                        return val.contains(q) || name.contains(q);
                                      },
                                    ),
                                    onMenuStateChange: (isOpen) {
                                      if (!isOpen) {
                                        _schoolSearchCtrl.clear();
                                      }
                                    },
                                    selectedItemBuilder: (context) => [
                                      for (final s in _schools)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            '${s.name} (ID: ${s.id})',
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
                                      labelText: '选择学校（支持关键词搜索）',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(Taste.radiusControl),
                                      ),
                                    ),
                                    items: [
                                      for (final s in _schools)
                                        DropdownMenuItem(
                                          value: s.id,
                                          child: Text(
                                            '${s.name} (ID: ${s.id})',
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
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() {
                                          _selectedSchoolId = v;
                                          _schoolIdCtrl.text = v;
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (ctx, box) {
                          final compact = box.maxWidth < 420;
                          return compact
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _inputField(
                                      '学生姓名',
                                      _nameCtrl,
                                      '输入姓名查询脱敏学号与 ID',
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: OutlinedButton(
                                        onPressed: _submitting
                                            ? null
                                            : _querySchoolStudents,
                                        child: const Text(
                                          '查询学生',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: _inputField(
                                        '学生姓名',
                                        _nameCtrl,
                                        '输入姓名查询脱敏学号与 ID',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      height: 36,
                                      child: OutlinedButton(
                                        onPressed: _submitting
                                            ? null
                                            : _querySchoolStudents,
                                        child: const Text(
                                          '查询学生',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                        },
                      ),
                      if (_matchedStudents.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        for (final ms in _matchedStudents)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Taste.raised,
                              borderRadius:
                                  BorderRadius.circular(Taste.radiusControl),
                              border: Border.all(color: Taste.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${ms.name} · ${ms.grade}${ms.className}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        'ID: ${ms.id} · 学号: ${ms.maskedXuehao.isEmpty ? "—" : ms.maskedXuehao}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Taste.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                FilledButton.tonal(
                                  onPressed: _submitting
                                      ? null
                                      : () => _submitBind(
                                            directStudentId: ms.id,
                                            targetStudentName: ms.name,
                                          ),
                                  child: Text(
                                    isRebindMode ? '换绑此人' : '立即绑定',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ] else if (_channel == 2) ...[
                      _inputField('好分数学生端账号', _stuAccCtrl, '输入学生端登录名'),
                      const SizedBox(height: 10),
                      _inputField('学生端登录密码', _stuPwdCtrl, '输入学生端密码',
                          obscure: true),
                    ] else ...[
                      _buildChannel3ClassmatesAndDirectBind(),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Taste.pillNegBg,
                          borderRadius:
                              BorderRadius.circular(Taste.radiusControl),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Taste.pillNegInk,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Taste.buildDialogFooter(
              children: [
                Taste.dialogCancelButton(
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                  label: '取消',
                ),
                if (_channel != 1)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Taste.primary,
                      foregroundColor: Taste.primaryInk,
                      minimumSize: const Size(116, 40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(Taste.radiusControl),
                      ),
                    ),
                    onPressed: _submitting ? null : () => _submitBind(),
                    child: Text(
                      _submitting
                          ? (isRebindMode ? '正在换绑…' : '正在绑定…')
                          : (isRebindMode
                              ? '确认换绑替换「${replaceStu.studentName}」'
                              : '确认新增绑定'),
                      maxLines: 2,
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

  Widget _buildChannelChip(int idx, String label) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: _channel == idx,
      visualDensity: VisualDensity.compact,
      onSelected: _submitting
          ? null
          : (_) {
              setState(() {
                _channel = idx;
                _error = null;
              });
              if (idx == 3 && _classmates.isEmpty && !_loadingClassmates) {
                _loadClassmatesForChannel3();
              }
            },
    );
  }

  Widget _buildChannel3ClassmatesAndDirectBind() {
    final allBound = _allBoundStudents();
    final replaceStu = _selectedReplaceStudent;
    final isRebindMode = replaceStu != null;
    final filteredClassmates = _classmates.where((c) {
      if (_classmateSearch.trim().isEmpty) return true;
      final q = _classmateSearch.trim();
      return c.name.contains(q) || c.id.contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (ctx, box) {
            final compact = box.maxWidth < 420;
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _inputField(
                        isRebindMode
                            ? '目标新学生 studentId (换绑「${replaceStu.studentName}」)'
                            : '直接输入或从下方名册点选 studentId',
                        _stuIdCtrl,
                        '24 位内部 studentId',
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonal(
                          onPressed: _submitting ? null : () => _submitBind(),
                          child: Text(
                            isRebindMode ? '换绑该 ID' : '直绑该 ID',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _inputField(
                          isRebindMode
                              ? '目标新学生 studentId (PATCH /v2/native-users/bind-student 替换「${replaceStu.studentName}」)'
                              : '直接输入或从下方名册点选 studentId (POST /v2/native-users/bind-students)',
                          _stuIdCtrl,
                          '24 位内部 studentId，点击下方同学可自动填入或一键执行',
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 36,
                        child: FilledButton.tonal(
                          onPressed: _submitting ? null : () => _submitBind(),
                          child: Text(
                            isRebindMode ? '换绑该 ID' : '直绑该 ID',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  );
          },
        ),
        if (isRebindMode) ...[
          const SizedBox(height: 8),
          _inputField('学校授权码（选填，换绑跨校或需授权码时填写）', _authCtrl, '无授权码请留空'),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Taste.raised,
            borderRadius: BorderRadius.circular(Taste.radiusControl),
            border: Border.all(color: Taste.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    '获取同班学生名册 (/v2/students/classmates · 共 ${_classmates.length} 人)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Taste.text,
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed:
                        _loadingClassmates ? null : _loadClassmatesForChannel3,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('刷新名册', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              if (allBound.isNotEmpty) ...[
                const SizedBox(height: 4),
                IsolatedHorizontalScroll(
                  convertVerticalWheelToHorizontal: true,
                  child: Row(
                    children: [
                      const Text(
                        '名册班级来源：',
                        style: TextStyle(fontSize: 11, color: Taste.muted),
                      ),
                      const SizedBox(width: 4),
                      for (final item in allBound)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            selected: _rosterSourceAcc?.id == item.acc.id &&
                                _rosterSourceStu?.studentId ==
                                    item.stu.studentId,
                            label: Text(
                              '${item.stu.studentName} (${item.stu.grade}${item.stu.className})',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onSelected: (_) {
                              setState(() {
                                _rosterSourceAcc = item.acc;
                                _rosterSourceStu = item.stu;
                              });
                              _loadClassmatesForChannel3();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: TextField(
                  onChanged: (v) => setState(() => _classmateSearch = v),
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '搜索同班同学姓名或 studentId…',
                    prefixIcon: const Icon(Icons.search, size: 15),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    filled: true,
                    fillColor: Taste.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Taste.radiusControl),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_loadingClassmates)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_classmatesError != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _classmatesError!,
                    style: const TextStyle(fontSize: 12, color: Taste.negative),
                  ),
                )
              else if (filteredClassmates.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                    child: Text(
                      '暂无匹配的同班同学记录',
                      style: TextStyle(fontSize: 12, color: Taste.muted),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filteredClassmates.length,
                    separatorBuilder: (ctx, idx) =>
                        const Divider(height: 1, color: Taste.rule),
                    itemBuilder: (ctx, i) {
                      final c = filteredClassmates[i];
                      final alreadyInTarget = _targetAccount.students
                          .any((s) => s.studentId == c.id);
                      final boundAccLabels = widget.accounts
                          .where(
                              (a) => a.students.any((s) => s.studentId == c.id))
                          .map((a) => a.displayLabel)
                          .toList();
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 2),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 5,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '${i + 1}. ${c.name}',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (c.isMember)
                                      const TastePill(
                                        label: 'VIP',
                                        tone: TastePillTone.warning,
                                      ),
                                    TastePill(
                                      label: c.hasStudentAccount
                                          ? '已绑学生端'
                                          : '无学生号',
                                      tone: c.hasStudentAccount
                                          ? TastePillTone.blue
                                          : TastePillTone.neutral,
                                    ),
                                    TastePill(
                                      label:
                                          c.hasParentAccount ? '已绑家长端' : '无家长号',
                                      tone: c.hasParentAccount
                                          ? TastePillTone.positive
                                          : TastePillTone.warning,
                                    ),
                                    if (boundAccLabels.isNotEmpty)
                                      TastePill(
                                        label:
                                            '已绑: ${boundAccLabels.join("/")}',
                                        tone: TastePillTone.positive,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                SelectableText(
                                  'studentId: ${c.id}',
                                  style: Taste.numStyle(
                                      size: 10.5, color: Taste.muted),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                  ),
                                  onPressed: () {
                                    setState(() => _stuIdCtrl.text = c.id);
                                  },
                                  child: const Text('填入ID',
                                      style: TextStyle(fontSize: 11)),
                                ),
                                FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    backgroundColor:
                                        (isRebindMode && c.hasStudentAccount)
                                            ? Taste.pillNegBg
                                            : null,
                                    foregroundColor:
                                        (isRebindMode && c.hasStudentAccount)
                                            ? Taste.negative
                                            : null,
                                  ),
                                  onPressed: (_submitting || alreadyInTarget)
                                      ? null
                                      : () {
                                          _stuIdCtrl.text = c.id;
                                          _submitBind(
                                            directStudentId: c.id,
                                            knownTargetHasStudentAccount:
                                                c.hasStudentAccount,
                                            targetStudentName: c.name,
                                          );
                                        },
                                  child: Text(
                                    alreadyInTarget
                                        ? '当前号已绑'
                                        : (isRebindMode
                                            ? (c.hasStudentAccount
                                                ? '⚠️ 风险换绑'
                                                : '⇄ 换绑此人')
                                            : '一键直绑'),
                                    style: const TextStyle(fontSize: 11),
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
      ],
    );
  }

  Widget _inputField(
    String label,
    TextEditingController ctrl,
    String hint, {
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Taste.muted,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: TextField(
            controller: ctrl,
            obscureText: obscure,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 12, color: Taste.faint),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Taste.radiusControl),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Interactive Wrong-Items Notebook View (Full question stem, student answer crop, xueba answer, jump to paper)
