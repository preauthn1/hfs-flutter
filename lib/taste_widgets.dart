import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'answer_sheet_painter.dart';
import 'hfs_client.dart';
import 'hfs_models.dart';

/// Taste-Skill 2.5 Design System Tokens (Warm Neutral Surface + Single Teal Accent)
class Taste {
  static const String fontFamily = 'NotoSansSC';

  // Neutral Surfaces & Borders (95% neutral interface)
  static const Color ground = Color(0xFFF5F7F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color raised = Color(0xFFF4F6F8);
  static const Color active = Color(0xFFEBEDEE);
  static const Color border = Color(0xFFE8EAEC);
  static const Color rule = Color(0xFFF0F1F2);
  static const Color control = Color(0xFFCDCED1);

  // Ink & Typography
  static const Color text = Color(0xFF131416);
  static const Color muted = Color(0xFF5D5F60);
  static const Color faint = Color(0xFF6B6E70);

  // Single Brand Accent & Semantic Colors (Never violet/purple)
  static const Color accent = Color(0xFF1B6C80);
  static const Color primary = Color(0xFF131416);
  static const Color primaryInk = Color(0xFFFFFFFF);
  static const Color positive = Color(0xFF1E7B4F);
  static const Color negative = Color(0xFFC4242A);
  static const Color warning = Color(0xFF92400E);
  static const Color chart1 = Color(0xFF1B6C80);
  static const Color chart2 = Color(0xFF2F70BB);
  static const Color chart3 = Color(0xFFA86F0C);

  // Semantic Pale Pills
  static const Color pillPosBg = Color(0xFFDCFAE5);
  static const Color pillPosInk = Color(0xFF04250E);
  static const Color pillNegBg = Color(0xFFFFEDEA);
  static const Color pillNegInk = Color(0xFF831C1E);
  static const Color pillWarnBg = Color(0xFFFFFBEB);
  static const Color pillWarnInk = Color(0xFF92400E);
  static const Color pillNeutralBg = Color(0xFFEBEDEE);
  static const Color pillNeutralInk = Color(0xFF353736);
  static const Color pillBlueBg = Color(0xFFE0F2FE);
  static const Color pillBlueInk = Color(0xFF0C4A6E);

  // Radii & Spacing
  static const double radiusCard = 8.0;
  static const double radiusControl = 6.0;
  static const double radiusSheet = 16.0;

  static const List<FontFeature> tabularNums = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static TextStyle numStyle({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = text,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      fontFeatures: tabularNums,
    );
  }
}

enum TastePillTone { neutral, positive, negative, warning, blue }

class TastePill extends StatelessWidget {
  final String label;
  final TastePillTone tone;

  const TastePill({
    super.key,
    required this.label,
    this.tone = TastePillTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    switch (tone) {
      case TastePillTone.positive:
        bg = Taste.pillPosBg;
        fg = Taste.pillPosInk;
        break;
      case TastePillTone.negative:
        bg = Taste.pillNegBg;
        fg = Taste.pillNegInk;
        break;
      case TastePillTone.warning:
        bg = Taste.pillWarnBg;
        fg = Taste.pillWarnInk;
        break;
      case TastePillTone.blue:
        bg = Taste.pillBlueBg;
        fg = Taste.pillBlueInk;
        break;
      case TastePillTone.neutral:
        bg = Taste.pillNeutralBg;
        fg = Taste.pillNeutralInk;
        break;
    }
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: Taste.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: fg,
          fontFeatures: Taste.tabularNums,
        ),
      ),
    );
  }
}

/// Unified Auth / Register / Forgot-Password Panel (works standalone or inside a dialog)
class HfsAuthPanel extends StatefulWidget {
  final HfsUpstreamClient client;
  final HfsAccount? reauthAccount;
  final bool isDialog;
  final Future<void> Function(HfsAccount account) onAuthenticated;

  const HfsAuthPanel({
    super.key,
    required this.client,
    required this.onAuthenticated,
    this.reauthAccount,
    this.isDialog = false,
  });

  @override
  State<HfsAuthPanel> createState() => _HfsAuthPanelState();
}

class _HfsAuthPanelState extends State<HfsAuthPanel> {
  // 0 = 登录已有账号, 1 = 注册新好分数账号, 2 = 短信找回密码
  int _mode = 0;
  int _roleType = 2; // 2 = 家长端, 1 = 学生端

