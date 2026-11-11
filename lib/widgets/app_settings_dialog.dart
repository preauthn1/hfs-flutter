part of '../taste_widgets.dart';

class AppSettingsDialog extends StatefulWidget {
  final AppSettings settings;
  final HfsUpstreamClient client;
  final HfsAccount? activeAccount;
  final List<HfsAccount> accounts;
  final StudentInfo? activeStudent;
  final ValueChanged<AppSettings> onSaveSettings;
  final Future<void> Function() onClearCache;
  final Future<String> Function() onExportConfigJson;
  final Future<void> Function(String rawJson) onImportConfigJson;

  const AppSettingsDialog({
    super.key,
    required this.settings,
    required this.client,
    required this.activeAccount,
    this.accounts = const [],
    this.activeStudent,
    required this.onSaveSettings,
    required this.onClearCache,
    required this.onExportConfigJson,
    required this.onImportConfigJson,
  });

  @override
  State<AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends State<AppSettingsDialog> {
  late AppSettings _draft;
  String _selectedDiagEndpoint = '/v2/user-center/user-snapshot?devicetype=1';
  late String _selectedDiagTargetKey;
  String? _diagOutput;
  bool _runningDiag = false;
  String? _statusMsg;

  static const List<({String path, String label})> _diagEndpoints = [
    (
      path: '/v2/user-center/user-snapshot?devicetype=1',
      label: '用户快照 (/v2/user-center/user-snapshot)'
    ),
    (
      path: '/v2/user-center/related-students',
      label: '关联学生列表 (/v2/user-center/related-students)'
    ),
    (
      path: '/v2/students/classmates',
      label: '同班同学名册 (/v2/students/classmates)'
    ),
    (
      path: '/v2/config/school/hidden-config',
      label: '学校隐藏配置 (/v2/config/school/hidden-config)'
    ),
    (
      path: '/v2/wrong-items/overview',
      label: '错题本概览 (/v2/wrong-items/overview)'
    ),
    (path: '/v3/exam/list?start=0', label: '考试列表 (/v3/exam/list?start=0)'),
  ];

  List<({String key, HfsAccount account, StudentInfo? student, String label})>
      _buildDiagTargets() {
    final sourceAccounts = widget.accounts.isNotEmpty
        ? widget.accounts
        : (widget.activeAccount != null
            ? <HfsAccount>[widget.activeAccount!]
            : const <HfsAccount>[]);
    final targets = <({
      String key,
      HfsAccount account,
      StudentInfo? student,
      String label
    })>[];
    for (final acc in sourceAccounts) {
      if (acc.students.isEmpty) {
        targets.add((
          key: '${acc.id}:',
          account: acc,
          student: null,
          label: '[${acc.displayLabel}] 默认会话',
        ));
      } else {
        for (final stu in acc.students) {
          final cls = '${stu.grade}${stu.className}'.trim();
          final school = stu.schoolName.trim();
          final meta = [
            if (school.isNotEmpty) school,
            if (cls.isNotEmpty) '$cls班',
          ].join(' · ');
          targets.add((
            key: '${acc.id}:${stu.studentId}',
            account: acc,
            student: stu,
            label: meta.isNotEmpty
                ? '[${acc.displayLabel}] ${stu.studentName} ($meta)'
                : '[${acc.displayLabel}] ${stu.studentName}',
          ));
        }
      }
    }
    return targets;
  }

  @override
  void initState() {
    super.initState();
    _draft = widget.settings;
    final accId = widget.activeAccount?.id ?? '';
    final stuId = widget.activeStudent?.studentId ??
        widget.activeAccount?.desiredStudentId ??
        widget.activeAccount?.activeStudentId ??
        '';
    _selectedDiagTargetKey = '$accId:$stuId';
  }

  Future<void> _runDiagnostic() async {
    final targets = _buildDiagTargets();
    if (targets.isEmpty) return;
    final chosen = targets.firstWhere(
      (t) => t.key == _selectedDiagTargetKey,
      orElse: () => targets.first,
    );
    setState(() {
      _runningDiag = true;
      _diagOutput = null;
    });
    try {
      final res = await widget.client.fetchDiagnosticEndpoint(
        chosen.account,
        _selectedDiagEndpoint,
        studentId: chosen.student?.studentId ?? '',
      );
      if (!mounted) return;
      setState(() {
        _runningDiag = false;
        _diagOutput = const JsonEncoder.withIndent('  ').convert(res);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _runningDiag = false;
        _diagOutput = 'Error: $e';
      });
    }
  }

  Future<String> _saveCredentialFileToDisk(
    String content, {
    String? customPath,
  }) async {
    final ts =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final defaultFileName = 'hfs_credentials_$ts.json';

    if (customPath != null && customPath.trim().isNotEmpty) {
      final f = File(customPath.trim());
      await f.parent.create(recursive: true);
      await f.writeAsString(content);
      return f.path;
    }

    final dlDir =
        await HfsImageClipboardAndExporter.resolveDownloadsDirectory();
    final f = File('${dlDir.path}${Platform.pathSeparator}$defaultFileName');
    await f.writeAsString(content, flush: true);
    return f.path;
  }

  Future<void> _exportCredentialFileQuick() async {
    try {
      final exported = await widget.onExportConfigJson();
      final savedPath = await _saveCredentialFileToDisk(exported);
      await Clipboard.setData(ClipboardData(text: exported));
      if (!mounted) return;
      setState(() {
        _statusMsg = '已导出好分数凭证文件至：$savedPath（并已同步复制到剪贴板）';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMsg = '导出凭证文件失败：$e';
      });
    }
  }

  Future<void> _showImportExportModal() async {
    final exported = await widget.onExportConfigJson();
    if (!mounted) return;
    final ctrl = TextEditingController(text: exported);
    final filePathCtrl = TextEditingController();
    String? modalFeedback;
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) => AlertDialog(
            backgroundColor: Taste.surface,
            surfaceTintColor: Colors.transparent,
            insetPadding: Taste.dialogInsetPadding(ctx),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            title: const Text(
              '好分数凭证文件导出与导入 (.json)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SizedBox(
                width: double.infinity,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '包含全部已挂载好分数账号、登录凭证、hfs-session-id Cookie Jar、绑定学生及快照：',
                        style: TextStyle(fontSize: 12, color: Taste.muted),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 34,
                        child: TextField(
                          controller: filePathCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: '指定凭证文件完整路径（留空则自动存至 Downloads）',
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(Taste.radiusControl),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final saved = await _saveCredentialFileToDisk(
                                  ctrl.text,
                                  customPath: filePathCtrl.text,
                                );
                                filePathCtrl.text = saved;
                                setModalState(() {
                                  modalFeedback = '凭证文件已保存至：$saved';
                                });
                              } catch (e) {
                                setModalState(() {
                                  modalFeedback = '保存文件失败：$e';
                                });
                              }
                            },
                            icon: const Icon(Icons.download_outlined, size: 15),
                            label: const Text('导出为文件',
                                style: TextStyle(fontSize: 12)),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final p = filePathCtrl.text.trim();
                              if (p.isEmpty) {
                                setModalState(() {
                                  modalFeedback = '请先在上方输入框填写要读取的 .json 凭证文件路径';
                                });
                                return;
                              }
                              try {
                                final raw = await File(p).readAsString();
                                ctrl.text = raw;
                                setModalState(() {
                                  modalFeedback =
                                      '已从文件读取凭证内容，点击下方「导入并覆盖保存」即可生效';
                                });
                              } catch (e) {
                                setModalState(() {
                                  modalFeedback = '读取凭证文件失败：$e';
                                });
                              }
                            },
                            icon: const Icon(Icons.folder_open_outlined,
                                size: 15),
                            label: const Text('从文件读取',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      if (modalFeedback != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Taste.pillPosBg,
                            borderRadius:
                                BorderRadius.circular(Taste.radiusControl),
                          ),
                          child: SelectableText(
                            modalFeedback!,
                            style: const TextStyle(
                                fontSize: 12, color: Taste.pillPosInk),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: ctrl,
                        maxLines: 8,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '粘贴备份的好分数凭证 JSON 以恢复多账号…',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              Taste.buildDialogFooter(
                padding: const EdgeInsets.only(top: 8),
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: ctrl.text));
                      setModalState(() {
                        modalFeedback = '凭证 JSON 已复制到系统剪贴板';
                      });
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('复制凭证内容'),
                  ),
                  Taste.dialogCancelButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    label: '取消',
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Taste.primary,
                      foregroundColor: Taste.primaryInk,
                      minimumSize: const Size(116, 38),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () async {
                      await widget.onImportConfigJson(ctrl.text);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (mounted) {
                        setState(() => _statusMsg = '好分数凭证已成功导入并恢复');
                      }
                    },
                    child: const Text(
                      '导入并覆盖保存',
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
    } finally {
      ctrl.dispose();
      filePathCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
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
          maxWidth: 540,
          maxHeight: Taste.dialogMaxHeight(context, desktopMax: 680),
        ),
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
                  const Expanded(
                    child: Text(
                      '工作台设置与好分数上游只读诊断',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    '性能与并发设置（避免点击学生时重复拉取网络）',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Taste.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      const Text(
                        '单次拉取历史考试上限（场次越少首次同步越快）：',
                        style: TextStyle(fontSize: 12, color: Taste.muted),
                      ),
                      SizedBox(
                        width: 156,
                        child: DropdownButtonFormField2<int>(
                          value: _draft.maxExamsToHydrate,
                          isExpanded: true,
                          isDense: true,
                          iconStyleData: Taste.dropdownIconStyle,
                          dropdownStyleData: Taste.dropdownStyle(
                            context,
                            maxHeight: 240,
                            dropdownWidth: 180,
                          ),
                          menuItemStyleData: Taste.menuItemStyle(context),
                          selectedItemBuilder: (ctx) => const [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '最近 5 场',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Taste.text),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '最近 10 场 (推荐)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Taste.text),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '最近 15 场',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Taste.text),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '最近 25 场',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Taste.text),
                              ),
                            ),
                          ],
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(Taste.radiusControl),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 5,
                              child: Text('最近 5 场',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            DropdownMenuItem(
                              value: 10,
                              child: Text('最近 10 场 (推荐)',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            DropdownMenuItem(
                              value: 15,
                              child: Text('最近 15 场',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            DropdownMenuItem(
                              value: 25,
                              child: Text('最近 25 场',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _draft =
                                  _draft.copyWith(maxExamsToHydrate: v));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      const Text(
                        '考试详情并发请求数：',
                        style: TextStyle(fontSize: 12, color: Taste.muted),
                      ),
                      SizedBox(
                        width: 156,
                        child: DropdownButtonFormField2<int>(
                          value: _draft.examConcurrency,
                          isExpanded: true,
                          isDense: true,
                          iconStyleData: Taste.dropdownIconStyle,
                          dropdownStyleData: Taste.dropdownStyle(
                            context,
                            maxHeight: 220,
                            dropdownWidth: 180,
                          ),
                          menuItemStyleData: Taste.menuItemStyle(context),
                          selectedItemBuilder: (ctx) => const [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '2 并发',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Taste.text),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '4 并发 (推荐)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Taste.text),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '6 并发',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Taste.text),
                              ),
                            ),
                          ],
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(Taste.radiusControl),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 2,
                              child:
                                  Text('2 并发', style: TextStyle(fontSize: 12)),
                            ),
                            DropdownMenuItem(
                              value: 4,
                              child: Text('4 并发 (推荐)',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            DropdownMenuItem(
                              value: 6,
                              child:
                                  Text('6 并发', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() =>
                                  _draft = _draft.copyWith(examConcurrency: v));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      '调阅答题卡时默认开启批改叠加层',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: _draft.defaultGradingOverlay,
                    onChanged: (v) => setState(() =>
                        _draft = _draft.copyWith(defaultGradingOverlay: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      '切换学生时强制重新拉取网络（关闭则优先秒开本地缓存）',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: _draft.autoHydrateOnSwitch,
                    onChanged: (v) => setState(
                        () => _draft = _draft.copyWith(autoHydrateOnSwitch: v)),
                  ),
                  const Divider(height: 20, color: Taste.border),
                  const Text(
                    '本地缓存与多账号备份管理',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Taste.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await widget.onClearCache();
                          if (!mounted) return;
                          setState(() => _statusMsg = '已清空全部内存与本地缓存快照');
                        },
                        icon: const Icon(Icons.cleaning_services_outlined,
                            size: 15),
                        label: const Text('清空缓存快照',
                            style: TextStyle(fontSize: 12)),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportCredentialFileQuick,
                        icon: const Icon(Icons.download_outlined, size: 15),
                        label: const Text('一键导出好分数凭证文件 (.json)',
                            style: TextStyle(fontSize: 12)),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showImportExportModal,
                        icon: const Icon(Icons.import_export, size: 15),
                        label: const Text('凭证文件管理 / 导入恢复',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  if (_statusMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _statusMsg!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Taste.positive,
                      ),
                    ),
                  ],
                  if (_buildDiagTargets().isNotEmpty) ...[
                    const Divider(height: 24, color: Taste.border),
                    const Text(
                      '好分数官方上游只读接口在线探测',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Taste.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (ctx) {
                        final diagTargets = _buildDiagTargets();
                        final validKey = diagTargets.any(
                          (t) => t.key == _selectedDiagTargetKey,
                        )
                            ? _selectedDiagTargetKey
                            : diagTargets.first.key;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField2<String>(
                              key: ValueKey('diag_target_$validKey'),
                              value: validKey,
                              isExpanded: true,
                              isDense: true,
                              iconStyleData: Taste.dropdownIconStyle,
                              dropdownStyleData: Taste.dropdownStyle(
                                ctx,
                                maxHeight: 280,
                                dropdownWidth: Taste.resolveDropdownMenuWidth(
                                  ctx,
                                  preferredWidth: 360,
                                ),
                              ),
                              menuItemStyleData: Taste.menuItemStyle(ctx),
                              selectedItemBuilder: (context) => [
                                for (final t in diagTargets)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      t.label,
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
                              decoration: const InputDecoration(
                                labelText: '探测目标学生 / 所在班级',
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                              items: [
                                for (final t in diagTargets)
                                  DropdownMenuItem(
                                    value: t.key,
                                    child: Text(
                                      t.label,
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
                                    _selectedDiagTargetKey = v;
                                  });
                                  _runDiagnostic();
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (ctx, box) {
                                final compact = box.maxWidth < 420;
                                final probeButton = OutlinedButton(
                                  onPressed:
                                      _runningDiag ? null : _runDiagnostic,
                                  child: Text(
                                    _runningDiag ? '请求中…' : '直连探测',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                                final endpoint =
                                    DropdownButtonFormField2<String>(
                                  value: _selectedDiagEndpoint,
                                  isExpanded: true,
                                  isDense: true,
                                  iconStyleData: Taste.dropdownIconStyle,
                                  dropdownStyleData: Taste.dropdownStyle(
                                    ctx,
                                    maxHeight: 280,
                                    dropdownWidth: Taste.resolveDropdownMenuWidth(
                                      ctx,
                                      preferredWidth:
                                          compact ? math.max(250.0, box.maxWidth) : 360,
                                    ),
                                  ),
                                  menuItemStyleData: Taste.menuItemStyle(ctx),
                                  selectedItemBuilder: (context) => [
                                    for (final ep in _diagEndpoints)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          ep.label,
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
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                  items: [
                                    for (final ep in _diagEndpoints)
                                      DropdownMenuItem(
                                        value: ep.path,
                                        child: Text(
                                          ep.label,
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
                                      setState(() => _selectedDiagEndpoint = v);
                                    }
                                  },
                                );
                                return compact
                                    ? Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          endpoint,
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: probeButton,
                                          ),
                                        ],
                                      )
                                    : Row(
                                        children: [
                                          Expanded(child: endpoint),
                                          const SizedBox(width: 8),
                                          probeButton,
                                        ],
                                      );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    if (_diagOutput != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Taste.raised,
                          borderRadius:
                              BorderRadius.circular(Taste.radiusControl),
                          border: Border.all(color: Taste.border),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _diagOutput!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Taste.text,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Taste.buildDialogFooter(
              children: [
                Taste.dialogCancelButton(
                  onPressed: () => Navigator.of(context).pop(),
                  label: '取消',
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Taste.primary,
                    foregroundColor: Taste.primaryInk,
                    minimumSize: const Size(104, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Taste.radiusControl),
                    ),
                  ),
                  onPressed: () {
                    widget.onSaveSettings(_draft);
                    Navigator.of(context).pop();
                  },
                  child: const Text('保存设置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
