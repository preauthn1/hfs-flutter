# 好分数 · 原生直连工作台 (`hfs_flutter` v2.6.3)

基于 Flutter 与 **Taste-Skill 2.5 设计规范** 构建的好分数原生跨平台工作台，**100% 使用原生 Widget 与 Canvas 渲染（零 WebView）**，严格直连好分数官方后端，不封装本机中转服务。

## 微信小程序 `/v2/mini/*`

新增微信小程序登录与注册链路（仅使用用户自己提供的 `wx.login()` code、unionId、手机号与短信验证码）：

- `GET https://hfs-wechat-be.yunxiao.com/v2/mini/account-related-user`
- `POST https://hfs-wechat-be.yunxiao.com/v2/mini/account-login`
- `POST https://hfs-wechat-be.yunxiao.com/v2/mini/account-register`
- `POST https://hfs-wechat-be.yunxiao.com/v2/mini/account-logout`

小程序会话换取的 JWT 会转换成普通 `HfsAccount`，后续继续复用成绩、同班名册、直绑与换绑逻辑。小程序账号的短期发现结果不落盘，仅保存已换取的会话；移除账号时尝试调用 logout。`account-register` 的短信验证码仍由上游校验，客户端不猜测、不绕过。

## 既有换绑能力

- 动态换绑配额：`min(6, count(changeBindTime == -1) + 3)`。
- `changeBindTime` 学期锁、`-1` 活名额缩容告警与 `4137` 删源风险拦截。
- 支持通过微信侧官方代理读取最近考试的总分、班排、年级排和分科成绩。
- 所有微信侧查询仍只使用官方域名与已换取会话，不封装本机服务。
- Android ARM64、Windows Inno Setup、Linux x64 构建流水线。

## 构建与测试

```bash
flutter pub get
flutter analyze --no-pub
flutter test test/widget_test.dart
```
