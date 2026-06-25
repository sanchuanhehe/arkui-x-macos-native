# ArkUI-X 原生 macOS 移植 · 渲染地基(Phase 0/1/A 完成)

把 **ArkUI-X 的标准 ArkUI 渲染后端**(完整声明式 ArkUI + 方舟 + skia + RenderService)移植到 **macOS(Apple Silicon)原生**,作为后续"原生 macOS ArkUI 桌面 App"的地基。

> 现状:**渲染后端已用真 GN/ninja 在 macOS 上编译链接通过**(NSOpenGLContext/CALayer/桌面 GL FBO)。**窗口层 + 跑起来(M1)是下一阶段**,步骤已在 `施工图.md` 写全。

---

## ✅ 已达成(可复现)

1. **GN `target_os=mac` 管线**:`BUILDCONFIG.gn` 加 mac 分支 + 新建 `build_plugins/toolchain/mac`(macosx sysroot)+ 修 `find_sdk.py` 正则(认 `MacOSX26.x` SDK)。`gn gen` 稳定产 ~11371 targets。
2. **macOS 图形后端**:新建 `appframework/graphic_2d/macos/`,把 iOS 后端的 **EAGL / UIKit / OpenGLES** 改写为 **NSOpenGLContext + CALayer + 桌面 GL 离屏 FBO**;`CADisplayLink → CVDisplayLink`;`CAEAGLLayer → CALayer`。
3. **全 GN ninja 编通**:真构建系统把后端 **及全部传递依赖**(skia_mac、2d_graphics、render_service_base、image_framework、hilog、c_utils、eventhandler)编出来——不是手工编 `.o`。
4. **关键坑已解**:OHOS 预编译 clang-15 **编不了 macOS SDK 的 Objective-C 头**(`NSUInteger unknown`)→ 全栈改用 **Xcode clang**(`use_xcode_clang=true`),并连带修一串兼容(CFI、BSD `ar`/`libtool`、`-segprot`、`-Werror` 降级、skia vulkan 关、ffmpeg(GNU sed)mac-gate、eventhandler epoll→CFRunLoop 等)。`third_party` **零改动**。

### 选路结论
- **走 iOS 的 appframework 后端(`additionalData=CALayer` 直渲),不走 darwin/预览器后端**(后者要 glfw 缺仓 + graphic_surface 注册 + HDI 设备依赖,墙更多)。
- GL→出图:iOS 用 layer 当 GL 后备;桌面 GL 无此能力 → 用**离屏 FBO 渲染**,出图交窗口层(走 CAOpenGLLayer/IOSurface 零拷贝)。

---

## ⏳ 待续:B 段(窗口层 → M1)

`adapter/macos` 的 WindowView(CAOpenGLLayer/IOSurface 接 FBO)、virtual_rs_window、`main.mm` + MacAppDelegate(独立可执行,免 Xcode 工程)、stage/osal、编 `ace_macos` 可执行、开窗、加载 `.abc` 渲染 `.ets` —— **尚未开始**。详细步骤见 `施工图.md` 第 5 节。

---

## 环境要求

- macOS Apple Silicon(在 macOS 26 / Xcode 全装上验证)
- **完整 Xcode**:`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- **Rosetta**(arkui-x 工具链含 x64 node):`softwareupdate --install-rosetta`
- ArkUI-X 源码 + `./build/prebuilts_download.sh`(~10GB)

## 应用补丁

```bash
scripts/apply_patches.sh /path/to/arkui-x
```
各仓基线 commit 见 `patches/BASE_COMMITS.txt`;脚本在 8 个仓建 `mac-port` 分支并 `git apply`。

## 构建(编 macOS 图形后端)

```bash
cd /path/to/arkui-x
./build.sh --product-name arkui-x --target-os mac --gn-args '
  target_cpu="arm64"
  mac_use_ios_backend=true
  use_xcode_clang=true
  graphic_2d_feature_enable_vulkan=false
  skia_feature_use_vulkan=false
  skia_enable_fontmgr_ohos=false
  skia_use_fonthost_mac=false '
# 或直接 gn gen + ninja 目标:appframework/graphic_2d:platform
```

---

## 改动范围(8 仓,third_party 零改)

| 仓 | patch | 文件 | 说明 |
|--|--|--|--|
| appframework | appframework.patch | 17 | **macos 图形后端**(主体) |
| build_plugins | build_plugins.patch | 7 | toolchain/mac + config/mac |
| build | build.patch | 10 | BUILDCONFIG mac 分支 / find_sdk |
| image_framework | image_framework.patch | 8 | mac-as-ios include / ffmpeg gate |
| graphic_2d | graphic_2d.patch | 9 | 平台路由 / EGL-shim / config |
| ace_engine | ace_engine.patch | 2 | rosen 平台分支 |
| hilog | hilog.patch | 2 | mac(iOS CFRunLoop)分支 |
| c_utils | c_utils.patch | 1 | mac 适配 |

完整设计与逐文件改写见 **`施工图.md`**。

---

## 许可

基于 OpenHarmony / ArkUI-X(Apache-2.0)二次开发,本仓以 **Apache-2.0** 发布,仅含改动补丁,不再分发上游源码。
