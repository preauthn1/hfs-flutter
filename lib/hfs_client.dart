import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'hfs_models.dart';

class HfsUpstreamClient {
  /// Strictly connects ONLY to official Haofenshu upstream hosts:
  /// - API: https://hfs-be.yunxiao.com
  /// - OSS exam images: https://yj-oss.yunxiao.com
  static const String kHfsApiHost = 'hfs-be.yunxiao.com';
  static const String kHfsOssHost = 'yj-oss.yunxiao.com';
  static const String kHfsBaseUrl = 'https://hfs-be.yunxiao.com';

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

  static void assertAllowedHost(Uri uri) {
    if (uri.scheme != 'https' ||
        (uri.host != kHfsApiHost && uri.host != kHfsOssHost)) {
      throw StateError('安全策略拦截：仅允许连接好分数官方后端 ($kHfsApiHost / $kHfsOssHost)');
    }
  }

  static String accountIdFor(String loginName, int roleType) {
    final digest =
        sha256.convert(utf8.encode('$roleType:${loginName.trim()}')).bytes;
    return base64UrlEncode(digest).replaceAll('=', '').substring(0, 14);
  }

  Map<String, String> _roleHeaders(int roleType, {List<String>? cookies}) {
    final headers = <String, String>{
      'deviceType': '1',
      'appType': roleType == 1 ? '1' : '2',
      'versionName': '4.31.81',
      'User-Agent': 'YX Android 14',
      'Accept': 'application/json',
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
        (code != 0 && code != 1 && code != 11)) {
      if (code == 4046) {
        final roleLabel = roleType == 1 ? '学生版' : '家长版';
        throw Exception('账号或密码错误（当前选择：$roleLabel）');
      }
      throw Exception(strOf(body['msg'], '好分数登录失败'));
    }
    return jar;
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

  Future<Map<String, dynamic>> ensureAccount(
    HfsAccount account, {
    String targetStudentId = '',
  }) async {
    var check = await _hfsFetch(
      account,
      '/v2/user-center/user-snapshot?devicetype=1',
    );
    if (intOf(check.body['code'], -1) == 3001 ||
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
        : account.desiredStudentId;
    var dataMap = (check.body['data'] is Map)
        ? Map<String, dynamic>.from(check.body['data'] as Map)
        : <String, dynamic>{};
    var linked = (dataMap['linkedStudent'] is Map)
        ? Map<String, dynamic>.from(dataMap['linkedStudent'] as Map)
        : <String, dynamic>{};
    final curLinkedId = strOf(linked['studentId']).isNotEmpty
        ? strOf(linked['studentId'])
        : strOf(linked['id']);

    if (wantStu.isNotEmpty && wantStu != curLinkedId) {
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
      }
    }
    return dataMap;
  }

  Future<Map<String, dynamic>> hydrateAccountStudents(HfsAccount account) async {
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
      if (account.students.isEmpty) {
        account.students = <StudentInfo>[linkedStu];
      }
    }
    account.lastRefreshAt = DateTime.now().millisecondsSinceEpoch;
    return snapData;
  }

  void invalidateCache(String accountId) {
    _dashCache.removeWhere(
        (key, _) => key == accountId || key.startsWith('$accountId:'));
  }

  Future<DashboardData> fetchDashboard(
    HfsAccount account, {
    bool allowCache = true,
  }) async {
    final snapData = await hydrateAccountStudents(account);
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

      wrongSummaries.add(
        WrongSubjectSummary(
          subject: sName,
          noReview: intOf(sm['noReview']),
          semesters: semList
              .whereType<Map>()
              .map((s) => WrongSemesterItem(
                    name: strOf(s['name']),
                    wrongNum: intOf(s['wrongNum']),
                  ))
              .toList(),
          examCount: exList.length,
        ),
      );

      for (final rawEx in exList) {
        if (rawEx is! Map) continue;
        final em = Map<String, dynamic>.from(rawEx);
        final id = strOf(em['examId']);
        if (id.isEmpty) continue;
        final seed = examSeeds.putIfAbsent(
          id,
          () => _ExamSeed(
            examId: id,
            examName: strOf(em['examName'], '考试'),
            examTime: intOf(em['examTime']),
          ),
        );
        final wn = intOf(em['wrongNum']);
        seed.wrongBySubject[sName] = wn;
        seed.totalWrong += wn;
      }
    }

    final sortedSeeds = examSeeds.values.toList()
      ..sort((a, b) {
        if (a.examTime != b.examTime) return b.examTime.compareTo(a.examTime);
        return b.examId.compareTo(a.examId);
      });
    final cappedSeeds = sortedSeeds.take(15).toList();

    final hydratedExams = <ExamRecord>[];
    for (var i = 0; i < cappedSeeds.length; i += 4) {
      final batch = cappedSeeds.skip(i).take(4);
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
    );

