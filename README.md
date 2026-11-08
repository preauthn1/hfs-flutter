# 好分数 · 原生直连工作台 (`hfs_flutter` v2.6.4)

基于 Flutter 与 **Taste-Skill 2.5 设计规范** 构建的好分数（Haofenshu）跨平台原生工作台。**100% 采用原生 Widget 与 Canvas 矢量渲染（零 `WebView` / 零内嵌网页）**，所有网络请求严格直连好分数官方后端，不封装任何本地或第三方中转服务。

---

## 核心特性

### 1. 纯官方直连与域白名单强约束
客户端内置 `HfsUpstreamClient.assertAllowedHost(Uri)` 域名门禁，仅允许向以下三个好分数官方 HTTPS 域名发起请求（任何非白名单域名调用均在本地直接拦截并抛出 `StateError`）：
- `https://hfs-be.yunxiao.com` — 好分数 App 核心后端（账号会话、学生绑定/换绑、考试列表、单科试卷、答题卡坐标、错题本、同班名册等）
- `https://hfs-wechat-be.yunxiao.com` — 好分数微信小程序后端（`/v2/mini/*` 微信关联发现、免密登录、注册、登出，以及 `/v1/be-proxy/*` 官方代理网关）
- `https://yj-oss.yunxiao.com` — 云校好分数阅卷与答题卡原图对象存储（OSS）

### 2. 多通道账号挂载与微信小程序直连 (`/v2/mini/*`)
支持多家长端（`roleType = 2`）/ 学生端（`roleType = 1`）账号并行挂载、一键切换与凭证导入导出：
- **账号密码直连登录**：`POST /v2/users/sessions`（支持手机号/用户名 + 密码，自动维护 `hfs-session-id` Cookie Jar 与 Token）。
- **手机号短信注册与密码重置**：支持官方短信验证码下发与 SVG 图形验证码（`4048`）原生解析展示。
- **微信小程序免密登录与注册**：
  - `GET https://hfs-wechat-be.yunxiao.com/v2/mini/account-related-user`（通过用户本人的 `wx.login()` code 或 `unionId` 发现关联账号）
  - `POST https://hfs-wechat-be.yunxiao.com/v2/mini/account-login`（使用返回的专属 `key` 换取正式会话 JWT）
  - `POST https://hfs-wechat-be.yunxiao.com/v2/mini/account-register`（本人手机号 + 短信验证码 + 微信 `unionId` 注册）
  - `POST https://hfs-wechat-be.yunxiao.com/v2/mini/account-logout`（移除小程序来源账号时自动请求上游注销）
- **微信侧官方代理兜底 (`/v1/be-proxy/*`)**：支持通过 `https://hfs-wechat-be.yunxiao.com/v1/be-proxy/v2/*` 与 `/v3/*` 查询最近考试快照、总分、班排、年级排及分科成绩。

### 3. 学生绑定、同班名册直绑与换绑风控体系
完整支持 4 种绑定检索通道，以及面向历史名额与上游非原子缺陷的安全换绑机制：
- **4 种绑定检索通道**：
  1. `姓名 + 学号/考号`（自动枚举关联学校匹配）
  2. `学校 + 年级 + 姓名`（内置全国省/市/区三级行政区划与学校模糊检索）
  3. `学生 ID (studentId)` 直绑 / 换绑（`POST /v2/native-users/bind-students` / `PATCH /v2/native-users/bind-student`）
  4. `好分数绑定码`
- **动态配额公式**：
  $$\text{MaxQuota} = \min\bigl(6,\; \text{count}(\text{changeBindTime} == -1) + 3\bigr)$$
  实时拉取 `GET /v2/native-users/bind-students` 计算当前账号已绑人数、剩余可新增名额及 `-1` 历史活名额数量。
