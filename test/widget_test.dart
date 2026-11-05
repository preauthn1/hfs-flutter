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

  testWidgets('Mobile and Desktop layouts render without overflow',
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

    SharedPreferences.setMockInitialValues({
      'hfs_direct_accounts_v1': jsonEncode(mockAccounts),
      'hfs_direct_selected_id_v1': 'acc_test_1',
    });

    // 1. Mobile phone viewport (360 x 780)
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HfsFlutterApp());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('账号与学生'), findsOneWidget);

    // Switch to mobile tab 3 (账号与学生)
    await tester.tap(find.text('账号与学生'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('已登录账号与绑定学生'), findsOneWidget);

    // 2. Desktop computer viewport (1440 x 900)
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(SegmentedButton<int>), findsOneWidget);
    expect(find.text('好分数成绩工作台'), findsOneWidget);
  });
}
