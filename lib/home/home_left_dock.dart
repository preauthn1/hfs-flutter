part of '../main.dart';

extension _HfsHomeLeftDockExt on _HfsHomeScreenState {
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
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Text(
                  '好分数账号与绑定学生',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Taste.muted,
                  ),
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _miniIconBtn(
                      label: '同步当前',
                      onTap: _loadingDashboard
                          ? null
                          : () => _loadDashboardForCurrent(allowCache: false),
                    ),
                    if (curAcc?.wechatSessionCookie.trim().isNotEmpty == true)
                      _miniIconBtn(
                        label: '微信成绩',
                        onTap: _openMiniScoresModal,
                      ),
                    if (curAcc?.wechatSessionCookie.trim().isNotEmpty == true)
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
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Text(
                  '挂载更多好分数账号',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Taste.muted,
                  ),
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _miniIconBtn(
                      label: _showInlineQuickAddAccount ? '收起' : '＋ 快速加号',
                      active: _showInlineQuickAddAccount,
                      onTap: () => _setHomeState(() => _showInlineQuickAddAccount =
                          !_showInlineQuickAddAccount),
                    ),
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
                        child: DropdownButtonFormField2<int>(
                          value: _inlineAddRole,
                          isExpanded: true,
                          isDense: true,
                          iconStyleData: Taste.dropdownIconStyle,
                          dropdownStyleData: Taste.dropdownStyle(
                            context,
                            maxHeight: 220,
                            dropdownWidth: Taste.resolveDropdownMenuWidth(
                              context,
                              preferredWidth: 168,
                            ),
                          ),
                          menuItemStyleData: Taste.menuItemStyle(context),
                          selectedItemBuilder: (ctx) => const [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '家长端 (可绑多人)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Taste.text,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '学生端',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
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
                                horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(Taste.radiusControl),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 2,
                              child: Text(
                                '家长端 (可绑多人)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 1,
                              child: Text(
                                '学生端',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) _setHomeState(() => _inlineAddRole = v);
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
                        _inlineAddingAccount ? '正在验证并拉取学生…' : '登录并挂载该账号',
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
            child: LayoutBuilder(
              builder: (ctx, box) {
                final compact = box.maxWidth < 420;
                final message = Text(
                  '${acc.maskedLogin} · 已绑 ${acc.students.length}/${acc.estimatedMaxQuota} 人${acc.minusOneSlotCount > 0 ? " (-1活名额×${acc.minusOneSlotCount})" : ""}',
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Taste.muted,
                  ),
                );
                final actions = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _svgIconActionBtn(
                      tooltip: '导出该账号凭证文件 (.json)',
                      icon: Icons.download_outlined,
                      onTap: () =>
                          _exportCredentialFileDirect(singleAccount: acc),
                    ),
                    const SizedBox(width: 4),
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
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (compact) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            acc.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                      const SizedBox(height: 4),
                      message,
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerRight, child: actions),
                    ] else
                      Row(
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
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
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
                                        label:
                                            acc.roleType == 1 ? '学生端' : '家长端',
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
                                  message,
                                ],
                              ),
                            ),
                          ),
                          actions,
                        ],
                      ),
                  ],
                );
              },
            ),
          ),

          // 2. Account Subbar (School + Traverse All + Bind Student)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Taste.surface,
              border: Border(bottom: BorderSide(color: Taste.rule)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  schoolTitle,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Taste.muted,
                  ),
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _miniIconBtn(
                      label: isProbingThis ? '遍历中…' : '遍历全员',
                      onTap: isProbingThis
                          ? null
                          : () => _handleProbeAccountStudents(acc),
                    ),
                    _miniIconBtn(
                      label: isBindingHere ? '收起' : '＋绑学生',
                      active: isBindingHere,
                      onTap: () => _setHomeState(() {
                        _inlineBindAccountId = isBindingHere ? null : acc.id;
                      }),
                    ),
                    _miniIconBtn(
                      label: '多通道/换绑',
                      onTap: () =>
                          _openAdvancedBindStudentModal(targetAccount: acc),
                    ),
                  ],
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
            _setHomeState(() => _activeTabIndex = 0);
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
                        if (stu.changeBindShortBadge.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: stu.isMinusOneSlot
                                  ? Taste.pillBlueBg
                                  : (stu.isSemesterLocked
                                      ? Taste.raised
                                      : Taste.pillPosBg),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              stu.changeBindShortBadge,
                              style: Taste.numStyle(
                                size: 9.5,
                                weight: FontWeight.w500,
                                color: stu.isMinusOneSlot
                                    ? Taste.pillBlueInk
                                    : (stu.isSemesterLocked
                                        ? Taste.muted
                                        : Taste.pillPosInk),
                              ),
                            ),
                          ),
                        ],
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
              const SizedBox(width: 6),
              Tooltip(
                message: '将该学生槽位换绑为其他学生 (${stu.changeBindStatusLabel})',
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _openAdvancedBindStudentModal(
                    targetAccount: acc,
                    initialReplaceStudentId: stu.studentId,
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Taste.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Taste.control),
                    ),
                    child: const Text(
                      '换绑',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: Taste.text,
                      ),
                    ),
                  ),
                ),
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
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 20 : 12,
            6,
            isDesktop ? 20 : 12,
            0,
          ),
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
                      SizedBox(width: isDesktop ? 24 : 16),
                      _buildStageUnderlineTab(1, '全账号与全体学生总览'),
                      SizedBox(width: isDesktop ? 24 : 16),
                      _buildStageUnderlineTab(2, '错题本与原始诊断'),
                    ],
                  ),
                ),
              ),
              if (isDesktop && _inspectingPaper != null && _inspectorCollapsed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 8),
                  child: _miniIconBtn(
                    label: '展开答题卡栏',
                    active: true,
                    onTap: () => _setHomeState(() => _inspectorCollapsed = false),
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
      onTap: () => _setHomeState(() => _activeTabIndex = index),
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

}
