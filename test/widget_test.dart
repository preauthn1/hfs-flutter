import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hfs_flutter/answer_sheet_painter.dart';
import 'package:hfs_flutter/hfs_client.dart';
import 'package:hfs_flutter/hfs_models.dart';
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

  test('WeChat mini-program models preserve role and key literally', () {
    final user = MiniRelatedUser.fromJson({
      'userId': 'mini_user_fixture',
      'type': 2,
      'phone': '[REDACTED]',
      'key': 'mini_key_fixture',
    });
    expect(user.roleType, 2);
    expect(user.key, 'mini_key_fixture');
    expect(user.roleLabel, '家长端');
    expect(
      () => HfsUpstreamClient.assertAllowedHost(
        Uri.parse('https://hfs-wechat-be.yunxiao.com/v2/mini/account-login'),
      ),
      returnsNormally,
    );
  });
  test('WeChat proxy URI stays on the official host', () {
    expect(
      HfsUpstreamClient.miniProxyUri('/v3/exam/list?start=0').toString(),
      'https://hfs-wechat-be.yunxiao.com/v1/be-proxy/v3/exam/list?start=0',
    );
  });

  test('Dynamic quota formula min(6, count(-1) + 3) and changeBindTime lock',
      () {
    final futureLock =
        DateTime.now().add(const Duration(days: 120)).millisecondsSinceEpoch;
    final acc = HfsAccount(
      id: 'acc_quota',
      label: '配额测试号',
      roleType: 2,
      loginName: 'fixture_phone',
      password: '',
      cookies: <String>[],
      students: [
        const StudentInfo(
          studentId: 's1',
          studentName: '甲',
          schoolName: '示例中学',
          grade: '初三',
          className: '1班',
          xuehao: '1001',
          isVirtual: 2,
          changeBindTime: -1,
        ),
        const StudentInfo(
          studentId: 's2',
          studentName: '乙',
          schoolName: '示例中学',
          grade: '初三',
          className: '1班',
          xuehao: '1002',
          isVirtual: 2,
          changeBindTime: -1,
        ),
        StudentInfo(
          studentId: 's3',
          studentName: '丙',
          schoolName: '示例中学',
          grade: '初三',
          className: '1班',
          xuehao: '1003',
          isVirtual: 2,
          changeBindTime: futureLock,
        ),
      ],
    );
    expect(acc.minusOneSlotCount, 2);
    expect(acc.estimatedMaxQuota, 5); // min(6, 2 + 3) = 5
    expect(acc.remainingAddQuota, 2);
    expect(acc.students[0].isMinusOneSlot, isTrue);
    expect(acc.students[0].canRebindNow, isTrue);
    expect(acc.students[2].isSemesterLocked, isTrue);
    expect(acc.students[2].canRebindNow, isFalse);
  });

  testWidgets('Mobile and Desktop Taste-Skill layouts render without overflow',
      (WidgetTester tester) async {
    final mockAccounts = [
      {
        'id': 'acc_test_1',
        'label': '测试家长号',
        'roleType': 2,
        'loginName': 'fixture_phone',
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

    // 1. Narrow mobile phone viewport (320 x 740) & standard phone (360 x 800):
    //    exercise all 4 tabs and modals to verify zero RenderFlex overflow or off-screen clipping.
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HfsFlutterApp());
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('多号与学生'), findsOneWidget);

    // Switch to mobile tab 1 (全员总览)
    await tester.tap(find.text('全员总览'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('全员学生最新考试成绩对照表'), findsOneWidget);

    // Switch to mobile tab 2 (错题与诊断)
    await tester.tap(find.text('错题与诊断'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('错题本深度复盘'), findsOneWidget);

    // Switch to mobile tab 3 (多号与学生)
    await tester.tap(find.text('多号与学生'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('好分数账号与绑定学生'), findsOneWidget);

    // Open Settings modal on 320px screen & verify bottom bar clearance + '取消' hit area
    final navBarTop320 = tester.getTopLeft(find.byType(NavigationBar)).dy;
    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('工作台设置与好分数上游只读诊断'), findsOneWidget);
    final settingsDialogBottom = tester
        .getBottomRight(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Material),
              )
              .first,
        )
        .dy;
    expect(settingsDialogBottom, lessThanOrEqualTo(navBarTop320));
    final cancelBtnSize =
        tester.getSize(find.widgetWithText(OutlinedButton, '取消'));
    expect(cancelBtnSize.width, greaterThanOrEqualTo(80));
    expect(cancelBtnSize.height, greaterThanOrEqualTo(38));
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 250));

    // Open BindStudentAdvancedDialog in rebind mode on 320x740 mobile screen,
    // switch to channel 1 ('学校 + 年级 + 姓名') where '取消' is at bottom-right,
    // and verify zero overflow, bottom bar clearance, and clean '取消' tap target.
    await tester.tap(find.text('换绑').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.textContaining('换绑学生（替换「测试生甲」· PATCH bind-student）'),
      findsOneWidget,
    );
    final bindDialogBottom = tester
        .getBottomRight(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Material),
              )
              .first,
        )
        .dy;
    expect(bindDialogBottom, lessThanOrEqualTo(navBarTop320));
    await tester.tap(find.text('学校 + 年级 + 姓名'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('不知道学校 ID？展开省市区检索学校'), findsOneWidget);
    final channel1CancelRect =
        tester.getRect(find.widgetWithText(OutlinedButton, '取消'));
    final queryBtnRect =
        tester.getRect(find.widgetWithText(OutlinedButton, '查询学生'));
    expect(channel1CancelRect.overlaps(queryBtnRect), isFalse);
    expect(channel1CancelRect.bottom, lessThanOrEqualTo(bindDialogBottom));
    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pump(const Duration(milliseconds: 250));

    // Trigger image context popup menu near bottom-right corner on 320x740 mobile screen
    // and verify it never covers the bottom NavigationBar and '取消' dismisses cleanly.
    final navElement = tester.element(find.byType(NavigationBar));
    HfsImageClipboardAndExporter.showImageContextMenu(
      context: navElement,
      globalPosition: const Offset(305, 715),
      rawBytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      label: 'test_sheet',
    );
    await tester.pumpAndSettle();
    expect(find.text('复制图片到剪贴板'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    final popupCancelRect = tester.getRect(find.text('取消'));
    expect(popupCancelRect.bottom, lessThanOrEqualTo(navBarTop320));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // Switch back to mobile tab 0 (成绩单) at 360x800
    tester.view.physicalSize = const Size(360, 800);
    await tester.tap(find.text('成绩单'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('总分 历次成绩变化趋势折线图与学科均衡度'), findsOneWidget);

    // Scroll down to verify the score matrix table renders without overflow
    final verticalScrollable = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    await tester.scrollUntilVisible(
      find.text('历次考试总分与单科矩阵'),
      250.0,
      scrollable: verticalScrollable.first,
    );
    expect(find.text('历次考试总分与单科矩阵'), findsOneWidget);

    // Scroll down to the subject paper cards and open mobile bottom-sheet PaperInspectionPane
    await tester.scrollUntilVisible(
      find.textContaining('已出分科目：2 科'),
      180.0,
      scrollable: verticalScrollable.first,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调阅答题卡 →').first);
    await tester.pumpAndSettle();
    expect(find.text('语文 · 试卷与答题卡调阅'), findsOneWidget);
    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();

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

    // 4. Verify combined Classmates Roster + POST /v2/native-users/bind-students + Rebind dialog
    expect(find.text('同班名册与直绑'), findsOneWidget);
    await tester.tap(find.text('同班名册与直绑'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.text('POST /v2/native-users/bind-students 挂载到：'),
      findsOneWidget,
    );
    expect(find.textContaining('⇄ 换绑：测试生甲'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump(const Duration(milliseconds: 250));

    // 5. Verify direct per-student '换绑' button in left dock opens BindStudentAdvancedDialog in rebind mode
    expect(find.text('换绑'), findsWidgets);
    await tester.tap(find.text('换绑').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.textContaining('换绑学生（替换「测试生甲」· PATCH bind-student）'),
      findsOneWidget,
    );
    expect(
      find.text('确认换绑替换「测试生甲」'),
      findsOneWidget,
    );
  });
}