- **三重换绑安全风控**：
  - **180 天学期锁识别**：自动解析 `changeBindTime` 时间戳，标注锁定状态与解锁日期，防止误触触发 `4137` 报错。
  - **`-1` 活名额永久缩容预警**：当源学生为 `changeBindTime == -1`（历史随时可换名额）时，弹窗明确提示换绑后新记录将写入 `+180` 天学期锁且账号总容量上限将永久减 `1`。
  - **`4137` 删源不加目标高危拦截**：针对好分数上游 `PATCH /v2/native-users/bind-student` 的非原子写缺陷（当目标同学已激活学生端账号 `bindStudent` 非空时，上游返回 `4137 Duplicate links` 却会将源学生直接删除），客户端在同班名册与换绑弹窗中自动探测目标状态并弹出红色高危拦截确认框，确保已绑定学生零意外丢失。
- **同班名册探索 (`ClassmateRosterDialog`)**：通过 `GET /v2/students/classmates` 拉取同班同学列表，直观展示 VIP 标识、是否已激活学生端/家长端、当前库内挂载状态，支持一键复制 `studentId`、新增直绑或指定槽位换绑。

### 4. 全量成绩看板、原生答题卡批改叠加层与错题本
- **成绩看板**：展示历次考试总分、满分、班级排名、年级排名、击败率、单科得分率对比条、等第分布及趋势曲线。
- **原生 Canvas 答题卡阅卷 (`AnswerSheetCanvas` & `_GradingOverlayPainter`)**：
  - 自动拼接多张答题卡原图，支持手势双指缩放、拖拽平移、双击复位与全屏灯箱无损阅卷（支持键盘 `←` / `→` 切图）。
  - 原生解析 OSS `@c_...,x_...,y_...,w_...,h_...` 裁切坐标参数，在答题卡原图上按真实比例绘制红笔批改框、题号角标、得分/满分胶囊与扣分高亮。
  - 支持一键导出/复制**带红笔批改合成图 (`.png`)** 或 **纯原图 (`.png`)**（Windows 端支持原生 Win32 文件另存为对话框）。
- **错题诊断与学情分析**：按考试与学科聚合客观题/主观题失分明细，支持定位到答题卡对应题号区域。

### 5. 响应式双端布局与防遮挡交互规范 (`v2.6.4`)
- **桌面端 (`>= 860px`) & 移动端 (`< 860px`) 自适应**：桌面端采用左侧导航栏 + 主工作区 + 右侧可调宽阅卷抽屉三栏布局；移动端采用顶部紧凑学生切换栏 + 底部 `62px` `NavigationBar` 四页签架构（总览、成绩、错题、账号）。
- **弹窗与菜单防遮挡设计**：
  - `Taste.dialogInsetPadding` 与 `Taste.dialogMaxHeight` 在手机端强制预留底部 `78px` 安全边距，确保任何弹窗或长按菜单绝不遮盖底部 `NavigationBar` 功能栏。
  - 所有弹窗统一采用**固定顶部栏 + 可滚动主体 + 独立不透明底栏 (`Taste.buildDialogFooter`)** 三段式物理隔离，右下角“取消”按钮具备独立边框、不透明背景及 `>= 80×38` 标准点击热区，彻底杜绝文字重叠与边缘误触。

---

## 安全与合规边界

本仓库与客户端严格执行以下安全与隐私边界：
1. **仅限本人合法凭证**：微信小程序链路仅允许用户输入本人通过微信小程序获得的真实 `wx.login()` code、本人 `unionId`、本人手机号及真实短信验证码；客户端不猜测、不伪造 `code`、`unionId` 或 `key`，不实现任何形如 `code="x"` / `union_id="x"` / `key="x"` 的绕过机制。
2. **零第三方探测**：不对任何第三方手机号发起关联查询。
3. **零敏感信息入库**：公开仓库不包含任何真实姓名、学号、`studentId`、学校名、手机号、Token、密码、Cookie、JWT、微信 `code`/`unionId`/`key` 或签名私钥。本地运行期的多账号会话仅保存在用户设备本地配置中（小程序短期发现态 `transient` 字段不落盘）。

---

## 项目结构

