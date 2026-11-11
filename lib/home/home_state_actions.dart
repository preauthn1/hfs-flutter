part of '../main.dart';

extension _HfsHomeStateActionsExt on _HfsHomeScreenState {
  Future<void> _restoreState() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final rawSettings = prefs.getString(_prefsSettingsKey);
      if (rawSettings != null && rawSettings.isNotEmpty) {
        final decoded = jsonDecode(rawSettings);
        if (decoded is Map) {
          _settings = AppSettings.fromJson(Map<String, dynamic>.from(decoded));
          _inspectorWidth = _settings.inspectorWidth;
        }
      }

      final rawList = prefs.getString(_prefsAccountsKey);
      final savedSel = prefs.getString(_prefsSelectedKey) ?? '';
      if (rawList != null && rawList.isNotEmpty) {
        final decoded = jsonDecode(rawList);
        if (decoded is List) {
          _accounts = decoded
              .whereType<Map>()
              .map((e) => HfsAccount.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
      if (_accounts.isNotEmpty) {
        _selectedAccountId = _accounts.any((a) => a.id == savedSel)
            ? savedSel
            : _accounts.first.id;
      }

      // Restore persisted Dashboard snapshots into memory cache for instant 0ms switch
      for (final acc in _accounts) {
        for (final stu in acc.students) {
          final snapRaw = prefs.getString(
            '$_prefsDashSnapPrefix${acc.id}:${stu.studentId}',
          );
          if (snapRaw != null && snapRaw.isNotEmpty) {
            try {
              final m = jsonDecode(snapRaw);
              if (m is Map) {
                final dash = DashboardData.fromJson(
                  acc,
                  Map<String, dynamic>.from(m),
                );
                _client.seedDashboardCache(acc.id, stu.studentId, dash);
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    if (!mounted) return;
    final curAcc = _currentAccount;
    DashboardData? instantDash;
    if (curAcc != null && curAcc.activeStudentId.isNotEmpty) {
      instantDash =
          _client.peekCachedDashboard(curAcc.id, curAcc.activeStudentId);
    }
    _setHomeState(() {
      _initializing = false;
      if (instantDash != null) {
        _dashboard = instantDash;
        _syncInspectorWithDashboard(instantDash);
      }
      _rebuildFleetRows();
    });

    if (curAcc != null) {
      // Refresh in background (or foreground if no cached snapshot)
      unawaited(_loadDashboardForCurrent(allowCache: instantDash != null));
    }
  }

  Future<void> _persistAccountsAndSettings() async {
    final prev = _persistGate;
    final completer = Completer<void>();
    _persistGate = completer.future;
    if (prev != null) {
      try {
        await prev;
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_accounts.map((a) => a.toJson()).toList());
      await prefs.setString(_prefsAccountsKey, raw);
      await prefs.setString(_prefsSelectedKey, _selectedAccountId);
      await prefs.setString(
        _prefsSettingsKey,
        jsonEncode(
          _settings.copyWith(inspectorWidth: _inspectorWidth).toJson(),
        ),
      );
    } catch (_) {
    } finally {
      completer.complete();
    }
  }

  Future<void> _persistDashboardSnapshot(DashboardData dash) async {
    final sid = dash.currentStudent?.studentId ?? dash.account.activeStudentId;
    if (sid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefsDashSnapPrefix${dash.account.id}:$sid',
        jsonEncode(dash.toJson()),
      );
    } catch (_) {}
  }

  void _syncInspectorWithDashboard(
    DashboardData dash, {
    bool openRightPane = true,
  }) {
    if (dash.exams.isEmpty) {
      _selectedExamId = '';
      _inspectingExam = null;
      _inspectingPaper = null;
      return;
    }
    if (!dash.exams.any((e) => e.examId == _selectedExamId)) {
      _selectedExamId = dash.exams.first.examId;
    }
    final targetExam = dash.exams.firstWhere(
      (e) => e.examId == _selectedExamId,
      orElse: () => dash.exams.first,
    );
    _inspectingExam = targetExam;
    if (targetExam.papers.isEmpty) {
      _inspectingPaper = null;
      return;
    }
    final prevSubj = _inspectingPaper?.subject ?? '';
    _inspectingPaper = targetExam.papers.firstWhere(
      (p) => prevSubj.isNotEmpty && p.subject == prevSubj,
      orElse: () => targetExam.papers.first,
    );
    if (openRightPane) {
      _inspectorCollapsed = false;
    }
  }

  void _rebuildFleetRows() {
    final rows = <({
      HfsAccount account,
      StudentInfo student,
      StudentSnapshot? snapshot
    })>[];
    for (final acc in _accounts) {
      for (final stu in acc.students) {
        rows.add((
          account: acc,
          student: stu,
          snapshot: acc.studentSnapshots[stu.studentId],
        ));
      }
    }
    rows.sort((a, b) {
      final sa = numOf(a.snapshot?.scoreS, -1);
      final sb = numOf(b.snapshot?.scoreS, -1);
      if (sa != sb) return sb.compareTo(sa);
      return a.student.studentName.compareTo(b.student.studentName);
    });
    _fleetRows = rows;
  }

  Future<void> _loadDashboardForCurrent({bool allowCache = true}) async {
    final acc = _currentAccount;
    if (acc == null) return;
    final reqId = ++_dashboardRequestId;
    final reqAccountId = acc.id;
    final reqStudentId = acc.desiredStudentId.isNotEmpty
        ? acc.desiredStudentId
        : acc.activeStudentId;
    _setHomeState(() {
      _loadingDashboard = true;
      _errorBanner = null;
    });
    try {
      final dash = await _client.fetchDashboard(
        acc,
        allowCache: allowCache,
        maxExams: _settings.maxExamsToHydrate,
        concurrency: _settings.examConcurrency,
      );
      await _persistAccountsAndSettings();
      await _persistDashboardSnapshot(dash);
      if (!mounted ||
          reqId != _dashboardRequestId ||
          _selectedAccountId != reqAccountId ||
          (reqStudentId.isNotEmpty &&
              acc.desiredStudentId.isNotEmpty &&
              acc.desiredStudentId != reqStudentId)) {
        return;
      }
      _setHomeState(() {
        _dashboard = dash;
        _loadingDashboard = false;
        _syncInspectorWithDashboard(dash, openRightPane: true);
        _rebuildFleetRows();
      });
    } catch (e) {
      if (!mounted || reqId != _dashboardRequestId) return;
      _setHomeState(() {
        _loadingDashboard = false;
        _errorBanner = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Instant student / account switch: uses memory/disk cache first so clicking never blocks or re-hydrates!
  Future<void> _handleSwitchStudent(
    HfsAccount acc,
    StudentInfo stu, {
    bool forceNetwork = false,
  }) async {
    final reqId = ++_dashboardRequestId;
    final reqAccountId = acc.id;
    final reqStudentId = stu.studentId;
    final allowCache = !forceNetwork && !_settings.autoHydrateOnSwitch;
    final cached =
        allowCache ? _client.peekCachedDashboard(acc.id, stu.studentId) : null;

    _setHomeState(() {
      _selectedAccountId = acc.id;
      acc.desiredStudentId = stu.studentId;
      acc.activeStudentId = stu.studentId;
      _errorBanner = null;
      if (cached != null) {
        _dashboard = cached;
        _loadingDashboard = false;
        _syncInspectorWithDashboard(cached, openRightPane: true);
      } else {
        _loadingDashboard = true;
      }
    });

    if (cached != null) {
      // Switch upstream session cookie silently in background without blocking UI
      unawaited(
        _client.switchStudent(
          acc,
          stu.studentId,
          allowCache: true,
          maxExams: _settings.maxExamsToHydrate,
          concurrency: _settings.examConcurrency,
        ),
      );
      unawaited(_persistAccountsAndSettings());
      return;
    }

    try {
      final dash = await _client.switchStudent(
        acc,
        stu.studentId,
        allowCache: allowCache,
        maxExams: _settings.maxExamsToHydrate,
        concurrency: _settings.examConcurrency,
      );
      await _persistAccountsAndSettings();
      await _persistDashboardSnapshot(dash);
      if (!mounted ||
          reqId != _dashboardRequestId ||
          _selectedAccountId != reqAccountId ||
          acc.desiredStudentId != reqStudentId) {
        return;
      }
      _setHomeState(() {
        _dashboard = dash;
        _loadingDashboard = false;
        _syncInspectorWithDashboard(dash, openRightPane: true);
        _rebuildFleetRows();
      });
    } catch (e) {
      if (!mounted || reqId != _dashboardRequestId) return;
      _setHomeState(() {
        _loadingDashboard = false;
        _errorBanner = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Switch account header click: if account already has cached active student dashboard, show immediately!
  Future<void> _handleSelectAccount(HfsAccount acc) async {
    if (acc.id == _selectedAccountId && _dashboard?.account.id == acc.id) {
      return;
    }
    final activeStu = acc.activeStudent;
    if (activeStu != null) {
      await _handleSwitchStudent(acc, activeStu);
      return;
    }
    _setHomeState(() {
      _selectedAccountId = acc.id;
    });
    await _loadDashboardForCurrent(allowCache: true);
  }

  Future<void> _handleProbeAccountStudents(
    HfsAccount acc, {
    bool forceAll = true,
  }) async {
    if (_probingAccountId != null) return;
    _setHomeState(() {
      _probingAccountId = acc.id;
      _errorBanner = null;
    });
    try {
      await _client.probeAllStudents(acc, forceRefreshAll: forceAll);
      await _persistAccountsAndSettings();
      if (!mounted) return;
      _setHomeState(() {
        _probingAccountId = null;
        _rebuildFleetRows();
      });
    } catch (e) {
      if (!mounted) return;
      _setHomeState(() {
        _probingAccountId = null;
        _errorBanner = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleProbeAllAccountsFleet() async {
    if (_loadingFleet) return;
    _setHomeState(() {
      _loadingFleet = true;
      _errorBanner = null;
    });
    try {
      for (final acc in _accounts) {
        await _client.probeAllStudents(acc, forceRefreshAll: true);
      }
      await _persistAccountsAndSettings();
      if (!mounted) return;
      _setHomeState(() {
        _loadingFleet = false;
        _rebuildFleetRows();
      });
    } catch (e) {
      if (!mounted) return;
      _setHomeState(() {
        _loadingFleet = false;
        _errorBanner = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleUpsertAuthenticatedAccount(HfsAccount acc) async {
    final idx = _accounts.indexWhere((a) => a.id == acc.id);
    if (idx >= 0) {
      _accounts[idx] = acc;
    } else {
      _accounts.add(acc);
    }
    _selectedAccountId = acc.id;
    await _persistAccountsAndSettings();
    if (!mounted) return;
    _setHomeState(() {
      _rebuildFleetRows();
    });
    await _loadDashboardForCurrent(allowCache: false);
  }

  Future<void> _handleInlineQuickAddAccount() async {
    final login = _inlineAddLoginCtrl.text.trim();
    final pass = _inlineAddPassCtrl.text;
    if (login.isEmpty || pass.isEmpty) {
      _setHomeState(() => _errorBanner = '请填写快速挂载的好分数账号与密码');
      return;
    }
    _setHomeState(() {
      _inlineAddingAccount = true;
      _errorBanner = null;
    });
    try {
      final jar = await _client.loginHfs(
        loginName: login,
        password: pass,
        roleType: _inlineAddRole,
      );
      final id = HfsUpstreamClient.accountIdFor(login, _inlineAddRole);
      final acc = HfsAccount(
        id: id,
        label: _inlineAddLabelCtrl.text.trim(),
        roleType: _inlineAddRole,
        loginName: login,
        password: pass,
        cookies: jar,
        students: <StudentInfo>[],
      );
      await _client.hydrateAccountStudents(acc);
      _inlineAddLoginCtrl.clear();
      _inlineAddPassCtrl.clear();
      _inlineAddLabelCtrl.clear();
      if (!mounted) return;
      _setHomeState(() {
        _inlineAddingAccount = false;
        _showInlineQuickAddAccount = false;
      });
      await _handleUpsertAuthenticatedAccount(acc);
    } catch (e) {
      if (!mounted) return;
      _setHomeState(() {
        _inlineAddingAccount = false;
        _errorBanner = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleInlineBindStudent(HfsAccount acc) async {
    final sName = _inlineBindNameCtrl.text.trim();
    final sCode = _inlineBindCodeCtrl.text.trim();
    if (sName.isEmpty || sCode.isEmpty) {
      _setHomeState(() => _errorBanner = '请填写要绑定的学生姓名与学号/考号');
      return;
    }
    _setHomeState(() {
      _inlineBindingStudent = true;
      _errorBanner = null;
    });
    try {
      final dash = await _client.bindStudent(
        account: acc,
        studentName: sName,
        identityCode: sCode,
        schoolAuthCode: _inlineBindAuthCtrl.text.trim(),
      );
      _inlineBindNameCtrl.clear();
      _inlineBindCodeCtrl.clear();
      _inlineBindAuthCtrl.clear();
      _selectedAccountId = acc.id;
      await _persistAccountsAndSettings();
      await _persistDashboardSnapshot(dash);
      if (!mounted) return;
      _setHomeState(() {
        _inlineBindingStudent = false;
        _inlineBindAccountId = null;
        _dashboard = dash;
        _syncInspectorWithDashboard(dash, openRightPane: true);
        _rebuildFleetRows();
      });
    } catch (e) {
      if (!mounted) return;
      _setHomeState(() {
        _inlineBindingStudent = false;
        _errorBanner = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openMiniScoresModal() async {
    final acc = _currentAccount;
    if (acc == null || acc.wechatSessionCookie.trim().isEmpty) {
      _setHomeState(() => _errorBanner = '当前账号不是微信小程序会话，无法使用小程序代理读取');
      return;
    }
    Taste.showResponsiveModal<void>(
      context: context,
      builder: (ctx) => MiniScoresDialog(client: _client, account: acc),
    );
  }

  void _openAuthOrRegisterModal({HfsAccount? reauthAccount}) {
    Taste.showResponsiveModal<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Taste.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: Taste.dialogInsetPadding(ctx),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Taste.radiusCard),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: Taste.dialogMaxHeight(ctx, desktopMax: 700),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: HfsAuthPanel(
              client: _client,
              reauthAccount: reauthAccount,
              isDialog: true,
              onAuthenticated: (acc) async {
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _handleUpsertAuthenticatedAccount(acc);
              },
              onMiniAuthenticated: (acc) async {
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _handleUpsertAuthenticatedAccount(acc);
              },
            ),
          ),
        ),
      ),
    );
  }

  void _openAdvancedBindStudentModal({
    HfsAccount? targetAccount,
    String? initialReplaceStudentId,
  }) {
    final initial = targetAccount ?? _currentAccount;
    if (initial == null) return;
    Taste.showResponsiveModal<void>(
      context: context,
      builder: (ctx) => BindStudentAdvancedDialog(
        client: _client,
        accounts: _accounts,
        initialAccount: initial,
        initialReplaceStudentId: initialReplaceStudentId,
        onBound: (acc, dash) async {
          _selectedAccountId = acc.id;
          await _persistAccountsAndSettings();
          await _persistDashboardSnapshot(dash);
          if (!mounted) return;
          _setHomeState(() {
            _dashboard = dash;
            _syncInspectorWithDashboard(dash, openRightPane: true);
            _rebuildFleetRows();
          });
        },
      ),
    );
  }

  void _openClassmatesRosterModal() {
    final acc = _currentAccount;
    if (acc == null) return;
    Taste.showResponsiveModal<void>(
      context: context,
      builder: (ctx) => ClassmatesRosterDialog(
        client: _client,
        account: acc,
        accounts: _accounts,
        currentStudent: _dashboard?.currentStudent ?? acc.activeStudent,
        onBound: (boundAcc, dash) async {
          _selectedAccountId = boundAcc.id;
          await _persistAccountsAndSettings();
          await _persistDashboardSnapshot(dash);
          if (!mounted) return;
          _setHomeState(() {
            _dashboard = dash;
            _syncInspectorWithDashboard(dash, openRightPane: true);
            _rebuildFleetRows();
          });
        },
        onSwitchStudent: (targetAcc, targetStu) {
          Navigator.of(ctx).pop();
          _handleSwitchStudent(targetAcc, targetStu);
        },
      ),
    );
  }

  Future<String> _buildExportConfigJson({HfsAccount? singleAccount}) async {
    final targetAccounts =
        singleAccount != null ? <HfsAccount>[singleAccount] : _accounts;
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'hfs_flutter_credentials_v2',
      'exportedAt': DateTime.now().toIso8601String(),
      'accounts': targetAccounts.map((a) => a.toJson()).toList(),
      'selectedAccountId': singleAccount?.id ?? _selectedAccountId,
      'settings': _settings.toJson(),
    });
  }

  Future<void> _exportCredentialFileDirect({HfsAccount? singleAccount}) async {
    try {
      final raw = await _buildExportConfigJson(singleAccount: singleAccount);
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final suffix = singleAccount != null ? '_${singleAccount.id}' : '';
      final fileName = 'hfs_credentials${suffix}_$ts.json';
      final dlDir =
          await HfsImageClipboardAndExporter.resolveDownloadsDirectory();
      final fb = File('${dlDir.path}${Platform.pathSeparator}$fileName');
      await fb.writeAsString(raw, flush: true);
      final savedPath = fb.path;
      await Clipboard.setData(ClipboardData(text: raw));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Taste.text,
          content: Text(
            '已导出好分数凭证文件至：$savedPath（并已同步复制到剪贴板）',
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _setHomeState(() => _errorBanner = '导出好分数凭证文件失败：$e');
    }
  }

  void _openSettingsModal() {
    Taste.showResponsiveModal<void>(
      context: context,
      builder: (ctx) => AppSettingsDialog(
        settings: _settings,
        client: _client,
        activeAccount: _currentAccount,
        accounts: _accounts,
        activeStudent:
            _dashboard?.currentStudent ?? _currentAccount?.activeStudent,
        onSaveSettings: (newSettings) {
          _setHomeState(() {
            _settings = newSettings;
            _inspectorWidth = newSettings.inspectorWidth;
          });
          unawaited(_persistAccountsAndSettings());
        },
        onClearCache: () async {
          _client.clearAllCaches();
          final prefs = await SharedPreferences.getInstance();
          final keys = prefs
              .getKeys()
              .where((k) => k.startsWith(_prefsDashSnapPrefix))
              .toList();
          for (final k in keys) {
            await prefs.remove(k);
          }
        },
        onExportConfigJson: _buildExportConfigJson,
        onImportConfigJson: (raw) async {
          final m = jsonDecode(raw);
          if (m is Map && m['accounts'] is List) {
            _accounts = (m['accounts'] as List)
                .whereType<Map>()
                .map((e) => HfsAccount.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            if (m['settings'] is Map) {
              _settings = AppSettings.fromJson(
                Map<String, dynamic>.from(m['settings'] as Map),
              );
              _inspectorWidth = _settings.inspectorWidth;
            }
            if (_accounts.isNotEmpty) {
              final wantedSel = strOf(m['selectedAccountId']);
              _selectedAccountId = _accounts.any((a) => a.id == wantedSel)
                  ? wantedSel
                  : _accounts.first.id;
            } else {
              _selectedAccountId = '';
            }
            await _persistAccountsAndSettings();
            if (!mounted) return;
            _setHomeState(() {
              _rebuildFleetRows();
            });
            await _loadDashboardForCurrent(allowCache: false);
          }
        },
      ),
    );
  }

  void _openPaperInspection(ExamRecord exam, PaperScore paper) {
    final acc = _currentAccount;
    if (acc == null) return;

    final screenWidth = MediaQuery.of(context).size.width;
    _setHomeState(() {
      _selectedExamId = exam.examId;
      _inspectingExam = exam;
      _inspectingPaper = paper;
      _inspectorCollapsed = false;
    });

    if (screenWidth >= 1080) {
      // Desktop 4-column Framed Sheet mode renders the right docked inspector automatically
      return;
    }

    if (screenWidth >= 768) {
      showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Taste.surface,
          surfaceTintColor: Colors.transparent,
          insetPadding: Taste.dialogInsetPadding(ctx),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Taste.radiusSheet),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 920,
              maxHeight: Taste.dialogMaxHeight(ctx, desktopMax: 860),
            ),
            child: PaperInspectionPane(
              client: _client,
              account: acc,
              exam: exam,
              paper: paper,
              defaultShowOverlay: _settings.defaultGradingOverlay,
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      );
      return;
    }

    mbs.showMaterialModalBottomSheet<void>(
      context: context,
      expand: true,
      duration: const Duration(milliseconds: 180),
      enableDrag:
          false, // Prevents accidental sheet drag when scrolling the answer sheet
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final viewPadding = MediaQuery.viewPaddingOf(ctx);
        final bottomReserve = math.max(66.0, viewPadding.bottom + 62.0);
        return Padding(
          padding: EdgeInsets.only(bottom: bottomReserve),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Taste.surface,
              clipBehavior: Clip.antiAlias,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(Taste.radiusSheet)),
              ),
              child: SafeArea(
                bottom: true,
                child: FractionallySizedBox(
                  heightFactor: 0.92,
                  child: PaperInspectionPane(
                    client: _client,
                    account: acc,
                    exam: exam,
                    paper: paper,
                    defaultShowOverlay: _settings.defaultGradingOverlay,
                    onClose: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openPaperByIds(String examId, String paperId, String subject) {
    final dash = _dashboard;
    if (dash != null) {
      for (final ex in dash.exams) {
        if (ex.examId == examId) {
          for (final p in ex.papers) {
            if (p.paperId.startsWith(paperId) || p.subject == subject) {
              _openPaperInspection(ex, p);
              return;
            }
          }
        }
      }
    }
    // Synthesize ExamRecord & PaperScore if the exam wasn't in the hydrated window
    final synPaper = PaperScore(
      paperId: paperId,
      pid: paperId,
      subject: subject,
      name: subject,
      score: 0,
      scoreS: '—',
      manfen: 100,
    );
    final synExam = ExamRecord(
      examId: examId,
      studentId: _currentAccount?.activeStudentId ?? '',
      name: '考试 $examId',
      time: 0,
      score: 0,
      scoreS: '—',
      manfen: 100,
      isPartial: false,
      reportedPaperCount: 1,
      classRankS: '',
      gradeRankS: '',
      totalWrong: 0,
      papers: <PaperScore>[synPaper],
    );
    _openPaperInspection(synExam, synPaper);
  }

  Future<void> _removeAccount(HfsAccount acc) async {
    if (acc.wechatSessionCookie.isNotEmpty) {
      try {
        await _client.miniAccountLogout(
          wechatCookie: acc.wechatSessionCookie,
        );
      } catch (_) {
        // Local removal remains available when the upstream session already expired.
      }
    }
    _accounts.removeWhere((a) => a.id == acc.id);
    if (_selectedAccountId == acc.id) {
      _selectedAccountId = _accounts.isNotEmpty ? _accounts.first.id : '';
    }
    await _persistAccountsAndSettings();
    _setHomeState(() {
      if (_accounts.isEmpty) {
        _dashboard = null;
        _fleetRows = const [];
      } else {
        _rebuildFleetRows();
      }
    });
    if (_currentAccount != null) {
      await _loadDashboardForCurrent(allowCache: true);
    }
  }

}
