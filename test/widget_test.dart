import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hfs_flutter/hfs_client.dart';
import 'package:hfs_flutter/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Only official Haofenshu hosts are allowed', () {
    expect(
      () => HfsUpstreamClient.assertAllowedHost(
        Uri.parse('https://hfs-be.yunxiao.com/v2/users/sessions'),
      ),
      returnsNormally,
    );
    expect(
      () => HfsUpstreamClient.assertAllowedHost(
        Uri.parse('https://yj-oss.yunxiao.com/exam/sheet.jpg'),
      ),
      returnsNormally,
    );
    expect(
      () => HfsUpstreamClient.assertAllowedHost(
        Uri.parse('https://example.com/api/session'),
      ),
      throwsStateError,
    );
    expect(
      () => HfsUpstreamClient.assertAllowedHost(
        Uri.parse('http://127.0.0.1:18880/api/session'),
      ),
      throwsStateError,
    );
  });

  testWidgets('Mobile and Desktop Taste-Skill layouts render without overflow',
      (WidgetTester tester) async {
    final mockAccounts = [
      {
        'id': 'acc_test_1',
        'label': '测试家长号',
        'roleType': 2,
        'loginName': '13800000000',
        'password': '',
        'cookies': <String>['hfs-session-id=mock'],
        'activeStudentId': 'stu_1',
        'desiredStudentId': 'stu_1',
        'students': [
          {
            'studentId': 'stu_1',
            'studentName': '测试生甲',
            'schoolName': '示例中学',
            'grade': '初三',
            'className': '1班',
            'xuehao': '10000001',
            'isVirtual': 2,
          },
          {
            'studentId': 'stu_2',
            'studentName': '测试生乙',
            'schoolName': '示例中学',
            'grade': '初三',
            'className': '1班',
            'xuehao': '10000002',
            'isVirtual': 2,
          },
        ],
        'studentSnapshots': {
          'stu_1': {
            'examId': 'ex_1',
            'examName': '期中联考',
            'examTime': 1730000000000,
            'scoreS': '568',
            'manfen': 660,
            'ratio': 86.1,
            'isPartial': false,
            'reportedPaperCount': 5,
            'classRankS': '3',
            'gradeRankS': '15',
            'updatedAt': 1730000000000,
          },
        },
      }
    ];

    final mockDash = {
      'account': mockAccounts.first,
      'currentStudent': (mockAccounts.first['students'] as List).first,
      'exams': [
        {
          'examId': 'ex_1',
          'studentId': 'stu_1',
          'name': '期中联考',
          'time': 1730000000000,
          'score': 568,
          'scoreS': '568',
          'manfen': 660,
          'ratio': 86.1,
          'isPartial': false,
          'reportedPaperCount': 2,
          'classRankS': '3',
          'gradeRankS': '15',
          'totalWrong': 4,
          'papers': [
            {
              'paperId': 'p_1',
              'pid': 'p_1',
              'subject': '语文',
              'name': '语文',
              'score': 108,
              'scoreS': '108',
              'manfen': 120,
              'ratio': 90.0,
              'wrongNum': 2,
            },
            {
              'paperId': 'p_2',
              'pid': 'p_2',
              'subject': '数学',
              'name': '数学',
              'score': 114,
              'scoreS': '114',
              'manfen': 120,
              'ratio': 95.0,
              'wrongNum': 2,
            },
          ],
        }
      ],
      'wrongOverview': [
        {
          'subject': '数学',
          'noReview': 2,
          'semesters': [
            {'name': '上学期', 'wrongNum': 2, 'reviewNum': 0}
          ],
          'exams': [
            {
              'examId': 'ex_1',
              'examName': '期中联考',
              'examTime': 1730000000000,
              'wrongNum': 2,
              'reviewNum': 0,
            }
          ],
        }
      ],
      'isMember': true,
      'isExamMember': true,
      'unlockedSubjects': 5,
      'totalSubjects': 5,
      'uploadRemain': '10',
      'exportRemain': '10',
    };

    SharedPreferences.setMockInitialValues({
      'hfs_direct_accounts_v1': jsonEncode(mockAccounts),
      'hfs_direct_selected_id_v1': 'acc_test_1',
      'hfs_dash_snap_v2:acc_test_1:stu_1': jsonEncode(mockDash),
    });

    // 1. Mobile phone viewport (390 x 844)
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HfsFlutterApp());
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('多号与学生'), findsOneWidget);

    // Switch to mobile tab 3 (多号与学生)
    await tester.tap(find.text('多号与学生'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('好分数账号与绑定学生'), findsOneWidget);

    // 2. Desktop computer viewport (1440 x 900)
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('好分数成绩工作台'), findsOneWidget);
    expect(find.text('总分 历次成绩变化趋势折线图与学科均衡度'), findsOneWidget);
    expect(find.text('语文 · 试卷与答题卡调阅'), findsOneWidget);

    // 3. Clicking '数学' in 趋势维度 immediately switches the right-side inspector to 数学
    final mathChip = find.widgetWithText(ChoiceChip, '数学');
    expect(mathChip, findsOneWidget);
    await tester.tap(mathChip);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('数学 历次成绩变化趋势折线图与学科均衡度'), findsOneWidget);
    expect(find.text('数学 · 试卷与答题卡调阅'), findsOneWidget);
  });
}