```text
hfs-flutter/
├── lib/
│   ├── main.dart                  # 应用入口、响应式主框架、成绩看板、错题本、答题卡抽屉
│   ├── taste_widgets.dart         # Taste-Skill 2.5 组件库、登录/注册面板、绑定/换绑弹窗、同班名册、设置诊断弹窗
│   ├── answer_sheet_painter.dart  # 答题卡原图加载、Canvas 批改层矢量合成、全屏灯箱、PNG 导出与剪贴板交互
│   ├── hfs_client.dart            # 好分数官方后端 HTTP 客户端（含域白名单强校验、App API 与 /v2/mini/* 接口）
│   ├── hfs_models.dart            # 账号、学生、动态配额公式、考试、单科试卷、题目裁切框与错题数据模型
│   └── win32_native.dart          # Windows 原生剪贴板位图写入与文件另存为对话框封装
├── test/
│   └── widget_test.dart           # 域白名单、小程序模型、动态配额公式、320px 窄屏防溢出与弹窗避让回归测试
├── windows/
│   └── installer.iss              # Windows Inno Setup 安装包构建脚本
├── android/                       # Android 工程配置（强制 Release 正式签名校验）
├── linux/                         # Linux GTK 桌面端工程配置
└── .github/workflows/
    └── build-release.yml          # GitHub Actions 三端自动构建、APK 证书指纹校验与 Release 发布流水线
```

---

## 本地开发、分析与测试

环境要求：**Flutter Stable `>= 3.24`（CI 使用 `3.47.7`）**，Dart SDK `>= 3.6.0 < 4.0.0`。

```bash
# 1. 安装依赖
flutter pub get

# 2. 代码格式检查与静态分析
dart format --output=none --set-exit-if-changed lib/ test/
flutter analyze --no-pub

# 3. 运行单元与 Widget 回归测试
flutter test test/widget_test.dart
```

---

## 跨平台构建指南

### Android (`arm64` 正式签名包)
Android Release 构建强制要求配置 `android/key.properties`（或环境变量 `ANDROID_KEYSTORE_PATH` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`），禁止回退至 debug 签名：

```bash
flutter build apk --release --target-platform android-arm64
```
- 正式版签名证书 SHA-256 指纹：
  `b3227391cd532acc2e3322521f97892262a0e828b61bbce03fb24b450169d346`

### Windows (`x64` 免安装压缩包 & Inno Setup 安装程序)
```powershell
flutter config --enable-windows-desktop
flutter build windows --release
iscc windows\installer.iss
```
- 产物：`out/hfs_flutter_windows_x64_setup.exe` 与 `out/hfs_flutter_windows_x64.zip`

### Linux (`x64` 桌面版)
```bash
flutter config --enable-linux-desktop
flutter build linux --release
```
- 产物目录：`build/linux/x64/release/bundle/`

---

## 最新发布版本 (`v2.6.4`)

- **Release 页面**：[https://github.com/preauthn1/hfs-flutter/releases/tag/v2.6.4](https://github.com/preauthn1/hfs-flutter/releases/tag/v2.6.4)
- **Android ARM64 APK**：[`hfs_flutter_android_arm64.apk`](https://github.com/preauthn1/hfs-flutter/releases/download/v2.6.4/hfs_flutter_android_arm64.apk)
- **Windows 安装包 (`Inno Setup`)**：[`hfs_flutter_windows_x64_setup.exe`](https://github.com/preauthn1/hfs-flutter/releases/download/v2.6.4/hfs_flutter_windows_x64_setup.exe)
- **Windows 便携包 (`.zip`)**：[`hfs_flutter_windows_x64.zip`](https://github.com/preauthn1/hfs-flutter/releases/download/v2.6.4/hfs_flutter_windows_x64.zip)
- **Linux x64 桌面包 (`.tar.gz`)**：[`hfs_flutter_linux_x64.tar.gz`](https://github.com/preauthn1/hfs-flutter/releases/download/v2.6.4/hfs_flutter_linux_x64.tar.gz)
- **SHA-256 校验清单**：[`SHA256SUMS.txt`](https://github.com/preauthn1/hfs-flutter/releases/download/v2.6.4/SHA256SUMS.txt)
