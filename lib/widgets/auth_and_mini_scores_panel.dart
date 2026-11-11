part of '../taste_widgets.dart';

class MiniScoresDialog extends StatefulWidget {
  final HfsUpstreamClient client;
  final HfsAccount account;

  const MiniScoresDialog({
    super.key,
    required this.client,
    required this.account,
  });

  @override
  State<MiniScoresDialog> createState() => _MiniScoresDialogState();
}

class _MiniScoresDialogState extends State<MiniScoresDialog> {
  MiniScoreReport? _report;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final report = await widget.client.miniProxyScores(widget.account);
      if (!mounted) return;
      setState(() {
        _report = report;
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
          maxWidth: 620,
          maxHeight: Taste.dialogMaxHeight(context, desktopMax: 680),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                style: const TextStyle(color: Taste.negative),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _load,
                                child: const Text('重试'),
                              ),
                            ],
                          )
                        : _buildReport(_report!),
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

  Widget _buildReport(MiniScoreReport report) {
    final studentLabel = strOf(report.student['studentName'], '当前学生');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '微信侧成绩读取 · $studentLabel',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
        const Divider(height: 16),
        Expanded(
          child: report.exams.isEmpty
              ? const Center(child: Text('该学生没有考试记录'))
              : ListView.separated(
                  itemCount: report.exams.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final exam = report.exams[index];
                    return ExpansionTile(
                      title: Text(exam.name),
                      subtitle: Text(
                        '总分 ${exam.score}/${exam.manfen} · 班排 ${exam.classRank.isEmpty ? '—' : exam.classRank} · 年级排 ${exam.gradeRank.isEmpty ? '—' : exam.gradeRank}',
                      ),
                      children: [
                        for (final paper in exam.papers)
                          ListTile(
                            dense: true,
                            title: Text(paper.subject),
                            trailing: Text('${paper.score}/${paper.manfen}'),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Unified Auth / Register / Forgot-Password Panel (works standalone or inside a dialog)
class HfsAuthPanel extends StatefulWidget {
  final HfsUpstreamClient client;
  final HfsAccount? reauthAccount;
  final bool isDialog;
  final Future<void> Function(HfsAccount account) onAuthenticated;
  final Future<void> Function(HfsAccount account)? onMiniAuthenticated;

  const HfsAuthPanel({
    super.key,
    required this.client,
    required this.onAuthenticated,
    this.reauthAccount,
    this.isDialog = false,
    this.onMiniAuthenticated,
  });

  @override
  State<HfsAuthPanel> createState() => _HfsAuthPanelState();
}

class _HfsAuthPanelState extends State<HfsAuthPanel> {
  // 0 = 登录已有账号, 1 = 注册新账号, 2 = 短信找回密码, 3 = 小程序免密登录, 4 = 小程序注册
  int _mode = 0;
  int _roleType = 2; // 2 = 家长端, 1 = 学生端

  late final TextEditingController _phoneCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _labelCtrl;
  final TextEditingController _smsCodeCtrl = TextEditingController();
  final TextEditingController _captchaCtrl = TextEditingController();
  final TextEditingController _inviteCtrl = TextEditingController();
  final TextEditingController _miniCodeCtrl = TextEditingController();
  final TextEditingController _miniUnionIdCtrl = TextEditingController();
  final TextEditingController _miniInvitationCtrl = TextEditingController();

  String? _selectedMiniUserId;
  MiniRelatedUsersResult? _miniRelated;
  bool _miniDiscovering = false;
  bool _miniLoggingIn = false;

  String? _captchaSvg;
  bool _busy = false;
  bool _sendingSms = false;
  int _smsCountdown = 0;
  Timer? _timer;
  String? _errorText;
  String? _infoText;

  @override
  void initState() {
    super.initState();
    final re = widget.reauthAccount;
    _phoneCtrl = TextEditingController(text: re?.loginName ?? '');
    _passCtrl = TextEditingController(text: re?.password ?? '');
    _labelCtrl = TextEditingController(text: re?.label ?? '');
    if (re != null) {
      _roleType = re.roleType;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _labelCtrl.dispose();
    _smsCodeCtrl.dispose();
    _captchaCtrl.dispose();
    _inviteCtrl.dispose();
    _miniCodeCtrl.dispose();
    _miniUnionIdCtrl.dispose();
    _miniInvitationCtrl.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _smsCountdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_smsCountdown <= 1) {
        t.cancel();
        setState(() => _smsCountdown = 0);
      } else {
        setState(() => _smsCountdown -= 1);
      }
    });
  }

  static final RegExp _phoneRe = RegExp(r'^1\d{10}$');

  Future<void> _refreshCaptcha() async {
    final phone = _phoneCtrl.text.trim();
    if (!_phoneRe.hasMatch(phone)) {
      setState(() => _errorText = '请输入有效的 11 位手机号码');
      return;
    }
    try {
      final svg = await widget.client.fetchCaptchaSvg(
        phoneNumber: phone,
        roleType: _roleType,
      );
      if (!mounted) return;
      setState(() {
        _captchaSvg = svg;
        _errorText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleSendSms() async {
    if (_mode == 4) {
      setState(() => _errorText = '微信侧注册短信验证码请在小程序中获取后填入');
      return;
    }
    final phone = _phoneCtrl.text.trim();
    if (!_phoneRe.hasMatch(phone)) {
      setState(() => _errorText = '请输入有效的 11 位手机号码');
      return;
    }
    setState(() {
      _sendingSms = true;
      _errorText = null;
      _infoText = null;
    });
    try {
      final outcome = _mode == 1
          ? await widget.client.sendRegisterSmsCode(
              phoneNumber: phone,
              roleType: _roleType,
              captchaCode: _captchaCtrl.text.trim(),
            )
          : await widget.client.sendResetPwdSmsCode(
              phoneNumber: phone,
              roleType: _roleType,
              captchaCode: _captchaCtrl.text.trim(),
            );
      if (!mounted) return;
      if (outcome.isOk) {
        setState(() {
          _sendingSms = false;
          _captchaSvg = null;
          _captchaCtrl.clear();
          _infoText = '短信验证码已发送至 $phone，请注意查收';
        });
        _startCountdown();
      } else if (outcome.needsCaptcha) {
        String? svg = outcome.captchaSvg;
        svg ??= await widget.client.fetchCaptchaSvg(
          phoneNumber: phone,
          roleType: _roleType,
        );
        if (!mounted) return;
        setState(() {
          _sendingSms = false;
          _captchaSvg = svg;
          _errorText = _captchaCtrl.text.trim().isEmpty
              ? '请输入下方图形验证码后再点击发送短信'
              : '图形验证码有误，请重新输入';
          _captchaCtrl.clear();
        });
      } else if (outcome.isAlreadyOccupied) {
        setState(() {
          _sendingSms = false;
          _errorText = '该手机号已注册过好分数账号，请直接切换至「登录已有账号」';
        });
      } else {
        setState(() {
          _sendingSms = false;
          _errorText = outcome.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sendingSms = false;
        _errorText = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleSubmit() async {
    final login = _phoneCtrl.text.trim();
    final pass = _passCtrl.text;
    if (login.isEmpty || pass.isEmpty) {
      setState(() => _errorText = '请填写手机号/好分数账号与密码');
      return;
    }
    if ((_mode == 1 || _mode == 2) && !_phoneRe.hasMatch(login)) {
      setState(() => _errorText = '请输入有效的 11 位手机号码');
      return;
    }
    if ((_mode == 1 || _mode == 2) && _smsCodeCtrl.text.trim().isEmpty) {
      setState(() => _errorText = '请输入收到的短信验证码');
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
      _infoText = null;
    });

    try {
      late List<String> jar;
      if (_mode == 0) {
        jar = await widget.client.loginHfs(
          loginName: login,
          password: pass,
          roleType: _roleType,
        );
      } else if (_mode == 1) {
        jar = await widget.client.registerNativeAccount(
          phoneNumber: login,
          password: pass,
          verificationCode: _smsCodeCtrl.text.trim(),
          roleType: _roleType,
          invitationCode: _inviteCtrl.text.trim(),
        );
      } else {
        await widget.client.resetForgotPassword(
          phoneNumber: login,
          smsCode: _smsCodeCtrl.text.trim(),
          newPassword: pass,
          roleType: _roleType,
        );
        jar = await widget.client.loginHfs(
          loginName: login,
          password: pass,
          roleType: _roleType,
        );
      }

      final id = widget.reauthAccount?.id ??
          HfsUpstreamClient.accountIdFor(login, _roleType);
      final acc = HfsAccount(
        id: id,
        label: _labelCtrl.text.trim(),
        roleType: _roleType,
        loginName: login,
        password: pass,
        cookies: jar,
        students: widget.reauthAccount?.students ?? <StudentInfo>[],
        activeStudentId: widget.reauthAccount?.activeStudentId ?? '',
        desiredStudentId: widget.reauthAccount?.desiredStudentId ?? '',
        studentSnapshots: widget.reauthAccount?.studentSnapshots,
      );
      await widget.client.hydrateAccountStudents(acc);
      if (!mounted) return;
      await widget.onAuthenticated(acc);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _discoverMiniAccounts() async {
    final phone = _phoneCtrl.text.trim();
    final code = _miniCodeCtrl.text.trim();
    if (!_phoneRe.hasMatch(phone)) {
      setState(() => _errorText = '请输入需要在微信小程序侧关联的 11 位手机号');
      return;
    }
    if (code.isEmpty) {
      setState(() => _errorText = '请输入你自己的 wx.login() code');
      return;
    }
    setState(() {
      _miniDiscovering = true;
      _errorText = null;
      _infoText = null;
    });
    try {
      final result = await widget.client.miniAccountRelatedUsers(
        code: code,
        phone: phone,
      );
      if (!mounted) return;
      setState(() {
        _miniRelated = result;
        _selectedMiniUserId =
            result.users.isNotEmpty ? result.users.first.userId : null;
        _miniDiscovering = false;
        _infoText = result.users.isEmpty
            ? '该微信/手机号没有关联的好分数账号'
            : '已找到 ${result.users.length} 个关联账号，请选择后换取会话';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _miniDiscovering = false;
        _errorText = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleMiniRegister() async {
    final phone = _phoneCtrl.text.trim();
    final password = _passCtrl.text;
    final unionId = _miniUnionIdCtrl.text.trim();
    final vcode = _smsCodeCtrl.text.trim();
    if (!_phoneRe.hasMatch(phone)) {
      setState(() => _errorText = '请输入有效的 11 位手机号码');
      return;
    }
    if (unionId.isEmpty || vcode.isEmpty || password.isEmpty) {
      setState(() => _errorText = '请填写 unionId、密码与真实短信验证码');
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
      _infoText = null;
    });
    try {
      final result = await widget.client.miniAccountRegister(
        phone: phone,
        unionId: unionId,
        roleType: _roleType,
        password: password,
        vcode: vcode,
        invitationCode: _miniInvitationCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _infoText = result.isOk
            ? '微信小程序账号注册成功，请切换到「微信小程序免密」并重新查询关联账号后登录'
            : result.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleMiniLogin() async {
    if (_miniRelated == null || _miniRelated!.users.isEmpty) {
      await _discoverMiniAccounts();
      if (!mounted || _miniRelated == null || _miniRelated!.users.isEmpty) {
        return;
      }
    }
    final unionId = _miniUnionIdCtrl.text.trim();
    if (unionId.isEmpty) {
      setState(() => _errorText = '请输入微信 unionId（小程序 wx.login 结果提供）');
      return;
    }
    final user = _miniRelated!.users.firstWhere(
      (u) => u.userId == _selectedMiniUserId,
      orElse: () => _miniRelated!.users.first,
    );
    setState(() {
      _busy = true;
      _miniLoggingIn = true;
      _errorText = null;
      _infoText = null;
    });
    try {
      final miniSession = await widget.client.miniAccountLogin(
        user: user,
        key: user.key,
        unionId: unionId,
      );
      final acc = await widget.client.miniLoginAsAccount(
        session: miniSession,
        label: _labelCtrl.text.trim(),
      );
      if (!mounted) return;
      if (widget.onMiniAuthenticated != null) {
        await widget.onMiniAuthenticated!(acc);
      } else {
        await widget.onAuthenticated(acc);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _miniLoggingIn = false;
        _errorText = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReauth = widget.reauthAccount != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(widget.isDialog ? 4 : 28),
        decoration: widget.isDialog
            ? null
            : BoxDecoration(
                color: Taste.surface,
                borderRadius: BorderRadius.circular(Taste.radiusCard),
                border: Border.all(color: Taste.border),
              ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isReauth && !widget.isDialog) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Taste.radiusControl),
                child: Container(
                  height: 118,
                  decoration: BoxDecoration(
                    color: Taste.raised,
                    border: Border.all(color: Taste.border),
                    borderRadius: BorderRadius.circular(Taste.radiusControl),
                  ),
                  child: Image.asset(
                    'assets/images/hero_auth_banner.png',
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
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
                        'HFS',
                        style: TextStyle(
                          fontFamily: Taste.fontFamily,
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isReauth
                        ? '重连账号 · ${widget.reauthAccount!.displayLabel}'
                        : (_mode == 0
                            ? '连接好分数官方账号'
                            : (_mode == 1
                                ? '注册好分数新账号'
                                : (_mode == 2
                                    ? '短信找回好分数密码'
                                    : (_mode == 3
                                        ? '微信小程序免密登录'
                                        : '微信小程序新号注册')))),
                    style: const TextStyle(
                      fontFamily: Taste.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Taste.text,
                    ),
                  ),
                ),
                if (widget.isDialog)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '直连 hfs-be.yunxiao.com 官方接口，支持无限叠加多个家长端与学生端账号。',
              style: TextStyle(
                fontFamily: Taste.fontFamily,
                fontSize: 12,
                color: Taste.muted,
              ),
            ),
            const SizedBox(height: 14),
            if (!isReauth) ...[
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Taste.raised,
                  borderRadius: BorderRadius.circular(Taste.radiusControl),
                  border: Border.all(color: Taste.border),
                ),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _buildModeTab(0, '登录已有账号'),
                    _buildModeTab(1, '注册新账号'),
                    _buildModeTab(2, '找回密码'),
                    _buildModeTab(3, '微信免密'),
                    _buildModeTab(4, '微信注册'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  '客户端类型：',
                  style: TextStyle(
                    fontFamily: Taste.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Taste.muted,
                  ),
                ),
                ChoiceChip(
                  label:
                      const Text('家长版 (可绑多人)', style: TextStyle(fontSize: 12)),
                  selected: _roleType == 2,
                  onSelected:
                      _busy ? null : (_) => setState(() => _roleType = 2),
                  visualDensity: VisualDensity.compact,
                ),
                ChoiceChip(
                  label: const Text('学生版', style: TextStyle(fontSize: 12)),
                  selected: _roleType == 1,
                  onSelected:
                      _busy ? null : (_) => setState(() => _roleType = 1),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildLabeledInput(
              label: _mode == 0
                  ? '手机号 / 好分数账号 / 学号'
                  : ((_mode == 3 || _mode == 4) ? '关联手机号' : '11 位手机号码'),
              controller: _phoneCtrl,
              hint: _mode == 0
                  ? '输入手机号或学生端账号'
                  : ((_mode == 3 || _mode == 4)
                      ? '仅填写你自己的手机号'
                      : '请输入未注册的 11 位手机号'),
            ),
            if (_mode == 3) ...[
              _buildLabeledInput(
                label: '微信 wx.login() code',
                controller: _miniCodeCtrl,
                hint: '从你自己的微信小程序 wx.login() 获取',
              ),
              const SizedBox(height: 10),
              _buildLabeledInput(
                label: '微信 unionId',
                controller: _miniUnionIdCtrl,
                hint: '从你自己的小程序会话/服务端获取',
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Taste.pillWarnBg,
                  borderRadius: BorderRadius.circular(Taste.radiusControl),
                ),
                child: const Text(
                  '此模式只连接你自己的微信身份，并将 account-related-user 返回的账号列表展示在本地；Flutter 无法自行调用 wx.login()。不会猜测 code、unionId，也不会对第三方手机号发起查询。',
                  style: TextStyle(fontSize: 11.5, color: Taste.pillWarnInk),
                ),
              ),
              const SizedBox(height: 8),
              if (_miniRelated != null && _miniRelated!.users.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Taste.raised,
                    borderRadius: BorderRadius.circular(Taste.radiusControl),
                    border: Border.all(color: Taste.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '微信关联账号（仅显示脱敏手机号与角色）',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      for (final u in _miniRelated!.users)
                        InkWell(
                          onTap: _busy
                              ? null
                              : () => setState(
                                    () => _selectedMiniUserId = u.userId,
                                  ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  _selectedMiniUserId == u.userId
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 19,
                                  color: _selectedMiniUserId == u.userId
                                      ? Taste.accent
                                      : Taste.muted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${u.roleLabel} · ${maskLoginName(u.phone)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: (_miniDiscovering || _busy)
                        ? null
                        : _discoverMiniAccounts,
                    icon: _miniDiscovering
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.6),
                          )
                        : const Icon(Icons.search, size: 15),
                    label: Text(
                      _miniDiscovering ? '查询中…' : '查询微信关联账号',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (_miniLoggingIn)
                    const Text(
                      '正在换取会话…',
                      style: TextStyle(fontSize: 12, color: Taste.muted),
                    ),
                ],
              ),
            ] else if (_mode == 4) ...[
              _buildLabeledInput(
                label: '微信 unionId',
                controller: _miniUnionIdCtrl,
                hint: '从你自己的小程序会话/服务端获取',
              ),
              const SizedBox(height: 10),
              _buildLabeledInput(
                label: '真实短信验证码',
                controller: _smsCodeCtrl,
                hint: '服务端会校验，不能绕过',
              ),
              const SizedBox(height: 10),
              _buildLabeledInput(
                label: '设置密码',
                controller: _passCtrl,
                hint: '输入新账号密码',
                obscure: true,
              ),
              const SizedBox(height: 8),
              _buildLabeledInput(
                label: '邀请码（选填）',
                controller: _miniInvitationCtrl,
                hint: '可留空',
              ),
              const Text(
                '微信侧注册不会绕过短信验证码；邀请码为可选项。',
                style: TextStyle(fontSize: 11.5, color: Taste.muted),
              ),
            ] else ...[
              if (_mode == 1 || _mode == 2) ...[
                if (_captchaSvg != null) ...[
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (ctx, box) {
                      final compact = box.maxWidth < 420;
                      return compact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildLabeledInput(
                                  label: '图形验证码',
                                  controller: _captchaCtrl,
                                  hint: '输入图中字符',
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: SvgCaptchaView(
                                    svgXml: _captchaSvg!,
                                    width: 124,
                                    height: 38,
                                    onTapRefresh: _refreshCaptcha,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: _buildLabeledInput(
                                    label: '图形验证码（点击右侧图片可刷新）',
                                    controller: _captchaCtrl,
                                    hint: '输入图中字符',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SvgCaptchaView(
                                  svgXml: _captchaSvg!,
                                  width: 124,
                                  height: 38,
                                  onTapRefresh: _refreshCaptcha,
                                ),
                              ],
                            );
                    },
                  ),
                ],
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (ctx, box) {
                    final compact = box.maxWidth < 420;
                    return compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildLabeledInput(
                                label: '短信验证码',
                                controller: _smsCodeCtrl,
                                hint: '6 位短信验证码',
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton(
                                  onPressed: (_sendingSms ||
                                          _smsCountdown > 0 ||
                                          _busy)
                                      ? null
                                      : _handleSendSms,
                                  child: Text(
                                    _sendingSms
                                        ? '发送中…'
                                        : (_smsCountdown > 0
                                            ? '重发 (${_smsCountdown}s)'
                                            : '获取验证码'),
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
                                child: _buildLabeledInput(
                                  label: '短信验证码',
                                  controller: _smsCodeCtrl,
                                  hint: '6 位短信验证码',
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 38,
                                child: OutlinedButton(
                                  onPressed: (_sendingSms ||
                                          _smsCountdown > 0 ||
                                          _busy)
                                      ? null
                                      : _handleSendSms,
                                  child: Text(
                                    _sendingSms
                                        ? '发送中…'
                                        : (_smsCountdown > 0
                                            ? '重发 (${_smsCountdown}s)'
                                            : '获取验证码'),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          );
                  },
                ),
              ],
            ],
            const SizedBox(height: 10),
            if (_mode != 3 && _mode != 4)
              _buildLabeledInput(
                label: _mode == 0 ? '登录密码' : '设置密码（8~20位，建议含字母+数字+符号）',
                controller: _passCtrl,
                hint: _mode == 0 ? '输入好分数密码' : '如：Abc12345!',
                obscure: true,
                onSubmitted: (_) => _handleSubmit(),
              ),
            LayoutBuilder(
              builder: (ctx, box) {
                final compact = box.maxWidth < 420;
                return compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildLabeledInput(
                            label: '账号备注名（选填，便于多号区分）',
                            controller: _labelCtrl,
                            hint: '如：家长主号 / 二号池',
                          ),
                          if (_mode == 1) ...[
                            const SizedBox(height: 10),
                            _buildLabeledInput(
                              label: '邀请码（选填）',
                              controller: _inviteCtrl,
                              hint: '可留空',
                            ),
                          ],
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: _buildLabeledInput(
                              label: '账号备注名（选填，便于多号区分）',
                              controller: _labelCtrl,
                              hint: '如：家长主号 / 二号池',
                            ),
                          ),
                          if (_mode == 1) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildLabeledInput(
                                label: '邀请码（选填）',
                                controller: _inviteCtrl,
                                hint: '可留空',
                              ),
                            ),
                          ],
                        ],
                      );
              },
            ),
            if (_infoText != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Taste.pillPosBg,
                  borderRadius: BorderRadius.circular(Taste.radiusControl),
                ),
                child: Text(
                  _infoText!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Taste.pillPosInk,
                  ),
                ),
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Taste.pillNegBg,
                  borderRadius: BorderRadius.circular(Taste.radiusControl),
                ),
                child: Text(
                  _errorText!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Taste.pillNegInk,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (widget.isDialog)
              Taste.buildDialogFooter(
                padding: const EdgeInsets.only(top: 12),
                children: [
                  Taste.dialogCancelButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
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
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(Taste.radiusControl),
                      ),
                    ),
                    onPressed: _busy
                        ? null
                        : (_mode == 3
                            ? _handleMiniLogin
                            : (_mode == 4
                                ? _handleMiniRegister
                                : _handleSubmit)),
                    child: Text(
                      _busy
                          ? '正在与好分数服务器通信…'
                          : (_mode == 0
                              ? (isReauth ? '更新凭据并重连' : '直连登录并挂载账号')
                              : (_mode == 1
                                  ? '立即注册并挂载账号'
                                  : (_mode == 2
                                      ? '重置密码并登录'
                                      : (_mode == 3 ? '微信免密登录并挂载' : '微信注册')))),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: Taste.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                height: 40,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Taste.primary,
                    foregroundColor: Taste.primaryInk,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Taste.radiusControl),
                    ),
                  ),
                  onPressed: _busy
                      ? null
                      : (_mode == 3
                          ? _handleMiniLogin
                          : (_mode == 4 ? _handleMiniRegister : _handleSubmit)),
                  child: Text(
                    _busy
                        ? '正在与好分数服务器通信…'
                        : (_mode == 0
                            ? (isReauth ? '更新凭据并重连' : '直连登录并挂载账号')
                            : (_mode == 1
                                ? '立即注册并挂载账号'
                                : (_mode == 2
                                    ? '重置密码并登录'
                                    : (_mode == 3 ? '微信免密登录并挂载' : '微信注册')))),
                    style: const TextStyle(
                      fontFamily: Taste.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTab(int index, String title) {
    final active = _mode == index;
    return SizedBox(
      width: 92,
      child: InkWell(
        onTap: _busy
            ? null
            : () => setState(() {
                  _mode = index;
                  _errorText = null;
                  _infoText = null;
                }),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Taste.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: active ? Border.all(color: Taste.border) : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              maxLines: 1,
              style: TextStyle(
                fontFamily: Taste.fontFamily,
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? Taste.text : Taste.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabeledInput({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: Taste.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Taste.muted,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 38,
          child: TextField(
            controller: controller,
            obscureText: obscure,
            onSubmitted: onSubmitted,
            style: const TextStyle(
              fontFamily: Taste.fontFamily,
              fontSize: 13,
              color: Taste.text,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Taste.faint, fontSize: 12),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              filled: true,
              fillColor: Taste.surface,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Taste.radiusControl),
                borderSide: const BorderSide(color: Taste.control),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Taste.radiusControl),
                borderSide: const BorderSide(color: Taste.accent, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Multi-Channel Student Binding & Rebinding Dialog
/// Supports Account Picker + Quota/Slot Inspector + Add (`PUT`/`POST`) or Rebind (`PATCH /v2/native-users/bind-student`) + 4 Channels
