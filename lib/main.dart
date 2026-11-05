import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'answer_sheet_painter.dart';
import 'hfs_client.dart';
import 'hfs_models.dart';

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
    return MaterialApp(
      title: '好分数 · 原生工作台',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00A870),
          primary: const Color(0xFF00A870),
          surface: Colors.white,
        ),
        dividerColor: const Color(0xFFE2E8F0),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      ),
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

  final HfsUpstreamClient _client = HfsUpstreamClient();

  List<HfsAccount> _accounts = <HfsAccount>[];
  String _selectedAccountId = '';
  DashboardData? _dashboard;
  bool _initializing = true;
  bool _loadingDashboard = false;
  bool _probingStudents = false;
  String? _errorBanner;

  // Navigation tab index:
  // 0 = 成绩单, 1 = 全班对照, 2 = 错题本, 3 = 账号与学生 (mobile dedicated tab)
  int _activeTabIndex = 0;
  String _selectedExamId = '';
  String _examFilterQuery = '';
  final Set<String> _hiddenSubjects = <String>{};

  // Docked inspection state (for desktop >= 1180px)
  ExamRecord? _inspectingExam;
  PaperScore? _inspectingPaper;

  // Fleet / All-students comparison cache
  List<({HfsAccount account, StudentInfo student, StudentSnapshot? snapshot})>
      _fleetRows = const [];
  bool _loadingFleet = false;

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

  @override
  void initState() {
    super.initState();
    _restoreAccounts();
  }

  Future<void> _restoreAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _initializing = false;
    });
    if (_currentAccount != null) {
      _loadDashboardForCurrent(allowCache: false);
    }
  }

  Future<void> _persistAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_accounts.map((a) => a.toJson()).toList());
      await prefs.setString(_prefsAccountsKey, raw);
      await prefs.setString(_prefsSelectedKey, _selectedAccountId);
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
    setState(() {
      _loadingDashboard = true;
      _errorBanner = null;
    });
    try {
      final dash = await _client.fetchDashboard(acc, allowCache: allowCache);
      await _persistAccounts();
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _loadingDashboard = false;
        _errorBanner = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleSwitchStudent(HfsAccount acc, StudentInfo stu) async {
    setState(() {
      _selectedAccountId = acc.id;
      _loadingDashboard = true;
      _errorBanner = null;
      _inspectingPaper = null;
      _inspectingExam = null;
    });
    try {
      final dash = await _client.switchStudent(acc, stu.studentId);
      await _persistAccounts();
      if (!mounted) return;
      setState(() {
        _dashboard = dash;
        _loadingDashboard = false;
        if (dash.exams.isNotEmpty) {
          _selectedExamId = dash.exams.first.examId;
        }
        _rebuildFleetRows();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDashboard = false;
        _errorBanner = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleProbeAllStudents() async {
    final acc = _currentAccount;
    if (acc == null || _probingStudents) return;
    setState(() {
      _probingStudents = true;
      _errorBanner = null;
    });
    try {
      await _client.probeAllStudents(acc);
      final dash = await _client.fetchDashboard(acc, allowCache: false);
      await _persistAccounts();
      if (!mounted) return;
      setState(() {
        _dashboard = dash;
        _probingStudents = false;
        _rebuildFleetRows();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probingStudents = false;
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
        await _client.probeAllStudents(acc);
      }
      await _persistAccounts();
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

  void _openPaperInspection(ExamRecord exam, PaperScore paper) {
    final acc = _currentAccount;
    if (acc == null) return;

    final screenWidth = MediaQuery.of(context).size.width;
    setState(() {
      _inspectingExam = exam;
      _inspectingPaper = paper;
    });

    if (screenWidth >= 1180) {
      // Desktop 3-column mode renders the right docked pane automatically
      return;
    }

    if (screenWidth >= 768) {
      // Tablet / compact desktop opens a centered wide modal dialog
      showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880, maxHeight: 820),
            child: PaperInspectionPane(
              client: _client,
              account: acc,
              exam: exam,
              paper: paper,
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      );
      return;
    }

    // Mobile phone opens a full-height native bottom sheet
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: PaperInspectionPane(
            client: _client,
            account: acc,
            exam: exam,
            paper: paper,
            onClose: () => Navigator.of(ctx).pop(),
          ),
        );
      },
    );
  }

  Future<void> _showAddAccountDialog() async {
    final loginCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    int roleType = 2; // 2 = 家长版, 1 = 学生版
    bool submitting = false;
    String? dialogErr;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            Future<void> submit() async {
              final login = loginCtrl.text.trim();
              final pass = passCtrl.text;
              if (login.isEmpty || pass.isEmpty) {
                setDlgState(() => dialogErr = '请输入好分数手机号/账号与密码');
                return;
              }
              setDlgState(() {
                submitting = true;
                dialogErr = null;
              });
              try {
                final jar = await _client.loginHfs(
                  loginName: login,
                  password: pass,
                  roleType: roleType,
                );
                final id = HfsUpstreamClient.accountIdFor(login, roleType);
                final acc = HfsAccount(
                  id: id,
                  label: labelCtrl.text.trim(),
                  roleType: roleType,
                  loginName: login,
                  password: pass,
                  cookies: jar,
                  students: <StudentInfo>[],
                );
                await _client.hydrateAccountStudents(acc);
                final idx = _accounts.indexWhere((a) => a.id == id);
                if (idx >= 0) {
                  _accounts[idx] = acc;
                } else {
                  _accounts.add(acc);
                }
                _selectedAccountId = acc.id;
                await _persistAccounts();
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _loadDashboardForCurrent(allowCache: false);
              } catch (e) {
                setDlgState(() {
                  submitting = false;
                  dialogErr = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            return AlertDialog(
              title: const Text(
                '登录好分数官方账号',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.verified_user_outlined,
                                size: 16, color: Color(0xFF15803D)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '直连 hfs-be.yunxiao.com 官方接口，凭据仅保存在本机',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF166534),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 2, label: Text('家长端 (默认)')),
                          ButtonSegment(value: 1, label: Text('学生端')),
                        ],
                        selected: {roleType},
                        onSelectionChanged: (s) =>
                            setDlgState(() => roleType = s.first),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: loginCtrl,
                        decoration: const InputDecoration(
                          labelText: '好分数账号 / 手机号',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passCtrl,
                        obscureText: true,
                        onSubmitted: (_) => submit(),
                        decoration: const InputDecoration(
                          labelText: '登录密码',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: labelCtrl,
                        decoration: const InputDecoration(
                          labelText: '备注名称（选填）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      if (dialogErr != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          dialogErr!,
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: Text(submitting ? '正在连接好分数…' : '登录并同步'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showBindStudentDialog() async {
    final acc = _currentAccount;
    if (acc == null) return;
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final authCtrl = TextEditingController();
    bool submitting = false;
    String? dialogErr;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            Future<void> submit() async {
              final sName = nameCtrl.text.trim();
              final sCode = codeCtrl.text.trim();
              if (sName.isEmpty || sCode.isEmpty) {
                setDlgState(() => dialogErr = '请填写学生姓名与准考证号/学号');
                return;
              }
              setDlgState(() {
                submitting = true;
                dialogErr = null;
              });
              try {
                final dash = await _client.bindStudent(
                  account: acc,
                  studentName: sName,
                  identityCode: sCode,
                  schoolAuthCode: authCtrl.text.trim(),
                );
                await _persistAccounts();
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (!mounted) return;
                setState(() {
                  _dashboard = dash;
                  if (dash.exams.isNotEmpty) {
                    _selectedExamId = dash.exams.first.examId;
                  }
                  _rebuildFleetRows();
                });
              } catch (e) {
                setDlgState(() {
                  submitting = false;
                  dialogErr = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            return AlertDialog(
              title: Text(
                '向账号 ${acc.displayLabel} 绑定学生',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: '学生姓名',
                          hintText: '如：张三',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeCtrl,
                        decoration: const InputDecoration(
                          labelText: '学号 / 准考证号 / 考号',
                          hintText: '请输入学号或准考证号',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: authCtrl,
                        decoration: const InputDecoration(
                          labelText: '学校授权码（选填）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      if (dialogErr != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          dialogErr!,
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: Text(submitting ? '正在绑定…' : '确认绑定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _removeAccount(HfsAccount acc) async {
    _accounts.removeWhere((a) => a.id == acc.id);
    if (_selectedAccountId == acc.id) {
      _selectedAccountId = _accounts.isNotEmpty ? _accounts.first.id : '';
    }
    await _persistAccounts();
    setState(() {
      if (_accounts.isEmpty) {
        _dashboard = null;
        _fleetRows = const [];
      } else {
        _rebuildFleetRows();
      }
    });
    if (_currentAccount != null) {
      _loadDashboardForCurrent(allowCache: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_accounts.isEmpty) {
      return _buildStandaloneLoginScreen();
    }

    final width = MediaQuery.of(context).size.width;
    final isDesktopOrTablet = width >= 768;
    final showRightDocked =
        width >= 1180 && _inspectingPaper != null && _inspectingExam != null;

    // If user resized from mobile tab 3 (账号与学生) to desktop where sidebar is permanent,
    // reset active tab to 0 (成绩单).
    final effectiveTab =
        (isDesktopOrTablet && _activeTabIndex == 3) ? 0 : _activeTabIndex;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f5): () {
          if (!_loadingDashboard) _loadDashboardForCurrent(allowCache: false);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_inspectingPaper != null) {
            setState(() {
              _inspectingPaper = null;
              _inspectingExam = null;
            });
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: _buildTopBar(isDesktopOrTablet, effectiveTab),
          bottomNavigationBar: isDesktopOrTablet
              ? null
              : NavigationBar(
                  selectedIndex: effectiveTab,
                  height: 64,
                  backgroundColor: Colors.white,
                  indicatorColor: const Color(0xFFD1FAE5),
                  onDestinationSelected: (idx) =>
                      setState(() => _activeTabIndex = idx),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.analytics_outlined),
                      selectedIcon:
                          Icon(Icons.analytics, color: Color(0xFF065F46)),
                      label: '成绩单',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.leaderboard_outlined),
                      selectedIcon:
                          Icon(Icons.leaderboard, color: Color(0xFF065F46)),
                      label: '全班对照',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.assignment_late_outlined),
                      selectedIcon:
                          Icon(Icons.assignment_late, color: Color(0xFF065F46)),
                      label: '错题本',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon:
                          Icon(Icons.people, color: Color(0xFF065F46)),
                      label: '账号与学生',
                    ),
                  ],
                ),
          body: Column(
            children: [
              if (!isDesktopOrTablet && effectiveTab != 3)
                _buildMobileStudentQuickStrip(),
              if (_errorBanner != null)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFFEF2F2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 18, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorBanner!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _errorBanner = null),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isDesktopOrTablet)
                      SizedBox(
                        width: 280,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              right: BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                          child: _buildAccountStudentPane(isMobileTab: false),
                        ),
                      ),
                    Expanded(
                      child: _buildCenterWorkspace(effectiveTab),
                    ),
                    if (showRightDocked && _currentAccount != null)
                      SizedBox(
                        width: 500,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              left: BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                          child: PaperInspectionPane(
                            key: ValueKey(
                              '${_inspectingExam!.examId}:${_inspectingPaper!.paperId}:${_currentAccount!.activeStudentId}',
                            ),
                            client: _client,
                            account: _currentAccount!,
                            exam: _inspectingExam!,
                            paper: _inspectingPaper!,
                            onClose: () => setState(() {
                              _inspectingPaper = null;
                              _inspectingExam = null;
                            }),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildTopBar(bool isDesktopOrTablet, int effectiveTab) {
    final stu = _dashboard?.currentStudent ?? _currentAccount?.activeStudent;
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      titleSpacing: 14,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00A870),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'HFS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              isDesktopOrTablet ? '好分数成绩工作台' : '好分数',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          if (stu != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: isDesktopOrTablet
                    ? null
                    : () => setState(() => _activeTabIndex = 3),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${stu.studentName}${stu.className.isNotEmpty ? " · ${stu.className}" : ""}${isDesktopOrTablet && stu.xuehao.isNotEmpty ? " (${stu.xuehao})" : ""}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (isDesktopOrTablet) ...[
          SegmentedButton<int>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
            segments: const [
              ButtonSegment(value: 0, label: Text('成绩单')),
              ButtonSegment(value: 1, label: Text('全班对照')),
              ButtonSegment(value: 2, label: Text('错题本')),
            ],
            selected: {effectiveTab},
            onSelectionChanged: (s) =>
                setState(() => _activeTabIndex = s.first),
          ),
          const SizedBox(width: 8),
        ] else ...[
          IconButton(
            tooltip: '绑定学生',
            onPressed: _showBindStudentDialog,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
          ),
        ],
        IconButton(
          tooltip: '刷新当前成绩 (F5)',
          onPressed: _loadingDashboard
              ? null
              : () => _loadDashboardForCurrent(allowCache: false),
          icon: _loadingDashboard
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 20),
        ),
        const SizedBox(width: 6),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: Color(0xFFE2E8F0)),
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
    if (allStudents.length <= 1) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in allStudents)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  selected: item.acc.id == _selectedAccountId &&
                      item.acc.activeStudentId == item.stu.studentId,
                  onSelected: (_) => _handleSwitchStudent(item.acc, item.stu),
                  label: Text(
                    item.acc.studentSnapshots[item.stu.studentId] != null
                        ? '${item.stu.studentName} (${item.acc.studentSnapshots[item.stu.studentId]!.scoreS}分)'
                        : item.stu.studentName,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandaloneLoginScreen() {
    final loginCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    int roleType = 2;
    bool busy = false;
    String? err;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (ctx, setCardState) {
                Future<void> doLogin() async {
                  final login = loginCtrl.text.trim();
                  final pass = passCtrl.text;
                  if (login.isEmpty || pass.isEmpty) {
                    setCardState(() => err = '请输入好分数账号与密码');
                    return;
                  }
                  setCardState(() {
                    busy = true;
                    err = null;
                  });
                  try {
                    final jar = await _client.loginHfs(
                      loginName: login,
                      password: pass,
                      roleType: roleType,
                    );
                    final id = HfsUpstreamClient.accountIdFor(login, roleType);
                    final acc = HfsAccount(
                      id: id,
                      label: '',
                      roleType: roleType,
                      loginName: login,
                      password: pass,
                      cookies: jar,
                      students: <StudentInfo>[],
                    );
                    await _client.hydrateAccountStudents(acc);
                    _accounts = <HfsAccount>[acc];
                    _selectedAccountId = acc.id;
                    await _persistAccounts();
                    if (!mounted) return;
                    setState(() {});
                    await _loadDashboardForCurrent(allowCache: false);
                  } catch (e) {
                    setCardState(() {
                      busy = false;
                      err = e.toString().replaceFirst('Exception: ', '');
                    });
                  }
                }

                return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(26),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00A870),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '好分数',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  '原生直连工作台',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '所有请求直接发往好分数官方后端 (hfs-be.yunxiao.com)，不经过任何第三方中转服务。完美适配手机触控与电脑大屏。',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 2, label: Text('家长版')),
                              ButtonSegment(value: 1, label: Text('学生版')),
                            ],
                            selected: {roleType},
                            onSelectionChanged: (s) =>
                                setCardState(() => roleType = s.first),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: loginCtrl,
                            decoration: const InputDecoration(
                              labelText: '手机号 / 好分数账号',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: passCtrl,
                            obscureText: true,
                            onSubmitted: (_) => doLogin(),
                            decoration: const InputDecoration(
                              labelText: '登录密码',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (err != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              err!,
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: busy ? null : doLogin,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(busy ? '正在直连好分数验证…' : '直连登录好分数'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountStudentPane({required bool isMobileTab}) {
    final curAcc = _currentAccount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '已登录账号与绑定学生',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _showAddAccountDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('加账号', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _accounts.length,
            itemBuilder: (ctx, idx) {
              final acc = _accounts[idx];
              final isSelectedAcc = acc.id == curAcc?.id;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: isSelectedAcc ? const Color(0xFFF8FAFC) : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                if (acc.id != _selectedAccountId) {
                                  setState(() => _selectedAccountId = acc.id);
                                  _loadDashboardForCurrent();
                                }
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    acc.displayLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    '${acc.roleType == 1 ? "学生端" : "家长端"} · 已绑 ${acc.students.length} 人',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '移除该账号',
                            icon: const Icon(Icons.delete_outline,
                                size: 16, color: Color(0xFF94A3B8)),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _removeAccount(acc),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final stu in acc.students)
                        _buildStudentRowTile(acc, stu, isMobileTab: isMobileTab),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _probingStudents ? null : _handleProbeAllStudents,
                  icon: const Icon(Icons.sync, size: 15),
                  label: Text(
                    _probingStudents ? '遍历中…' : '遍历全员成绩',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showBindStudentDialog,
                  icon: const Icon(Icons.person_add_alt_1, size: 15),
                  label: const Text(
                    '绑定学生',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStudentRowTile(
    HfsAccount acc,
    StudentInfo stu, {
    required bool isMobileTab,
  }) {
    final isActive =
        acc.id == _selectedAccountId && acc.activeStudentId == stu.studentId;
    final snap = acc.studentSnapshots[stu.studentId];

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: isActive ? const Color(0xFFECFDF5) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (isMobileTab) {
              setState(() => _activeTabIndex = 0);
            }
            _handleSwitchStudent(acc, stu);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF10B981)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stu.studentName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isActive ? FontWeight.w800 : FontWeight.w600,
                          color: isActive
                              ? const Color(0xFF065F46)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        [
                          if (stu.className.isNotEmpty) stu.className,
                          if (stu.xuehao.isNotEmpty) stu.xuehao,
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (snap != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFFD1FAE5)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${snap.scoreS}分',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? const Color(0xFF047857)
                            : const Color(0xFF334155),
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

  Widget _buildCenterWorkspace(int effectiveTab) {
    if (effectiveTab == 3) {
      return _buildAccountStudentPane(isMobileTab: true);
    }

    if (_loadingDashboard && _dashboard == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              '正在直连好分数拉取考试与科目成绩…',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    if (effectiveTab == 1) {
      return _buildFleetComparisonView();
    }
    if (effectiveTab == 2) {
      return _buildWrongOverviewView();
    }
    return _buildExamWorkbenchView();
  }

  Widget _buildExamWorkbenchView() {
    final dash = _dashboard;
    if (dash == null || dash.exams.isEmpty) {
      return const Center(
        child: Text(
          '当前学生暂无已发布的考试记录',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }

    final filteredExams = dash.exams.where((ex) {
      if (_examFilterQuery.trim().isEmpty) return true;
      return ex.name.toLowerCase().contains(_examFilterQuery.toLowerCase());
    }).toList();

    final curExam = _selectedExam ?? dash.exams.first;
    final allSubjects = dash.discoveredSubjects;
    final visiblePapers = curExam.papers
        .where((p) => !_hiddenSubjects.contains(p.subject))
        .toList();

    final visibleScoreSum =
        visiblePapers.fold<double>(0, (s, p) => s + p.score);
    final visibleManfenSum =
        visiblePapers.fold<double>(0, (s, p) => s + p.manfen);

    final isCompactMobile = MediaQuery.of(context).size.width < 600;

    return ListView(
      padding: EdgeInsets.all(isCompactMobile ? 12 : 16),
      children: [
        // 1. Exam selector & search bar
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      '历次考试',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: TextField(
                          onChanged: (v) =>
                              setState(() => _examFilterQuery = v),
                          decoration: const InputDecoration(
                            hintText: '搜索考试名称…',
                            prefixIcon: Icon(Icons.search, size: 16),
                            contentPadding: EdgeInsets.symmetric(vertical: 0),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final ex in filteredExams)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: ex.examId == curExam.examId,
                            onSelected: (_) =>
                                setState(() => _selectedExamId = ex.examId),
                            label: Text(
                              '${ex.name} (${ex.scoreS}分)',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 2. Current exam headline & subject filter
        Card(
          child: Padding(
            padding: EdgeInsets.all(isCompactMobile ? 14 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            curExam.name,
                            style: TextStyle(
                              fontSize: isCompactMobile ? 16 : 18,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '考试日期：${formatDateMs(curExam.time)} · 已出卷 ${curExam.reportedPaperCount} 科${curExam.classRankS.isNotEmpty ? " · 班排 ${curExam.classRankS}" : ""}${curExam.gradeRankS.isNotEmpty ? " · 年排 ${curExam.gradeRankS}" : ""}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _hiddenSubjects.isEmpty
                              ? '${curExam.scoreS} / ${round1(curExam.manfen)}'
                              : '${round1(visibleScoreSum)} / ${round1(visibleManfenSum)}',
                          style: TextStyle(
                            fontSize: isCompactMobile ? 19 : 22,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF00A870),
                          ),
                        ),
                        Text(
                          _hiddenSubjects.isEmpty ? '原始总分' : '筛选科目合计',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (allSubjects.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final subj in allSubjects)
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          label:
                              Text(subj, style: const TextStyle(fontSize: 12)),
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
                          label: const Text('重置全部科目',
                              style: TextStyle(fontSize: 12)),
                          onPressed: () =>
                              setState(() => _hiddenSubjects.clear()),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                const Divider(height: 1),
                for (final paper in visiblePapers)
                  _buildPaperScoreRow(curExam, paper),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaperScoreRow(ExamRecord exam, PaperScore paper) {
    final isSelected = _inspectingPaper?.paperId == paper.paperId &&
        _inspectingExam?.examId == exam.examId;
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0FDF4) : Colors.transparent,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              paper.subject,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Text(
                  paper.scoreS,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  ' / ${round1(paper.manfen)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: paper.paperId.isEmpty
                ? null
                : () => _openPaperInspection(exam, paper),
            icon: const Icon(Icons.document_scanner_outlined, size: 16),
            label: const Text('调阅答题卡', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFleetComparisonView() {
    _rebuildFleetRows();
    final isCompactMobile = MediaQuery.of(context).size.width < 600;
    return ListView(
      padding: EdgeInsets.all(isCompactMobile ? 12 : 16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已绑全体学生最新总分对照',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '汇总本地已登录账号下的全部学生最新考试快照（按总分降序）',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed:
                          _loadingFleet ? null : _handleProbeAllAccountsFleet,
                      icon: const Icon(Icons.sync, size: 16),
                      label: Text(_loadingFleet ? '正在同步全员…' : '同步全部账号学生'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                if (_fleetRows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('暂无已绑定学生')),
                  )
                else
                  for (var i = 0; i < _fleetRows.length; i++)
                    _buildFleetStudentTile(i + 1, _fleetRows[i]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFleetStudentTile(
    int rank,
    ({HfsAccount account, StudentInfo student, StudentSnapshot? snapshot}) row,
  ) {
    final snap = row.snapshot;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor:
            rank <= 3 ? const Color(0xFF00A870) : const Color(0xFFE2E8F0),
        child: Text(
          '$rank',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: rank <= 3 ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
      title: Text(
        '${row.student.studentName} (${row.student.className.isNotEmpty ? row.student.className : "未分班"})',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        snap != null
            ? '${snap.examName} · 学号 ${row.student.xuehao.isNotEmpty ? row.student.xuehao : "—"}'
            : '尚未拉取最新成绩（点击右侧切换）',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (snap != null)
            Text(
              '${snap.scoreS} / ${round1(snap.manfen)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF00A870),
              ),
            ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: () {
              setState(() => _activeTabIndex = 0);
              _handleSwitchStudent(row.account, row.student);
            },
            child: const Text('查看', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildWrongOverviewView() {
    final dash = _dashboard;
    if (dash == null || dash.wrongOverview.isEmpty) {
      return const Center(child: Text('暂无错题本统计数据'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '错题本概览（待复习总计 ${dash.totalWrong} 题）',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                for (final w in dash.wrongOverview)
                  ListTile(
                    title: Text(
                      w.subject,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      w.semesters
                          .map((s) => '${s.name}: ${s.wrongNum}题')
                          .join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(
                      '待复习 ${w.noReview} 题',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class PaperInspectionPane extends StatefulWidget {
  final HfsUpstreamClient client;
  final HfsAccount account;
  final ExamRecord exam;
  final PaperScore paper;
  final VoidCallback onClose;

  const PaperInspectionPane({
    super.key,
    required this.client,
    required this.account,
    required this.exam,
    required this.paper,
    required this.onClose,
  });

  @override
  State<PaperInspectionPane> createState() => _PaperInspectionPaneState();
}

class _PaperInspectionPaneState extends State<PaperInspectionPane> {
  PaperInspectionData? _data;
  String? _error;
  bool _loading = true;
  bool _showGradingOverlay = true;
  int _selectedSheetPage = 0;

  @override
  void initState() {
    super.initState();
    _loadInspection();
  }

  @override
  void didUpdateWidget(covariant PaperInspectionPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exam.examId != widget.exam.examId ||
        oldWidget.paper.paperId != widget.paper.paperId ||
        oldWidget.paper.pid != widget.paper.pid) {
      _selectedSheetPage = 0;
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
      );
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.paper.subject} · 答题卡与批改原迹',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      widget.exam.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              FilterChip(
                visualDensity: VisualDensity.compact,
                label: const Text('批改叠加层', style: TextStyle(fontSize: 12)),
                selected: _showGradingOverlay,
                onSelected: (v) => setState(() => _showGradingOverlay = v),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '关闭 (Esc)',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
        if (_loading)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text(
                    '正在直连好分数调阅答题卡与批改坐标…',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          )
        else if (_error != null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 36, color: Color(0xFFDC2626)),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFDC2626)),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loadInspection,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (data != null)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildScoreMiniStat('卷面总分', '${data.totalScore}'),
                      _buildScoreMiniStat('客观题得分', '${data.objectScore}'),
                      _buildScoreMiniStat('主观题得分', '${data.subjectScore}'),
                      _buildScoreMiniStat(
                          '失分题数', '${data.lostQuestions.length}题'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (data.answerPages.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < data.answerPages.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('第 ${i + 1} 页'),
                                selected: _selectedSheetPage == i,
                                onSelected: (_) =>
                                    setState(() => _selectedSheetPage = i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (data.answerPages.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: AnswerSheetCanvas(
                        client: widget.client,
                        imageUrl: data.answerPages[_selectedSheetPage
                            .clamp(0, data.answerPages.length - 1)],
                        overlay: _selectedSheetPage < data.pageOverlays.length
                            ? data.pageOverlays[_selectedSheetPage]
                            : null,
                        showOverlay: _showGradingOverlay,
                      ),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('该科目未返回答题卡扫描件')),
                  ),
                const SizedBox(height: 16),
                const Text(
                  '逐题得分与失分明细',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final q in data.questions) _buildQuestionDetailTile(q),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildScoreMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionDetailTile(QuestionDetailItem q) {
    final Color tagColor = q.isFullScore
        ? const Color(0xFF16A34A)
        : (q.isZeroScore ? const Color(0xFFDC2626) : const Color(0xFFD97706));

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: tagColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第 ${q.name} 题 (${q.type == 2 ? "客观题" : "主观题"})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (q.type == 2 &&
                    (q.myAnswer.isNotEmpty || q.answer.isNotEmpty))
                  Text(
                    '作答: ${q.myAnswer.isEmpty ? "—" : q.myAnswer}  ·  标答: ${q.answer.isEmpty ? "—" : q.answer}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${q.scoreS} / ${round1(q.manfen)}分',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: tagColor,
            ),
          ),
        ],
      ),
    );
  }
}
