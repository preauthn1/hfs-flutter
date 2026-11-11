part of '../main.dart';

extension _HfsHomeScaffoldAndTopBarExt on _HfsHomeScreenState {
  // Main scaffold builder delegated from _HfsHomeScreenState.build
  Widget _buildHomeScreen(BuildContext context) {
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
                onMiniAuthenticated: _handleUpsertAuthenticatedAccount,
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
            _setHomeState(() => _inspectorCollapsed = true);
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
                        _setHomeState(() => _activeTabIndex = idx),
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
                          onPressed: () => _setHomeState(() => _errorBanner = null),
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
                                _setHomeState(() {
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
                                onSelectPaper: (nextPaper) =>
                                    _openPaperInspection(
                                  _inspectingExam!,
                                  nextPaper,
                                ),
                                onClose: () => _setHomeState(() {
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
    if (!isDesktop) {
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: Taste.ground,
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Taste.accent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Image.asset(
                'assets/images/app_logo.png',
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, st) => const Center(
                  child: Text(
                    '好',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '好分数工作台',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Taste.text,
                ),
              ),
            ),
            if (_loadingDashboard)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
              ),
            _buildTopBarBtn(
              label: '加号',
              icon: Icons.person_add_alt_outlined,
              compact: true,
              onTap: () => _openAuthOrRegisterModal(),
            ),
            const SizedBox(width: 5),
            _buildTopBarBtn(
              label: '刷新',
              icon: Icons.refresh,
              compact: true,
              onTap: _loadingDashboard
                  ? null
                  : () => _loadDashboardForCurrent(allowCache: false),
            ),
            const SizedBox(width: 5),
            _buildTopBarBtn(
              label: '设置',
              icon: Icons.tune,
              compact: true,
              onTap: _openSettingsModal,
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (ctx, box) {
        if (box.maxWidth < 1180) {
          return _buildCompactDesktopTopBar(curExam);
        }
        return Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color: Taste.ground,
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Taste.accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, st) => const Center(
                    child: Text(
                      '好',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '好分数成绩工作台',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Taste.text,
                  ),
                ),
              ),
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
              const Spacer(),
              _buildStatPill('已挂账号', '${_accounts.length}'),
              const SizedBox(width: 8),
              _buildStatPill('已绑学生', '$_totalBoundStudentsCount'),
              const SizedBox(width: 8),
              _buildStatPill('当前考试', curExam != null ? curExam.name : '—'),
              const SizedBox(width: 14),
              if (_loadingDashboard)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                      Text('同步中…',
                          style: TextStyle(fontSize: 11, color: Colors.white)),
                    ],
                  ),
                ),
              _buildTopBarBtn(
                label: '账号登录/注册',
                icon: Icons.person_add_alt_outlined,
                onTap: () => _openAuthOrRegisterModal(),
              ),
              const SizedBox(width: 5),
              _buildTopBarBtn(
                label: '微信侧成绩',
                icon: Icons.fact_check_outlined,
                onTap: _openMiniScoresModal,
              ),
              const SizedBox(width: 5),
              _buildTopBarBtn(
                label: '刷新当前',
                icon: Icons.refresh,
                onTap: _loadingDashboard
                    ? null
                    : () => _loadDashboardForCurrent(allowCache: false),
              ),
              const SizedBox(width: 5),
              _buildTopBarBtn(
                label: '导出凭证',
                icon: Icons.download_outlined,
                onTap: () => _exportCredentialFileDirect(),
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
      },
    );
  }

  Widget _buildCompactDesktopTopBar(ExamRecord? curExam) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: Taste.ground,
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Taste.accent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Image.asset(
              'assets/images/app_logo.png',
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, st) => const Center(
                child: Text(
                  '好',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '好分数成绩工作台',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Taste.text,
              ),
            ),
          ),
          if (_loadingDashboard)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            ),
          _buildTopBarBtn(
            label: '登录',
            icon: Icons.person_add_alt_outlined,
            compact: true,
            onTap: () => _openAuthOrRegisterModal(),
          ),
          const SizedBox(width: 5),
          _buildTopBarBtn(
            label: '刷新',
            icon: Icons.refresh,
            compact: true,
            onTap: _loadingDashboard
                ? null
                : () => _loadDashboardForCurrent(allowCache: false),
          ),
          const SizedBox(width: 5),
          _buildTopBarBtn(
            label: '设置',
            icon: Icons.tune,
            compact: true,
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
    bool compact = false,
  }) {
    return SizedBox(
      height: 30,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: Taste.surface,
          foregroundColor: Taste.text,
          side: const BorderSide(color: Taste.control),
          padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Taste.radiusControl),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: compact ? 13 : 14, color: Taste.text),
        label: Text(
          label,
          style: TextStyle(
            fontSize: compact ? 11.5 : 12,
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

}
