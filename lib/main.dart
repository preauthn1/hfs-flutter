import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'answer_sheet_painter.dart';
import 'hfs_client.dart';
import 'hfs_models.dart';
import 'taste_widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HfsFlutterApp());
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

class HfsFlutterApp extends StatelessWidget {
  const HfsFlutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      fontFamily: Taste.fontFamily,
      scaffoldBackgroundColor: Taste.ground,
      colorScheme: const ColorScheme.light(
        primary: Taste.accent,
        onPrimary: Colors.white,
        secondary: Taste.primary,
        onSecondary: Colors.white,
        surface: Taste.surface,
        onSurface: Taste.text,
        error: Taste.negative,
      ),
      dividerColor: Taste.border,
      cardTheme: CardThemeData(
        color: Taste.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Taste.radiusCard),
          side: const BorderSide(color: Taste.border),
        ),
      ),
    );

    return MaterialApp(
      title: '好分数 · 原生工作台',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: baseTheme,
      home: const HfsHomeScreen(),
    );
  }
}

class HfsHomeScreen extends StatefulWidget {
  const HfsHomeScreen({super.key});

  @override
  State<HfsHomeScreen> createState() => _HfsHomeScreenState();
}

class _HfsHomeScreenState extends State<HfsHomeScreen> {
  static const String _prefsAccountsKey = 'hfs_direct_accounts_v1';
  static const String _prefsSelectedKey = 'hfs_direct_selected_id_v1';
  static const String _prefsSettingsKey = 'hfs_direct_settings_v2';
  static const String _prefsDashSnapPrefix = 'hfs_dash_snap_v2:';

  final HfsUpstreamClient _client = HfsUpstreamClient();
  final ScrollController _leftDockScrollCtrl = ScrollController();
  final ScrollController _centerScrollCtrl = ScrollController();

  List<HfsAccount> _accounts = <HfsAccount>[];
  String _selectedAccountId = '';
  AppSettings _settings = const AppSettings();
  DashboardData? _dashboard;
  bool _initializing = true;
  bool _loadingDashboard = false;
  String? _probingAccountId;
  String? _errorBanner;

  // Navigation tab index:
  // 0 = 成绩单与单科卷面, 1 = 全账号与全体学生总览, 2 = 错题本与诊断, 3 = 账号与学生 (Mobile Tab)
  int _activeTabIndex = 0;
  String _selectedExamId = '';
  String _examFilterQuery = '';
  final Set<String> _hiddenSubjects = <String>{};

  // Inline Quick-Add Account & Inline Bind-Student states in Left Dock
  bool _showInlineQuickAddAccount = false;
  int _inlineAddRole = 2;
  final TextEditingController _inlineAddLoginCtrl = TextEditingController();
  final TextEditingController _inlineAddPassCtrl = TextEditingController();
  final TextEditingController _inlineAddLabelCtrl = TextEditingController();
  bool _inlineAddingAccount = false;

  String? _inlineBindAccountId;
  final TextEditingController _inlineBindNameCtrl = TextEditingController();
  final TextEditingController _inlineBindCodeCtrl = TextEditingController();
  final TextEditingController _inlineBindAuthCtrl = TextEditingController();
  bool _inlineBindingStudent = false;

  // Right Docked Inspector state (for desktop >= 1080px)
  ExamRecord? _inspectingExam;
  PaperScore? _inspectingPaper;
  bool _inspectorCollapsed = true;
  late double _inspectorWidth;

  // Fleet / All-students comparison cache
  List<({HfsAccount account, StudentInfo student, StudentSnapshot? snapshot})>
      _fleetRows = const [];
  bool _loadingFleet = false;
  int _dashboardRequestId = 0;
  Future<void>? _persistGate;

  HfsAccount? get _currentAccount {
    if (_accounts.isEmpty) return null;
    for (final a in _accounts) {
      if (a.id == _selectedAccountId) return a;
    }
    return _accounts.first;
  }

  ExamRecord? get _selectedExam {
    final dash = _dashboard;
    if (dash == null || dash.exams.isEmpty) return null;
    for (final ex in dash.exams) {
      if (ex.examId == _selectedExamId) return ex;
    }
    return dash.exams.first;
  }

  int get _totalBoundStudentsCount =>
      _accounts.fold<int>(0, (s, a) => s + a.students.length);

  @override
  void initState() {
    super.initState();
    _inspectorWidth = _settings.inspectorWidth;
    _restoreState();
  }

  @override
  void dispose() {
    _leftDockScrollCtrl.dispose();
    _centerScrollCtrl.dispose();
    _inlineAddLoginCtrl.dispose();
    _inlineAddPassCtrl.dispose();
    _inlineAddLabelCtrl.dispose();
    _inlineBindNameCtrl.dispose();
    _inlineBindCodeCtrl.dispose();
    _inlineBindAuthCtrl.dispose();
    super.dispose();
  }