  late final TextEditingController _phoneCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _labelCtrl;
  final TextEditingController _smsCodeCtrl = TextEditingController();
  final TextEditingController _captchaCtrl = TextEditingController();
  final TextEditingController _inviteCtrl = TextEditingController();

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
                          : (_mode == 1 ? '注册好分数新账号' : '短信找回好分数密码')),
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
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(),
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
              child: Row(
                children: [
                  _buildModeTab(0, '登录已有账号'),
                  _buildModeTab(1, '注册新账号'),
                  _buildModeTab(2, '找回密码'),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
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
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('家长版 (可绑多人)', style: TextStyle(fontSize: 12)),
                selected: _roleType == 2,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _roleType = 2),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('学生版', style: TextStyle(fontSize: 12)),
                selected: _roleType == 1,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _roleType = 1),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildLabeledInput(
            label: _mode == 0 ? '手机号 / 好分数账号 / 学号' : '11 位手机号码',
            controller: _phoneCtrl,
            hint: _mode == 0 ? '输入手机号或学生端账号' : '请输入未注册的 11 位手机号',
          ),
          if (_mode == 1 || _mode == 2) ...[
            if (_captchaSvg != null) ...[
              const SizedBox(height: 10),
              Row(
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
              ),
            ],
            const SizedBox(height: 10),
            Row(
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
                    onPressed: (_sendingSms || _smsCountdown > 0 || _busy)
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
            ),
          ],
          const SizedBox(height: 10),
          _buildLabeledInput(
            label: _mode == 0
                ? '登录密码'
                : '设置密码（8~20位，建议含字母+数字+符号）',
            controller: _passCtrl,
            hint: _mode == 0 ? '输入好分数密码' : '如：Abc12345!',
            obscure: true,
            onSubmitted: (_) => _handleSubmit(),
          ),
          const SizedBox(height: 10),
          Row(
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
              onPressed: _busy ? null : _handleSubmit,
              child: Text(
                _busy
                    ? '正在与好分数服务器通信…'
                    : (_mode == 0
                        ? (isReauth ? '更新凭据并重连' : '直连登录并挂载账号')
                        : (_mode == 1 ? '立即注册并挂载账号' : '重置密码并登录')),
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
    return Expanded(
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
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Taste.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: active ? Border.all(color: Taste.border) : null,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: Taste.fontFamily,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? Taste.text : Taste.muted,
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

/// Multi-Channel Student Binding Dialog (Supports Account Picker + 4 Binding Channels)
class BindStudentAdvancedDialog extends StatefulWidget {
  final HfsUpstreamClient client;
  final List<HfsAccount> accounts;
  final HfsAccount initialAccount;
  final Future<void> Function(HfsAccount targetAccount, DashboardData dash)
      onBound;

  const BindStudentAdvancedDialog({
    super.key,
    required this.client,
    required this.accounts,
    required this.initialAccount,
    required this.onBound,
  });

  @override
  State<BindStudentAdvancedDialog> createState() =>
      _BindStudentAdvancedDialogState();
}

class _BindStudentAdvancedDialogState extends State<BindStudentAdvancedDialog> {
  late HfsAccount _targetAccount;
  // 0 = 姓名+学号/考号, 1 = 按学校+年级+姓名查询绑定, 2 = 按学生端账号密码绑定, 3 = 按内部 studentId 直绑
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
  List<RegionSchoolItem> _schools = const [];
  List<SchoolMatchedStudent> _matchedStudents = const [];
  bool _loadingRegions = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _targetAccount = widget.initialAccount;
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
          _schoolIdCtrl.text = list.first.id;
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

  Future<void> _submitBind({String? directStudentId}) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      late DashboardData dash;
      if (directStudentId != null && directStudentId.isNotEmpty) {
        dash = await widget.client.bindStudentById(
          account: _targetAccount,
          studentId: directStudentId,
        );
      } else if (_channel == 0) {
        if (_nameCtrl.text.trim().isEmpty || _codeCtrl.text.trim().isEmpty) {
          throw Exception('请填写学生姓名与学号/准考证号');
        }
        dash = await widget.client.bindStudent(
          account: _targetAccount,
          studentName: _nameCtrl.text.trim(),
          identityCode: _codeCtrl.text.trim(),
          schoolAuthCode: _authCtrl.text.trim(),
        );
      } else if (_channel == 2) {
        if (_stuAccCtrl.text.trim().isEmpty || _stuPwdCtrl.text.isEmpty) {
          throw Exception('请填写好分数学生端账号与密码');
        }
        dash = await widget.client.bindStudentByAccount(
          account: _targetAccount,
          studentAccount: _stuAccCtrl.text.trim(),
          studentPassword: _stuPwdCtrl.text,
        );
      } else if (_channel == 3) {
        if (_stuIdCtrl.text.trim().isEmpty) {
          throw Exception('请填写内部 studentId');
        }
        dash = await widget.client.bindStudentById(
          account: _targetAccount,
          studentId: _stuIdCtrl.text.trim(),
        );
      } else {
        throw Exception('请先点击“查询同名学生”，然后点击对应学生的“立即绑定”');
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

    return Dialog(
      backgroundColor: Taste.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Taste.radiusCard),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '多通道绑定学生（零换绑安全模式）',
                      style: TextStyle(
                        fontFamily: Taste.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Taste.text,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Account selector
              Row(
                children: [
                  const Text(
                    '挂载到账号：',
                    style: TextStyle(fontSize: 12, color: Taste.muted),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _targetAccount.id,
                      isDense: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
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
                              '${a.displayLabel} (${a.roleType == 1 ? "学生端" : "家长端"} · 已绑${a.students.length}人)',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (val) {
                              if (val == null) return;
                              final found = widget.accounts
                                  .firstWhere((a) => a.id == val);
                              setState(() => _targetAccount = found);
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildChannelChip(0, '姓名 + 学号/考号'),
                  _buildChannelChip(1, '学校 + 年级 + 姓名'),
                  _buildChannelChip(2, '学生端账号密码'),
                  _buildChannelChip(3, '内部 studentId 直绑'),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_channel == 0) ...[
                        _inputField('学生姓名', _nameCtrl, '请输入学生真实姓名'),
                        const SizedBox(height: 10),
                        _inputField('学号 / 准考证号 / 考号', _codeCtrl, '请输入学号或考号'),
                        const SizedBox(height: 10),
                        _inputField('学校授权码（选填）', _authCtrl, '无授权码请留空'),
                      ] else if (_channel == 1) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _inputField(
                                  '学校 ID (如已知可直接填)', _schoolIdCtrl, '如 103797'),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 110,
                              child: _inputField('年级', _gradeCtrl, '如 初三 / 高一'),
                            ),
                          ],
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
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              DropdownButton<String>(
                                hint: const Text('省份',
                                    style: TextStyle(fontSize: 12)),
                                value: _selectedProvince,
                                items: [
                                  for (final p in _provinces)
                                    DropdownMenuItem(
                                      value: p.name,
                                      child: Text(p.name,
                                          style: const TextStyle(fontSize: 12)),
                                    ),
                                ],
                                onChanged: (v) => setState(() {
                                  _selectedProvince = v;
                                  _selectedCity = null;
                                  _selectedCounty = null;
                                  _schools = const [];
                                }),
                              ),
                              if (curProv != null)
                                DropdownButton<String>(
                                  hint: const Text('城市',
                                      style: TextStyle(fontSize: 12)),
                                  value: _selectedCity,
                                  items: [
                                    for (final c in curProv.cities)
                                      DropdownMenuItem(
                                        value: c.name,
                                        child: Text(c.name,
                                            style:
                                                const TextStyle(fontSize: 12)),
                                      ),
                                  ],
                                  onChanged: (v) => setState(() {
                                    _selectedCity = v;
                                    _selectedCounty = null;
                                    _schools = const [];
                                  }),
                                ),
                              if (curCity != null)
                                DropdownButton<String>(
                                  hint: const Text('区县',
                                      style: TextStyle(fontSize: 12)),
                                  value: _selectedCounty,
                                  items: [
                                    for (final co in curCity.counties)
                                      DropdownMenuItem(
                                        value: co,
                                        child: Text(co,
                                            style:
                                                const TextStyle(fontSize: 12)),
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
                          ),
                          if (_schools.isNotEmpty)
                            DropdownButtonFormField<String>(
                              initialValue: _schools.first.id,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: '选择学校',
                                isDense: true,
                              ),
                              items: [
                                for (final s in _schools)
                                  DropdownMenuItem(
                                    value: s.id,
                                    child: Text('${s.name} (ID: ${s.id})',
                                        style: const TextStyle(fontSize: 12)),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v != null) _schoolIdCtrl.text = v;
                              },
                            ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: _inputField(
                                  '学生姓名', _nameCtrl, '输入姓名查询脱敏学号与 ID'),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 36,
                              child: OutlinedButton(
                                onPressed:
                                    _submitting ? null : _querySchoolStudents,
                                child: const Text('查询学生',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          ],
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
                                            directStudentId: ms.id),
                                    child: const Text('立即绑定',
                                        style: TextStyle(fontSize: 12)),
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
                        _inputField('内部 studentId', _stuIdCtrl,
                            '如从同班名册中获取的 24 位数字 ID'),
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
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  if (_channel != 1)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Taste.primary,
                        foregroundColor: Taste.primaryInk,
                      ),
                      onPressed: _submitting ? null : () => _submitBind(),
                      child: Text(_submitting ? '正在绑定…' : '确认绑定学生'),
                    ),
                ],
              ),
            ],
          ),
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
          : (_) => setState(() {
                _channel = idx;
                _error = null;
              }),
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
class WrongNotebookPanel extends StatefulWidget {
  final HfsUpstreamClient client;
  final HfsAccount account;
  final DashboardData dashboard;
  final void Function(String examId, String paperId, String subject)
      onOpenPaperByIds;

  const WrongNotebookPanel({
    super.key,
    required this.client,
    required this.account,
    required this.dashboard,
    required this.onOpenPaperByIds,
  });

  @override
  State<WrongNotebookPanel> createState() => _WrongNotebookPanelState();
}

class _WrongNotebookPanelState extends State<WrongNotebookPanel> {
  String _selectedSubject = '';
  int _filterMode = 0; // 0 = 按考试场次, 1 = 按学期筛选
  String _selectedExamId = '';
  int _selectedSemesterIndex = 0;
  List<WrongQuestionItem> _items = const [];
  bool _loadingItems = false;
  String? _error;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _initSelection();
  }

  @override
  void didUpdateWidget(covariant WrongNotebookPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dashboard != widget.dashboard) {
      _initSelection();
    }
  }

  void _initSelection() {
    final list = widget.dashboard.wrongOverview;
    if (list.isEmpty) return;
    if (!list.any((s) => s.subject == _selectedSubject)) {
      _selectedSubject = list.first.subject;
    }
    final curSubj = list.firstWhere(
      (s) => s.subject == _selectedSubject,
      orElse: () => list.first,
    );
    if (curSubj.exams.isNotEmpty &&
        !curSubj.exams.any((e) => e.examId == _selectedExamId)) {
      _selectedExamId = curSubj.exams.first.examId;
    }
    if (_selectedSemesterIndex >= curSubj.semesters.length) {
      _selectedSemesterIndex = 0;
    }
    _loadWrongItems();
  }

  Future<void> _loadWrongItems({bool allowCache = true}) async {
    final list = widget.dashboard.wrongOverview;
    if (list.isEmpty || _selectedSubject.isEmpty) {
      return;
    }
    final curSubj = list.firstWhere(
      (s) => s.subject == _selectedSubject,
      orElse: () => list.first,
    );
    final reqToken = ++_requestToken;
    final reqSubject = _selectedSubject;
    final reqMode = _filterMode;
    final reqExamId = _selectedExamId;
    final reqSemIdx = _selectedSemesterIndex;
    final stuId = widget.dashboard.currentStudent?.studentId ??
        widget.account.activeStudentId;

    setState(() {
      _loadingItems = true;
      _error = null;
    });

    try {
      List<WrongQuestionItem> res = const [];
      if (reqMode == 1 && curSubj.semesters.isNotEmpty) {
        final sem = curSubj
            .semesters[reqSemIdx.clamp(0, curSubj.semesters.length - 1)];
        if (sem.startMs > 0 && sem.endMs > 0) {
          res = await widget.client.fetchWrongSemesterItems(
            account: widget.account,
            studentId: stuId,
            subject: reqSubject,
            startMs: sem.startMs,
            endMs: sem.endMs,
            allowCache: allowCache,
          );
        } else {
          // Fallback: aggregate exams belonging to this subject
          final matchingExams = curSubj.exams.take(3);
          final agg = <WrongQuestionItem>[];
          for (final ex in matchingExams) {
            final subRes = await widget.client.fetchWrongExamItems(
              account: widget.account,
              studentId: stuId,
              subject: reqSubject,
              examId: ex.examId,
              allowCache: allowCache,
            );
            agg.addAll(subRes);
          }
          res = agg;
        }
      } else if (reqExamId.isNotEmpty) {
        res = await widget.client.fetchWrongExamItems(
          account: widget.account,
          studentId: stuId,
          subject: reqSubject,
          examId: reqExamId,
          allowCache: allowCache,
        );
      }

      if (!mounted ||
          reqToken != _requestToken ||
          _selectedSubject != reqSubject ||
          _filterMode != reqMode ||
          (reqMode == 0 && _selectedExamId != reqExamId) ||
          (reqMode == 1 && _selectedSemesterIndex != reqSemIdx)) {
        return;
      }
      setState(() {
        _items = res;
        _loadingItems = false;
      });
    } catch (e) {
      if (!mounted || reqToken != _requestToken) return;
      setState(() {
        _loadingItems = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dash = widget.dashboard;
    final overviews = dash.wrongOverview;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Subject & Exam Selector Panel
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
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Text(
                      '错题本深度复盘 · 待复习总计 ${dash.totalWrong} 题',
                      style: const TextStyle(
                        fontFamily: Taste.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Taste.text,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TastePill(
                          label:
                              '已解锁 ${dash.unlockedSubjects}/${dash.totalSubjects} 科',
                          tone: TastePillTone.positive,
                        ),
                        OutlinedButton.icon(
                          onPressed: _loadingItems
                              ? null
                              : () => _loadWrongItems(allowCache: false),
                          icon: const Icon(Icons.refresh, size: 14),
                          label: const Text('刷新错题',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Taste.border),
              if (overviews.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            'assets/images/empty_wrong_book.png',
                            width: 136,
                            height: 136,
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, st) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '当前学生暂无错题本记录',
                          style: TextStyle(color: Taste.muted),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '选择科目：',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Taste.muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in overviews)
                            ChoiceChip(
                              selected: s.subject == _selectedSubject,
                              label: Text(
                                '${s.subject} (${s.noReview}题 · ${s.examCount}场)',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onSelected: (_) {
                                setState(() {
                                  _selectedSubject = s.subject;
                                  if (s.exams.isNotEmpty) {
                                    _selectedExamId = s.exams.first.examId;
                                  }
                                });
                                _loadWrongItems();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            '筛选维度：',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Taste.muted,
                            ),
                          ),
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            selected: _filterMode == 0,
                            label: const Text('按考试场次',
                                style: TextStyle(fontSize: 12)),
                            onSelected: (_) {
                              setState(() => _filterMode = 0);
                              _loadWrongItems();
                            },
                          ),
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            selected: _filterMode == 1,
                            label: const Text('按学期汇总',
                                style: TextStyle(fontSize: 12)),
                            onSelected: (_) {
                              setState(() => _filterMode = 1);
                              _loadWrongItems();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (ctx) {
                          final curSubj = overviews.firstWhere(
                            (s) => s.subject == _selectedSubject,
                            orElse: () => overviews.first,
                          );
                          if (_filterMode == 1) {
                            if (curSubj.semesters.isEmpty) {
                              return const Text(
                                '该科目暂无学期汇总段',
                                style:
                                    TextStyle(fontSize: 12, color: Taste.muted),
                              );
                            }
                            return IsolatedHorizontalScroll(
                              child: Row(
                                children: [
                                  for (var sIdx = 0;
                                      sIdx < curSubj.semesters.length;
                                      sIdx++)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        selected:
                                            sIdx == _selectedSemesterIndex,
                                        label: Text(
                                          '${curSubj.semesters[sIdx].name} (错${curSubj.semesters[sIdx].wrongNum}题)',
                                          style:
                                              const TextStyle(fontSize: 12),
                                        ),
                                        onSelected: (_) {
                                          setState(() =>
                                              _selectedSemesterIndex = sIdx);
                                          _loadWrongItems();
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }
                          return IsolatedHorizontalScroll(
                            child: Row(
                              children: [
                                for (final ex in curSubj.exams)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      selected: ex.examId == _selectedExamId,
                                      label: Text(
                                        '${ex.examName} (错${ex.wrongNum}题)',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      onSelected: (_) {
                                        setState(
                                            () => _selectedExamId = ex.examId);
                                        _loadWrongItems();
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Wrong Question Cards Stream
        if (_loadingItems)
          Container(
            padding: const EdgeInsets.all(36),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Taste.surface,
              borderRadius: BorderRadius.circular(Taste.radiusCard),
              border: Border.all(color: Taste.border),
            ),
            child: const Column(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Taste.accent,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '正在拉取该场考试的错题原卷题干与作答图片…',
                  style: TextStyle(fontSize: 13, color: Taste.muted),
                ),
              ],
            ),
          )
        else if (_error != null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Taste.pillNegBg,
              borderRadius: BorderRadius.circular(Taste.radiusCard),
            ),
            child: Text(
              _error!,
              style: const TextStyle(color: Taste.pillNegInk),
            ),
          )
        else if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Taste.surface,
              borderRadius: BorderRadius.circular(Taste.radiusCard),
              border: Border.all(color: Taste.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/empty_wrong_book.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '本场考试该科目暂无错题明细',
                  style: TextStyle(color: Taste.muted),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < _items.length; i++)
            _buildWrongQuestionCard(i + 1, _items[i]),

        const SizedBox(height: 16),
        // 3. Account & Upstream Diagnostics Details
        _buildAccountDiagnosticsPanel(dash),
      ],
    );
  }

  Widget _buildWrongQuestionCard(int idx, WrongQuestionItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Taste.surface,
        borderRadius: BorderRadius.circular(Taste.radiusCard),
        border: Border.all(color: Taste.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    TastePill(
                      label: '#$idx · 第 ${item.shortName} 题',
                      tone: TastePillTone.negative,
                    ),
                    const SizedBox(width: 8),
                    TastePill(
                      label: item.style,
                      tone: TastePillTone.neutral,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.examName,
                      style: const TextStyle(fontSize: 12, color: Taste.muted),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '得分 ${round1(item.myScore)} / ${round1(item.score)}分',
                      style: Taste.numStyle(
                        size: 13,
                        weight: FontWeight.w700,
                        color: Taste.negative,
                      ),
                    ),
                    if (item.classAvgScore > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '(班均 ${round2(item.classAvgScore)}分)',
                        style: Taste.numStyle(size: 12, color: Taste.muted),
                      ),
                    ],
                    if (item.paperId.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => widget.onOpenPaperByIds(
                          item.examId,
                          item.paperId,
                          _selectedSubject,
                        ),
                        icon: const Icon(Icons.description_outlined, size: 14),
                        label: const Text('调阅整卷答题卡',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.knowledges.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      const Text(
                        '考查知识点：',
                        style: TextStyle(fontSize: 12, color: Taste.muted),
                      ),
                      for (final k in item.knowledges)
                        TastePill(label: k, tone: TastePillTone.blue),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (item.myAnswer.isNotEmpty || item.answer.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Taste.raised,
                      borderRadius: BorderRadius.circular(Taste.radiusControl),
                    ),
                    child: Wrap(
                      spacing: 20,
                      runSpacing: 6,
                      children: [
                        Text(
                          '我的作答：${item.myAnswer.isEmpty ? "未填/见下图" : item.myAnswer}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Taste.negative,
                          ),
                        ),
                        if (item.answer.isNotEmpty)
                          Text(
                            '标准答案：${item.answer}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Taste.positive,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (item.stemPictures.isNotEmpty) ...[
                  const Text(
                    '原卷题干扫描（点击图片可全屏无损放大）：',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Taste.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final u in item.stemPictures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OssCropImage(
                        client: widget.client,
                        imageUrl: u,
                        maxHeight: 220,
                        caption:
                            '${item.examName} · $_selectedSubject 第${item.shortName}题 原卷题干',
                      ),
                    ),
                ],
                if (item.myAnswerPictures.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '我的答题卡作答裁切：',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Taste.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final u in item.myAnswerPictures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OssCropImage(
                        client: widget.client,
                        imageUrl: u,
                        maxHeight: 180,
                        caption:
                            '${item.examName} · $_selectedSubject 第${item.shortName}题 我的作答',
                      ),
                    ),
                ],
                if (item.xbAnswerPictures.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '优秀作答 / 参考解析示例：',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Taste.accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final u in item.xbAnswerPictures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OssCropImage(
                        client: widget.client,
                        imageUrl: u,
                        maxHeight: 180,
                        caption:
                            '${item.examName} · $_selectedSubject 第${item.shortName}题 优秀解答',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountDiagnosticsPanel(DashboardData dash) {
    return Container(
      decoration: BoxDecoration(
        color: Taste.surface,
        borderRadius: BorderRadius.circular(Taste.radiusCard),
        border: Border.all(color: Taste.border),
      ),
      child: ExpansionTile(
        title: const Text(
          '好分数账号权益与学校门禁配置明细',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Taste.text,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              TastePill(
                label: '会员状态: ${dash.isMember ? "VIP会员" : "普通账号"}',
                tone: dash.isMember
                    ? TastePillTone.positive
                    : TastePillTone.neutral,
              ),
              TastePill(
                label: '单次考试会员: ${dash.isExamMember ? "是" : "否"}',
                tone: TastePillTone.neutral,
              ),
              TastePill(
                label: '错题解锁科目: ${dash.unlockedSubjects}/${dash.totalSubjects}',
                tone: TastePillTone.blue,
              ),
              TastePill(
                label: '剩余拍照上传额度: ${dash.uploadRemain}',
                tone: TastePillTone.neutral,
              ),
              TastePill(
                label: '剩余错题导出额度: ${dash.exportRemain}',
                tone: TastePillTone.neutral,
              ),
            ],
          ),
          if (dash.rawSchoolHidden.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Taste.raised,
                borderRadius: BorderRadius.circular(Taste.radiusControl),
              ),
              child: Text(
                '学校隐藏策略配置 (/v2/config/school/hidden-config)：\n${const JsonEncoder.withIndent("  ").convert(dash.rawSchoolHidden)}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Taste.muted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Classmates Roster Dialog (`GET /v2/students/classmates`)
class ClassmatesRosterDialog extends StatefulWidget {
  final HfsUpstreamClient client;
  final HfsAccount account;
  final StudentInfo? currentStudent;

  const ClassmatesRosterDialog({
    super.key,
    required this.client,
    required this.account,
    this.currentStudent,
  });

  @override
  State<ClassmatesRosterDialog> createState() => _ClassmatesRosterDialogState();
}

class _ClassmatesRosterDialogState extends State<ClassmatesRosterDialog> {
  List<ClassmateBindEntry> _roster = const [];
  String _search = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.client.fetchClassmates(
        widget.account,
        studentId: widget.currentStudent?.studentId ?? '',
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

  @override
  Widget build(BuildContext context) {
    final filtered = _roster.where((c) {
      if (_search.trim().isEmpty) return true;
      final q = _search.trim();
      return c.name.contains(q) || c.id.contains(q);
    }).toList();
    final stuBoundCnt = _roster.where((c) => c.hasStudentAccount).length;
    final parBoundCnt = _roster.where((c) => c.hasParentAccount).length;

    return Dialog(
      backgroundColor: Taste.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Taste.radiusCard),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '同班同学名册 (${widget.currentStudent?.className ?? "当前班级"} · 共 ${_roster.length} 人)',
                      style: const TextStyle(
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
              const SizedBox(height: 8),
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
                    label:
                        '未绑家长端: ${_roster.length - parBoundCnt} 人',
                    tone: TastePillTone.warning,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '搜索同学姓名或内部 studentId…',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Taste.radiusControl),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : (_error != null)
                        ? Center(
                            child: Text(_error!,
                                style:
                                    const TextStyle(color: Taste.negative)),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (ctx, idx) =>
                                const Divider(height: 1, color: Taste.rule),
                            itemBuilder: (ctx, i) {
                              final c = filtered[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 4),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 32,
                                      child: Text(
                                        '${i + 1}',
                                        style: Taste.numStyle(
                                            size: 12, color: Taste.muted),
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                c.name,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              if (c.isMember) ...[
                                                const SizedBox(width: 6),
                                                const TastePill(
                                                  label: 'VIP',
                                                  tone: TastePillTone.warning,
                                                ),
                                              ],
                                            ],
                                          ),
                                          SelectableText(
                                            'studentId: ${c.id}',
                                            style: Taste.numStyle(
                                                size: 11, color: Taste.muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TastePill(
                                      label: c.hasStudentAccount
                                          ? '已绑学生端'
                                          : '无学生号',
                                      tone: c.hasStudentAccount
                                          ? TastePillTone.blue
                                          : TastePillTone.neutral,
                                    ),
                                    const SizedBox(width: 6),
                                    TastePill(
                                      label: c.hasParentAccount
                                          ? '已绑家长端'
                                          : '无家长号',
                                      tone: c.hasParentAccount
                                          ? TastePillTone.positive
                                          : TastePillTone.warning,
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
    );
  }
}

/// Settings & Upstream Diagnostics Dialog
class AppSettingsDialog extends StatefulWidget {
  final AppSettings settings;
  final HfsUpstreamClient client;
  final HfsAccount? activeAccount;
  final ValueChanged<AppSettings> onSaveSettings;
  final Future<void> Function() onClearCache;
  final Future<String> Function() onExportConfigJson;
  final Future<void> Function(String rawJson) onImportConfigJson;

  const AppSettingsDialog({
    super.key,
    required this.settings,
    required this.client,
    required this.activeAccount,
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
    (
      path: '/v3/exam/list?start=0',
      label: '考试列表 (/v3/exam/list?start=0)'
    ),
  ];

  @override
  void initState() {
    super.initState();
    _draft = widget.settings;
  }

  Future<void> _runDiagnostic() async {
    final acc = widget.activeAccount;
    if (acc == null) return;
    setState(() {
      _runningDiag = true;
      _diagOutput = null;
    });
    try {
      final res = await widget.client.fetchDiagnosticEndpoint(
        acc,
        _selectedDiagEndpoint,
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
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final defaultFileName = 'hfs_credentials_$ts.json';

    if (customPath != null && customPath.trim().isNotEmpty) {
      final f = File(customPath.trim());
      await f.parent.create(recursive: true);
      await f.writeAsString(content);
      return f.path;
    }

    final candidates = <String>[];
    final env = Platform.environment;
    final userProfile = env['USERPROFILE'] ?? '';
    final home = env['HOME'] ?? '';
    if (userProfile.isNotEmpty) {
      candidates.add('$userProfile\\Downloads\\$defaultFileName');
      candidates.add('$userProfile\\Desktop\\$defaultFileName');
    }
    if (home.isNotEmpty) {
      candidates.add('$home/Downloads/$defaultFileName');
      candidates.add('$home/Desktop/$defaultFileName');
      candidates.add('$home/$defaultFileName');
    }
    if (Platform.isAndroid) {
      candidates.add('/sdcard/Download/$defaultFileName');
      candidates.add('/storage/emulated/0/Download/$defaultFileName');
    }
    candidates.add(
      '${Directory.current.path}${Platform.pathSeparator}$defaultFileName',
    );
    candidates.add(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$defaultFileName',
    );

    for (final p in candidates) {
      try {
        final f = File(p);
        if (await f.parent.exists()) {
          await f.writeAsString(content);
          return f.path;
        }
      } catch (_) {}
    }

    final fallback = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$defaultFileName',
    );
    await fallback.writeAsString(content);
    return fallback.path;
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
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: Taste.surface,
          title: const Text(
            '好分数凭证文件导出与导入 (.json)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 520,
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
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: TextField(
                            controller: filePathCtrl,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: '指定凭证文件完整路径（留空则自动存至 Downloads/桌面）',
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(Taste.radiusControl),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
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
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final p = filePathCtrl.text.trim();
                          if (p.isEmpty) {
                            setModalState(() {
                              modalFeedback = '请先在左侧输入框填写要读取的 .json 凭证文件路径';
                            });
                            return;
                          }
                          try {
                            final raw = await File(p).readAsString();
                            ctrl.text = raw;
                            setModalState(() {
                              modalFeedback = '已从文件读取凭证内容，点击下方「导入并覆盖保存」即可生效';
                            });
                          } catch (e) {
                            setModalState(() {
                              modalFeedback = '读取凭证文件失败：$e';
                            });
                          }
                        },
                        icon: const Icon(Icons.folder_open_outlined, size: 15),
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
                    maxLines: 11,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '粘贴备份的好分数凭证 JSON 以恢复多账号…',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
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
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Taste.primary,
                foregroundColor: Taste.primaryInk,
              ),
              onPressed: () async {
                await widget.onImportConfigJson(ctrl.text);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  setState(() => _statusMsg = '好分数凭证已成功导入并恢复');
                }
              },
              child: const Text('导入并覆盖保存'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Taste.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Taste.radiusCard),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '工作台设置与好分数上游只读诊断',
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
              const Divider(height: 16, color: Taste.border),
              Expanded(
                child: ListView(
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
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '单次拉取历史考试上限（场次越少首次同步越快）：',
                            style: TextStyle(fontSize: 12, color: Taste.muted),
                          ),
                        ),
                        DropdownButton<int>(
                          value: _draft.maxExamsToHydrate,
                          items: const [
                            DropdownMenuItem(value: 5, child: Text('最近 5 场')),
                            DropdownMenuItem(value: 10, child: Text('最近 10 场 (推荐)')),
                            DropdownMenuItem(value: 15, child: Text('最近 15 场')),
                            DropdownMenuItem(value: 25, child: Text('最近 25 场')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _draft =
                                  _draft.copyWith(maxExamsToHydrate: v));
                            }
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '考试详情并发请求数：',
                            style: TextStyle(fontSize: 12, color: Taste.muted),
                          ),
                        ),
                        DropdownButton<int>(
                          value: _draft.examConcurrency,
                          items: const [
                            DropdownMenuItem(value: 2, child: Text('2 并发')),
                            DropdownMenuItem(value: 4, child: Text('4 并发 (推荐)')),
                            DropdownMenuItem(value: 6, child: Text('6 并发')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() =>
                                  _draft = _draft.copyWith(examConcurrency: v));
                            }
                          },
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
                      onChanged: (v) => setState(() =>
                          _draft = _draft.copyWith(autoHydrateOnSwitch: v)),
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
                            setState(() =>
                                _statusMsg = '已清空全部内存与本地缓存快照');
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
                    if (widget.activeAccount != null) ...[
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
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedDiagEndpoint,
                              isExpanded: true,
                              isDense: true,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                              ),
                              items: [
                                for (final ep in _diagEndpoints)
                                  DropdownMenuItem(
                                    value: ep.path,
                                    child: Text(ep.label,
                                        style: const TextStyle(fontSize: 12)),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedDiagEndpoint = v);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _runningDiag ? null : _runDiagnostic,
                            child: Text(
                              _runningDiag ? '请求中…' : '直连探测',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
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
                  ],
                ),
              ),
              const Divider(height: 16, color: Taste.border),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Taste.primary,
                      foregroundColor: Taste.primaryInk,
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
      ),
    );
  }
}

class _ChartPoint {
  final ExamRecord exam;
  final double value;
  final String displayValue;
  final String subtitle;

  const _ChartPoint({
    required this.exam,
    required this.value,
    required this.displayValue,
    required this.subtitle,
  });
}

/// Interactive Score Trend Line Chart + Subject Radar Balance Panel
class ScoreTrendAnalyticsCard extends StatefulWidget {
  final DashboardData dashboard;
  final ExamRecord? selectedExam;
  final ValueChanged<ExamRecord> onSelectExam;

  const ScoreTrendAnalyticsCard({
    super.key,
    required this.dashboard,
    required this.selectedExam,
    required this.onSelectExam,
  });

  @override
  State<ScoreTrendAnalyticsCard> createState() =>
      _ScoreTrendAnalyticsCardState();
}

class _ScoreTrendAnalyticsCardState extends State<ScoreTrendAnalyticsCard> {
  String _metricSubject = '总分';
  bool _usePercentageRatio = false;
  int? _hoveredIndex;

  List<_ChartPoint> _buildPoints() {
    // Chronological order (oldest -> newest)
    final chronological = widget.dashboard.exams.reversed.toList();
    final pts = <_ChartPoint>[];
    for (final ex in chronological) {
      if (_metricSubject == '总分') {
        if (ex.score <= 0 && ex.papers.isEmpty) continue;
        final val = _usePercentageRatio
            ? (ex.ratio ??
                (ex.manfen > 0 ? round1((ex.score / ex.manfen) * 100) : 0))
            : ex.score;
        pts.add(
          _ChartPoint(
            exam: ex,
            value: val,
            displayValue: _usePercentageRatio ? '$val%' : ex.scoreS,
            subtitle: ex.manfen > 0
                ? '${ex.scoreS}/${round1(ex.manfen)} (${ex.ratio ?? 0}%)'
                : ex.scoreS,
          ),
        );
      } else {
        PaperScore? match;
        for (final p in ex.papers) {
          if (p.subject == _metricSubject) {
            match = p;
            break;
          }
        }
        if (match == null) continue;
        final val = _usePercentageRatio
            ? (match.ratio ??
                (match.manfen > 0
                    ? round1((match.score / match.manfen) * 100)
                    : 0))
            : match.score;
        pts.add(
          _ChartPoint(
            exam: ex,
            value: val,
            displayValue: _usePercentageRatio ? '$val%' : match.scoreS,
            subtitle: match.manfen > 0
                ? '${match.scoreS}/${round1(match.manfen)} (${match.ratio ?? 0}%)'
                : match.scoreS,
          ),
        );
      }
    }
    return pts;
  }

  @override
  Widget build(BuildContext context) {
    final subjects = <String>['总分', ...widget.dashboard.discoveredSubjects];
    if (!subjects.contains(_metricSubject)) {
      _metricSubject = '总分';
    }
    final points = _buildPoints();
    final curExam = widget.selectedExam ??
        (widget.dashboard.exams.isNotEmpty
            ? widget.dashboard.exams.first
            : null);

    double maxVal = 0;
    double minVal = 0;
    double avgVal = 0;
    if (points.isNotEmpty) {
      maxVal = points.map((p) => p.value).reduce(math.max);
      minVal = points.map((p) => p.value).reduce(math.min);
      avgVal = round1(
        points.fold<double>(0, (s, p) => s + p.value) / points.length,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Taste.surface,
        borderRadius: BorderRadius.circular(Taste.radiusCard),
        border: Border.all(color: Taste.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header & Subject Metric Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.show_chart, size: 18, color: Taste.accent),
                    const SizedBox(width: 8),
                    Text(
                      '$_metricSubject 历次成绩变化趋势折线图与学科均衡度',
                      style: const TextStyle(
                        fontFamily: Taste.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Taste.text,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (points.isNotEmpty) ...[
                      TastePill(
                        label:
                            '最高 ${round1(maxVal)}${_usePercentageRatio ? "%" : ""}',
                        tone: TastePillTone.positive,
                      ),
                      TastePill(
                        label:
                            '均值 ${round1(avgVal)}${_usePercentageRatio ? "%" : ""}',
                        tone: TastePillTone.blue,
                      ),
                      TastePill(
                        label:
                            '最低 ${round1(minVal)}${_usePercentageRatio ? "%" : ""}',
                        tone: TastePillTone.warning,
                      ),
                    ],
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      selected: !_usePercentageRatio,
                      label:
                          const Text('原始分值', style: TextStyle(fontSize: 11)),
                      onSelected: (_) =>
                          setState(() => _usePercentageRatio = false),
                    ),
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      selected: _usePercentageRatio,
                      label: const Text('标准得分率 (%)',
                          style: TextStyle(fontSize: 11)),
                      onSelected: (_) =>
                          setState(() => _usePercentageRatio = true),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Taste.raised,
              border: Border(
                top: BorderSide(color: Taste.border),
                bottom: BorderSide(color: Taste.border),
              ),
            ),
            child: IsolatedHorizontalScroll(
              child: Row(
                children: [
                  const Text(
                    '趋势维度：',
                    style: TextStyle(fontSize: 12, color: Taste.muted),
                  ),
                  const SizedBox(width: 6),
                  for (final s in subjects)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        selected: _metricSubject == s,
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        onSelected: (_) => setState(() {
                          _metricSubject = s;
                          _hoveredIndex = null;
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (ctx, box) {
                final showRadarSideBySide =
                    box.maxWidth >= 820 &&
                    curExam != null &&
                    curExam.papers.length >= 3;
                final lineChartWidget = _buildInteractiveLineChart(
                  points,
                  avgVal,
                  curExam,
                );
                if (!showRadarSideBySide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      lineChartWidget,
                      if (curExam != null && curExam.papers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: Taste.rule),
                        const SizedBox(height: 12),
                        _buildSubjectBalanceBars(curExam),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: lineChartWidget),
                    const SizedBox(width: 16),
                    Container(
                      width: 1,
                      height: 220,
                      color: Taste.border,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: _buildSubjectBalanceBars(curExam),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveLineChart(
    List<_ChartPoint> points,
    double avgVal,
    ExamRecord? selectedExam,
  ) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text(
            '当前维度暂无足够考试数据绘制折线图',
            style: TextStyle(fontSize: 12, color: Taste.muted),
          ),
        ),
      );
    }

    final selectedIdx = points.indexWhere(
      (p) => p.exam.examId == selectedExam?.examId,
    );
    final activeIdx = _hoveredIndex ??
        (selectedIdx >= 0 ? selectedIdx : points.length - 1);
    final activePt = points[activeIdx.clamp(0, points.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Active point summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Taste.raised,
            borderRadius: BorderRadius.circular(Taste.radiusControl),
            border: Border.all(color: Taste.border),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Taste.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${formatDateMs(activePt.exam.time)} · ${activePt.exam.name}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Taste.text,
                    ),
                  ),
                ],
              ),
              Text(
                '$_metricSubject：${activePt.subtitle}（点击折线节点可切换考试与右侧答题卡）',
                style: Taste.numStyle(
                  size: 12,
                  weight: FontWeight.w500,
                  color: Taste.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 196,
          child: LayoutBuilder(
            builder: (ctx, box) {
              const leftPad = 44.0;
              const rightPad = 20.0;
              final plotW = math.max(10.0, box.maxWidth - leftPad - rightPad);

              int hitIndexForDx(double dx) {
                if (points.length <= 1) return 0;
                final rel = (dx - leftPad).clamp(0.0, plotW);
                final step = plotW / (points.length - 1);
                return (rel / step).round().clamp(0, points.length - 1);
              }

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onHover: (ev) {
                  final idx = hitIndexForDx(ev.localPosition.dx);
                  if (idx != _hoveredIndex) {
                    setState(() => _hoveredIndex = idx);
                  }
                },
                onExit: (_) => setState(() => _hoveredIndex = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final idx = hitIndexForDx(details.localPosition.dx);
                    setState(() => _hoveredIndex = idx);
                    widget.onSelectExam(points[idx].exam);
                  },
                  child: CustomPaint(
                    size: Size(box.maxWidth, 196),
                    painter: _ScoreLineChartPainter(
                      points: points,
                      avgValue: avgVal,
                      selectedExamId: selectedExam?.examId ?? '',
                      hoveredIndex: _hoveredIndex,
                      isPercentage: _usePercentageRatio,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectBalanceBars(ExamRecord exam) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${exam.name} · 各科得分率均衡度',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Taste.text,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '对比各学科得分率强弱项（≥85% 优秀 / 60-84% 良好 / <60% 待加强）',
          style: TextStyle(fontSize: 11, color: Taste.muted),
        ),
        const SizedBox(height: 10),
        for (final p in exam.papers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      p.subject,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Taste.text,
                      ),
                    ),
                    Text(
                      '${p.scoreS}/${round1(p.manfen)} (${p.ratio ?? 0}%)',
                      style: Taste.numStyle(
                        size: 11,
                        weight: FontWeight.w700,
                        color: Taste.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: Taste.raised,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: ((p.ratio ?? 0) / 100.0).clamp(0.0, 1.0),
                    child: Container(
                      color: (p.ratio ?? 0) >= 85
                          ? Taste.positive
                          : ((p.ratio ?? 0) >= 60
                              ? Taste.accent
                              : Taste.chart3),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ScoreLineChartPainter extends CustomPainter {
  final List<_ChartPoint> points;
  final double avgValue;
  final String selectedExamId;
  final int? hoveredIndex;
  final bool isPercentage;

  const _ScoreLineChartPainter({
    required this.points,
    required this.avgValue,
    required this.selectedExamId,
    required this.hoveredIndex,
    required this.isPercentage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPad = 44.0;
    const rightPad = 20.0;
    const topPad = 22.0;
    const bottomPad = 30.0;
    final plotW = math.max(10.0, size.width - leftPad - rightPad);
    final plotH = math.max(10.0, size.height - topPad - bottomPad);

    double minV = points.map((p) => p.value).reduce(math.min);
    double maxV = points.map((p) => p.value).reduce(math.max);
    if ((maxV - minV).abs() < 4.0) {
      minV = math.max(0.0, minV - 5.0);
      maxV = maxV + 5.0;
    } else {
      final pad = (maxV - minV) * 0.14;
      minV = math.max(0.0, minV - pad);
      maxV = isPercentage ? math.min(100.0, maxV + pad) : maxV + pad;
    }
    final span = math.max(1.0, maxV - minV);

    double xAt(int i) {
      if (points.length == 1) return leftPad + plotW / 2.0;
      return leftPad + (i / (points.length - 1)) * plotW;
    }

    double yAt(double v) {
      return topPad + plotH - ((v - minV) / span).clamp(0.0, 1.0) * plotH;
    }

    // 1. Horizontal grid lines & Y-axis labels
    final gridPaint = Paint()
      ..color = Taste.rule
      ..strokeWidth = 1.0;

    for (var g = 0; g <= 3; g++) {
      final ratio = g / 3.0;
      final gy = topPad + plotH * (1.0 - ratio);
      final gv = minV + span * ratio;
      canvas.drawLine(
        Offset(leftPad, gy),
        Offset(leftPad + plotW, gy),
        gridPaint,
      );
      _drawLabel(
        canvas,
        isPercentage ? '${gv.round()}%' : '${gv.round()}',
        Offset(2, gy - 7),
        color: Taste.faint,
        fontSize: 10,
        weight: FontWeight.w400,
      );
    }

    // 2. Dashed average reference line
    final avgY = yAt(avgValue);
    final avgPaint = Paint()
      ..color = Taste.chart2.withValues(alpha: 0.45)
      ..strokeWidth = 1.0;
    for (double dx = leftPad; dx < leftPad + plotW; dx += 8) {
      canvas.drawLine(
        Offset(dx, avgY),
        Offset(math.min(dx + 4, leftPad + plotW), avgY),
        avgPaint,
      );
    }

    // 3. Area fill & Smooth Line Path
    final linePath = Path();
    final fillPath = Path();
    for (var i = 0; i < points.length; i++) {
      final px = xAt(i);
      final py = yAt(points[i].value);
      if (i == 0) {
        linePath.moveTo(px, py);
        fillPath.moveTo(px, topPad + plotH);
        fillPath.lineTo(px, py);
      } else {
        final prevX = xAt(i - 1);
        final prevY = yAt(points[i - 1].value);
        final midX = (prevX + px) / 2.0;
        linePath.cubicTo(midX, prevY, midX, py, px, py);
        fillPath.cubicTo(midX, prevY, midX, py, px, py);
      }
      if (i == points.length - 1) {
        fillPath.lineTo(px, topPad + plotH);
        fillPath.close();
      }
    }

    if (points.length > 1) {
      final fillShader = ui.Gradient.linear(
        const Offset(0, topPad),
        Offset(0, topPad + plotH),
        <Color>[
          Taste.accent.withValues(alpha: 0.16),
          Taste.accent.withValues(alpha: 0.01),
        ],
      );
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = fillShader
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        linePath,
        Paint()
          ..color = Taste.accent
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // 4. Data nodes, value tags & X-axis dates
    final labelStep = math.max(1, (points.length / 7).ceil());
    for (var i = 0; i < points.length; i++) {
      final pt = points[i];
      final px = xAt(i);
      final py = yAt(pt.value);
      final isSel = pt.exam.examId == selectedExamId;
      final isHov = hoveredIndex == i;

      if (isSel || isHov) {
        canvas.drawLine(
          Offset(px, topPad),
          Offset(px, topPad + plotH),
          Paint()
            ..color = Taste.accent.withValues(alpha: 0.25)
            ..strokeWidth = 1.2,
        );
      }

      // Outer halo for active/selected point
      if (isSel || isHov) {
        canvas.drawCircle(
          Offset(px, py),
          7.0,
          Paint()..color = Taste.accent.withValues(alpha: 0.18),
        );
      }
      canvas.drawCircle(
        Offset(px, py),
        isSel || isHov ? 4.5 : 3.4,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(px, py),
        isSel || isHov ? 4.5 : 3.4,
        Paint()
          ..color = isSel || isHov ? Taste.primary : Taste.accent
          ..strokeWidth = isSel || isHov ? 2.4 : 1.8
          ..style = PaintingStyle.stroke,
      );

      // Value label above point
      if (points.length <= 10 || isSel || isHov || i == points.length - 1) {
        _drawLabel(
          canvas,
          pt.displayValue,
          Offset(px - 16, py - 18),
          color: isSel || isHov ? Taste.text : Taste.accent,
          fontSize: 10.5,
          weight: isSel || isHov ? FontWeight.w700 : FontWeight.w500,
        );
      }

      // X-axis date label
      if (i % labelStep == 0 || i == points.length - 1 || isSel) {
        final dateStr = formatDateMs(pt.exam.time);
        final shortDate =
            dateStr.length >= 10 ? dateStr.substring(5, 10) : dateStr;
        _drawLabel(
          canvas,
          shortDate,
          Offset(px - 16, topPad + plotH + 6),
          color: isSel ? Taste.text : Taste.muted,
          fontSize: 10,
          weight: isSel ? FontWeight.w700 : FontWeight.w400,
        );
      }
    }
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color color,
    required double fontSize,
    required FontWeight weight,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: Taste.fontFamily,
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ScoreLineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.avgValue != avgValue ||
        oldDelegate.selectedExamId != selectedExamId ||
        oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.isPercentage != isPercentage;
  }
}
