import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'hfs_models.dart';

class SmsSendOutcome {
  final int code;
  final String message;
  final String? captchaSvg;

  const SmsSendOutcome({
    required this.code,
    required this.message,
    this.captchaSvg,
  });

  bool get isOk => code == 0;
  bool get needsCaptcha => code == 4048;
  bool get isAlreadyOccupied => code == 4044;
}

class HfsUpstreamClient {
  /// Strictly connects ONLY to official Haofenshu upstream hosts:
  /// - App API: https://hfs-be.yunxiao.com
  /// - WeChat mini-program API: https://hfs-wechat-be.yunxiao.com
  /// - OSS exam images: https://yj-oss.yunxiao.com
  static const String kHfsApiHost = 'hfs-be.yunxiao.com';
  static const String kHfsWechatHost = 'hfs-wechat-be.yunxiao.com';
  static const String kHfsOssHost = 'yj-oss.yunxiao.com';
  static const String kHfsBaseUrl = 'https://hfs-be.yunxiao.com';
  static const String kHfsWechatBaseUrl =
      'https://hfs-wechat-be.yunxiao.com';

  static final RegExp _cropMetaRe = RegExp(
    r'@c_[^?]*,x_(\d+),y_(\d+),w_(\d+),h_(\d+)',
    caseSensitive: false,
  );
  static final RegExp _cropTailRe = RegExp(
    r'@c_[^?|]+(?:\|[^?]*)?$',
    caseSensitive: false,
  );
  static final RegExp _setCookieSplitRe = RegExp(
    r',(?=\s*[A-Za-z0-9_-]+=)',
  );

  final http.Client _http = http.Client();
  final Map<String, ({DashboardData data, DateTime expiresAt})> _dashCache = {};
  final Map<String, ({Uint8List bytes, DateTime expiresAt})> _imgCache = {};
  final Map<String, ({List<WrongQuestionItem> items, DateTime expiresAt})>
      _wrongExamCache = {};
  final Map<String, Future<void>> _accountGates = {};
  final Map<String, int> _switchGenerations = {};
  List<RegionProvinceItem>? _regionCache;

  static void assertAllowedHost(Uri uri) {
    if (uri.scheme != 'https' ||
        (uri.host != kHfsApiHost &&
            uri.host != kHfsWechatHost &&
            uri.host != kHfsOssHost)) {
      throw StateError(
          '安全策略拦截：仅允许连接好分数官方后端 ($kHfsApiHost / $kHfsWechatHost / $kHfsOssHost)');
    }
  }

  Map<String, String> _miniHeaders({
    String? cookie,
    bool json = false,
  }) {
    final headers = <String, String>{
      'deviceType': '7',
      'Accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) WeChat/8.0',
    };
    if (json) {
      headers['Content-Type'] = 'application/json; charset=UTF-8';
    }
    if (cookie != null && cookie.trim().isNotEmpty) {
      // The mini-program intentionally sends this as lower-case `cookie`,
      // which is distinct from the App API's `Cookie: hfs-session-id=...`.
      headers['cookie'] = cookie.trim();
    }
    return headers;
  }

