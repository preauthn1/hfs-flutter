import 'dart:math' as math;

const List<String> kSubjectOrder = <String>[
  '语文',
  '数学',
  '英语',
  '科学',
  '历史与社会',
  '历史',
  '道德与法治',
  '物理',
  '化学',
  '生物',
  '地理',
];

String strOf(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

double numOf(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  final parsed = double.tryParse(v.toString().trim());
  return parsed ?? fallback;
}

int intOf(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.round();
  final parsed = int.tryParse(v.toString().trim());
  if (parsed != null) return parsed;
  final d = double.tryParse(v.toString().trim());
  return d?.round() ?? fallback;
}

bool boolOf(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  return s == 'true' || s == '1';
}

double round1(double v) => (v * 10).roundToDouble() / 10;
double round2(double v) => (v * 100).roundToDouble() / 100;

int subjectIndex(String subject) {
  final idx = kSubjectOrder.indexOf(subject);
  return idx >= 0 ? idx : 999;
}

String maskLoginName(String raw) {
  final s = raw.trim();
  if (s.length <= 4) return s;
  if (s.length >= 11) {
    return '${s.substring(0, 3)}••••${s.substring(s.length - 4)}';
  }
  return '${s.substring(0, 2)}•••${s.substring(s.length - 2)}';
}

String formatDateMs(int ms) {
  if (ms <= 0) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class AppSettings {
  final int maxExamsToHydrate;
  final int examConcurrency;
  final bool defaultGradingOverlay;
  final bool autoHydrateOnSwitch;
  final double inspectorWidth;

  const AppSettings({
    this.maxExamsToHydrate = 10,
    this.examConcurrency = 4,
    this.defaultGradingOverlay = true,
    this.autoHydrateOnSwitch = false,
    this.inspectorWidth = 460.0,
  });

  AppSettings copyWith({
    int? maxExamsToHydrate,
    int? examConcurrency,
    bool? defaultGradingOverlay,
    bool? autoHydrateOnSwitch,
    double? inspectorWidth,
  }) {
    return AppSettings(
      maxExamsToHydrate: (maxExamsToHydrate ?? this.maxExamsToHydrate).clamp(3, 30),
      examConcurrency: (examConcurrency ?? this.examConcurrency).clamp(1, 8),
      defaultGradingOverlay: defaultGradingOverlay ?? this.defaultGradingOverlay,
      autoHydrateOnSwitch: autoHydrateOnSwitch ?? this.autoHydrateOnSwitch,
      inspectorWidth: (inspectorWidth ?? this.inspectorWidth).clamp(360.0, 680.0),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'maxExamsToHydrate': maxExamsToHydrate,
        'examConcurrency': examConcurrency,
        'defaultGradingOverlay': defaultGradingOverlay,
        'autoHydrateOnSwitch': autoHydrateOnSwitch,
        'inspectorWidth': inspectorWidth,
      };

  factory AppSettings.fromJson(Map<String, dynamic> m) {
    return AppSettings(
      maxExamsToHydrate: intOf(m['maxExamsToHydrate'], 10).clamp(3, 30),
      examConcurrency: intOf(m['examConcurrency'], 4).clamp(1, 8),
      defaultGradingOverlay:
          m['defaultGradingOverlay'] == null ? true : boolOf(m['defaultGradingOverlay']),
      autoHydrateOnSwitch: boolOf(m['autoHydrateOnSwitch']),
      inspectorWidth: numOf(m['inspectorWidth'], 460.0).clamp(360.0, 680.0),
    );
  }
}

class StudentSnapshot {
  final String examId;
  final String examName;
  final int examTime;
  final String scoreS;
  final double manfen;
  final double? ratio;
  final bool isPartial;
  final int reportedPaperCount;
  final String classRankS;
  final String gradeRankS;
  final int updatedAt;

  const StudentSnapshot({
    required this.examId,
    required this.examName,
    required this.examTime,
    required this.scoreS,
    required this.manfen,
    this.ratio,
    this.isPartial = false,
    this.reportedPaperCount = 0,
    this.classRankS = '',
    this.gradeRankS = '',
    this.updatedAt = 0,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'examId': examId,
        'examName': examName,
        'examTime': examTime,
        'scoreS': scoreS,
        'manfen': manfen,
        'ratio': ratio,
        'isPartial': isPartial,
        'reportedPaperCount': reportedPaperCount,
        'classRankS': classRankS,
        'gradeRankS': gradeRankS,
        'updatedAt': updatedAt,
      };

  factory StudentSnapshot.fromJson(Map<String, dynamic> m) {
    return StudentSnapshot(
      examId: strOf(m['examId']),
      examName: strOf(m['examName'], '考试'),
      examTime: intOf(m['examTime']),
      scoreS: strOf(m['scoreS'], '0'),
      manfen: numOf(m['manfen']),
      ratio: m['ratio'] == null ? null : numOf(m['ratio']),
      isPartial: boolOf(m['isPartial']),
      reportedPaperCount: intOf(m['reportedPaperCount']),
      classRankS: strOf(m['classRankS']),
      gradeRankS: strOf(m['gradeRankS']),
      updatedAt: intOf(m['updatedAt']),
    );
  }
}

class StudentInfo {
  final String studentId;
  final String studentName;
  final String schoolName;
  final String grade;
  final String className;
  final String xuehao;
  final int isVirtual;
  final int linkedTime;
  final int changeBindTime;

  const StudentInfo({
    required this.studentId,
    required this.studentName,
    required this.schoolName,
    required this.grade,
    required this.className,
    required this.xuehao,
    required this.isVirtual,
    this.linkedTime = 0,
    this.changeBindTime = 0,
  });

  /// `-1` means legacy permanent unlocked slot (`随时可换`).
  /// Consuming it via rebind writes `linkedTime + 180d` and reduces max quota by 1.
  bool get isMinusOneSlot => changeBindTime == -1;

  /// Locked when `changeBindTime` is a future timestamp (`linkedTime + 180d`).
  bool get isSemesterLocked =>
      changeBindTime > 0 &&
      changeBindTime > DateTime.now().millisecondsSinceEpoch;

  /// Whether this student slot can currently be rebound without triggering semester lock `4137`.
  bool get canRebindNow => !isSemesterLocked;

  String get changeBindStatusLabel {
    if (changeBindTime == -1) {
      return '随时可换 (-1活名额)';
    }
    if (changeBindTime > 0) {
      final dateStr = formatDateMs(changeBindTime);
      if (changeBindTime > DateTime.now().millisecondsSinceEpoch) {
        return '锁定至 $dateStr';
      }
      return '可换绑 ($dateStr已解锁)';
    }
    return '待刷新锁状态';
  }

  String get changeBindShortBadge {
    if (changeBindTime == -1) return '-1活名额';
    if (changeBindTime > 0) {
      final dateStr = formatDateMs(changeBindTime);
      if (changeBindTime > DateTime.now().millisecondsSinceEpoch) {
        return '锁至$dateStr';
      }
      return '可换绑';
    }
    return '';
  }

  factory StudentInfo.fromUpstream(Map<String, dynamic> s) {
    final sid = strOf(s['studentId']).isNotEmpty
        ? strOf(s['studentId'])
        : strOf(s['id']);
    String xh = '';
    if (s['xuehao'] is List && (s['xuehao'] as List).isNotEmpty) {
      xh = strOf((s['xuehao'] as List).first);
    } else {
      xh = strOf(s['xuehao']);
    }
    if (xh.isEmpty) {
      if (s['kaohao'] is List && (s['kaohao'] as List).isNotEmpty) {
        xh = strOf((s['kaohao'] as List).first);
      } else {
        xh = strOf(s['kaohao']);
      }
    }
    return StudentInfo(
      studentId: sid,
      studentName: strOf(s['studentName'], strOf(s['name'], '学生')),
      schoolName: strOf(s['schoolName']),
      grade: strOf(s['grade']).isNotEmpty ? strOf(s['grade']) : strOf(s['sgrade']),
      className: strOf(s['class']).isNotEmpty
          ? strOf(s['class'])
          : strOf(s['className']),
      xuehao: xh,
      isVirtual: intOf(s['isVirtual'], 2),
      linkedTime: intOf(s['linkedTime'], 0),
      changeBindTime: intOf(s['changeBindTime'], 0),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'studentId': studentId,
        'studentName': studentName,
        'schoolName': schoolName,
        'grade': grade,
        'className': className,
        'xuehao': xuehao,
        'isVirtual': isVirtual,
        'linkedTime': linkedTime,
        'changeBindTime': changeBindTime,
      };
}

class HfsAccount {
  final String id;
  String label;
  final int roleType; // 2 = 家长版, 1 = 学生版
  final String loginName;
  final String password;
  List<String> cookies;
  List<StudentInfo> students;
  String activeStudentId;
  String desiredStudentId;
  Map<String, StudentSnapshot> studentSnapshots;
  String state;
  int lastRefreshAt;

  HfsAccount({
    required this.id,
    required this.label,
    required this.roleType,
    required this.loginName,
    required this.password,
    required this.cookies,
    required this.students,
    this.activeStudentId = '',
    this.desiredStudentId = '',
    Map<String, StudentSnapshot>? studentSnapshots,
    this.state = 'connected',
    this.lastRefreshAt = 0,
  }) : studentSnapshots = studentSnapshots ?? <String, StudentSnapshot>{};

  String get maskedLogin => maskLoginName(loginName);

  String get displayLabel =>
      label.trim().isNotEmpty ? label.trim() : maskedLogin;

  StudentInfo? get activeStudent {
    if (students.isEmpty) return null;
    for (final s in students) {
      if (s.studentId == activeStudentId) return s;
    }
    return students.first;
  }

  String get activeStudentName =>
      activeStudent?.studentName ?? displayLabel;

  /// Count of legacy `changeBindTime == -1` slots on this account
  int get minusOneSlotCount =>
      students.where((s) => s.changeBindTime == -1).length;

  /// Exact Haofenshu quota formula: `max_total = min(6, count(changeBindTime == -1) + 3)`
  int get estimatedMaxQuota => math.min(6, minusOneSlotCount + 3);

  /// Remaining direct-add slots before hitting `4010` / `4025`
  int get remainingAddQuota =>
      math.max(0, estimatedMaxQuota - students.length);

  bool get isQuotaFull => students.length >= estimatedMaxQuota;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'roleType': roleType,
        'loginName': loginName,
        'password': password,
        'cookies': cookies,
        'students': students.map((e) => e.toJson()).toList(),
        'activeStudentId': activeStudentId,
        'desiredStudentId': desiredStudentId,
        'studentSnapshots':
            studentSnapshots.map((k, v) => MapEntry(k, v.toJson())),
        'state': state,
        'lastRefreshAt': lastRefreshAt,
      };

  factory HfsAccount.fromJson(Map<String, dynamic> m) {
    final rawCookies = (m['cookies'] as List?) ?? const [];
    final rawStudents = (m['students'] as List?) ?? const [];
    final rawSnaps = (m['studentSnapshots'] as Map?) ?? const {};
    final snaps = <String, StudentSnapshot>{};
    rawSnaps.forEach((k, v) {
      if (v is Map) {
        snaps[k.toString()] =
            StudentSnapshot.fromJson(Map<String, dynamic>.from(v));
      }
    });
    return HfsAccount(
      id: strOf(m['id']),
      label: strOf(m['label']),
      roleType: intOf(m['roleType'], 2),
      loginName: strOf(m['loginName']),
      password: strOf(m['password']),
      cookies: rawCookies.map((e) => e.toString()).toList(),
      students: rawStudents
          .whereType<Map>()
          .map((e) => StudentInfo.fromUpstream(Map<String, dynamic>.from(e)))
          .toList(),
      activeStudentId: strOf(m['activeStudentId']),
      desiredStudentId: strOf(m['desiredStudentId']).isNotEmpty
          ? strOf(m['desiredStudentId'])
          : strOf(m['activeStudentId']),
      studentSnapshots: snaps,
      state: strOf(m['state'], 'connected'),
      lastRefreshAt: intOf(m['lastRefreshAt']),
    );
  }
}

class PaperScore {
  final String paperId;
  final String pid;
  final String subject;
  final String name;
  final double score;
  final String scoreS;
  final double manfen;
  final double? ratio;
  final int? wrongNum;

  const PaperScore({
    required this.paperId,
    required this.pid,
    required this.subject,
    required this.name,
    required this.score,
    required this.scoreS,
    required this.manfen,
    this.ratio,
    this.wrongNum,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'paperId': paperId,
        'pid': pid,
        'subject': subject,
        'name': name,
        'score': score,
        'scoreS': scoreS,
        'manfen': manfen,
        'ratio': ratio,
        'wrongNum': wrongNum,
      };

  factory PaperScore.fromJson(Map<String, dynamic> m) => PaperScore(
        paperId: strOf(m['paperId']),
        pid: strOf(m['pid']),
        subject: strOf(m['subject']),
        name: strOf(m['name']),
        score: numOf(m['score']),
        scoreS: strOf(m['scoreS'], '0'),
        manfen: numOf(m['manfen']),
        ratio: m['ratio'] == null ? null : numOf(m['ratio']),
        wrongNum: m['wrongNum'] == null ? null : intOf(m['wrongNum']),
      );
}

class ExamRecord {
  final String examId;
  final String studentId;
  final String name;
  final int time;
  final double score;
  final String scoreS;
  final double manfen;
  final double? ratio;
  final bool isPartial;
  final int reportedPaperCount;
  final String classRankS;
  final String gradeRankS;
  final int totalWrong;
  final List<PaperScore> papers;

  const ExamRecord({
    required this.examId,
    required this.studentId,
    required this.name,
    required this.time,
    required this.score,
    required this.scoreS,
    required this.manfen,
    this.ratio,
    required this.isPartial,
    required this.reportedPaperCount,
    required this.classRankS,
    required this.gradeRankS,
    required this.totalWrong,
    required this.papers,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'examId': examId,
        'studentId': studentId,
        'name': name,
        'time': time,
        'score': score,
        'scoreS': scoreS,
        'manfen': manfen,
        'ratio': ratio,
        'isPartial': isPartial,
        'reportedPaperCount': reportedPaperCount,
        'classRankS': classRankS,
        'gradeRankS': gradeRankS,
        'totalWrong': totalWrong,
        'papers': papers.map((e) => e.toJson()).toList(),
      };

  factory ExamRecord.fromJson(Map<String, dynamic> m) {
    final rawPapers = (m['papers'] as List?) ?? const [];
    return ExamRecord(
      examId: strOf(m['examId']),
      studentId: strOf(m['studentId']),
      name: strOf(m['name'], '考试'),
      time: intOf(m['time']),
      score: numOf(m['score']),
      scoreS: strOf(m['scoreS'], '0'),
      manfen: numOf(m['manfen']),
      ratio: m['ratio'] == null ? null : numOf(m['ratio']),
      isPartial: boolOf(m['isPartial']),
      reportedPaperCount: intOf(m['reportedPaperCount']),
      classRankS: strOf(m['classRankS']),
      gradeRankS: strOf(m['gradeRankS']),
      totalWrong: intOf(m['totalWrong']),
      papers: rawPapers
          .whereType<Map>()
          .map((e) => PaperScore.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class WrongSemesterItem {
  final String name;
  final int startMs;
  final int endMs;
  final int wrongNum;
  final int reviewNum;

  const WrongSemesterItem({
    required this.name,
    this.startMs = 0,
    this.endMs = 0,
    required this.wrongNum,
    this.reviewNum = 0,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'startMs': startMs,
        'endMs': endMs,
        'wrongNum': wrongNum,
        'reviewNum': reviewNum,
      };

  factory WrongSemesterItem.fromJson(Map<String, dynamic> m) =>
      WrongSemesterItem(
        name: strOf(m['name']),
        startMs: intOf(m['startMs'] ?? m['start'] ?? m['startTime']),
        endMs: intOf(m['endMs'] ?? m['end'] ?? m['endTime']),
        wrongNum: intOf(m['wrongNum'] ?? m['count']),
        reviewNum: intOf(m['reviewNum']),
      );
}

class WrongExamRef {
  final String examId;
  final String examName;
  final int examTime;
  final int wrongNum;
  final int reviewNum;

  const WrongExamRef({
    required this.examId,
    required this.examName,
    required this.examTime,
    required this.wrongNum,
    this.reviewNum = 0,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'examId': examId,
        'examName': examName,
        'examTime': examTime,
        'wrongNum': wrongNum,
        'reviewNum': reviewNum,
      };

  factory WrongExamRef.fromJson(Map<String, dynamic> m) => WrongExamRef(
        examId: strOf(m['examId']),
        examName: strOf(m['examName'], '考试'),
        examTime: intOf(m['examTime']),
        wrongNum: intOf(m['wrongNum']),
        reviewNum: intOf(m['reviewNum']),
      );
}

class WrongSubjectSummary {
  final String subject;
  final int noReview;
  final List<WrongSemesterItem> semesters;
  final List<WrongExamRef> exams;

  const WrongSubjectSummary({
    required this.subject,
    required this.noReview,
    required this.semesters,
    required this.exams,
  });

  int get examCount => exams.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'subject': subject,
        'noReview': noReview,
        'semesters': semesters.map((e) => e.toJson()).toList(),
        'exams': exams.map((e) => e.toJson()).toList(),
      };

  factory WrongSubjectSummary.fromJson(Map<String, dynamic> m) {
    final sems = (m['semesters'] as List?) ?? const [];
    final exs = (m['exams'] as List?) ?? const [];
    return WrongSubjectSummary(
      subject: strOf(m['subject']),
      noReview: intOf(m['noReview']),
      semesters: sems
          .whereType<Map>()
          .map((e) => WrongSemesterItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      exams: exs
          .whereType<Map>()
          .map((e) => WrongExamRef.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class WrongQuestionItem {
  final String questionId;
  final String shortName;
  final String examId;
  final String paperId;
  final String examName;
  final int examTime;
  final double score;
  final double myScore;
  final double classAvgScore;
  final int type; // 2 = 客观题, 1 = 主观题
  final String style;
  final String myAnswer;
  final String answer;
  final List<String> stemPictures;
  final List<String> myAnswerPictures;
  final List<String> xbAnswerPictures;
  final List<String> knowledges;

  const WrongQuestionItem({
    required this.questionId,
    required this.shortName,
    required this.examId,
    required this.paperId,
    required this.examName,
    required this.examTime,
    required this.score,
    required this.myScore,
    required this.classAvgScore,
    required this.type,
    required this.style,
    required this.myAnswer,
    required this.answer,
    required this.stemPictures,
    required this.myAnswerPictures,
    required this.xbAnswerPictures,
    required this.knowledges,
  });

  double get lostScore => math.max(0, round2(score - myScore));
  String get id => questionId.isNotEmpty ? questionId : shortName;
}

class DashboardData {
  final HfsAccount account;
  final StudentInfo? currentStudent;
  final List<ExamRecord> exams;
  final List<WrongSubjectSummary> wrongOverview;
  final bool isMember;
  final bool isExamMember;
  final int unlockedSubjects;
  final int totalSubjects;
  final String uploadRemain;
  final String exportRemain;
  final Map<String, dynamic> rawProfile;
  final Map<String, dynamic> rawSnapshot;
  final Map<String, dynamic> rawPayment;
  final Map<String, dynamic> rawUnlock;
  final Map<String, dynamic> rawRights;
  final Map<String, dynamic> rawSchoolHidden;

  const DashboardData({
    required this.account,
    required this.currentStudent,
    required this.exams,
    required this.wrongOverview,
    required this.isMember,
    required this.isExamMember,
    required this.unlockedSubjects,
    required this.totalSubjects,
    required this.uploadRemain,
    required this.exportRemain,
    this.rawProfile = const <String, dynamic>{},
    this.rawSnapshot = const <String, dynamic>{},
    this.rawPayment = const <String, dynamic>{},
    this.rawUnlock = const <String, dynamic>{},
    this.rawRights = const <String, dynamic>{},
    this.rawSchoolHidden = const <String, dynamic>{},
  });

  int get totalWrong =>
      wrongOverview.fold<int>(0, (sum, w) => sum + w.noReview);

  List<String> get discoveredSubjects {
    final set = <String>{};
    for (final ex in exams) {
      for (final p in ex.papers) {
        if (p.subject.isNotEmpty) set.add(p.subject);
      }
    }
    final ordered = <String>[
      ...kSubjectOrder.where(set.contains),
      ...set.where((s) => !kSubjectOrder.contains(s)),
    ];
    return ordered;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'account': account.toJson(),
        'currentStudent': currentStudent?.toJson(),
        'exams': exams.map((e) => e.toJson()).toList(),
        'wrongOverview': wrongOverview.map((e) => e.toJson()).toList(),
        'isMember': isMember,
        'isExamMember': isExamMember,
        'unlockedSubjects': unlockedSubjects,
        'totalSubjects': totalSubjects,
        'uploadRemain': uploadRemain,
        'exportRemain': exportRemain,
        'rawProfile': rawProfile,
        'rawSnapshot': rawSnapshot,
        'rawPayment': rawPayment,
        'rawUnlock': rawUnlock,
        'rawRights': rawRights,
        'rawSchoolHidden': rawSchoolHidden,
      };

  factory DashboardData.fromJson(HfsAccount account, Map<String, dynamic> m) {
    final rawExams = (m['exams'] as List?) ?? const [];
    final rawWrongs = (m['wrongOverview'] as List?) ?? const [];
    StudentInfo? curStu = account.activeStudent;
    if (m['currentStudent'] is Map) {
      curStu = StudentInfo.fromUpstream(
          Map<String, dynamic>.from(m['currentStudent'] as Map));
    }
    return DashboardData(
      account: account,
      currentStudent: curStu,
      exams: rawExams
          .whereType<Map>()
          .map((e) => ExamRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      wrongOverview: rawWrongs
          .whereType<Map>()
          .map((e) => WrongSubjectSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      isMember: boolOf(m['isMember']),
      isExamMember: boolOf(m['isExamMember']),
      unlockedSubjects: intOf(m['unlockedSubjects']),
      totalSubjects: intOf(m['totalSubjects']),
      uploadRemain: strOf(m['uploadRemain'], '-'),
      exportRemain: strOf(m['exportRemain'], '-'),
      rawProfile: m['rawProfile'] is Map
          ? Map<String, dynamic>.from(m['rawProfile'] as Map)
          : const <String, dynamic>{},
      rawSnapshot: m['rawSnapshot'] is Map
          ? Map<String, dynamic>.from(m['rawSnapshot'] as Map)
          : const <String, dynamic>{},
      rawPayment: m['rawPayment'] is Map
          ? Map<String, dynamic>.from(m['rawPayment'] as Map)
          : const <String, dynamic>{},
      rawUnlock: m['rawUnlock'] is Map
          ? Map<String, dynamic>.from(m['rawUnlock'] as Map)
          : const <String, dynamic>{},
      rawRights: m['rawRights'] is Map
          ? Map<String, dynamic>.from(m['rawRights'] as Map)
          : const <String, dynamic>{},
      rawSchoolHidden: m['rawSchoolHidden'] is Map
          ? Map<String, dynamic>.from(m['rawSchoolHidden'] as Map)
          : const <String, dynamic>{},
    );
  }
}

class ObjectiveMark {
  final String qName;
  final String option;
  final String stdAnswer;
  final double x;
  final double y;
  final double w;
  final double h;
  final bool isRight;
  final double score;
  final String scoreS;
  final double manfen;

  const ObjectiveMark({
    required this.qName,
    required this.option,
    required this.stdAnswer,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.isRight,
    required this.score,
    required this.scoreS,
    required this.manfen,
  });
}

class SubjectiveRemark {
  final int type;
  final double x;
  final double y;
  final double w;
  final double h;
  final String content;

  const SubjectiveRemark({
    required this.type,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.content,
  });
}

class SubjectiveBlock {
  final int pageIndex;
  final List<String> qNames;
  final int x;
  final int y;
  final int w;
  final int h;
  double score;
  double manfen;
  final List<String> itemScores;
  final bool drawScore;
  final List<SubjectiveRemark> remarks;

  SubjectiveBlock({
    required this.pageIndex,
    required this.qNames,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.score,
    required this.manfen,
    required this.itemScores,
    required this.drawScore,
    required this.remarks,
  });
}

class PageOverlayData {
  final int pageIndex;
  final List<ObjectiveMark> objectives;
  final List<SubjectiveBlock> blocks;

  const PageOverlayData({
    required this.pageIndex,
    required this.objectives,
    required this.blocks,
  });
}

class QuestionDetailItem {
  final String id;
  final String name;
  final double score;
  final String scoreS;
  final double manfen;
  final int type;
  final String myAnswer;
  final String answer;
  final List<String> stemUrls;
  final List<String> cropUrls;
  final List<String> xbAnswerUrls;
  final List<String> knowledges;

  const QuestionDetailItem({
    required this.id,
    required this.name,
    required this.score,
    required this.scoreS,
    required this.manfen,
    required this.type,
    required this.myAnswer,
    required this.answer,
    this.stemUrls = const <String>[],
    required this.cropUrls,
    this.xbAnswerUrls = const <String>[],
    required this.knowledges,
  });

  bool get isFullScore => manfen > 0 && (score - manfen).abs() < 0.01;
  bool get isZeroScore => score <= 0.001;
  double get lostScore => math.max(0, round2(manfen - score));
}

class PaperInspectionData {
  final String studentId;
  final double totalScore;
  final double objectScore;
  final double subjectScore;
  final List<String> originalPages;
  final List<String> answerPages;
  final List<PageOverlayData> pageOverlays;
  final List<QuestionDetailItem> questions;

  const PaperInspectionData({
    required this.studentId,
    required this.totalScore,
    required this.objectScore,
    required this.subjectScore,
    required this.originalPages,
    required this.answerPages,
    required this.pageOverlays,
    required this.questions,
  });

  List<QuestionDetailItem> get lostQuestions =>
      questions.where((q) => q.manfen > 0 && q.score < q.manfen).toList();

  List<QuestionDetailItem> get questionsWithOriginStems =>
      questions.where((q) => q.stemUrls.isNotEmpty).toList();
}

class ClassmateBindEntry {
  final String id;
  final String name;
  final int sex;
  final bool isMember;
  final String grade;
  final String className;
  final bool hasStudentAccount;
  final bool hasParentAccount;

  const ClassmateBindEntry({
    required this.id,
    required this.name,
    required this.sex,
    required this.isMember,
    this.grade = '',
    this.className = '',
    required this.hasStudentAccount,
    required this.hasParentAccount,
  });

  factory ClassmateBindEntry.fromJson(Map<String, dynamic> m) {
    return ClassmateBindEntry(
      id: strOf(m['id']),
      name: strOf(m['name'], '同学'),
      sex: intOf(m['sex']),
      isMember: boolOf(m['isMember']),
      grade: strOf(m['grade']),
      className: strOf(m['className']).isNotEmpty
          ? strOf(m['className'])
          : strOf(m['class']),
      hasStudentAccount: m['bindStudent'] is Map,
      hasParentAccount: m['bindParent'] is Map,
    );
  }
}

class RegionSchoolItem {
  final String id;
  final String name;

  const RegionSchoolItem({required this.id, required this.name});

  factory RegionSchoolItem.fromJson(Map<String, dynamic> m) =>
      RegionSchoolItem(id: strOf(m['id']), name: strOf(m['name']));
}

class RegionCityItem {
  final String name;
  final List<String> counties;

  const RegionCityItem({required this.name, required this.counties});
}

class RegionProvinceItem {
  final String name;
  final List<RegionCityItem> cities;

  const RegionProvinceItem({required this.name, required this.cities});
}

class SchoolMatchedStudent {
  final String id;
  final String name;
  final String grade;
  final String className;
  final String maskedXuehao;
  final String maskedKaohao;

  const SchoolMatchedStudent({
    required this.id,
    required this.name,
    required this.grade,
    required this.className,
    required this.maskedXuehao,
    required this.maskedKaohao,
  });

  factory SchoolMatchedStudent.fromJson(Map<String, dynamic> m) =>
      SchoolMatchedStudent(
        id: strOf(m['id']),
        name: strOf(m['name']),
        grade: strOf(m['grade']),
        className: strOf(m['className']),
        maskedXuehao: strOf(m['maskedXuehao']),
        maskedKaohao: strOf(m['maskedKaohao']),
      );
}