  Future<void> _restoreState() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final rawSettings = prefs.getString(_prefsSettingsKey);
      if (rawSettings != null && rawSettings.isNotEmpty) {
        final decoded = jsonDecode(rawSettings);
        if (decoded is Map) {
          _settings =
              AppSettings.fromJson(Map<String, dynamic>.from(decoded));
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
    setState(() {
      _initializing = false;
      if (instantDash != null) {
        _dashboard = instantDash;
        if (instantDash.exams.isNotEmpty) {
          _selectedExamId = instantDash.exams.first.examId;
        }
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
    setState(() {
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
      setState(() {
        _dashboard = dash;
        _loadingDashboard = false;
        if (dash.exams.isNotEmpty &&
            !dash.exams.any((e) => e.examId == _selectedExamId)) {
          _selectedExamId = dash.exams.first.examId;
        }
        _rebuildFleetRows();
      });
    } catch (e) {
      if (!mounted || reqId != _dashboardRequestId) return;
      setState(() {
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
    final cached = allowCache
        ? _client.peekCachedDashboard(acc.id, stu.studentId)
        : null;

    setState(() {
      _selectedAccountId = acc.id;
      acc.desiredStudentId = stu.studentId;
      acc.activeStudentId = stu.studentId;
      _errorBanner = null;
      if (cached != null) {
        _dashboard = cached;
        _loadingDashboard = false;
        if (cached.exams.isNotEmpty &&
            !cached.exams.any((e) => e.examId == _selectedExamId)) {
          _selectedExamId = cached.exams.first.examId;
        }
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
      setState(() {
        _dashboard = dash;
        _loadingDashboard = false;
        if (dash.exams.isNotEmpty) {
          _selectedExamId = dash.exams.first.examId;
        }
        _rebuildFleetRows();
      });
    } catch (e) {
      if (!mounted || reqId != _dashboardRequestId) return;
      setState(() {
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
    setState(() {
      _selectedAccountId = acc.id;
    });
    await _loadDashboardForCurrent(allowCache: true);
  }

  Future<void> _handleProbeAccountStudents(
    HfsAccount acc, {
    bool forceAll = true,
  }) async {
    if (_probingAccountId != null) return;
    setState(() {
      _probingAccountId = acc.id;
      _errorBanner = null;
    });
    try {
      await _client.probeAllStudents(acc, forceRefreshAll: forceAll);
      await _persistAccountsAndSettings();
      if (!mounted) return;
      setState(() {
        _probingAccountId = null;
        _rebuildFleetRows();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probingAccountId = null;
        _errorBanner = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleProbeAllAccountsFleet() async {
    if (_loadingFleet) return;
    setState(() {
      _loadingFleet = true;
      _errorBanner = null;
    });
    try {
      for (final acc in _accounts) {
        await _client.probeAllStudents(acc, forceRefreshAll: true);
      }
      await _persistAccountsAndSettings();
      if (!mounted) return;
      setState(() {
        _loadingFleet = false;
        _rebuildFleetRows();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
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
    setState(() {
      _rebuildFleetRows();
    });
    await _loadDashboardForCurrent(allowCache: false);
  }

  Future<void> _handleInlineQuickAddAccount() async {
    final login = _inlineAddLoginCtrl.text.trim();
    final pass = _inlineAddPassCtrl.text;
    if (login.isEmpty || pass.isEmpty) {
      setState(() => _errorBanner = '请填写快速挂载的好分数账号与密码');
      return;
    }
    setState(() {
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
      setState(() {
        _inlineAddingAccount = false;
        _showInlineQuickAddAccount = false;
      });
      await _handleUpsertAuthenticatedAccount(acc);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineAddingAccount = false;
        _errorBanner = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleInlineBindStudent(HfsAccount acc) async {
    final sName = _inlineBindNameCtrl.text.trim();
    final sCode = _inlineBindCodeCtrl.text.trim();
    if (sName.isEmpty || sCode.isEmpty) {
      setState(() => _errorBanner = '请填写要绑定的学生姓名与学号/考号');
      return;
    }
    setState(() {
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
      setState(() {
        _inlineBindingStudent = false;
        _inlineBindAccountId = null;
        _dashboard = dash;
        if (dash.exams.isNotEmpty) {
          _selectedExamId = dash.exams.first.examId;
        }
        _rebuildFleetRows();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineBindingStudent = false;
        _errorBanner = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _openAuthOrRegisterModal({HfsAccount? reauthAccount}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Taste.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Taste.radiusCard),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: HfsAuthPanel(
            client: _client,
            reauthAccount: reauthAccount,
            isDialog: true,
            onAuthenticated: (acc) async {
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _handleUpsertAuthenticatedAccount(acc);
            },
          ),
        ),
      ),
    );
  }

  void _openAdvancedBindStudentModal({HfsAccount? targetAccount}) {
    final initial = targetAccount ?? _currentAccount;
    if (initial == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => BindStudentAdvancedDialog(
        client: _client,
        accounts: _accounts,
        initialAccount: initial,
        onBound: (acc, dash) async {
          _selectedAccountId = acc.id;
          await _persistAccountsAndSettings();
          await _persistDashboardSnapshot(dash);
          if (!mounted) return;
          setState(() {
            _dashboard = dash;
            if (dash.exams.isNotEmpty) {
              _selectedExamId = dash.exams.first.examId;
            }
            _rebuildFleetRows();
          });
        },
      ),
    );
  }

  void _openClassmatesRosterModal() {
    final acc = _currentAccount;
    if (acc == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => ClassmatesRosterDialog(
        client: _client,
        account: acc,
        currentStudent: _dashboard?.currentStudent ?? acc.activeStudent,
      ),
    );
  }

  void _openSettingsModal() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AppSettingsDialog(
        settings: _settings,
        client: _client,
        activeAccount: _currentAccount,
        onSaveSettings: (newSettings) {
          setState(() {
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
        onExportConfigJson: () async {
          return const JsonEncoder.withIndent('  ').convert({
            'accounts': _accounts.map((a) => a.toJson()).toList(),
            'selectedAccountId': _selectedAccountId,
            'settings': _settings.toJson(),
          });
        },
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
            setState(() {
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
    setState(() {
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
          insetPadding: const EdgeInsets.all(20),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Taste.radiusSheet),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920, maxHeight: 860),
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

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false, // Prevents accidental sheet drag when scrolling the answer sheet
      backgroundColor: Taste.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Taste.radiusSheet)),
      ),
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: PaperInspectionPane(
            client: _client,
            account: acc,
            exam: exam,
            paper: paper,
            defaultShowOverlay: _settings.defaultGradingOverlay,
            onClose: () => Navigator.of(ctx).pop(),
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
    _accounts.removeWhere((a) => a.id == acc.id);
    if (_selectedAccountId == acc.id) {
      _selectedAccountId = _accounts.isNotEmpty ? _accounts.first.id : '';
    }
    await _persistAccountsAndSettings();
    setState(() {
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

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        backgroundColor: Taste.ground,
        body: Center(
          child: CircularProgressIndicator(color: Taste.accent),
        ),
      );
    }

    if (_accounts.isEmpty) {
      return Scaffold(
        backgroundColor: Taste.ground,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: HfsAuthPanel(
                client: _client,
                onAuthenticated: _handleUpsertAuthenticatedAccount,
              ),
            ),
          ),
        ),
      );
    }

    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 860;
    final canDockInspector = width >= 1080;
    final showRightDocked = canDockInspector &&
        !_inspectorCollapsed &&
        _inspectingPaper != null &&
        _inspectingExam != null;

    final effectiveTab =
        (isDesktop && _activeTabIndex == 3) ? 0 : _activeTabIndex;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f5): () {
          if (!_loadingDashboard) _loadDashboardForCurrent(allowCache: false);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_inspectorCollapsed) {
            setState(() => _inspectorCollapsed = true);
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Taste.ground,
          bottomNavigationBar: isDesktop
              ? null
              : Container(
                  decoration: const BoxDecoration(
                    color: Taste.surface,
                    border: Border(top: BorderSide(color: Taste.border)),
                  ),
                  child: NavigationBar(
                    selectedIndex: effectiveTab,
                    height: 62,
                    backgroundColor: Taste.surface,
                    indicatorColor: Taste.pillPosBg,
                    onDestinationSelected: (idx) =>
                        setState(() => _activeTabIndex = idx),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.table_chart_outlined, size: 20),
                        selectedIcon: Icon(Icons.table_chart,
                            size: 20, color: Taste.pillPosInk),
                        label: '成绩单',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.groups_outlined, size: 20),
                        selectedIcon: Icon(Icons.groups,
                            size: 20, color: Taste.pillPosInk),
                        label: '全员总览',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.assignment_late_outlined, size: 20),
                        selectedIcon: Icon(Icons.assignment_late,
                            size: 20, color: Taste.pillPosInk),
                        label: '错题与诊断',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.manage_accounts_outlined, size: 20),
                        selectedIcon: Icon(Icons.manage_accounts,
                            size: 20, color: Taste.pillPosInk),
                        label: '多号与学生',
                      ),
                    ],
                  ),
                ),
          body: SafeArea(
            child: Column(
              children: [
                // 1. Taste-Skill 48px Topbar on Tinted Chrome Ground (#F5F7F9)
                _buildTasteTopBar(isDesktop),

                // Mobile quick student switcher bar
                if (!isDesktop && effectiveTab != 3)
                  _buildMobileStudentQuickStrip(),

                if (_errorBanner != null)
                  Container(
                    width: double.infinity,
                    color: Taste.pillNegBg,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            size: 16, color: Taste.negative),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorBanner!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Taste.pillNegInk,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 15),
                          onPressed: () => setState(() => _errorBanner = null),
                        ),
                      ],
                    ),
                  ),

                // 2. 4-Column Framed Sheet Workspace (Left Dock | White Framed Center Sheet | Resizer | Right Inspector)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: isDesktop ? 8 : 0,
                      bottom: isDesktop ? 8 : 0,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isDesktop)
                          SizedBox(
                            width: 300,
                            child: _buildLeftDock(isMobileTab: false),
                          ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Taste.surface,
                              border: isDesktop
                                  ? Border.all(color: Taste.border)
                                  : null,
                              borderRadius: isDesktop
                                  ? BorderRadius.only(
                                      topLeft: const Radius.circular(
                                          Taste.radiusSheet),
                                      bottomLeft: const Radius.circular(
                                          Taste.radiusSheet),
                                      topRight: Radius.circular(showRightDocked
                                          ? 0
                                          : Taste.radiusSheet),
                                      bottomRight: Radius.circular(
                                          showRightDocked
                                              ? 0
                                              : Taste.radiusSheet),
                                    )
                                  : null,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _buildCenterStage(isDesktop, effectiveTab),
                          ),
                        ),
                        if (showRightDocked && _currentAccount != null) ...[
                          MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (details) {
                                setState(() {
                                  _inspectorWidth =
                                      (_inspectorWidth - details.delta.dx)
                                          .clamp(360.0, 680.0);
                                });
                              },
                              onHorizontalDragEnd: (_) {
                                unawaited(_persistAccountsAndSettings());
                              },
                              child: Container(
                                width: 8,
                                color: Taste.ground,
                                alignment: Alignment.center,
                                child: const Text(
                                  '⋮',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Taste.muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: _inspectorWidth,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Taste.surface,
                                border: Border(
                                  top: BorderSide(color: Taste.border),
                                  right: BorderSide(color: Taste.border),
                                  bottom: BorderSide(color: Taste.border),
                                ),
                                borderRadius: BorderRadius.only(
                                  topRight: Radius.circular(Taste.radiusSheet),
                                  bottomRight:
                                      Radius.circular(Taste.radiusSheet),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: PaperInspectionPane(
                                key: ValueKey(
                                  '${_inspectingExam!.examId}:${_inspectingPaper!.paperId}:${_currentAccount!.activeStudentId}',
                                ),
                                client: _client,
                                account: _currentAccount!,
                                exam: _inspectingExam!,
                                paper: _inspectingPaper!,
                                defaultShowOverlay:
                                    _settings.defaultGradingOverlay,
                                onClose: () => setState(() {
                                  _inspectorCollapsed = true;
                                }),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTasteTopBar(bool isDesktop) {
    final curExam = _selectedExam;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: Taste.ground,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Taste.accent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '好',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              isDesktop ? '好分数成绩工作台' : '好分数工作台',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Taste.text,
              ),
            ),
          ),
          if (isDesktop) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.only(left: 8),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Taste.border)),
              ),
              child: const Text(
                '多账号与多学生试卷成绩同步',
                style: TextStyle(fontSize: 12, color: Taste.muted),
              ),
            ),
          ],
          const SizedBox(width: 8),
          if (isDesktop) const Spacer(),
          if (isDesktop) ...[
            _buildStatPill('已挂账号', '${_accounts.length}'),
            const SizedBox(width: 8),
            _buildStatPill('已绑学生', '$_totalBoundStudentsCount'),
            const SizedBox(width: 8),
            _buildStatPill(
              '当前考试',
              curExam != null ? curExam.name : '—',
            ),
            const SizedBox(width: 14),
          ],
          if (_loadingDashboard && isDesktop)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Taste.text,
                borderRadius: BorderRadius.circular(Taste.radiusControl),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '同步中…',
                    style: TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ],
              ),
            ),
          _buildTopBarBtn(
            label: isDesktop ? '账号登录/注册' : '加号',
            icon: Icons.person_add_alt_outlined,
            onTap: () => _openAuthOrRegisterModal(),
          ),
          const SizedBox(width: 6),
          _buildTopBarBtn(
            label: isDesktop ? '刷新当前' : '刷新',
            icon: Icons.refresh,
            onTap: _loadingDashboard
                ? null
                : () => _loadDashboardForCurrent(allowCache: false),
          ),
          const SizedBox(width: 6),
          _buildTopBarBtn(
            label: '设置',
            icon: Icons.tune,
            onTap: _openSettingsModal,
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, String val) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Taste.surface,
        borderRadius: BorderRadius.circular(Taste.radiusControl),
        border: Border.all(color: Taste.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: const TextStyle(fontSize: 12, color: Taste.muted),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              val,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Taste.numStyle(
                size: 12,
                weight: FontWeight.w700,
                color: Taste.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBarBtn({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 30,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: Taste.surface,
          foregroundColor: Taste.text,
          side: const BorderSide(color: Taste.control),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Taste.radiusControl),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 14, color: Taste.text),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Taste.text,
          ),
        ),
      ),
    );
  }

  Widget _buildMobileStudentQuickStrip() {
    final allStudents = <({HfsAccount acc, StudentInfo stu})>[];
    for (final a in _accounts) {
      for (final s in a.students) {
        allStudents.add((acc: a, stu: s));
      }
    }
    if (allStudents.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Taste.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: IsolatedHorizontalScroll(
        child: Row(
          children: [
            for (final item in allStudents)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  selected: item.acc.id == _selectedAccountId &&
                      item.acc.activeStudentId == item.stu.studentId,
                  onSelected: (_) => _handleSwitchStudent(item.acc, item.stu),
                  label: Text(
                    item.acc.studentSnapshots[item.stu.studentId] != null
                        ? '${item.stu.studentName} (${item.acc.studentSnapshots[item.stu.studentId]!.scoreS})'
                        : item.stu.studentName,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.add, size: 14),
              label: const Text('绑学生', style: TextStyle(fontSize: 12)),
              onPressed: () => _openAdvancedBindStudentModal(),
            ),
          ],
        ),
      ),
    );
  }

  /// Left Dock on Tinted Ground (#F5F7F9): Account & Student Tree + Inline Quick Add Account
  Widget _buildLeftDock({required bool isMobileTab}) {
    final curAcc = _currentAccount;
    return Container(
      color: Taste.ground,
      padding: const EdgeInsets.fromLTRB(12, 4, 10, 12),
      child: ListView(
        controller: isMobileTab ? null : _leftDockScrollCtrl,
        primary: false,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '好分数账号与绑定学生',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Taste.muted,
                  ),
                ),
                Row(
                  children: [
                    _miniIconBtn(
                      label: '同步当前',
                      onTap: _loadingDashboard
                          ? null
                          : () => _loadDashboardForCurrent(allowCache: false),
                    ),
                    const SizedBox(width: 4),
                    _miniIconBtn(
                      label: '注册/登录',
                      active: true,
                      onTap: () => _openAuthOrRegisterModal(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Account Tree Nodes
          for (final acc in _accounts)
            _buildAccountNodeCard(
              acc,
              isActiveAccount: acc.id == curAcc?.id,
              isMobileTab: isMobileTab,
            ),

          const SizedBox(height: 8),
          // Inline Quick-Add Account Box (#quick-add-box)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '挂载更多好分数账号',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Taste.muted,
                  ),
                ),
                Row(
                  children: [
                    _miniIconBtn(
                      label: _showInlineQuickAddAccount ? '收起' : '＋ 快速加号',
                      active: _showInlineQuickAddAccount,
                      onTap: () => setState(() =>
                          _showInlineQuickAddAccount =
                              !_showInlineQuickAddAccount),
                    ),
                    const SizedBox(width: 4),
                    _miniIconBtn(
                      label: '注册新号',
                      onTap: () => _openAuthOrRegisterModal(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_showInlineQuickAddAccount)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Taste.surface,
                borderRadius: BorderRadius.circular(Taste.radiusCard),
                border: Border.all(color: Taste.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _inlineAddRole,
                          isDense: true,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(Taste.radiusControl),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 2,
                              child:
                                  Text('家长端', style: TextStyle(fontSize: 12)),
                            ),
                            DropdownMenuItem(
                              value: 1,
                              child:
                                  Text('学生端', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _inlineAddRole = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _compactInput(_inlineAddLabelCtrl, '备注名(选填)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _compactInput(_inlineAddLoginCtrl, '手机号 / 好分数账号'),
                  const SizedBox(height: 8),
                  _compactInput(
                    _inlineAddPassCtrl,
                    '好分数密码',
                    obscure: true,
                    onSubmitted: (_) => _handleInlineQuickAddAccount(),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 32,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Taste.primary,
                        foregroundColor: Taste.primaryInk,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(Taste.radiusControl),
                        ),
                      ),
                      onPressed: _inlineAddingAccount
                          ? null
                          : _handleInlineQuickAddAccount,
                      child: Text(
                        _inlineAddingAccount
                            ? '正在验证并拉取学生…'
                            : '登录并挂载该账号',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAccountNodeCard(
    HfsAccount acc, {
    required bool isActiveAccount,
    required bool isMobileTab,
  }) {
    final isBindingHere = _inlineBindAccountId == acc.id;
    final isProbingThis = _probingAccountId == acc.id;
    final schoolTitle = acc.activeStudent?.schoolName.isNotEmpty == true
        ? acc.activeStudent!.schoolName
        : (acc.students.isNotEmpty && acc.students.first.schoolName.isNotEmpty
            ? acc.students.first.schoolName
            : '已绑 ${acc.students.length} 名学生');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Taste.surface,
        borderRadius: BorderRadius.circular(Taste.radiusCard),
        border: Border.all(
          color: isActiveAccount ? Taste.accent : Taste.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Account Node Header (#F4F6F8)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Taste.raised,
              border: Border(bottom: BorderSide(color: Taste.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _handleSelectAccount(acc),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              acc.displayLabel,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Taste.text,
                              ),
                            ),
                            TastePill(
                              label: acc.roleType == 1 ? '学生端' : '家长端',
                              tone: acc.roleType == 1
                                  ? TastePillTone.blue
                                  : TastePillTone.positive,
                            ),
                            if (acc.state == 'reauth_required')
                              const TastePill(
                                label: '需重登',
                                tone: TastePillTone.negative,
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${acc.maskedLogin} · 已绑 ${acc.students.length} 人',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Taste.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _svgIconActionBtn(
                      tooltip: '重连 / 更换密码',
                      icon: Icons.key_outlined,
                      onTap: () => _openAuthOrRegisterModal(reauthAccount: acc),
                    ),
                    const SizedBox(width: 4),
                    _svgIconActionBtn(
                      tooltip: '移除该账号',
                      icon: Icons.close,
                      danger: true,
                      onTap: () => _removeAccount(acc),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Account Subbar (School + Traverse All + Bind Student)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Taste.surface,
              border: Border(bottom: BorderSide(color: Taste.rule)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    schoolTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Taste.muted,
                    ),
                  ),
                ),
                _miniIconBtn(
                  label: isProbingThis ? '遍历中…' : '遍历全员',
                  onTap: isProbingThis
                      ? null
                      : () => _handleProbeAccountStudents(acc),
                ),
                const SizedBox(width: 4),
                _miniIconBtn(
                  label: isBindingHere ? '收起' : '＋绑学生',
                  active: isBindingHere,
                  onTap: () => setState(() {
                    _inlineBindAccountId = isBindingHere ? null : acc.id;
                  }),
                ),
                const SizedBox(width: 4),
                _miniIconBtn(
                  label: '高级',
                  onTap: () =>
                      _openAdvancedBindStudentModal(targetAccount: acc),
                ),
              ],
            ),
          ),

          // 3. Inline Bind Student Box (mirrors .bind-student-box)
          if (isBindingHere)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Taste.raised,
                border: Border(bottom: BorderSide(color: Taste.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _compactInput(_inlineBindNameCtrl, '学生姓名'),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _compactInput(_inlineBindCodeCtrl, '准考证号/考号/学号'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _compactInput(_inlineBindAuthCtrl, '学校授权码(选填)'),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        height: 30,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Taste.primary,
                            foregroundColor: Taste.primaryInk,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(Taste.radiusControl),
                            ),
                          ),
                          onPressed: _inlineBindingStudent
                              ? null
                              : () => _handleInlineBindStudent(acc),
                          child: Text(
                            _inlineBindingStudent ? '绑定中…' : '确认绑定',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // 4. Student List Items (.stu-list -> .stu-item)
          Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                if (acc.students.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      '暂无绑定学生，请点击上方「＋绑学生」',
                      style: TextStyle(fontSize: 11, color: Taste.muted),
                    ),
                  )
                else
                  for (final stu in acc.students)
                    _buildLeftDockStudentItem(
                      acc,
                      stu,
                      isMobileTab: isMobileTab,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftDockStudentItem(
    HfsAccount acc,
    StudentInfo stu, {
    required bool isMobileTab,
  }) {
    final isCurrent =
        acc.id == _selectedAccountId && acc.activeStudentId == stu.studentId;
    final snap = acc.studentSnapshots[stu.studentId];

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(Taste.radiusControl),
        onTap: () {
          if (isMobileTab) {
            setState(() => _activeTabIndex = 0);
          }
          _handleSwitchStudent(acc, stu);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: isCurrent ? Taste.active : Taste.surface,
            borderRadius: BorderRadius.circular(Taste.radiusControl),
            border: Border.all(
              color: isCurrent ? Taste.control : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isCurrent) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Taste.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            stu.studentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Taste.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (stu.grade.isNotEmpty || stu.className.isNotEmpty)
                          '${stu.grade}${stu.className}',
                        if (stu.xuehao.isNotEmpty) '考号 ${stu.xuehao}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Taste.numStyle(size: 11, color: Taste.muted),
                    ),
                  ],
                ),
              ),
              if (snap != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: Taste.numStyle(
                          size: 12,
                          weight: FontWeight.w700,
                          color: Taste.text,
                        ),
                        children: [
                          TextSpan(text: snap.scoreS),
                          if (snap.manfen > 0)
                            TextSpan(
                              text: '/${round1(snap.manfen)}',
                              style: Taste.numStyle(
                                size: 11,
                                weight: FontWeight.w400,
                                color: Taste.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (snap.classRankS.isNotEmpty || snap.isPartial)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Taste.raised,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          snap.classRankS.isNotEmpty
                              ? '班排 ${snap.classRankS}'
                              : '出分中(${snap.reportedPaperCount}科)',
                          style: Taste.numStyle(size: 10, color: Taste.muted),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterStage(bool isDesktop, int effectiveTab) {
    if (effectiveTab == 3) {
      return _buildLeftDock(isMobileTab: true);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Stage Toolbar with 2px Accent Underline Tabs
        Container(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          decoration: const BoxDecoration(
            color: Taste.surface,
            border: Border(bottom: BorderSide(color: Taste.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: IsolatedHorizontalScroll(
                  child: Row(
                    children: [
                      _buildStageUnderlineTab(0, '成绩单与单科卷面'),
                      const SizedBox(width: 24),
                      _buildStageUnderlineTab(1, '全账号与全体学生总览'),
                      const SizedBox(width: 24),
                      _buildStageUnderlineTab(2, '错题本与原始诊断'),
                    ],
                  ),
                ),
              ),
              if (_inspectingPaper != null && _inspectorCollapsed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _miniIconBtn(
                    label: '展开答题卡栏',
                    active: true,
                    onTap: () => setState(() => _inspectorCollapsed = false),
                  ),
                ),
            ],
          ),
        ),

        Expanded(
          child: (_loadingDashboard && _dashboard == null)
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Taste.accent),
                      SizedBox(height: 12),
                      Text(
                        '正在直连好分数同步试卷与成绩数据…',
                        style: TextStyle(fontSize: 13, color: Taste.muted),
                      ),
                    ],
                  ),
                )
              : effectiveTab == 1
                  ? _buildFleetOverviewStage()
                  : effectiveTab == 2
                      ? (_dashboard != null && _currentAccount != null
                          ? WrongNotebookPanel(
                              client: _client,
                              account: _currentAccount!,
                              dashboard: _dashboard!,
                              onOpenPaperByIds: _openPaperByIds,
                            )
                          : const Center(child: Text('暂无错题数据')))
                      : _buildGradesStage(isDesktop),
        ),
      ],
    );
  }

  Widget _buildStageUnderlineTab(int index, String label) {
    final active = _activeTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
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
          style: TextStyle(
            fontSize: 14,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Taste.text : Taste.muted,
          ),
        ),
      ),
    );
  }

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
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              stu?.studentName ?? dash.account.displayLabel,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Taste.text,
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
                          style: const TextStyle(
                            fontSize: 12,
                            color: Taste.muted,
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (exams.isNotEmpty)
                          SizedBox(
                            width: 240,
                            height: 32,
                            child: DropdownButtonFormField<String>(
                              initialValue: curExam?.examId ?? exams.first.examId,
                              isExpanded: true,
                              isDense: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
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
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedExamId = val);
                                }
                              },
                            ),
                          ),
                        _buildTopBarBtn(
                          label: '同班同学名册',
                          icon: Icons.people_outline,
                          onTap: _openClassmatesRosterModal,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildDividedKpiStrip(dash, curExam, prevExam, isDesktop),
            ],
          ),
        ),
        const SizedBox(height: 20),

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
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '历次考试总分与单科矩阵',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Taste.text,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '点击任意单科分数立即在右侧调阅高清答题卡',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Taste.muted,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: 200,
                      height: 30,
                      child: TextField(
                        onChanged: (v) =>
                            setState(() => _examFilterQuery = v),
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
                    ),
                  ],
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
                            setState(() {
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
                              setState(() => _hiddenSubjects.clear()),
                        ),
                    ],
                  ),
                )
              else
                const Divider(height: 1, color: Taste.border),
              _buildScoreMatrixTable(filteredExams, visibleSubjects, curExam),
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
                      final tileW =
                          (box.maxWidth - (cols - 1) * 12) / cols;
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
    final manfenStr =
        (curExam != null && curExam.manfen > 0) ? '/ ${round1(curExam.manfen)}' : '';
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
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Taste.border),
            cells[i],
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
              const VerticalDivider(width: 1, thickness: 1, color: Taste.border),
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
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
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Taste.numStyle(
                    size: 24,
                    weight: FontWeight.w500,
                    color: isPrimary ? Taste.accent : Taste.text,
                  ),
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
    ExamRecord? selectedExam,
  ) {
    if (exams.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text('无匹配的考试记录', style: TextStyle(color: Taste.muted)),
        ),
      );
    }