    _dashCache[cacheKey] = (
      data: dash,
      expiresAt: DateTime.now().add(const Duration(seconds: 45)),
    );
    return dash;
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
    String studentId,
  ) async {
    account.desiredStudentId = studentId;
    await ensureAccount(account, targetStudentId: studentId);
    account.activeStudentId = studentId;
    return fetchDashboard(account, allowCache: false);
  }

  Future<DashboardData> bindStudent({
    required HfsAccount account,
    required String studentName,
    required String identityCode,
    String? schoolAuthCode,
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
    final targetId = strOf(targetStu['studentId']);

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
    await ensureAccount(account, targetStudentId: targetId);
    account.activeStudentId = targetId;
    invalidateCache(account.id);
    return fetchDashboard(account, allowCache: false);
  }

  Future<void> probeAllStudents(HfsAccount account) async {
    await hydrateAccountStudents(account);
    final origStuId = account.activeStudentId;

    for (final s in account.students) {
      final sid = s.studentId;
      if (sid.isEmpty) continue;
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
        final rawPapers = (ov['papers'] is List && (ov['papers'] as List).isNotEmpty)
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

    if (origStuId.isNotEmpty) {
      await _hfsFetch(
        account,
        '/v2/user-center/sessions',
        method: 'POST',
        jsonBody: <String, dynamic>{'deviceType': 1, 'studentId': origStuId},
      );
      account.activeStudentId = origStuId;
    }
    invalidateCache(account.id);
  }

  Future<PaperInspectionData> fetchPaperInspection({
    required HfsAccount account,
    required String studentId,
    required String examId,
    required String paperId,
    required String pid,
  }) async {
    await ensureAccount(account, targetStudentId: studentId);
    final cleanPaperId =
        paperId.contains(':') ? paperId.split(':').last : paperId;
    final cleanPid = pid.contains(':') ? pid.split(':').last : pid;

    final path =
        '/v3/exam/${Uri.encodeComponent(examId)}/papers/${Uri.encodeComponent(cleanPaperId)}/answer-picture?pid=${Uri.encodeQueryComponent(cleanPid)}';
    final res = await _hfsFetch(account, path);
    if (!_isCodeOk(res.body['code'])) {
      throw Exception(strOf(res.body['msg'], '调阅答题卡失败'));
    }

    final source = (res.body['data'] is Map)
        ? Map<String, dynamic>.from(res.body['data'] as Map)
        : <String, dynamic>{};

    List<String> validOssUrls(dynamic items) {
      if (items is! List) return const <String>[];
      final out = <String>[];
      for (final it in items) {
        final u = strOf(it);
        if (u.isEmpty) continue;
        final uri = Uri.tryParse(u);
        if (uri != null && uri.scheme == 'https' && uri.host == kHfsOssHost) {
          out.add(u);
        }
      }
      return out;
    }

    final originalPages = validOssUrls(source['paperPic']);
    final answerPages = validOssUrls(source['url']);
    final overlayCalc = _buildPaperOverlays(source);

    final rawQs =
        (source['questions'] is List) ? (source['questions'] as List) : const [];
    final questions = <QuestionDetailItem>[];
    for (final rq in rawQs) {
      if (rq is! Map) continue;
      final qm = Map<String, dynamic>.from(rq);
      final ks = <String>[];
      if (qm['knowledges'] is List) {
        for (final k in qm['knowledges'] as List) {
          if (k is Map && strOf(k['name']).isNotEmpty) {
            ks.add(strOf(k['name']));
          }
        }
      }
      questions.add(
        QuestionDetailItem(
          id: strOf(qm['id']),
          name: strOf(qm['name']),
          score: numOf(qm['score']),
          scoreS: strOf(qm['scoreS'], '${numOf(qm['score'])}'),
          manfen: numOf(qm['manfen']),
          type: intOf(qm['type'], 1),
          myAnswer: strOf(qm['myAnswer']),
          answer: strOf(qm['answer']),
          cropUrls: validOssUrls(qm['url']),
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
        .get(uri, headers: const {'Accept': 'image/*,*/*;q=0.8'})
        .timeout(const Duration(seconds: 25));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('答题卡原图下载失败 (HTTP ${resp.statusCode})');
    }
    if (resp.bodyBytes.length > 20 * 1024 * 1024) {
      throw Exception('图片体积超过 20MB 安全上限');
    }
    if (_imgCache.length >= 48) {
      _imgCache.remove(_imgCache.keys.first);
    }
    _imgCache[imageUrl] = (
      bytes: resp.bodyBytes,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
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
        var pIdx = 0;
        for (var idx = 0; idx < pageKeys.length; idx++) {
          if (pageKeys[idx] == key) {
            pIdx = idx;
            break;
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
