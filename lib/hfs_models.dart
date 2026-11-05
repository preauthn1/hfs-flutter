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

  const StudentInfo({
    required this.studentId,
    required this.studentName,
    required this.schoolName,
    required this.grade,
    required this.className,
    required this.xuehao,
    required this.isVirtual,
  });

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
      desiredStudentId: strOf(m['desiredStudentId']),
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
}

class WrongSemesterItem {
  final String name;
  final int wrongNum;

  const WrongSemesterItem({required this.name, required this.wrongNum});
}

class WrongSubjectSummary {
  final String subject;
  final int noReview;
  final List<WrongSemesterItem> semesters;
  final int examCount;

  const WrongSubjectSummary({
    required this.subject,
    required this.noReview,
    required this.semesters,
    required this.examCount,
  });
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
  final List<String> cropUrls;
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
    required this.cropUrls,
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
}
