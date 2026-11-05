# 好分数 · 原生直连工作台 (`hfs_flutter`)

基于 Flutter Material 3 编写的好分数（Haofenshu）原生跨平台客户端，**100% 使用原生 Widget 与 Canvas 渲染（零 WebView）**，并**严格直连好分数官方后端**（不依赖、不封装任何第三方或本机中转服务）。

## 核心特性

- **100% 官方后端直连 (`lib/hfs_client.dart`)**：
  - 内置域名白名单守卫 `HfsUpstreamClient.assertAllowedHost`，仅允许访问好分数官方 API (`https://hfs-be.yunxiao.com`) 与答题卡原图 OSS (`https://yj-oss.yunxiao.com`)。
  - 原生实现家长端/学生端登录 (`/v2/users/sessions`)、`hfs-session-id` Cookie Jar 维护与过期自动重登、关联学生同步 (`/v2/user-center/related-students`)、学生切换 (`/v2/user-center/sessions`)、绑定新学生 (`PUT /v2/users/bind-student`)、历次考试并发水合 (`/v3/exam/{id}/overview` + `brief`) 及全员成绩遍历。
- **手机与电脑全端原生适配 (`lib/main.dart`)**：
  - **电脑桌面端 (`>= 768px`，Windows / Linux / macOS)**：
    - 左侧常驻多账号与学生导航树，顶部切换「成绩单 / 全班对照 / 错题本」，支持鼠标滚轮与拖拽横向滚动、`F5` 快捷刷新、`Esc` 关闭阅卷栏。
    - 宽屏 (`>= 1180px`) 自动开启三栏同屏工作台（右侧常驻 500px 答题卡阅卷栏）。
  - **手机移动端 (`< 768px`，Android / iOS)**：
    - 顶部置顶「多学生一键切换胶囊条」，底部采用原生 4 栏 `NavigationBar`（成绩单 / 全班对照 / 错题本 / 账号与学生），调阅答题卡自动弹出 94% 高度原生 `ModalBottomSheet`。
- **原生 Canvas 答题卡批改叠加层 (`lib/answer_sheet_painter.dart`)**：
  - 基于 `CustomPainter` + `InteractiveViewer` 在高清答题卡原图上直接绘制客观题涂卡正误框、标准答案提示、主观题裁切框、题号得分胶囊、红字总分戳记及教师对勾/半对勾/叉号批改轨迹。
  - 同时支持手机双指捏合/双击缩放与电脑右上角浮动缩放工具栏 (`-` / `100%` / `+`)。

## 构建说明

```bash
flutter pub get
flutter analyze
flutter test

# Android ARM64 APK
flutter build apk --release --target-platform android-arm64

# Linux x64 Desktop
flutter build linux --release

# Windows x64 Desktop
flutter build windows --release
```
