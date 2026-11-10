# hfs_flutter — 好分数原生工作台
用 Flutter 在 Android、Windows 和 Linux 上管理本人好分数账号、查看成绩与答题卡，并在本地合成批改标记。

## 先试一次

从 [v2.6.4 发行页](https://github.com/preauthn1/hfs-flutter/releases/tag/v2.6.4) 下载对应安装包：Android ARM64 APK、Windows x64 安装版或便携版、Linux x64 压缩包。安装并启动后，添加本人账号，选择已绑定学生，再打开考试和答题卡。能否看到成绩取决于账号权限和上游返回，不提供演示账号。

已核对该发行页包含上述四种安装资产及 `SHA256SUMS.txt`。下载后可在同一目录校验文件；例如 Linux 上：

```bash
sha256sum -c SHA256SUMS.txt --ignore-missing
```

校验通过的文件应显示 `OK`；这只是预期格式，不是本次下载校验或应用登录实测的记录。请勿把“构建成功”理解为账号业务已验证。

> **使用与许可边界**：这是非官方客户端，只使用本人或获得授权的账号与凭证，不提供短信、验证码或访问权限绕过。仓库目前没有应用源码的顶层许可证，公开可见不等于已授予开源再分发权；内置字体的 [SIL Open Font License 1.1](assets/fonts/LICENSE.txt) 只覆盖对应字体。

![hfs_flutter：从考试列表到本地答题卡批改叠加的原生工作台](readme/assets/hero.svg)

## 适合什么，不适合什么

这里比较的是本项目的可核对设计取舍，不推断官方客户端或其他工具缺少哪些能力。

| 采用判断 | 仓库中的实现 | 必须接受的边界 |
| --- | --- | --- |
| 希望不自建业务中转服务 | `HfsUpstreamClient` 在请求入口校验三个官方 HTTPS 主机 | 依赖上游协议与账号权限；不是离线成绩服务 |
| 希望在桌面与手机上查看同类信息 | Flutter 界面、桌面窗口与手机导航布局 | 发行目标是 Android ARM64、Windows x64、Linux x64；iOS/macOS 工程目录不代表已发布支持 |
| 希望保留多个本地账号 | `SharedPreferences` 保存账号，提供 JSON 导入导出 | 本地备份可能包含密码和会话，应视作敏感文件；不是端到端加密同步 |
| 希望保存带批改标记的答题卡 | Canvas 绘制批改层，可导出原图或合成 PNG | 依赖可读取的试卷图片与裁切元数据，不承诺所有考试格式都兼容 |
| 需要绑定风险提示 | 模型估算名额，换绑前展示锁定与风险确认 | 不是服务端事务保护；界面存在强制继续选项，不能保证阻止丢失绑定 |

## 日常使用流程

![使用流程：添加本人账号、选择学生考试、查看并导出答题卡](readme/assets/workflow.svg)

1. **添加账号**：选择家长端或学生端，按界面完成登录；短信或图形验证码由用户手动处理。微信小程序入口需要本人合法取得的凭证，客户端不会自动取得 `wx.login()` 的授权结果。
2. **选择学生和考试**：读取已绑定学生、考试与分科信息。新增绑定或换绑会改变上游账号状态，不是查看成绩的必要步骤。
3. **查看答题卡**：打开试卷原图，查看批改叠加；按需要导出原图或合成图。导出的图片和凭证文件都可能包含个人信息。

### 绑定操作前必读

[`HfsAccount`](lib/hfs_models.dart) 按 `min(6, count(changeBindTime == -1) + 3)` **估算**容量，并结合解锁时间展示状态；这是客户端逻辑，不是对上游长期规则的保证。历史 `-1` 名额的数量和是否还能新增由上游决定。

[`taste_widgets.dart`](lib/taste_widgets.dart) 对历史名额消耗、学期锁及 `4137` 删源风险展示警告。界面包含用户确认后继续请求的分支，因此不能宣称“自动拦截所有风险”。本次文档审查没有执行换绑，也未重新验证上游缺陷；不确定时不要继续，不要拿他人绑定做试验。

## 安装与源码入口

### 发行安装包

以 [Releases](https://github.com/preauthn1/hfs-flutter/releases) 的实际资产为准。已核对 `v2.6.4` 包含：

- `hfs_flutter_android_arm64.apk`
- `hfs_flutter_windows_x64_setup.exe`
- `hfs_flutter_windows_x64.zip`
- `hfs_flutter_linux_x64.tar.gz`
- `SHA256SUMS.txt`

Windows 安装器配置见 [`windows/installer.iss`](windows/installer.iss)。Linux 压缩包包含桌面 bundle，运行依赖 GTK 环境；本次未在目标设备安装这些包。

### 开发与构建

[`pubspec.yaml`](pubspec.yaml) 声明版本 `2.6.4+13`、Dart SDK `>=3.6.0 <4.0.0`；当前 [构建工作流](.github/workflows/build-release.yml) 使用 Flutter `3.47.7`。源码入口：

```bash
git clone https://github.com/preauthn1/hfs-flutter.git
cd hfs-flutter
flutter pub get
```

这会获取依赖，不等于应用已启动。构建应使用仓库的 GitHub Actions 工作流，在对应平台 runner 上生成 Android、Windows、Linux 产物；Android release 需要工作流指定的签名 secrets。不要把签名材料或账号备份提交到仓库。

[`test/widget_test.dart`](test/widget_test.dart) 包含域名门禁、微信模型、代理 URI、名额模型与布局用例。它们是源码中的验证入口；本轮仅进行文档、引用和图形的轻量审查，未重新执行 Flutter 测试、编译或完整安装路径。现有工作流中非标签运行的发布名称仍固定为 `v2.6.3`，与应用版本不同；应检查实际运行与发行资产，不凭名称推断新版本。

## 架构与代码地图

![架构：Flutter 工作台通过带主机校验的客户端读取官方 API 与答题卡资源](readme/assets/architecture.svg)

主路径是界面调用 `HfsUpstreamClient`，在客户端请求入口执行主机校验，再读取官方 API 或图片资源；本地模型、账号存储和 Canvas 输出留在应用侧。校验允许 `hfs-be.yunxiao.com`、`hfs-wechat-be.yunxiao.com`、`yj-oss.yunxiao.com`；这是源码请求入口的约束，不是经过完整抓包证明的网络隔离保证。

- [`lib/main.dart`](lib/main.dart)：应用入口、账号状态、考试与错题界面、凭证导入导出。
- [`lib/taste_widgets.dart`](lib/taste_widgets.dart)：登录、绑定、风险确认、设置与响应式组件。
- [`lib/hfs_client.dart`](lib/hfs_client.dart)：主机校验、App/微信请求、考试数据与图片读取。
- [`lib/hfs_models.dart`](lib/hfs_models.dart)：账号、学生、考试模型及容量估算。
- [`lib/answer_sheet_painter.dart`](lib/answer_sheet_painter.dart)：答题卡交互、Canvas 叠加及图片导出。
- [`lib/win32_native.dart`](lib/win32_native.dart)：Windows 剪贴板及保存对话框适配。

## 状态与验证边界

本 README 对应应用版本 `2.6.4+13`。已有 [Actions 运行 42870022268](https://github.com/preauthn1/hfs-flutter/actions/runs/42870022268) 在源码提交 `06db7c6` 上显示成功；`v2.6.4` 发行页列出三端资产。这是历史 CI 与发行元数据证据，不是本次真机登录、上游业务可用性、升级兼容性或未来维护承诺。

上游协议变化可能造成登录、成绩或试卷读取失效；不承诺与所有旧备份兼容，也不以界面风险提示代替服务端保护。

## 许可证

**应用源码：未发现顶层许可证，授权范围尚未明确。** 字体许可单独见 [SIL Open Font License 1.1](assets/fonts/LICENSE.txt)，不能据此推定整个客户端采用该许可证。
