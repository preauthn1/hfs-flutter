# 好分数 · 原生直连工作台 (`hfs_flutter` v2.0.0)

基于 Flutter 与 **Taste-Skill 2.5 设计规范** 构建的好分数（Haofenshu）原生跨平台工作台，**100% 使用原生 Widget 与 Canvas 渲染（零 WebView）**，并**严格直连好分数官方后端**（不依赖、不封装任何第三方或本机中转服务）。

## v2.0.0 升级与完整能力

- **Taste-Skill 2.5 视觉与排版体系 (`lib/taste_widgets.dart`, `lib/main.dart`)**：
  - 95% 暖灰中性界面（`#F5F7F9` Chrome Ground、`#FFFFFF` Framed Sheet、`#F4F6F8` Raised Header、`#E8EAEC` 1px 实线分割、零紫色渐变与浓重弥散阴影）+ 单一天青强调色 `#1B6C80`。
  - 内置思源黑体 3 字重字体包 (`NotoSansSC-400/500/700.ttf`)，解决 Windows / Linux / Android 跨平台中文字重失真；全量分数、名次、考号启用 `tabular-nums` 等宽数字对齐。
  - 修复 Windows (`CMakeLists.txt /utf-8` + Unicode 宽字符)、Linux (`my_application.cc`) 与 macOS (`MainFlutterWindow.swift`) 窗口标题编码问题。
- **100% 官方后端直连与全流程账号能力 (`lib/hfs_client.dart`)**：
  - 内置硬编码白名单守卫 `HfsUpstreamClient.assertAllowedHost`，仅允许访问 `https://hfs-be.yunxiao.com` 与 `https://yj-oss.yunxiao.com`。
  - **好分数新账号注册与密码找回**：原生解析绘制好分数 `<svg>` 矢量图形验证码 (`/v2/users/captcha`)、发送注册/找回短信 (`/v2/native-users/verification-msg`)、校验短信并激活新账号 (`/v2/native-users/activation`)、重置密码 (`/v2/users/forgot-password`) 与在线改密 (`/v2/users/password`)。
  - **多账号共存与 4 通道绑定学生**：支持无限挂载多个家长端/学生端账号；支持「姓名+学号/考号匹配」、「按省市区与学校检索匹配 (`/v2/region` + `/v2/schools`)」、「按好分数学生端账号密码绑定」与「按内部 `studentId` 直接绑定」，并提供同班同学名册探测 (`/v2/students/classmates`)。
- **原卷题块、答题卡批改与完整错题本 (`lib/answer_sheet_painter.dart`, `lib/taste_widgets.dart`)**：
  - **三模式阅卷检视台**：「批改合成与答题卡」（矢量红笔批改叠加层 + 失分题一键定位高亮 + 全屏无损灯箱）、「原卷与题块」（整卷原卷图 + 逐题原卷题干扫描 + 本人作答切块 + 优秀解答切块）、「逐题得分明细表」。
  - **完整错题本工作台**：支持「按考试场次 (`/v2/wrong-items/exam-items`)」与「按学期汇总 (`/v2/wrong-items/items`)」双维度筛选，完整展示原卷题干、我的作答切块、参考解析及一键调阅所属原卷。
- **零滚动穿透与毫秒级秒切体验**：
  - 使用 `GestureBinding.instance.pointerSignalResolver` 独占隔离横向表格与阅卷画布滚轮事件，杜绝答题卡与外部信息流同时滚动。
  - 内存 + `SharedPreferences` 磁盘双层学生快照缓存，点击已加载学生 **0ms 立即切换渲染**，避免每次点击重复遍历请求。

## 构建与测试

```bash
flutter pub get
flutter analyze --no-pub
flutter test

# Android ARM64 APK
flutter build apk --release --target-platform android-arm64

# Linux x64 Desktop
flutter build linux --release

# Windows x64 Desktop
flutter build windows --release
```