  Future<({Map<String, dynamic> body, List<String> cookies})> _miniRequest(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? query,
    Map<String, dynamic>? jsonBody,
    String? cookie,
  }) async {
    final base = Uri.parse('$kHfsWechatBaseUrl$path');
    assertAllowedHost(base);
    final uri = query == null
        ? base
        : base.replace(
            queryParameters: <String, String>{
              ...base.queryParameters,
              for (final e in query.entries)
                if (e.value != null) e.key: e.value.toString(),
            },
          );
    final headers = _miniHeaders(cookie: cookie, json: jsonBody != null);
    final payload = jsonBody == null ? null : jsonEncode(jsonBody);
    late http.Response resp;
    switch (method.toUpperCase()) {
      case 'POST':
        resp = await _http
            .post(uri, headers: headers, body: payload)
            .timeout(const Duration(seconds: 20));
        break;
      case 'PUT':
        resp = await _http
            .put(uri, headers: headers, body: payload)
            .timeout(const Duration(seconds: 20));
        break;
      default:
        resp = await _http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 20));
    }
    final body = _decodeJsonMap(resp.bodyBytes);
    final fresh = <String>[];
    for (final c in _parseAllSetCookies(resp.headers)) {
      if (c.startsWith('hfs-wechat-be-session-id=')) fresh.add(c);
    }
    final code = intOf(body['code'], -1);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
          '好分数微信接口 HTTP ${resp.statusCode}: ${strOf(body['msg'], '请求失败')}');
    }
    if (code != 0) {
      final detail = strOf(body['errStack']);
      throw Exception(
          '好分数微信接口 ${strOf(body['msg'], '请求失败')} (code=$code)${detail.isEmpty ? '' : ' · $detail'}');
    }
    return (body: body, cookies: fresh);
  }

  List<String> _parseAllSetCookies(Map<String, String> headers) {
    final out = <String>[];
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'set-cookie') continue;
      for (final part in entry.value.split(_setCookieSplitRe)) {
        final pair = part.split(';').first.trim();
        if (pair.isNotEmpty) out.add(pair);
      }
    }
    return out;
  }

  static String accountIdFor(String loginName, int roleType) {
    final digest =
        sha256.convert(utf8.encode('$roleType:${loginName.trim()}')).bytes;
    return base64UrlEncode(digest).replaceAll('=', '').substring(0, 14);
  }

  Future<T> _withAccountLock<T>(
    String accountId,
    Future<T> Function() action,
  ) async {
    final prev = _accountGates[accountId];
    final completer = Completer<void>();
    _accountGates[accountId] = completer.future;
    if (prev != null) {
      try {
        await prev;
      } catch (_) {}
    }
    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_accountGates[accountId], completer.future)) {
        _accountGates.remove(accountId);
      }
    }
  }

  Map<String, String> _roleHeaders(int roleType, {List<String>? cookies}) {
    final headers = <String, String>{
      'deviceType': '1',
      'appType': roleType == 1 ? '1' : '2',
      'versionName': '4.31.81',
      'User-Agent': 'YX Android 14',
      'Accept': 'application/json',
      'checkYlt': 'false',
    };
    if (cookies != null && cookies.isNotEmpty) {
      headers['Cookie'] = cookies.join('; ');
    }
    return headers;
  }

  List<String> _parseSetCookies(Map<String, String> headers) {
    final out = <String>[];
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'set-cookie') {
        final parts = entry.value.split(_setCookieSplitRe);
        for (final part in parts) {
          final pair = part.split(';').first.trim();
          if (pair.startsWith('hfs-session-id=') ||
              pair.startsWith('hfs-test-session-id=')) {
            out.add(pair);
          }
        }
      }
    }
    return out;
  }

  List<String> _mergeCookies(List<String> existing, List<String> fresh) {
    if (fresh.isEmpty) return existing;
    final map = <String, String>{};
    final order = <String>[];
    for (final c in existing) {
      final k = c.split('=').first;
      if (!map.containsKey(k)) order.add(k);
      map[k] = c;
    }
    for (final c in fresh) {
      final k = c.split('=').first;
      if (!map.containsKey(k)) order.add(k);
      map[k] = c;
    }
    return [for (final k in order) map[k]!];
  }

  bool _isCodeOk(dynamic code) => intOf(code, -1) == 0;

  Map<String, dynamic> _decodeJsonMap(Uint8List bytes) {
    if (bytes.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  List<String> _miniSessionCookies({
    required String jwt,
    required List<String> setCookies,
  }) {
    final value = jwt.trim();
    final out = <String>[];
    for (final c in setCookies) {
      if (c.startsWith('hfs-wechat-be-session-id=')) {
        out.add(c);
      }
    }
    if (value.isNotEmpty &&
        !out.any((c) => c.startsWith('hfs-wechat-be-session-id='))) {
      out.add('hfs-wechat-be-session-id=$value');
    }
    return out;
  }

  /// WeChat mini-program: discover accounts associated with a phone/WeChat identity.
  /// The `code` is deliberately sent as supplied; the upstream contract only
  /// requires that the parameter exists. This UI never probes an unknown phone.
  Future<MiniRelatedUsersResult> miniAccountRelatedUsers({
    required String code,
    String phone = '',
    String gzhAppId = '',
    String gzhOpenId = '',
    String accessToken = '',
  }) async {
    if (code.trim().isEmpty) {
      throw ArgumentError('微信登录 code 不能为空');
    }
    final res = await _miniRequest(
      '/v2/mini/account-related-user',
      query: <String, dynamic>{
        'code': code,
        if (phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (gzhAppId.trim().isNotEmpty) 'gzhAppId': gzhAppId.trim(),
        if (gzhOpenId.trim().isNotEmpty) 'gzhOpenId': gzhOpenId.trim(),
        if (accessToken.trim().isNotEmpty) 'accessToken': accessToken.trim(),
      },
    );
    final data = res.body['data'] is Map
        ? Map<String, dynamic>.from(res.body['data'] as Map)
        : const <String, dynamic>{};
    final users = data['users'] is List
        ? (data['users'] as List)
            .whereType<Map>()
            .map((m) => MiniRelatedUser.fromJson(
                  Map<String, dynamic>.from(m),
                ))
            .where((u) => u.userId.isNotEmpty)
            .toList()
        : <MiniRelatedUser>[];
    return MiniRelatedUsersResult(
      unionId: strOf(data['unionId']),
      users: users,
    );
  }

  /// WeChat mini-program passwordless account-login exchange.
  /// `key` and `unionId` are passed literally; no normalization or guessing.
  Future<MiniLoginResult> miniAccountLogin({
    required MiniRelatedUser user,
    required String key,
    required String unionId,
  }) async {
    if (user.userId.trim().isEmpty) {
      throw ArgumentError('微信账号 userId 不能为空');
    }
    final res = await _miniRequest(
      '/v2/mini/account-login',
      method: 'POST',
      jsonBody: <String, dynamic>{
        'userId': user.userId,
        'roleType': user.roleType,
        'key': key,
        'unionId': unionId,
      },
    );
    final data = res.body['data'] is Map
        ? Map<String, dynamic>.from(res.body['data'] as Map)
        : const <String, dynamic>{};
    final jwt = strOf(data['cookie']);
    final cookies = _miniSessionCookies(jwt: jwt, setCookies: res.cookies);
    return MiniLoginResult(
      userId: strOf(data['userId'], user.userId),
      unionId: strOf(data['unionId'], unionId),
      roleType: intOf(data['roleType'], user.roleType),
      studentId: strOf(data['studentId']),
      schoolId: intOf(data['schoolId']),
      jwt: jwt,
      key: user.key,
      cookies: cookies,
      wechatCookie: cookies.isNotEmpty ? cookies.first : '',
    );
  }

  /// Read the App-side roster using the JWT returned by mini account-login.
  /// This deliberately returns the same domain model as regular App login.
  Future<List<StudentInfo>> miniReadRelatedStudents(MiniLoginResult session) async {
    final cookieValue = session.jwt.trim();
    if (cookieValue.isEmpty) throw Exception('微信免密登录未返回会话 JWT');
    final uri = Uri.parse('$kHfsBaseUrl/v2/user-center/related-students');
    assertAllowedHost(uri);
    final headers = _roleHeaders(session.roleType, cookies: <String>[
      'hfs-session-id=$cookieValue',
    ]);
    final resp = await _http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));
    final body = _decodeJsonMap(resp.bodyBytes);
    if (intOf(body['code'], -1) != 0 || body['data'] is! List) {
      throw Exception(strOf(body['msg'], '微信免密会话读取学生名单失败'));
    }
    return (body['data'] as List)
        .whereType<Map>()
        .map((m) => StudentInfo.fromUpstream(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// WeChat mini-program registration. `vcode` is a real SMS code and is
  /// intentionally not auto-filled or bypassed.
  Future<MiniRegisterResult> miniAccountRegister({
    required String phone,
    required String unionId,
    required int roleType,
    required String password,
    required String vcode,
    String invitationCode = '',
  }) async {
    final res = await _miniRequest(
      '/v2/mini/account-register',
      method: 'POST',
      jsonBody: <String, dynamic>{
        'phone': phone.trim(),
        'unionId': unionId,
        'roleType': roleType,
        'password': password,
        'vcode': vcode.trim(),
        'invitationCode': invitationCode.trim(),
      },
    );
    final data = res.body['data'] is Map
        ? Map<String, dynamic>.from(res.body['data'] as Map)
        : const <String, dynamic>{};
    return MiniRegisterResult(
      code: intOf(res.body['code']),
      message: strOf(res.body['msg'], '注册完成'),
      data: data,
      cookies: res.cookies,
    );
  }

  Future<void> miniAccountLogout({required String wechatCookie}) async {
    if (wechatCookie.trim().isEmpty) {
      throw ArgumentError('微信会话 cookie 不能为空');
    }
    await _miniRequest(
      '/v2/mini/account-logout',
      method: 'POST',
      cookie: wechatCookie,
    );
  }

  /// Exchange a mini-program session into the regular account model so all
  /// existing dashboard, roster and rebind UI can operate on it.
  Future<HfsAccount> miniLoginAsAccount({
    required MiniLoginResult session,
    String label = '',
  }) async {
    // `_miniRelated` is deliberately not persisted; the wx.login code and
    // account discovery response are short-lived and must be reacquired.
    // Only the exchanged session cookie is persisted in HfsAccount.
    final account = HfsAccount(
      id: accountIdFor(session.userId, session.roleType),
      label: label,
      roleType: session.roleType,
      loginName: '',
      password: '',
      cookies: <String>['hfs-session-id=${session.jwt}'],
      students: <StudentInfo>[],
      activeStudentId: session.studentId,
      desiredStudentId: session.studentId,
      wechatSessionCookie: session.wechatCookie,
    );
    await hydrateAccountStudents(account);
    return account;
  }

  Future<List<String>> loginHfs({
    required String loginName,
    required String password,
    required int roleType,
  }) async {
    final uri = Uri.parse('$kHfsBaseUrl/v2/users/sessions');
    assertAllowedHost(uri);

    final pwEncoded = '${base64Encode(utf8.encode(password))}\n';
    final payload = jsonEncode(<String, dynamic>{
      'loginName': loginName.trim(),
      'password': pwEncoded,
      'loginType': 1,
      'roleType': roleType,
      'rememberMe': 1,
      'deviceType': 1,
    });

    final headers = _roleHeaders(roleType);
    headers['Content-Type'] = 'application/json; charset=UTF-8';

    final resp = await _http
        .post(uri, headers: headers, body: payload)
        .timeout(const Duration(seconds: 20));
    final body = _decodeJsonMap(resp.bodyBytes);
    final jar = _parseSetCookies(resp.headers);
    final code = intOf(body['code'], -1);

    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        jar.isEmpty ||
        (code != 0 && code != 1 && code != 10 && code != 11)) {
      if (code == 4046) {
        final roleLabel = roleType == 1 ? '学生版' : '家长版';
        throw Exception('账号或密码错误（当前选择：$roleLabel）');
      }
      throw Exception(strOf(body['msg'], '好分数登录失败'));
    }
    return jar;
  }

  /// Fetch graphical SVG captcha (`GET /v2/users/captcha?phone=...`)
  Future<String> fetchCaptchaSvg({
    required String phoneNumber,
    int roleType = 2,
  }) async {
    final cleanPhone = phoneNumber.trim();
    final uri = Uri.parse(
      '$kHfsBaseUrl/v2/users/captcha?phone=${Uri.encodeQueryComponent(cleanPhone)}',
    );
    assertAllowedHost(uri);
    final resp = await _http
        .get(uri, headers: _roleHeaders(roleType))
        .timeout(const Duration(seconds: 15));
    final body = _decodeJsonMap(resp.bodyBytes);
    final data = (body['data'] is Map)
        ? Map<String, dynamic>.from(body['data'] as Map)
        : const <String, dynamic>{};
    final pic = strOf(data['pic']);
    if (pic.isEmpty) {
      throw Exception(strOf(body['msg'], '获取图形验证码失败'));
    }
    return pic;
  }

  /// Send registration SMS verification code (`POST /v2/native-users/verification-msg-with-captcha`)
  Future<SmsSendOutcome> sendRegisterSmsCode({
    required String phoneNumber,
    required int roleType,
    String captchaCode = '',
  }) async {
    final uri = Uri.parse(
      '$kHfsBaseUrl/v2/native-users/verification-msg-with-captcha',
    );
    assertAllowedHost(uri);
    final headers = _roleHeaders(roleType);
    headers['Content-Type'] = 'application/json; charset=UTF-8';
    final payload = jsonEncode(<String, dynamic>{
      'roleType': roleType,
      'phoneNumber': phoneNumber.trim(),
      'code': captchaCode.trim(),
    });
    final resp = await _http
        .post(uri, headers: headers, body: payload)
        .timeout(const Duration(seconds: 20));
    final body = _decodeJsonMap(resp.bodyBytes);
    final code = intOf(body['code'], -1);
    final data = (body['data'] is Map)
        ? Map<String, dynamic>.from(body['data'] as Map)
        : const <String, dynamic>{};
    final svg = strOf(data['pic']);
    return SmsSendOutcome(
      code: code,
      message: strOf(body['msg'], code == 0 ? '验证码已发送' : '发送验证码失败'),
      captchaSvg: svg.isNotEmpty ? svg : null,
    );
  }

  /// Register new Haofenshu account (`POST /v2/native-users/activation`)
  /// Mirrors APK `UserTask.b(phone, password, smsCode, invitationCode)` -> `BindPhoneReq(JsonUtils.b(NativeMsgToken))`
  Future<List<String>> registerNativeAccount({
    required String phoneNumber,
    required String password,
    required String verificationCode,
    required int roleType,
    String invitationCode = '',
  }) async {
    final uri = Uri.parse('$kHfsBaseUrl/v2/native-users/activation');
    assertAllowedHost(uri);

    final tokenMap = <String, dynamic>{
      'roleType': roleType,
      'phoneNumber': phoneNumber.trim(),
      'verificationCode': verificationCode.trim(),
      'password': password,
      if (invitationCode.trim().isNotEmpty)
        'invitationCode': invitationCode.trim(),
    };
    final bodyPayload = jsonEncode(<String, dynamic>{
      'verificationType': 2,
      'verificationMsgToken': jsonEncode(tokenMap),
      'deviceType': 1,
      'forceReplace': false,
    });

    final headers = _roleHeaders(roleType);
    headers['Content-Type'] = 'application/json; charset=UTF-8';
    final resp = await _http
        .post(uri, headers: headers, body: bodyPayload)
        .timeout(const Duration(seconds: 20));
    final body = _decodeJsonMap(resp.bodyBytes);
    final code = intOf(body['code'], -1);
    var jar = _parseSetCookies(resp.headers);
    final data = (body['data'] is Map)
        ? Map<String, dynamic>.from(body['data'] as Map)
        : const <String, dynamic>{};
    final dataCookie = strOf(data['cookie']);
    if (jar.isEmpty && dataCookie.isNotEmpty) {
      jar = <String>[dataCookie.split(';').first.trim()];
    }

    if (code == 4044) {
      throw Exception('该手机号已被注册，请直接切换到“登录已有账号”');
    }
    if (code != 0 && code != 10 && code != 11) {
      throw Exception(strOf(body['msg'], '注册好分数账号失败 (code=$code)'));
    }
    if (jar.isEmpty) {
      // Automatically login to obtain fresh session cookies
      jar = await loginHfs(
        loginName: phoneNumber.trim(),
        password: password,
        roleType: roleType,
      );
    }
    return jar;
  }

  /// Send password-reset SMS verification code (`POST /v2/users/retrieving-msg-code-with-captcha`)
  Future<SmsSendOutcome> sendResetPwdSmsCode({
    required String phoneNumber,
    required int roleType,
    String captchaCode = '',
  }) async {
    final uri = Uri.parse(
      '$kHfsBaseUrl/v2/users/retrieving-msg-code-with-captcha',
    );
    assertAllowedHost(uri);
    final headers = _roleHeaders(roleType);
    headers['Content-Type'] = 'application/json; charset=UTF-8';
    final payload = jsonEncode(<String, dynamic>{
      'roleType': roleType,
      'phoneNumber': phoneNumber.trim(),
      'code': captchaCode.trim(),
    });
    final resp = await _http
        .post(uri, headers: headers, body: payload)
        .timeout(const Duration(seconds: 20));
    final body = _decodeJsonMap(resp.bodyBytes);
    final code = intOf(body['code'], -1);
    final data = (body['data'] is Map)
        ? Map<String, dynamic>.from(body['data'] as Map)
        : const <String, dynamic>{};
    final svg = strOf(data['pic']);
    return SmsSendOutcome(
      code: code,
      message: strOf(body['msg'], code == 0 ? '找回密码验证码已发送' : '发送验证码失败'),
      captchaSvg: svg.isNotEmpty ? svg : null,
    );
  }

  /// Complete password reset (`POST /v2/users/retrieving-msg-token` -> `PUT /v2/users/forgot-password`)
  Future<void> resetForgotPassword({
    required String phoneNumber,
    required String smsCode,
    required String newPassword,
    required int roleType,
  }) async {
    final tokenUri = Uri.parse('$kHfsBaseUrl/v2/users/retrieving-msg-token');
    assertAllowedHost(tokenUri);
    final headers = _roleHeaders(roleType);
    headers['Content-Type'] = 'application/json; charset=UTF-8';

    final tokenResp = await _http
        .post(
          tokenUri,
          headers: headers,
          body: jsonEncode(<String, dynamic>{
            'roleType': roleType,
            'phoneNumber': phoneNumber.trim(),
            'retrievingMsgCode': smsCode.trim(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    final tokenBody = _decodeJsonMap(tokenResp.bodyBytes);
    if (!_isCodeOk(tokenBody['code'])) {
      throw Exception(strOf(tokenBody['msg'], '短信验证码校验失败'));
    }
    final tData = (tokenBody['data'] is Map)
        ? Map<String, dynamic>.from(tokenBody['data'] as Map)
        : const <String, dynamic>{};
    final retrievingToken = tData['retrievingToken'] is String
        ? strOf(tData['retrievingToken'])
        : (tData['token'] is String
            ? strOf(tData['token'])
            : (tokenBody['data'] is String ? strOf(tokenBody['data']) : ''));
    if (retrievingToken.isEmpty) {
      throw Exception('未获取到重置密码令牌');
    }

    final resetUri = Uri.parse('$kHfsBaseUrl/v2/users/forgot-password');
    assertAllowedHost(resetUri);
    final resetResp = await _http
        .put(
          resetUri,
          headers: headers,
          body: jsonEncode(<String, dynamic>{
            'retrievingType': 2,
            'retrievingToken': retrievingToken,
            'password': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 20));
    final resetBody = _decodeJsonMap(resetResp.bodyBytes);
    if (!_isCodeOk(resetBody['code'])) {
      throw Exception(strOf(resetBody['msg'], '重置密码失败'));
    }
  }

  /// Change account password when logged in (`PUT /v2/users/password`)
  Future<void> changeAccountPassword({
    required HfsAccount account,
    required String originalPassword,
    required String newPassword,
  }) async {
    await ensureAccount(account);
    final res = await _hfsFetch(
      account,
      '/v2/users/password',
      method: 'PUT',
      jsonBody: <String, dynamic>{
        'originalPassword': originalPassword,
        'newPassword': newPassword,
      },
    );
    if (!_isCodeOk(res.body['code'])) {
      throw Exception(strOf(res.body['msg'], '修改密码失败'));
    }
  }

  Future<({int status, Map<String, dynamic> body})> _hfsFetch(
    HfsAccount account,
    String path, {
    String method = 'GET',
    Map<String, dynamic>? jsonBody,
  }) async {
    final uri = Uri.parse('$kHfsBaseUrl$path');
    assertAllowedHost(uri);

    final headers = _roleHeaders(account.roleType, cookies: account.cookies);
    String? encodedBody;
    if (jsonBody != null) {
      headers['Content-Type'] = 'application/json; charset=UTF-8';
      encodedBody = jsonEncode(jsonBody);
    }

    late http.Response resp;
    switch (method.toUpperCase()) {
      case 'POST':
        resp = await _http
            .post(uri, headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 20));
        break;
      case 'PUT':
        resp = await _http
            .put(uri, headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 20));
        break;
      case 'PATCH':
        resp = await _http
            .patch(uri, headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 20));
        break;
      case 'DELETE':
        resp = await _http
            .delete(uri, headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 20));
        break;
      default:
        resp = await _http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 20));
    }

    final fresh = _parseSetCookies(resp.headers);
    if (fresh.isNotEmpty) {
      account.cookies = _mergeCookies(account.cookies, fresh);
    }
    return (status: resp.statusCode, body: _decodeJsonMap(resp.bodyBytes));
  }

  Future<Map<String, dynamic>> ensureAccount(
    HfsAccount account, {
    String targetStudentId = '',
    bool forceSwitchSession = false,
  }) async {
    var check = await _hfsFetch(
      account,
      '/v2/user-center/user-snapshot?devicetype=1',
    );
    final checkCode = intOf(check.body['code'], -1);
    if (checkCode == 3001 ||
        checkCode == 1004 ||
        checkCode == 4101 ||
        check.status == 401 ||
        check.status == 403 ||
        check.status < 200 ||
        check.status >= 300) {
      if (account.loginName.trim().isEmpty || account.password.isEmpty) {
        account.state = 'reauth_required';
        throw Exception('好分数会话已过期，请重新登录');
      }
      final jar = await loginHfs(
        loginName: account.loginName,
        password: account.password,
        roleType: account.roleType,
      );
      account.cookies = jar;
      account.lastRefreshAt = DateTime.now().millisecondsSinceEpoch;
      account.state = 'connected';
      check = await _hfsFetch(
        account,
        '/v2/user-center/user-snapshot?devicetype=1',
      );
      if (intOf(check.body['code'], -1) == 3001) {
        account.state = 'reauth_required';
        throw Exception('好分数会话自动刷新失败');
      }
    }

    final wantStu = targetStudentId.isNotEmpty
        ? targetStudentId
        : (account.desiredStudentId.isNotEmpty
            ? account.desiredStudentId
            : account.activeStudentId);
    var dataMap = (check.body['data'] is Map)
        ? Map<String, dynamic>.from(check.body['data'] as Map)
        : <String, dynamic>{};
    var linked = (dataMap['linkedStudent'] is Map)
        ? Map<String, dynamic>.from(dataMap['linkedStudent'] as Map)
        : <String, dynamic>{};
    final curLinkedId = strOf(linked['studentId']).isNotEmpty
        ? strOf(linked['studentId'])
        : strOf(linked['id']);

    if (wantStu.isNotEmpty && (forceSwitchSession || wantStu != curLinkedId)) {
      try {
        await _hfsFetch(
          account,
          '/v2/user-center/sessions',
          method: 'POST',
          jsonBody: <String, dynamic>{'deviceType': 1, 'studentId': wantStu},
        );
        final check2 = await _hfsFetch(
          account,
          '/v2/user-center/user-snapshot?devicetype=1',
        );
        check = check2;
        dataMap = (check.body['data'] is Map)
            ? Map<String, dynamic>.from(check.body['data'] as Map)
            : <String, dynamic>{};
        linked = (dataMap['linkedStudent'] is Map)
            ? Map<String, dynamic>.from(dataMap['linkedStudent'] as Map)
            : <String, dynamic>{};
      } catch (_) {}
    }

    if (linked.isNotEmpty) {
      final sid = strOf(linked['studentId']).isNotEmpty
          ? strOf(linked['studentId'])
          : strOf(linked['id']);
      if (sid.isNotEmpty) {
        account.activeStudentId = sid;
        if (targetStudentId.isNotEmpty && sid == targetStudentId) {
          account.desiredStudentId = sid;
        }
      }
    }
    return dataMap;
  }

  Future<Map<String, dynamic>> hydrateAccountStudents(HfsAccount account) async {
    return _withAccountLock(account.id, () => _hydrateAccountStudentsUnlocked(account));
  }

  Future<Map<String, dynamic>> _hydrateAccountStudentsUnlocked(
    HfsAccount account,
  ) async {
    final snapData = await ensureAccount(account);
    final rel = await _hfsFetch(account, '/v2/user-center/related-students');
    if (_isCodeOk(rel.body['code']) && rel.body['data'] is List) {
      final list = (rel.body['data'] as List)
          .whereType<Map>()
          .map((e) => StudentInfo.fromUpstream(Map<String, dynamic>.from(e)))
          .toList();
      if (list.isNotEmpty) {
        account.students = list;
      }
    }
    if (snapData['linkedStudent'] is Map) {
      final linkedStu = StudentInfo.fromUpstream(
        Map<String, dynamic>.from(snapData['linkedStudent'] as Map),
      );
      if (linkedStu.studentId.isNotEmpty) {
        account.activeStudentId = linkedStu.studentId;
      }
      if (account.students.isEmpty && linkedStu.studentId.isNotEmpty) {
        account.students = <StudentInfo>[linkedStu];
      }
    }
    account.lastRefreshAt = DateTime.now().millisecondsSinceEpoch;
    return snapData;
  }

  void invalidateCache(String accountId) {
    _dashCache.removeWhere(
      (key, _) => key == accountId || key.startsWith('$accountId:'),
    );
    _wrongExamCache.removeWhere(
      (key, _) => key.startsWith('$accountId:'),
    );
  }

  void clearAllCaches() {
    _dashCache.clear();
    _imgCache.clear();
    _wrongExamCache.clear();
  }

  void seedDashboardCache(
    String accountId,
    String studentId,
    DashboardData data,
  ) {
    final cacheKey = '$accountId:$studentId';
    _dashCache[cacheKey] = (
      data: data,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  DashboardData? peekCachedDashboard(String accountId, String studentId) {
    final hit = _dashCache['$accountId:$studentId'];
    if (hit != null && DateTime.now().isBefore(hit.expiresAt)) {
      return hit.data;
    }
    return null;
  }

  Future<DashboardData> fetchDashboard(
    HfsAccount account, {
    bool allowCache = true,
    int maxExams = 10,
    int concurrency = 4,
  }) async {
    return _withAccountLock(account.id, () async {
      final wantStu = account.desiredStudentId.isNotEmpty
          ? account.desiredStudentId
          : account.activeStudentId;
      if (allowCache && wantStu.isNotEmpty) {
        final fastHit = _dashCache['${account.id}:$wantStu'];
        if (fastHit != null && DateTime.now().isBefore(fastHit.expiresAt)) {
          account.activeStudentId = wantStu;
          return fastHit.data;
        }
      }

      final snapData = await _hydrateAccountStudentsUnlocked(account);
      final activeStuId = account.activeStudentId;
      final cacheKey = '${account.id}:$activeStuId';
      if (allowCache) {
        final hit = _dashCache[cacheKey];
        if (hit != null && DateTime.now().isBefore(hit.expiresAt)) {
          return hit.data;
        }
      }

      const baseRoutes = <String>[
        '/v2/user-center/profile',
        '/v2/user-center/payment-info',
        '/v2/wrong-items/overview',
        '/v2/wrong-items/unlock-status',
        '/v3/cuoti/remain-right',
        '/v3/exam/list?start=0',
        '/v2/config/school/hidden-config',
      ];

      final baseRes = await Future.wait(
        baseRoutes.map((p) async {
          try {
            final r = await _hfsFetch(account, p);
            return r.body;
          } catch (_) {
            return <String, dynamic>{};
          }
        }),
      );

      final profile = (baseRes[0]['data'] is Map)
          ? Map<String, dynamic>.from(baseRes[0]['data'] as Map)
          : <String, dynamic>{};
      final payment = (baseRes[1]['data'] is Map)
          ? Map<String, dynamic>.from(baseRes[1]['data'] as Map)
          : <String, dynamic>{};
      final wrongRaw = (baseRes[2]['data'] is List)
          ? (baseRes[2]['data'] as List)
          : const <dynamic>[];
      final unlock = (baseRes[3]['data'] is Map)
          ? Map<String, dynamic>.from(baseRes[3]['data'] as Map)
          : <String, dynamic>{};
      final rights = (baseRes[4]['data'] is Map)
          ? Map<String, dynamic>.from(baseRes[4]['data'] as Map)
          : <String, dynamic>{};
      final schoolHidden = (baseRes[6]['data'] is Map)
          ? Map<String, dynamic>.from(baseRes[6]['data'] as Map)
          : <String, dynamic>{};

      List<dynamic> examListResp = const [];
      final exData = baseRes[5]['data'];
      if (exData is Map && exData['list'] is List) {
        examListResp = exData['list'] as List;
      } else if (exData is List) {
        examListResp = exData;
      }

      final examSeeds = <String, _ExamSeed>{};
      for (final raw in examListResp) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final id =
            strOf(m['examId']).isNotEmpty ? strOf(m['examId']) : strOf(m['id']);
        if (id.isEmpty) continue;
        examSeeds[id] = _ExamSeed(
          examId: id,
          examName: strOf(m['name'], strOf(m['examName'], '考试')),
          examTime: intOf(m['time'], intOf(m['examTime'])),
        );
      }

      final wrongSummaries = <WrongSubjectSummary>[];
      for (final rawSubj in wrongRaw) {
        if (rawSubj is! Map) continue;
        final sm = Map<String, dynamic>.from(rawSubj);
        final sName = strOf(sm['subject'], '学科');
        final exList =
            (sm['examList'] is List) ? (sm['examList'] as List) : const [];
        final semList = (sm['semesterList'] is List)
            ? (sm['semesterList'] as List)
            : const [];

        final examRefs = <WrongExamRef>[];
        for (final rawEx in exList) {
          if (rawEx is! Map) continue;
          final em = Map<String, dynamic>.from(rawEx);
          final id = strOf(em['examId']);
          if (id.isEmpty) continue;
          final wn = intOf(em['wrongNum']);
          final rn = intOf(em['reviewNum']);
          final eName = strOf(em['examName'], '考试');
          final eTime = intOf(em['examTime']);
          examRefs.add(
            WrongExamRef(
              examId: id,
              examName: eName,
              examTime: eTime,
              wrongNum: wn,
              reviewNum: rn,
            ),
          );

          final seed = examSeeds.putIfAbsent(
            id,
            () => _ExamSeed(
              examId: id,
              examName: eName,
              examTime: eTime,
            ),
          );
          seed.wrongBySubject[sName] = wn;
          seed.totalWrong += wn;
        }
        examRefs.sort((a, b) => b.examTime.compareTo(a.examTime));

        wrongSummaries.add(
          WrongSubjectSummary(
            subject: sName,
            noReview: intOf(sm['noReview']),
            semesters: semList
                .whereType<Map>()
                .map((s) => WrongSemesterItem.fromJson(
                      Map<String, dynamic>.from(s),
                    ))
                .toList(),
            exams: examRefs,
          ),
        );
      }

      final sortedSeeds = examSeeds.values.toList()
        ..sort((a, b) {
          if (a.examTime != b.examTime) return b.examTime.compareTo(a.examTime);
          return intOf(b.examId).compareTo(intOf(a.examId));
        });
      final cappedSeeds = sortedSeeds.take(maxExams.clamp(3, 30)).toList();
      final step = concurrency.clamp(1, 8);

      final hydratedExams = <ExamRecord>[];
      for (var i = 0; i < cappedSeeds.length; i += step) {
        final batch = cappedSeeds.skip(i).take(step);
        final batchRes = await Future.wait(
          batch.map((seed) => _hydrateSingleExam(account, seed, activeStuId)),
        );
        hydratedExams.addAll(batchRes);
      }

      if (activeStuId.isNotEmpty && hydratedExams.isNotEmpty) {
        final latest = hydratedExams.first;
        account.studentSnapshots[activeStuId] = StudentSnapshot(
          examId: latest.examId,
          examName: latest.name,
          examTime: latest.time,
          scoreS: latest.scoreS,
          manfen: latest.manfen,
          ratio: latest.ratio,
          isPartial: latest.isPartial,
          reportedPaperCount: latest.reportedPaperCount,
          classRankS: latest.classRankS,
          gradeRankS: latest.gradeRankS,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }

      final dash = DashboardData(
        account: account,
        currentStudent: account.activeStudent,
        exams: hydratedExams,
        wrongOverview: wrongSummaries,
        isMember: boolOf(payment['isMember']) || boolOf(snapData['isMember']),
        isExamMember: boolOf(snapData['isExamMember']),
        unlockedSubjects: intOf(unlock['unlockedSubjectNumber']),
        totalSubjects: intOf(unlock['totalSubjectNumber']),
        uploadRemain: strOf(rights['uploadRemain'], '-'),
        exportRemain: strOf(rights['exportRemain'], '-'),
        rawProfile: profile,
        rawSnapshot: snapData,
        rawPayment: payment,
        rawUnlock: unlock,
        rawRights: rights,
        rawSchoolHidden: schoolHidden,
      );

      _dashCache[cacheKey] = (
        data: dash,
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );
      return dash;
    });
  }

  Future<ExamRecord> _hydrateSingleExam(
    HfsAccount account,
    _ExamSeed seed,
    String activeStuId,
  ) async {
    final pair = await Future.wait([
      _hfsFetch(account, '/v3/exam/${seed.examId}/overview')
          .then((r) => r.body)
          .catchError((_) => <String, dynamic>{}),
      _hfsFetch(account, '/v3/exam/${seed.examId}/brief?withSubPapers=1')
          .then((r) => r.body)
          .catchError((_) => <String, dynamic>{}),
    ]);

    final ov = (pair[0]['data'] is Map)
        ? Map<String, dynamic>.from(pair[0]['data'] as Map)
        : <String, dynamic>{};
    final br = (pair[1]['data'] is Map)
        ? Map<String, dynamic>.from(pair[1]['data'] as Map)
        : <String, dynamic>{};

    var rawPapers = (ov['papers'] is List) ? (ov['papers'] as List) : const [];
    if (rawPapers.isEmpty && br['papers'] is List) {
      rawPapers = br['papers'] as List;
    }

    final brMap = <String, Map<String, dynamic>>{};
    if (br['papers'] is List) {
      for (final item in br['papers'] as List) {
        if (item is Map) {
          final pm = Map<String, dynamic>.from(item);
          final k = strOf(pm['paperId']).isNotEmpty
              ? strOf(pm['paperId'])
              : strOf(pm['subject']);
          brMap[k] = pm;
        }
      }
    }

    final papers = <PaperScore>[];
    for (final item in rawPapers) {
      if (item is! Map) continue;
      final pm = Map<String, dynamic>.from(item);
      final k = strOf(pm['paperId']).isNotEmpty
          ? strOf(pm['paperId'])
          : strOf(pm['subject']);
      final bp = brMap[k] ?? const <String, dynamic>{};

      final pScore = numOf(pm['score'] ?? bp['score']);
      final pManfen = numOf(pm['manfen'] ?? bp['manfen']);
      final subject = strOf(
        pm['subject'],
        strOf(bp['subject'], strOf(pm['name'], '科目')),
      );
      final paperId = strOf(pm['paperId'], strOf(bp['paperId']));
      final pid = strOf(pm['pid'], strOf(bp['pid']));
      final pRatio = pManfen > 0 ? round1((pScore / pManfen) * 100) : null;

      int? wrongVal = seed.wrongBySubject[subject] ??
          seed.wrongBySubject[subject.replaceAll('与社会', '')];

      papers.add(
        PaperScore(
          paperId: paperId,
          pid: pid,
          subject: subject,
          name: strOf(pm['name'], strOf(bp['subject'], subject)),
          score: pScore,
          scoreS: strOf(pm['scoreS'], strOf(bp['scoreS'], '$pScore')),
          manfen: pManfen,
          ratio: pRatio,
          wrongNum: wrongVal,
        ),
      );
    }

    papers.sort((a, b) {
      final ia = subjectIndex(a.subject);
      final ib = subjectIndex(b.subject);
      if (ia != ib) return ia.compareTo(ib);
      return a.subject.compareTo(b.subject);
    });

    final score = numOf(ov['score'] ?? br['score']);
    final manfen = numOf(ov['manfen'] ?? br['manfen']);
    final ratio = manfen > 0 ? round1((score / manfen) * 100) : null;
    final isPartial = papers.isNotEmpty && papers.length < 5;
    final exTime = intOf(ov['time'] ?? br['time'], seed.examTime);

    return ExamRecord(
      examId: seed.examId,
      studentId: activeStuId,
      name: strOf(ov['name'], strOf(br['name'], seed.examName)),
      time: exTime,
      score: score,
      scoreS: strOf(ov['scoreS'], strOf(br['scoreS'], '$score')),
      manfen: manfen,
      ratio: ratio,
      isPartial: isPartial,
      reportedPaperCount: papers.length,
      classRankS: strOf(ov['classRankS']),
      gradeRankS: strOf(ov['gradeRankS']),
      totalWrong: seed.totalWrong,
      papers: papers,
    );
  }

  Future<DashboardData> switchStudent(
    HfsAccount account,
    String studentId, {
    bool allowCache = true,
    int maxExams = 10,
    int concurrency = 4,
  }) async {
    final gen = (_switchGenerations[account.id] ?? 0) + 1;
    _switchGenerations[account.id] = gen;
    account.desiredStudentId = studentId;
    if (allowCache) {
      final cached = peekCachedDashboard(account.id, studentId);
      if (cached != null) {
        account.activeStudentId = studentId;
        // Fire-and-forget session sync in background so UI switches in <10ms
        unawaited(
          _withAccountLock(account.id, () async {
            if (_switchGenerations[account.id] != gen ||
                account.desiredStudentId != studentId) {
              return;
            }
            try {
              await ensureAccount(account, targetStudentId: studentId);
            } catch (_) {}
          }),
        );
        return cached;
      }
    }
    return fetchDashboard(
      account,
      allowCache: allowCache,
      maxExams: maxExams,
      concurrency: concurrency,
    );
  }

  /// Bind or Rebind student via Name + Exam/Student No:
  /// - Resolves `studentId` via `GET /v2/users/matched-students`
  /// - If `replaceStudentId` is empty -> adds via `PUT /v2/users/bind-student`
  /// - If `replaceStudentId` is provided -> rebinds via `PATCH /v2/native-users/bind-student`
  Future<DashboardData> bindStudent({
    required HfsAccount account,
    required String studentName,
    required String identityCode,
    String? schoolAuthCode,
    String replaceStudentId = '',
  }) async {
    await hydrateAccountStudents(account);
    final role = account.roleType == 1 ? 1 : 2;
    final matchPath =
        '/v2/users/matched-students?roleType=$role&studentName=${Uri.encodeQueryComponent(studentName.trim())}&identityCode=${Uri.encodeQueryComponent(identityCode.trim())}';
    final matchRes = await _hfsFetch(account, matchPath);
    if (!_isCodeOk(matchRes.body['code'])) {
      throw Exception(strOf(matchRes.body['msg'], '未匹配到该姓名与准考证号对应的学生'));
    }
    final mData = (matchRes.body['data'] is Map)
        ? Map<String, dynamic>.from(matchRes.body['data'] as Map)
        : <String, dynamic>{};
    final mList =
        (mData['students'] is List) ? (mData['students'] as List) : const [];
    if (mList.isEmpty || mList.first is! Map) {
      throw Exception('未找到匹配的学生信息，请核对姓名与准考证号');
    }
    final targetStu = Map<String, dynamic>.from(mList.first as Map);
    final targetId = strOf(
      targetStu['studentId'],
      strOf(targetStu['id']),
    );
    if (targetId.isEmpty) {
      throw Exception('匹配到的学生记录缺少有效 studentId');
    }

    if (replaceStudentId.trim().isNotEmpty) {
      return rebindStudent(
        account: account,
        selectStudentId: replaceStudentId.trim(),
        targetStudentId: targetId,
        schoolAuthCode: schoolAuthCode,
      );
    }

    final bindRes = await _hfsFetch(
      account,
      '/v2/users/bind-student',
      method: 'PUT',
      jsonBody: <String, dynamic>{
        'deviceType': 1,
        'studentId': targetId,
        'identityCode': identityCode.trim(),
        'schoolAuthCode':
            (schoolAuthCode != null && schoolAuthCode.trim().isNotEmpty)
                ? schoolAuthCode.trim()
                : null,
      },
    );
    if (!_isCodeOk(bindRes.body['code'])) {
      throw Exception(
        strOf(bindRes.body['msg'], '绑定学生失败 (code=${bindRes.body['code']})'),
      );
    }

    account.desiredStudentId = targetId;
    await ensureAccount(
      account,
      targetStudentId: targetId,
      forceSwitchSession: true,
    );
    account.activeStudentId = targetId;
    invalidateCache(account.id);
    return fetchDashboard(account, allowCache: false);
  }

  /// Bind student via Student Account + Password (`POST /v2/native-users/bind-student-by-account`)
  /// NOTE: Defaults `chooseStudentId` to `""` so existing bound students are never overwritten unless explicitly requested.
  Future<DashboardData> bindStudentByAccount({
    required HfsAccount account,
    required String studentAccount,
    required String studentPassword,
    String chooseStudentId = '',
  }) async {
    await hydrateAccountStudents(account);
    final res = await _hfsFetch(
      account,
      '/v2/native-users/bind-student-by-account',
      method: 'POST',
      jsonBody: <String, dynamic>{
        'account': studentAccount.trim(),
        'password': studentPassword,
        'chooseStuId': chooseStudentId.trim(),
      },
    );
    if (!_isCodeOk(res.body['code'])) {
      throw Exception(
        strOf(res.body['msg'], '按学生账号绑定失败 (code=${res.body['code']})'),
      );
    }
    invalidateCache(account.id);
    return fetchDashboard(account, allowCache: false);
  }

  /// Fetch province/city/county hierarchy (`GET /v2/region`)
  Future<List<RegionProvinceItem>> fetchRegions(HfsAccount account) async {
    if (_regionCache != null && _regionCache!.isNotEmpty) {
      return _regionCache!;
    }
    await ensureAccount(account);
    final res = await _hfsFetch(account, '/v2/region');
    if (!_isCodeOk(res.body['code']) || res.body['data'] is! List) {
      throw Exception(strOf(res.body['msg'], '获取省市区列表失败'));
    }
    final provinces = <RegionProvinceItem>[];
    for (final rp in res.body['data'] as List) {
      if (rp is! Map) continue;
      final pm = Map<String, dynamic>.from(rp);
      final pName = strOf(pm['name']);
      if (pName.isEmpty) continue;
      final cities = <RegionCityItem>[];
      if (pm['cities'] is List) {
        for (final rc in pm['cities'] as List) {
          if (rc is! Map) continue;
          final cm = Map<String, dynamic>.from(rc);
          final cName = strOf(cm['name']);
          final counties = <String>[];
          if (cm['counties'] is List) {
            for (final rco in cm['counties'] as List) {
              if (rco is Map && strOf(rco['name']).isNotEmpty) {
                counties.add(strOf(rco['name']));
              }
            }
          }
          if (cName.isNotEmpty) {
            cities.add(RegionCityItem(name: cName, counties: counties));
          }
        }
      }
      provinces.add(RegionProvinceItem(name: pName, cities: cities));
    }
    _regionCache = provinces;
    return provinces;
  }

  /// Fetch schools in region (`GET /v2/region/schools`)
  Future<List<RegionSchoolItem>> fetchRegionSchools({
    required HfsAccount account,
    required String province,
    required String city,
    required String county,
  }) async {
    await ensureAccount(account);
    final path =
        '/v2/region/schools?province=${Uri.encodeQueryComponent(province)}&city=${Uri.encodeQueryComponent(city)}&county=${Uri.encodeQueryComponent(county)}';
    final res = await _hfsFetch(account, path);
    if (!_isCodeOk(res.body['code']) || res.body['data'] is! List) {
      throw Exception(strOf(res.body['msg'], '获取学校列表失败'));
    }
    return (res.body['data'] as List)
        .whereType<Map>()
        .map((e) => RegionSchoolItem.fromJson(Map<String, dynamic>.from(e)))
        .where((s) => s.id.isNotEmpty && s.name.isNotEmpty)
        .toList();
  }

  /// Match students by schoolId + grade + studentName (`GET /v2/native-users/matched-students`)
  Future<List<SchoolMatchedStudent>> matchStudentsBySchool({
    required HfsAccount account,
    required String schoolId,
    required String studentName,
    String grade = '',
  }) async {
    await ensureAccount(account);
    var path =
        '/v2/native-users/matched-students?schoolId=${Uri.encodeQueryComponent(schoolId.trim())}&studentName=${Uri.encodeQueryComponent(studentName.trim())}';
    if (grade.trim().isNotEmpty) {
      path += '&grade=${Uri.encodeQueryComponent(grade.trim())}';
    }
    final res = await _hfsFetch(account, path);
    final code = intOf(res.body['code'], -1);
    if (code == 1) {
      throw Exception('在该学校下未找到同名学生，请核对学校、年级与姓名');
    }
    if (code != 0 || res.body['data'] is! List) {
      throw Exception(strOf(res.body['msg'], '查询学校学生失败'));
    }
    return (res.body['data'] as List)
        .whereType<Map>()
        .map((e) => SchoolMatchedStudent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Bind student directly by internal `studentId` (`POST /v2/native-users/bind-students`)
  Future<DashboardData> bindStudentById({
    required HfsAccount account,
    required String studentId,
  }) async {
    await hydrateAccountStudents(account);
    final cleanId = studentId.trim();
    if (cleanId.isEmpty) {
      throw Exception('studentId 不能为空');
    }
    final res = await _hfsFetch(
      account,
      '/v2/native-users/bind-students',
      method: 'POST',
      jsonBody: <String, dynamic>{
        'studentId': cleanId,
      },
    );
    if (!_isCodeOk(res.body['code'])) {
      final code = res.body['code'];
      final msg = strOf(res.body['msg'], '按 studentId 直绑失败');
      throw Exception('$msg (code=$code)');
    }
    account.desiredStudentId = cleanId;
    await ensureAccount(
      account,
      targetStudentId: cleanId,
      forceSwitchSession: true,
    );
    account.activeStudentId = cleanId;
    invalidateCache(account.id);
    return fetchDashboard(account, allowCache: false);
  }

  /// Rebind (replace) an existing bound student with a new target student
  /// via `PATCH /v2/native-users/bind-student` (`{selectStudentId, studentId, schoolAuthCode}`).
  ///
  /// Enforces safety rules:
  /// 1. Takes a live `GET /v2/user-center/related-students` snapshot before writing.
  /// 2. Verifies `selectStudentId` is not in semester lock (`changeBindTime > now` -> `4137`).
  /// 3. Guards against targets that already hold a student account (`bindStudent` non-null ->
  ///    `4137 Duplicate links` non-atomic bug where server deletes `selectStudentId` without adding `studentId`).
  /// 4. Re-reads `GET /v2/user-center/related-students` after the write to verify the actual roster state.
  Future<DashboardData> rebindStudent({
    required HfsAccount account,
    required String selectStudentId,
    required String targetStudentId,
    String? schoolAuthCode,
    bool? knownTargetHasStudentAccount,
    bool forceAllowStudentAccountTarget = false,
  }) async {
    final cleanSelectId = selectStudentId.trim();
    final cleanTargetId = targetStudentId.trim();
    if (cleanSelectId.isEmpty) {
      throw Exception('请选择要被替换的源学生 (selectStudentId)');
    }
    if (cleanTargetId.isEmpty) {
      throw Exception('目标学生 studentId 不能为空');
    }
    if (cleanSelectId == cleanTargetId) {
      throw Exception('源学生与目标学生相同，无需换绑');
    }
    if (knownTargetHasStudentAccount == true &&
        !forceAllowStudentAccountTarget) {
      throw Exception(
        '安全拦截：该目标同学已绑定学生端账号 (bindStudent非空)，好分数上游会返回 4137 Duplicate links 且非原子删除源学生！请优先换绑无学生端账号的目标，或勾选强制覆盖。',
      );
    }

    // 1. Pre-write live snapshot of `/v2/user-center/related-students`
    await hydrateAccountStudents(account);
    final preStudents = List<StudentInfo>.from(account.students);
    StudentInfo? sourceStu;
    for (final s in preStudents) {
      if (s.studentId == cleanSelectId) {
        sourceStu = s;
        break;
      }
    }
    if (sourceStu == null) {
      throw Exception('源学生 ($cleanSelectId) 不在当前账号已绑定名单中');
    }
    if (preStudents.any((s) => s.studentId == cleanTargetId)) {
      throw Exception('目标学生已绑定在当前账号下，无需重复换绑');
    }
    if (sourceStu.isSemesterLocked) {
      throw Exception(
        '源学生「${sourceStu.studentName}」处于学期锁定期（解锁日：${formatDateMs(sourceStu.changeBindTime)}），每生每学期只能换绑一次 (code=4137)',
      );
    }

    // 2. Execute `PATCH /v2/native-users/bind-student`
    final res = await _hfsFetch(
      account,
      '/v2/native-users/bind-student',
      method: 'PATCH',
      jsonBody: <String, dynamic>{
        'selectStudentId': cleanSelectId,
        'studentId': cleanTargetId,
        'schoolAuthCode':
            (schoolAuthCode != null && schoolAuthCode.trim().isNotEmpty)
                ? schoolAuthCode.trim()
                : null,
      },
    );

    // 3. Post-write live verification via `GET /v2/user-center/related-students` (2 verification reads)
    await hydrateAccountStudents(account);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await hydrateAccountStudents(account);
    final postStudents = List<StudentInfo>.from(account.students);

    final hasSourceNow =
        postStudents.any((s) => s.studentId == cleanSelectId);
    final hasTargetNow =
        postStudents.any((s) => s.studentId == cleanTargetId);

    if (!_isCodeOk(res.body['code'])) {
      final code = res.body['code'];
      final msg = strOf(res.body['msg'], '换绑学生失败');
      if (!hasSourceNow && !hasTargetNow) {
        invalidateCache(account.id);
        throw Exception(
          '$msg (code=$code) — 警告：触发上游 4137 非原子写缺陷，源学生「${sourceStu.studentName}」已被移除且目标未加入（当前剩余 ${postStudents.length} 人）',
        );
      }
      throw Exception(
        '$msg (code=$code)（已回读核实：原有名单 ${postStudents.length} 人完好未变）',
      );
    }

    final activeAfter = hasTargetNow
        ? cleanTargetId
        : (postStudents.isNotEmpty ? postStudents.first.studentId : '');
    if (activeAfter.isNotEmpty) {
      account.desiredStudentId = activeAfter;
      await ensureAccount(
        account,
        targetStudentId: activeAfter,
        forceSwitchSession: true,
      );
      account.activeStudentId = activeAfter;
    }
    invalidateCache(account.id);
    return fetchDashboard(account, allowCache: false);
  }

  /// Fetch full wrong-items details for a subject + exam (`GET /v2/wrong-items/exam-items`)
  /// Works for ALL bound students without VIP lock!
  Future<List<WrongQuestionItem>> fetchWrongExamItems({
    required HfsAccount account,
    required String studentId,
    required String subject,
    required String examId,
    bool allowCache = true,
  }) async {
    return _withAccountLock(account.id, () async {
      final cacheKey = '${account.id}:$studentId:$subject:$examId';
      if (allowCache) {
        final hit = _wrongExamCache[cacheKey];
        if (hit != null && DateTime.now().isBefore(hit.expiresAt)) {
          return hit.items;
        }
      }
      await ensureAccount(account, targetStudentId: studentId);

      Future<({int status, Map<String, dynamic> body})> queryFor(
        String subjName,
      ) {
        final p =
            '/v2/wrong-items/exam-items?subject=${Uri.encodeQueryComponent(subjName)}&examId=${Uri.encodeQueryComponent(examId)}';
        return _hfsFetch(account, p);
      }

      var res = await queryFor(subject);
      if ((!_isCodeOk(res.body['code']) ||
              res.body['data'] is! List ||
              (res.body['data'] as List).isEmpty) &&
          subject.contains('与社会')) {
        res = await queryFor(subject.replaceAll('与社会', ''));
      }
      if (!_isCodeOk(res.body['code'])) {
        throw Exception(strOf(res.body['msg'], '拉取错题本详情失败'));
      }

      List<String> validOssUrls(dynamic raw) {
        if (raw == null) return const <String>[];
        final out = <String>[];
        void addOne(dynamic candidate) {
          if (candidate == null) return;
          if (candidate is List) {
            for (final sub in candidate) {
              addOne(sub);
            }
            return;
          }
          if (candidate is Map) {
            final m = Map<String, dynamic>.from(candidate);
            addOne(m['url'] ?? m['contentPic'] ?? m['answerPic'] ?? m['pic']);
            return;
          }
          final u = strOf(candidate);
          if (u.isEmpty) return;
          final uri = Uri.tryParse(u);
          if (uri != null &&
              uri.scheme == 'https' &&
              uri.host == kHfsOssHost &&
              !out.contains(u)) {
            out.add(u);
          }
        }

        addOne(raw);
        return out;
      }

      final rawList =
          (res.body['data'] is List) ? (res.body['data'] as List) : const [];
      final items = <WrongQuestionItem>[];
      for (final raw in rawList) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final ks = <String>[];
        if (m['knowledges'] is List) {
          for (final k in m['knowledges'] as List) {
            if (k is Map && strOf(k['name']).isNotEmpty) {
              ks.add(strOf(k['name']));
            }
          }
        }
        items.add(
          WrongQuestionItem(
            questionId: strOf(m['questionId']),
            shortName: strOf(m['shortName'], '题目'),
            examId: strOf(m['examId'], examId),
            paperId: strOf(m['paperId']),
            examName: strOf(m['examName'], '考试'),
            examTime: intOf(m['examTime']),
            score: numOf(m['score']),
            myScore: numOf(m['myScore']),
            classAvgScore: numOf(m['classAvgScore']),
            type: intOf(m['type'], 1),
            style: strOf(m['style'], intOf(m['type'], 1) == 2 ? '客观题' : '主观题'),
            myAnswer: strOf(m['myAnswer']),
            answer: strOf(m['answer']),
            stemPictures: validOssUrls(m['pictures']),
            myAnswerPictures: validOssUrls(m['myAnswers']),
            xbAnswerPictures: validOssUrls(m['xbAnswers']),
            knowledges: ks,
          ),
        );
      }

      _wrongExamCache[cacheKey] = (
        items: items,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );
      return items;
    });
  }

  /// Fetch wrong questions for a semester range (`GET /v2/wrong-items/items`)
  Future<List<WrongQuestionItem>> fetchWrongSemesterItems({
    required HfsAccount account,
    required String studentId,
    required String subject,
    required int startMs,
    required int endMs,
    bool allowCache = true,
  }) async {
    return _withAccountLock(account.id, () async {
      final cacheKey =
          '${account.id}:$studentId:$subject:sem:$startMs:$endMs';
      if (allowCache) {
        final hit = _wrongExamCache[cacheKey];
        if (hit != null && DateTime.now().isBefore(hit.expiresAt)) {
          return hit.items;
        }
      }
      await ensureAccount(account, targetStudentId: studentId);
      final p =
          '/v2/wrong-items/items?subject=${Uri.encodeQueryComponent(subject)}&start=$startMs&end=$endMs&pageIndex=1&pageSize=50';
      final res = await _hfsFetch(account, p);
      if (!_isCodeOk(res.body['code'])) {
        throw Exception(strOf(res.body['msg'], '按学期拉取错题失败'));
      }

      List<String> validOssUrls(dynamic raw) {
        if (raw == null) return const <String>[];
        final out = <String>[];
        void addOne(dynamic candidate) {
          if (candidate == null) return;
          if (candidate is List) {
            for (final sub in candidate) {
              addOne(sub);
            }
            return;
          }
          if (candidate is Map) {
            final m = Map<String, dynamic>.from(candidate);
            addOne(m['url'] ?? m['contentPic'] ?? m['answerPic'] ?? m['pic']);
            return;
          }
          final u = strOf(candidate);
          if (u.isEmpty) return;
          final uri = Uri.tryParse(u);
          if (uri != null &&
              uri.scheme == 'https' &&
              uri.host == kHfsOssHost &&
              !out.contains(u)) {
            out.add(u);
          }
        }

        addOne(raw);
        return out;
      }

      final dataField = res.body['data'];
      final List<dynamic> rawList = dataField is List
          ? dataField
          : (dataField is Map && dataField['items'] is List
              ? (dataField['items'] as List)
              : const []);
      final items = <WrongQuestionItem>[];
      for (final raw in rawList) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final ks = <String>[];
        if (m['knowledges'] is List) {
          for (final k in m['knowledges'] as List) {
            if (k is Map && strOf(k['name']).isNotEmpty) {
              ks.add(strOf(k['name']));
            }
          }
        }
        items.add(
          WrongQuestionItem(
            questionId: strOf(m['questionId'] ?? m['id']),
            shortName: strOf(m['shortName'] ?? m['questionNum'], '题目'),
            examId: strOf(m['examId']),
            paperId: strOf(m['paperId']),
            examName: strOf(m['examName'], '学期错题'),
            examTime: intOf(m['examTime'] ?? m['time']),
            score: numOf(m['score'] ?? m['manfen']),
            myScore: numOf(m['myScore']),
            classAvgScore: numOf(m['classAvgScore']),
            type: intOf(m['type'], 1),
            style: strOf(m['style'], intOf(m['type'], 1) == 2 ? '客观题' : '主观题'),
            myAnswer: strOf(m['myAnswer']),
            answer: strOf(m['answer']),
            stemPictures: validOssUrls(m['pictures'] ?? m['kbQuestion']),
            myAnswerPictures: validOssUrls(m['myAnswers'] ?? m['pics']),
            xbAnswerPictures: validOssUrls(m['xbAnswers']),
            knowledges: ks,
          ),
        );
      }

      _wrongExamCache[cacheKey] = (
        items: items,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );
      return items;
    });
  }

  /// Fetch class roster (`GET /v2/students/classmates`)
  Future<List<ClassmateBindEntry>> fetchClassmates(
    HfsAccount account, {
    String studentId = '',
  }) async {
    return _withAccountLock(account.id, () async {
      final prevActive = account.activeStudentId;
      final prevDesired = account.desiredStudentId;
      try {
        await ensureAccount(
          account,
          targetStudentId: studentId,
          forceSwitchSession: studentId.isNotEmpty,
        );
        final res = await _hfsFetch(account, '/v2/students/classmates');
        if (!_isCodeOk(res.body['code']) || res.body['data'] is! List) {
          throw Exception(strOf(res.body['msg'], '获取同班同学名册失败'));
        }
        return (res.body['data'] as List)
            .whereType<Map>()
            .map(
                (e) => ClassmateBindEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } finally {
        final restoreId =
            prevDesired.isNotEmpty ? prevDesired : prevActive;
        if (studentId.isNotEmpty &&
            restoreId.isNotEmpty &&
            restoreId != studentId) {
          try {
            await _hfsFetch(
              account,
              '/v2/user-center/sessions',
              method: 'POST',
              jsonBody: <String, dynamic>{
                'deviceType': 1,
                'studentId': restoreId,
              },
            );
          } catch (_) {}
          account.activeStudentId = prevActive;
          account.desiredStudentId = prevDesired;
        }
      }
    });
  }

  /// Execute read-only upstream diagnostic endpoint (`GET <path>`) for a specific bound student/class
  Future<Map<String, dynamic>> fetchDiagnosticEndpoint(
    HfsAccount account,
    String path, {
    String studentId = '',
  }) async {
    return _withAccountLock(account.id, () async {
      final prevActive = account.activeStudentId;
      final prevDesired = account.desiredStudentId;
      try {
        await ensureAccount(
          account,
          targetStudentId: studentId,
          forceSwitchSession: studentId.isNotEmpty,
        );
        final res = await _hfsFetch(account, path);
        return res.body;
      } finally {
        final restoreId =
            prevDesired.isNotEmpty ? prevDesired : prevActive;
        if (studentId.isNotEmpty &&
            restoreId.isNotEmpty &&
            restoreId != studentId) {
          try {
            await _hfsFetch(
              account,
              '/v2/user-center/sessions',
              method: 'POST',
              jsonBody: <String, dynamic>{
                'deviceType': 1,
                'studentId': restoreId,
              },
            );
          } catch (_) {}
          account.activeStudentId = prevActive;
          account.desiredStudentId = prevDesired;
        }
      }
    });
  }

  Future<void> probeAllStudents(
    HfsAccount account, {
    bool forceRefreshAll = false,
  }) async {
    return _withAccountLock(account.id, () async {
      await _hydrateAccountStudentsUnlocked(account);
      final origStuId = account.activeStudentId;
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final s in account.students) {
        final sid = s.studentId;
        if (sid.isEmpty) continue;
        final existingSnap = account.studentSnapshots[sid];
        if (!forceRefreshAll &&
            existingSnap != null &&
            existingSnap.examId.isNotEmpty &&
            (now - existingSnap.updatedAt) < 10 * 60 * 1000) {
          continue;
        }

        await _hfsFetch(
          account,
          '/v2/user-center/sessions',
          method: 'POST',
          jsonBody: <String, dynamic>{'deviceType': 1, 'studentId': sid},
        );

        final pair = await Future.wait([
          _hfsFetch(account, '/v3/exam/list?start=0')
              .then((r) => r.body)
              .catchError((_) => <String, dynamic>{}),
          _hfsFetch(account, '/v2/wrong-items/overview')
              .then((r) => r.body)
              .catchError((_) => <String, dynamic>{}),
        ]);

        final examIds = <String>{};
        final exData = pair[0]['data'];
        final rList = (exData is Map && exData['list'] is List)
            ? (exData['list'] as List)
            : (exData is List ? exData : const []);
        for (final item in rList) {
          if (item is Map) {
            final id = strOf(item['examId']).isNotEmpty
                ? strOf(item['examId'])
                : strOf(item['id']);
            if (id.isNotEmpty) examIds.add(id);
          }
        }
        if (pair[1]['data'] is List) {
          for (final subj in pair[1]['data'] as List) {
            if (subj is Map && subj['examList'] is List) {
              for (final ex in subj['examList'] as List) {
                if (ex is Map) {
                  final id = strOf(ex['examId']);
                  if (id.isNotEmpty) examIds.add(id);
                }
              }
            }
          }
        }

        if (examIds.isNotEmpty) {
          final sorted = examIds.toList()
            ..sort((a, b) => intOf(b).compareTo(intOf(a)));
          final latestId = sorted.first;
          final detailPair = await Future.wait([
            _hfsFetch(account, '/v3/exam/$latestId/overview')
                .then((r) => r.body)
                .catchError((_) => <String, dynamic>{}),
            _hfsFetch(account, '/v3/exam/$latestId/brief?withSubPapers=1')
                .then((r) => r.body)
                .catchError((_) => <String, dynamic>{}),
          ]);
          final ov = (detailPair[0]['data'] is Map)
              ? Map<String, dynamic>.from(detailPair[0]['data'] as Map)
              : <String, dynamic>{};
          final br = (detailPair[1]['data'] is Map)
              ? Map<String, dynamic>.from(detailPair[1]['data'] as Map)
              : <String, dynamic>{};
          final rawPapers =
              (ov['papers'] is List && (ov['papers'] as List).isNotEmpty)
                  ? (ov['papers'] as List)
                  : ((br['papers'] is List) ? (br['papers'] as List) : const []);
          final sc = numOf(ov['score'] ?? br['score']);
          final mf = numOf(ov['manfen'] ?? br['manfen']);
          final ratio = mf > 0 ? round1((sc / mf) * 100) : null;

          account.studentSnapshots[sid] = StudentSnapshot(
            examId: latestId,
            examName: strOf(ov['name'], strOf(br['name'], '考试')),
            examTime: intOf(ov['time'] ?? br['time']),
            scoreS: strOf(ov['scoreS'], strOf(br['scoreS'], '$sc')),
            manfen: mf,
            ratio: ratio,
            isPartial: rawPapers.isNotEmpty && rawPapers.length < 5,
            reportedPaperCount: rawPapers.length,
            classRankS: strOf(ov['classRankS']),
            gradeRankS: strOf(ov['gradeRankS']),
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
        }
      }

      final restoreStuId = origStuId.isNotEmpty
          ? origStuId
          : (account.desiredStudentId.isNotEmpty
              ? account.desiredStudentId
              : (account.students.isNotEmpty
                  ? account.students.first.studentId
                  : ''));
      if (restoreStuId.isNotEmpty) {
        await _hfsFetch(
          account,
          '/v2/user-center/sessions',
          method: 'POST',
          jsonBody: <String, dynamic>{
            'deviceType': 1,
            'studentId': restoreStuId,
          },
        );
        account.activeStudentId = restoreStuId;
      }
    });
  }

  Future<PaperInspectionData> fetchPaperInspection({
    required HfsAccount account,
    required String studentId,
    required String examId,
    required String paperId,
    required String pid,
    String subject = '',
  }) async {
    return _withAccountLock(account.id, () async {
      await ensureAccount(account, targetStudentId: studentId);
      final cleanPaperId =
          paperId.contains(':') ? paperId.split(':').last : paperId;
      final cleanPid = pid.contains(':') ? pid.split(':').last : pid;

      final answerPath =
          '/v3/exam/${Uri.encodeComponent(examId)}/papers/${Uri.encodeComponent(cleanPaperId)}/answer-picture?pid=${Uri.encodeQueryComponent(cleanPid)}';
      final qDetailPath =
          '/v3/exam/${Uri.encodeComponent(examId)}/papers/${Uri.encodeComponent(cleanPaperId)}/question-detail';

      final futures = <Future<Map<String, dynamic>>>[
        _hfsFetch(account, answerPath).then((r) => r.body),
        _hfsFetch(account, qDetailPath)
            .then((r) => r.body)
            .catchError((_) => <String, dynamic>{}),
        if (subject.trim().isNotEmpty)
          _hfsFetch(
            account,
            '/v2/wrong-items/exam-items?subject=${Uri.encodeQueryComponent(subject.trim())}&examId=${Uri.encodeQueryComponent(examId)}',
          ).then((r) => r.body).catchError((_) => <String, dynamic>{}),
        if (subject.contains('与社会'))
          _hfsFetch(
            account,
            '/v2/wrong-items/exam-items?subject=${Uri.encodeQueryComponent(subject.replaceAll('与社会', '').trim())}&examId=${Uri.encodeQueryComponent(examId)}',
          ).then((r) => r.body).catchError((_) => <String, dynamic>{}),
      ];

      final resList = await Future.wait(futures);
      final ansBody = resList[0];
      if (!_isCodeOk(ansBody['code'])) {
        throw Exception(strOf(ansBody['msg'], '调阅答题卡失败'));
      }

      final source = (ansBody['data'] is Map)
          ? Map<String, dynamic>.from(ansBody['data'] as Map)
          : <String, dynamic>{};

      List<String> validOssUrls(dynamic items) {
        if (items == null) return const <String>[];
        final out = <String>[];
        void addOne(dynamic candidate) {
          if (candidate == null) return;
          if (candidate is List) {
            for (final sub in candidate) {
              addOne(sub);
            }
            return;
          }
          if (candidate is Map) {
            final m = Map<String, dynamic>.from(candidate);
            addOne(m['url'] ?? m['contentPic'] ?? m['answerPic'] ?? m['pic']);
            return;
          }
          final u = strOf(candidate);
          if (u.isEmpty) return;
          final uri = Uri.tryParse(u);
          if (uri != null &&
              uri.scheme == 'https' &&
              uri.host == kHfsOssHost &&
              !out.contains(u)) {
            out.add(u);
          }
        }

        addOne(items);
        return out;
      }

      // Collect origin question stem pictures & xbAnswers from question-detail and wrong-items/exam-items
      final stemByQId = <String, List<String>>{};
      final stemByQName = <String, List<String>>{};
      final xbByQId = <String, List<String>>{};
      final xbByQName = <String, List<String>>{};
      final myCropByQName = <String, List<String>>{};
      final knowledgeByQName = <String, List<String>>{};

      void mergeStem(String qid, String qName, List<String> urls) {
        if (urls.isEmpty) return;
        if (qid.isNotEmpty) {
          final list = stemByQId.putIfAbsent(qid, () => []);
          for (final u in urls) {
            if (!list.contains(u)) list.add(u);
          }
        }
        if (qName.isNotEmpty) {
          final list = stemByQName.putIfAbsent(qName, () => []);
          for (final u in urls) {
            if (!list.contains(u)) list.add(u);
          }
        }
      }

      void mergeXb(String qid, String qName, List<String> urls) {
        if (urls.isEmpty) return;
        if (qid.isNotEmpty) {
          final list = xbByQId.putIfAbsent(qid, () => []);
          for (final u in urls) {
            if (!list.contains(u)) list.add(u);
          }
        }
        if (qName.isNotEmpty) {
          final list = xbByQName.putIfAbsent(qName, () => []);
          for (final u in urls) {
            if (!list.contains(u)) list.add(u);
          }
        }
      }

      final qdData = (resList[1]['data'] is Map)
          ? Map<String, dynamic>.from(resList[1]['data'] as Map)
          : const <String, dynamic>{};
      if (qdData['questionList'] is List) {
        for (final rq in qdData['questionList'] as List) {
          if (rq is! Map) continue;
          final m = Map<String, dynamic>.from(rq);
          final qid = strOf(m['id']);
          final qName = strOf(m['name']);
          mergeStem(qid, qName, validOssUrls(m['pictures']));
          mergeXb(qid, qName, validOssUrls(m['xbAnswerPics']));
        }
      }

      for (var idx = 2; idx < resList.length; idx++) {
        final wiBody = resList[idx];
        if (wiBody['data'] is List) {
          for (final rw in wiBody['data'] as List) {
            if (rw is! Map) continue;
            final m = Map<String, dynamic>.from(rw);
            final qid = strOf(m['questionId']);
            final qName = strOf(m['shortName']);
            mergeStem(qid, qName, validOssUrls(m['pictures']));
            mergeXb(qid, qName, validOssUrls(m['xbAnswers']));
            final myAns = validOssUrls(m['myAnswers']);
            if (qName.isNotEmpty && myAns.isNotEmpty) {
              myCropByQName[qName] = myAns;
            }
            if (qName.isNotEmpty && m['knowledges'] is List) {
              final ks = <String>[];
              for (final k in m['knowledges'] as List) {
                if (k is Map && strOf(k['name']).isNotEmpty) {
                  ks.add(strOf(k['name']));
                }
              }
              if (ks.isNotEmpty) knowledgeByQName[qName] = ks;
            }
          }
        }
      }

      final originalPages = validOssUrls(source['paperPic']);
      final answerPages = validOssUrls(source['url']);
      final overlayCalc = _buildPaperOverlays(source);

      final rawQs = (source['questions'] is List)
          ? (source['questions'] as List)
          : const [];
      final questions = <QuestionDetailItem>[];
      for (final rq in rawQs) {
        if (rq is! Map) continue;
        final qm = Map<String, dynamic>.from(rq);
        final qid = strOf(qm['id']);
        final qName = strOf(qm['name']);
        final ks = <String>[];
        if (qm['knowledges'] is List) {
          for (final k in qm['knowledges'] as List) {
            if (k is Map && strOf(k['name']).isNotEmpty) {
              ks.add(strOf(k['name']));
            }
          }
        }
        if (ks.isEmpty && knowledgeByQName.containsKey(qName)) {
          ks.addAll(knowledgeByQName[qName]!);
        }

        final directStems = validOssUrls(qm['pictures']);
        final stems = <String>{
          ...directStems,
          ...?stemByQId[qid],
          ...?stemByQName[qName],
        }.toList();

        final crops = validOssUrls(qm['url']);
        final mergedCrops = crops.isNotEmpty
            ? crops
            : (myCropByQName[qName] ?? const <String>[]);

        final xbList = <String>{
          ...?xbByQId[qid],
          ...?xbByQName[qName],
        }.toList();

        questions.add(
          QuestionDetailItem(
            id: qid,
            name: qName,
            score: numOf(qm['score']),
            scoreS: strOf(qm['scoreS'], '${numOf(qm['score'])}'),
            manfen: numOf(qm['manfen']),
            type: intOf(qm['type'], 1),
            myAnswer: strOf(qm['myAnswer']),
            answer: strOf(qm['answer']),
            stemUrls: stems,
            cropUrls: mergedCrops,
            xbAnswerUrls: xbList,
            knowledges: ks,
          ),
        );
      }

      return PaperInspectionData(
        studentId: account.activeStudentId.isNotEmpty
            ? account.activeStudentId
            : studentId,
        totalScore: overlayCalc.totalScore,
        objectScore: overlayCalc.objectScore,
        subjectScore: overlayCalc.subjectScore,
        originalPages: originalPages,
        answerPages: answerPages,
        pageOverlays: overlayCalc.pageOverlays,
        questions: questions,
      );
    });
  }

  Future<Uint8List> fetchOssImageBytes(String imageUrl) async {
    final hit = _imgCache[imageUrl];
    if (hit != null && DateTime.now().isBefore(hit.expiresAt)) {
      return hit.bytes;
    }
    final uri = Uri.parse(imageUrl);
    if (uri.scheme != 'https' || uri.host != kHfsOssHost) {
      throw StateError('图片来源未获允许 (仅允许 https://$kHfsOssHost)');
    }
    final resp = await _http
        .get(
          uri,
          headers: const {
            'Accept': 'image/*,*/*;q=0.8',
            'User-Agent': 'YX Android 14',
          },
        )
        .timeout(const Duration(seconds: 25));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('原图下载失败 (HTTP ${resp.statusCode})');
    }
    if (resp.bodyBytes.length > 20 * 1024 * 1024) {
      throw Exception('图片体积超过 20MB 安全上限');
    }
    if (_imgCache.length >= 64) {
      _imgCache.remove(_imgCache.keys.first);
    }
    _imgCache[imageUrl] = (
      bytes: resp.bodyBytes,
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
    return resp.bodyBytes;
  }

  static String _decodeUriSafe(String raw) {
    try {
      return Uri.decodeFull(raw.replaceAll('+', '%2B'));
    } catch (_) {
      return raw;
    }
  }

  static Map<String, int>? _parseCropMeta(String urlText) {
    final s = _decodeUriSafe(urlText);
    final m = _cropMetaRe.firstMatch(s);
    if (m == null) return null;
    return <String, int>{
      'x': int.tryParse(m.group(1) ?? '') ?? 0,
      'y': int.tryParse(m.group(2) ?? '') ?? 0,
      'w': int.tryParse(m.group(3) ?? '') ?? 0,
      'h': int.tryParse(m.group(4) ?? '') ?? 0,
    };
  }

  static String _normalizeImageKey(String urlText) {
    final raw = _decodeUriSafe(urlText);
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.host.isNotEmpty) {
      return '${uri.host}${uri.path}'.replaceAll(_cropTailRe, '');
    }
    final base = raw.split('?').first;
    return base.replaceAll(_cropTailRe, '');
  }

  ({
    double totalScore,
    double objectScore,
    double subjectScore,
    List<PageOverlayData> pageOverlays,
  }) _buildPaperOverlays(Map<String, dynamic> source) {
    final pageUrls =
        (source['url'] is List) ? (source['url'] as List) : const [];
    final pageKeys = <String>[
      for (final u in pageUrls) _normalizeImageKey(strOf(u)),
    ];
    final objectivesPerPage = <int, List<ObjectiveMark>>{
      for (var i = 0; i < pageUrls.length; i++) i: <ObjectiveMark>[],
    };
    final blocksPerPage = <int, List<SubjectiveBlock>>{
      for (var i = 0; i < pageUrls.length; i++) i: <SubjectiveBlock>[],
    };

    final questions = (source['questions'] is List)
        ? (source['questions'] as List)
        : const [];
    final isConvert = boolOf(source['isScoreConvert']);
    double objectScore = 0;
    double subjectScore = 0;

    final blockOrder = <String>[];
    final blockMap = <String, SubjectiveBlock>{};

    for (final rq in questions) {
      if (rq is! Map) continue;
      final q = Map<String, dynamic>.from(rq);
      final qType = intOf(q['type'], 1);
      final sc = numOf(q['score']);
      final mf = numOf(q['manfen']);
      var ratio = numOf(q['trasRatio'], 1);
      if (ratio == 0) ratio = 1;

      if (sc >= 0) {
        final val = isConvert ? sc * ratio : sc;
        if (qType == 2) {
          objectScore += val;
        } else if (qType == 1) {
          subjectScore += val;
        }
      }

      if (q['answerOption'] is List && pageUrls.isNotEmpty) {
        for (final ro in q['answerOption'] as List) {
          if (ro is! Map) continue;
          final opt = Map<String, dynamic>.from(ro);
          var pIdx = intOf(opt['index']);
          if (pIdx < 0 || pIdx >= pageUrls.length) pIdx = 0;
          var w = numOf(opt['w'], 30);
          if (w == 0) w = 30;
          var h = numOf(opt['h'], 24);
          if (h == 0) h = 24;
          final isRight =
              intOf(opt['right']) == 1 || ((sc - mf).abs() < 0.01 && mf > 0);
          objectivesPerPage[pIdx]!.add(
            ObjectiveMark(
              qName: strOf(q['name']),
              option: strOf(opt['option'], strOf(q['myAnswer'])),
              stdAnswer: strOf(q['answer']),
              x: numOf(opt['x']),
              y: numOf(opt['y']),
              w: w,
              h: h,
              isRight: isRight,
              score: sc,
              scoreS: strOf(q['scoreS'], '$sc'),
              manfen: mf,
            ),
          );
        }
      }

      final qUrls = (q['url'] is List) ? (q['url'] as List) : const [];
      for (var uIdx = 0; uIdx < qUrls.length; uIdx++) {
        final rawUrl = strOf(qUrls[uIdx]);
        final meta = _parseCropMeta(rawUrl);
        if (meta == null) continue;
        final key = _normalizeImageKey(rawUrl);
        var pIdx = -1;
        for (var idx = 0; idx < pageKeys.length; idx++) {
          if (pageKeys[idx] == key) {
            pIdx = idx;
            break;
          }
        }
        if (pIdx < 0) {
          final fallbackPage = intOf(q['pageIndex'] ?? q['index'], -1);
          if (fallbackPage >= 0 && fallbackPage < pageUrls.length) {
            pIdx = fallbackPage;
          } else if (pageUrls.length == 1) {
            pIdx = 0;
          } else {
            continue;
          }
        }
        final bKey =
            '$pIdx:${meta['x']}:${meta['y']}:${meta['w']}:${meta['h']}';
        final qName = strOf(q['name']);
        final itemSc = strOf(q['scoreS'], '$sc');
        var blk = blockMap[bKey];
        if (blk == null) {
          blk = SubjectiveBlock(
            pageIndex: pIdx,
            qNames: <String>[qName],
            x: meta['x']!,
            y: meta['y']!,
            w: meta['w']!,
            h: meta['h']!,
            score: sc,
            manfen: mf,
            itemScores: <String>[itemSc],
            drawScore: uIdx == 0,
            remarks: <SubjectiveRemark>[],
          );
          blockMap[bKey] = blk;
          blockOrder.add(bKey);
        } else {
          if (!blk.qNames.contains(qName)) blk.qNames.add(qName);
          blk.score = round2(blk.score + sc);
          blk.manfen = round2(blk.manfen + mf);
          blk.itemScores.add(itemSc);
        }

        if (q['remark2'] is List) {
          for (final rrm in q['remark2'] as List) {
            if (rrm is! Map) continue;
            final rm = Map<String, dynamic>.from(rrm);
            if (rm['i'] == null || intOf(rm['i']) == uIdx) {
              blk.remarks.add(
                SubjectiveRemark(
                  type: intOf(rm['type']),
                  x: numOf(rm['x']),
                  y: numOf(rm['y']),
                  w: numOf(rm['w']),
                  h: numOf(rm['h']),
                  content: strOf(rm['content']),
                ),
              );
            }
          }
        }
      }
    }

    for (final bKey in blockOrder) {
      final blk = blockMap[bKey]!;
      if (pageUrls.isEmpty) continue;
      var pIdx = blk.pageIndex;
      if (pIdx < 0 || pIdx >= pageUrls.length) pIdx = 0;
      blocksPerPage[pIdx]!.add(blk);
    }

    var totalScore = objectScore + subjectScore;
    if (source['score'] != null) {
      totalScore = numOf(source['score'], totalScore);
    }
    if (boolOf(source['isShuangPing']) && totalScore > 0) {
      subjectScore = math.max(0, round2(totalScore - objectScore));
    }

    final overlays = <PageOverlayData>[
      for (var i = 0; i < pageUrls.length; i++)
        PageOverlayData(
          pageIndex: i,
          objectives: objectivesPerPage[i]!,
          blocks: blocksPerPage[i]!,
        ),
    ];

    return (
      totalScore: round2(totalScore),
      objectScore: round2(objectScore),
      subjectScore: round2(subjectScore),
      pageOverlays: overlays,
    );
  }
}

class _ExamSeed {
  final String examId;
  final String examName;
  final int examTime;
  final Map<String, int> wrongBySubject = <String, int>{};
  int totalWrong = 0;

  _ExamSeed({
    required this.examId,
    required this.examName,
    required this.examTime,
  });
}