    return IsolatedHorizontalScroll(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: math.max(780, 460.0 + subjects.length * 136.0),
        ),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: <int, TableColumnWidth>{
            0: const FixedColumnWidth(112), // 日期
            1: const FixedColumnWidth(210), // 考试名称
            2: const FixedColumnWidth(148), // 总分
            for (var i = 0; i < subjects.length; i++)
              i + 3: const FixedColumnWidth(136),
            subjects.length + 3: const FixedColumnWidth(84), // 错题数
          },
          border: const TableBorder(
            horizontalInside: BorderSide(color: Taste.rule),
          ),
          children: [
            // Header Row
            TableRow(
              decoration: const BoxDecoration(
                color: Taste.surface,
                border: Border(bottom: BorderSide(color: Taste.border)),
              ),
              children: [
                _matrixHeaderCell('日期'),
                _matrixHeaderCell('考试名称'),
                _matrixHeaderCell('总分', alignRight: true, rightBorder: true),
                for (final subj in subjects)
                  _matrixHeaderCell(subj, alignRight: true),
                _matrixHeaderCell('错题', alignRight: true),
              ],
            ),
            // Data Rows
            for (var rIdx = 0; rIdx < exams.length; rIdx++)
              _buildScoreMatrixRow(
                exams[rIdx],
                rIdx + 1 < exams.length ? exams[rIdx + 1] : null,
                subjects,
                isSelectedExam: exams[rIdx].examId == selectedExam?.examId,
              ),
          ],
        ),
      ),
    );
  }

  Widget _matrixHeaderCell(
    String text, {
    bool alignRight = false,
    bool rightBorder = false,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
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

  TableRow _buildScoreMatrixRow(
    ExamRecord exam,
    ExamRecord? olderExam,
    List<String> subjects, {
    required bool isSelectedExam,
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
          onTap: () => setState(() => _selectedExamId = exam.examId),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: Text(
              formatDateMs(exam.time),
              style: Taste.numStyle(size: 12, color: Taste.muted),
            ),
          ),
        ),
        // Exam name cell
        InkWell(
          onTap: () => setState(() => _selectedExamId = exam.examId),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: Text(
              exam.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Taste.text,
              ),
            ),
          ),
        ),
        // Total score cell
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 10),
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
            padding: const EdgeInsets.symmetric(horizontal: 8),
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
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  paper.subject,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Taste.text,
                  ),
                ),
                TastePill(
                  label: paper.ratio != null ? '${paper.ratio}%' : '已出分',
                  tone: ratio >= 85
                      ? TastePillTone.positive
                      : (ratio >= 60
                          ? TastePillTone.blue
                          : TastePillTone.warning),
                ),
              ],
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

  /// Tab 1: Fleet & All-Students Overview Stage (1:1 parity with #tab-fleet)
  Widget _buildFleetOverviewStage() {
    return ListView(
      padding: const EdgeInsets.all(20),
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '已连接好分数账号池（共 ${_accounts.length} 个账号）',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Taste.text,
                      ),
                    ),
                    _buildTopBarBtn(
                      label: '＋ 新增 / 注册账号',
                      icon: Icons.add,
                      onTap: () => _openAuthOrRegisterModal(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Taste.border),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final acc in _accounts)
                      SizedBox(
                        width: 320,
                        child: _buildFleetAccountCard(acc),
                      ),
                  ],
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
            snap != null
                ? '${snap.scoreS} / ${round1(snap.manfen)}'
                : '—',
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
              setState(() => _activeTabIndex = 0);
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
                    setState(() => _activeTabIndex = 0);
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
  final VoidCallback onClose;

  const PaperInspectionPane({
    super.key,
    required this.client,
    required this.account,
    required this.exam,
    required this.paper,
    this.defaultShowOverlay = true,
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

  @override
  void initState() {
    super.initState();
    _showGradingOverlay = widget.defaultShowOverlay;
    _loadInspection();
  }

  @override
  void dispose() {
    _inspectorScrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PaperInspectionPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exam.examId != widget.exam.examId ||
        oldWidget.paper.paperId != widget.paper.paperId ||
        oldWidget.paper.pid != widget.paper.pid) {
      _highlightedQName = null;
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
            final key = _pageKeys[ov.pageIndex];
            if (key?.currentContext != null) {
              Scrollable.ensureVisible(
                key!.currentContext!,
                duration: const Duration(milliseconds: 220),
              );
            }
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Taste.control),
                    borderRadius: BorderRadius.circular(Taste.radiusControl),
                  ),
                  child: const Text(
                    '收起',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
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
                        : () => setState(
                            () => _zoomScale = (_zoomScale - 0.25).clamp(0.6, 2.5)),
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
                        : () => setState(
                            () => _zoomScale = (_zoomScale + 0.25).clamp(0.6, 2.5)),
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
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('该科目暂无答题卡扫描件', style: TextStyle(color: Taste.muted)),
          ),
        ),
      ];
    }

    return [
      for (var i = 0; i < data.answerPages.length; i++)
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '答题卡 第 ${i + 1} / ${data.answerPages.length} 页',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Taste.muted,
                      ),
                    ),
                    _toolBtn(
                      '全屏放大阅卷',
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
                      ),
                    ),
                  ],
                ),
              ),
              AnswerSheetCanvas(
                client: widget.client,
                imageUrl: data.answerPages[i],
                overlay:
                    i < data.pageOverlays.length ? data.pageOverlays[i] : null,
                showOverlay: _showGradingOverlay,
                zoomScale: _zoomScale,
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

    if (data.originalPages.isNotEmpty) {
      for (var i = 0; i < data.originalPages.length; i++) {
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
                  showOverlay: false,
                  zoomScale: _zoomScale,
                  onOpenLightbox: () => showOssImageLightbox(
                    context: context,
                    client: widget.client,
                    imageUrl: data.originalPages[i],
                    caption:
                        '${widget.exam.name} · ${widget.paper.subject} 原卷第 ${i + 1} 页',
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          '第 ${q.name} 题',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Taste.text,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TastePill(
                          label: q.type == 2 ? '客观题' : '主观题',
                          tone: TastePillTone.neutral,
                        ),
                      ],
                    ),
                    TastePill(
                      label: '${q.scoreS} / ${round1(q.manfen)}分',
                      tone: q.isFullScore
                          ? TastePillTone.positive
                          : (q.isZeroScore
                              ? TastePillTone.negative
                              : TastePillTone.warning),
                    ),
                  ],
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
                        '原卷题干扫描（点击放大）：',
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
                          ),
                        ),
                    ],
                    if (q.cropUrls.isNotEmpty) ...[
                      const Text(
                        '我的作答切块（点击放大）：',
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '第 ${q.name} 题',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Taste.text,
                        ),
                      ),
                      const SizedBox(width: 6),
                      TastePill(
                        label: q.type == 2 ? '客观题' : '主观题',
                        tone: TastePillTone.neutral,
                      ),
                    ],
                  ),
                  TastePill(
                    label: '${q.scoreS} / ${round1(q.manfen)}分',
                    tone: q.isFullScore
                        ? TastePillTone.positive
                        : (q.isZeroScore
                            ? TastePillTone.negative
                            : TastePillTone.warning),
                  ),
                ],
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
