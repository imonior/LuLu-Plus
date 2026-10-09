# LuLu_Plus

[English](README.md) | [正體中文](README_zh-Hant.md)

LuLu_Plus 是一款免费的开源 macOS 防火墙，由 [imonior](https://github.com/imonior) 开发，仓库地址为
[github.com/imonior/LuLu-Plus](https://github.com/imonior/LuLu-Plus)。

**来源说明：** \
LuLu_Plus 派生自 [Objective-See](https://objective-see.com) 的 [LuLu](https://github.com/objective-see/LuLu)，
基线为 2026 年 10 月 4 日的 master 分支代码（4.5.1 发布之后、4.5.2 发布之前），而非 4.5.1 标签本身。出站防火墙、
规则模型、提醒流程以及系统扩展与网络扩展的整体框架均来自该项目。感谢 Patrick Wardle 与 Objective-See 将 LuLu
开源，本项目的全部工作都建立在其成果之上。

**本 fork 新增的内容：**

- 规则带有方向（`both`、`outbound`、`inbound`）：规则列表会说明某条规则管哪个方向，新增/编辑窗口可以选择它
- 入站连接会被判定并上报：对端主动连进来时有自己的提醒，也会落成自己的一条规则
- profile 可以指定它适用于哪些网络（网卡、网卡类型、ssid、bssid、网关），新增 profile 的向导里有专门一页来写这些条件
- 网卡名称与 bssid 等信息由主程序采集后通过 XPC 交给扩展：系统扩展无法弹出定位授权对话框，而读取这些字段必须有该授权
- `LuLu_Plus/Tests` 下有一套测试，其中包含变异检查：把每个已修的 bug 重新改坏，验证测试确实会变红

上游项目的产品页、截图与捐助入口都不再引用：本 fork 以自身仓库为准，检查项的说明见
[`LuLu_Plus/Tests/README.md`](LuLu_Plus/Tests/README.md)。

## 接管的旧安装

本构建把规则、偏好设置与 profile 存放在 `/Library/Application Support/lulu_plus`。上一个名字的安装在
`/Library/Objective-See/LuLu`，所以本构建的扩展首次启动时会接管那份数据：`rules.plist`、`rules_v1.plist`、
`preferences.plist` 以及整个 `Profiles` 目录都会被搬走，旧目录在空了之后删除。本构建不读取的文件一律原地保留，
仍在存放这些文件的目录也同样保留。

只要 `/Applications/LuLu.app` 还在安装，它的文件就是*复制*而非移动：那个防火墙运行期间会一直从该目录读取这些
文件，把它们拿走就会让它停止过滤。

有一种情况不接管：最初版本的安装会把程序自身放在 `/Library/Objective-See/LuLu/LuLu.bundle`。本应用不会与它并存，
并在启动时明确提示；必须先移除旧安装。接管流程见
[`LuLu_Plus/Tests/README.md`](LuLu_Plus/Tests/README.md)，`run_install_migration_tests.sh` 会在临时目录树上执行它。

## 检查更新

更新检查读取本项目的最新 GitHub release
（[`api.github.com/repos/imonior/LuLu-Plus/releases/latest`](https://api.github.com/repos/imonior/LuLu-Plus/releases/latest)），
因此标记为 `v4.5.3` 的 release 才是 4.5.2 构建所报告的更新版本。标签不是版本号时——`latest`、`nightly`、
`v4.5.3-rc1`——会被拒绝，而不是当成某个未来的发布；版本号按数字比较，所以 `4.5.10` 正确地位于 `4.5.2` 之后。
「有新版本」窗口里的按钮打开的是 release 页面，不是 API 的返回内容。

未认证时该 API 每个 IP 每小时只有 60 次；超出后检查只是报告失败。release 并不声明自己需要哪个 macOS，所以检查
也不会假装知道：它只会说明存在新版本。

## 签名身份

代码里不再写任何人的名字：两半各自从「正在运行的这一份构建」的签名上读出它的 Team
（`SecCodeCopySelf` → 叶子证书里的 team），据此构造要校验的内容（`Shared/SigningIdentity.m`）。

- 扩展对每个连进来的客户端下一条代码签名要求：必须是本构建的主程序
  （`identifier "com.imonior.lulu-plus.app"`），且由同一个 Team 签发（`certificate leaf [subject.OU] =
  "<TEAM>"`）。macOS 13 及以上，这条要求连同 `info [CFBundleShortVersionString] >= "2.0.0"` 版本下限一起交给
  监听器（`setConnectionCodeSigningRequirement:`）；不带下限的那一条，扩展自己在连接的 audit token 上用
  `SecTaskValidateForRequirement` 执行。签给其他团队的客户端不可能匹配——Apple 不会把它没签发过的 team 写进
  证书——于是校验回答 `errSecCSReqFailed`（-67050），连接根本不会建立。同一条路径还要求签名有效且开启加固运行时
  （`CS_VALID` 与 `CS_RUNTIME`），所以未签名或 ad-hoc 构建的主程序会更早一步失败。自身签名里没有 team 的构建没有
  可钉住的对象，要求便退化为只校验 identifier——这是弱一些的检查，也是仅剩能做的。
- 两半相遇的 mach service 是推导出来的，不是写死的：扩展监听的名字就是它 `Info.plist` 注册的名字
  （`NEMachServiceName`，写作 `$(TeamIdentifierPrefix)com.imonior.lulu-plus`，构建时展开为真正签名者的 Team），
  运行时从该文件读回；主程序则从自己内嵌的 system extension 里读同一个键。`Shared/consts.h` 里的
  `DAEMON_MACH_SERVICE` 只是基础名，仅在两个文件都读不到时使用。两个 application-group 权限也是同样写法。

于是任何 Developer ID 签这个 fork 都无需改一行：两半都认定实际签名的那一个。签名的*步骤*当然仍要写明签名者——
Xcode 构建看 `LuLu_Plus/LuLu_Plus.xcodeproj/project.pbxproj` 里的 `DEVELOPMENT_TEAM`，发布看
`DMG/createDMG.sh` 里的 `codesign --sign` 身份——但代码不再需要。

这一切不能消除的是：Network Extension 与 System Extension 权限属于*受限*权限——只有当构建带着付费 Apple
Developer Program 会员签发的 provisioning profile 时，系统才会认账。用免费 Apple ID 签的、未签名的或 ad-hoc 的
构建都能编译，但 macOS 不会加载它的 system extension，无论 XPC 校验怎么说。开发机可以被配置成接受本地签名的扩展
（关闭 SIP、打开 developer mode），但那是逐机设置，分发的构建不能依赖它。

Bundle id 也已改动（`com.imonior.lulu-plus`、`.app`、`.extension`），而 TCC 是按 bundle id 记录授权的：旧主程序
被允许的能力——ssid/bssid 条件所需的定位访问——都必须对新程序重新授权一次。
