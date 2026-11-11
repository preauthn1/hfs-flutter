import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart' as mbs;
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'answer_sheet_painter.dart';
import 'hfs_client.dart';
import 'hfs_models.dart';
import 'taste_widgets.dart';

part 'home/home_state_actions.dart';
part 'home/home_scaffold_and_topbar.dart';
part 'home/home_left_dock.dart';
part 'home/home_grades_stage.dart';
part 'home/home_fleet_stage.dart';
part 'home/paper_inspection_pane.dart';

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

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
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
      builder: (context, child) => ResponsiveBreakpoints.builder(
        child: child ?? const SizedBox.shrink(),
        breakpoints: const [
          Breakpoint(start: 0, end: 450, name: MOBILE),
          Breakpoint(start: 451, end: 859, name: TABLET),
          Breakpoint(start: 860, end: 1920, name: DESKTOP),
          Breakpoint(start: 1921, end: double.infinity, name: '4K'),
        ],
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

const String _prefsAccountsKey = 'hfs_direct_accounts_v1';
const String _prefsSelectedKey = 'hfs_direct_selected_id_v1';
const String _prefsSettingsKey = 'hfs_direct_settings_v2';
const String _prefsDashSnapPrefix = 'hfs_dash_snap_v2:';

class _HfsHomeScreenState extends State<HfsHomeScreen> {
  void _setHomeState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

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
  final TextEditingController _examDropdownSearchCtrl = TextEditingController();
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
  bool _inspectorCollapsed = false;
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
    _examDropdownSearchCtrl.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) => _buildHomeScreen(context);
}
