# ArkUI-X 原生 macOS 移植 · M1 完成(ArkUI 页面在 macOS 原生渲染)

把 **完整标准 ArkUI**(声明式 ArkUI + 方舟 ets_runtime + skia + RenderService + napi + mmi)移植到 **macOS(Apple Silicon)原生桌面**,目标是不依赖 iOS 模拟器、直接以 AppKit 跑起 `.ets` 页面。

> **M1 完成 ✅**:用官方 `ace build bundle`(DevEco hvigor + OpenHarmony SDK)编出的标准 stage app,在原生 AppKit 窗口里**真实渲染出 ArkUI 页面**(声明式 `@Entry @Component` → 方舟运行时 → RenderService → NSOpenGLContext/CAOpenGLLayer)。截图见 `screenshots/M1_arkui_rendered.png`。
>
> 渲染管线打通的关键修复链:① mac 从不 Init RSUIDirector → 补 renderThreadClient + 启 RS 渲染线程;② RS 渲染线程一次性 vsync → 改持续渲染;③ 双 director,client 设在渲染页面那个;④ stage 首帧 0×0 早退 → 页面子树标脏测量;⑤ **真因**:CAOpenGLLayer pixel format ≠ render_context Core 3.2 → GL share group 失败 → colorbuffer 不可见 → 强制 Core 3.2 + 经本地 FBO blit 共享 renderbuffer。
>
> 旧现状:**整个 ArkUI 框架已用真 GN/ninja 在 macOS 上编译链接通过**(`libace_static_mac` = 7224 个 .o / 23 个静态库 / 184.5MB,含 skia/napi/graphic_2d/ets_runtime/mmi/image_framework 全部传递依赖)。**最后一步——链 `ace_macos` 可执行 → 开 AppKit 窗 → 渲染第一帧——进行中。**

---

## ✅ 已达成(可复现)

### A 段 · GN 管线 + macOS 图形后端
1. **GN `target_os=mac` 管线**:`BUILDCONFIG.gn` 加 mac 分支 + 新建 `build_plugins/toolchain/mac`(macosx sysroot)+ 修 `find_sdk.py`(认 `MacOSX26.x` SDK)。
2. **macOS 图形后端**:新建 `appframework/graphic_2d/macos/`,把 iOS 后端的 **EAGL / UIKit / OpenGLES** 改写为 **NSOpenGLContext + CALayer + 桌面 GL 离屏 FBO**;`CADisplayLink → CVDisplayLink`;`CAEAGLLayer → CALayer`。
3. **关键坑已解**:OHOS 预编译 clang-15 **编不了 macOS SDK 的 ObjC 头** → 全栈改用 **Xcode clang**(`use_xcode_clang=true`),连带修 CFI / BSD `ar`·`libtool` / `-segprot` / skia vulkan 关 / ffmpeg(GNU sed)mac-gate / eventhandler epoll→CFRunLoop 等。

### B 段 · 窗口层(adapter/macos)
4. **新建 `ace_engine/adapter/macos/`**(~150 文件):`virtual_rs_window`(UIWindow/UIScreen→NSWindow/NSScreen)、`WindowView`(NSView + `WindowGLLayer:CAOpenGLLayer`,`glBlitFramebuffer` 把离屏 FBO 贴上层,Y 翻转 + `backingScaleFactor`→density)、`main.mm`+`MacAppDelegate`(独立可执行,免 Xcode 工程)、stage/ability(NSViewController)、osal(91)、uicontent(11)。

### C 段 · 整框架编通(本阶段重头)
5. **`libace_static_mac` 全编通并归档**:`ninja` 干净跑完 **0 编译失败**,产出 **7224 .o + 23 静态库 / 184.5MB**——ace_engine 框架 **及全部传递依赖**(skia_canvaskit / napi / graphic_2d / ets_runtime / mmi / image_framework / appframework)在 mac 全部编译链接通过。
6. **逐类扫平的硬坑**(详见 `施工图.md` 与 memory 笔记):
   - **GN 重复规则**:skcms.o 被两 target 重复生成(预存 latent bug)+ ets2panda copy 产物跨 toolchain 重复 → `ninja` 加载失败;mac-gate 去重。
   - **184× `-Werror=unknown-warning-option`**:Xcode clang 不识别某 warning,`-Wno-error=` 被提升成硬错;mac 下移除该 `-Werror`,一处清零。
   - **IOS_PLATFORM 复用塌缩**:给跨平台模块(window_manager/uicontent/ability cross-platform)mac 同时定义 `IOS_PLATFORM+MAC_PLATFORM`,让 mac 复用 iOS 分支,把一批 `jni.h`/头文件 not-found 一把消掉。
   - **Carbon `Component` 撞名**:AppKit 经 CoreServices 带入 `typedef ComponentRecord* Component`,撞 ets_runtime `enum class Component` → `#define Component CarbonComponent` 包住 AppKit import 再 `#undef` 隔离。
   - **PREVIEW 误判**:napi 对 `is_mac` 无脑当预览器加 `PREVIEW`,使 `AceContainerSG` 抽象 → 改 `... && !is_arkui_x`(我们的 mac 是 arkui-x)。
   - 另:securec snprintf/vsnprintf 启用、NG_BUILD、napi 引擎 Linux-ism(epoll/pthread)、mmi `<linux/types.h>`、display_info/virtual_rs_window 的 UIKit→AppKit、26 处 `adapter/ios`→`adapter/macos` include。

---

## ⏳ 待续:M1 终点(临门一脚)

链 `ace_macos` 可执行 → `NSApplicationMain` 开 AppKit 窗 → 把 `render_context` 的离屏 `framebuffer_` publish 给 `WindowGLLayer.sourceFramebuffer`(`glBlitFramebuffer` 出图)→ 加载 `.abc` 渲染 `.ets`。步骤见 `施工图.md`。

---

## 环境要求

- macOS Apple Silicon(在 macOS 26 / Xcode 全装验证)
- **完整 Xcode**:`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`(构建/运行需 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`)
- **Rosetta**(arkui-x 工具链含 x64 node):`softwareupdate --install-rosetta`
- ArkUI-X 源码 + `./build/prebuilts_download.sh`(~10GB)

## 应用补丁

```bash
scripts/apply_patches.sh /path/to/arkui-x
```
各仓基线 commit 见 `patches/BASE_COMMITS.txt`;脚本在 14 个仓建 `mac-port` 分支并 `git apply`。

## 构建(整框架)

```bash
cd /path/to/arkui-x
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./build.sh --product-name arkui-x --target-os mac --gn-args '
  target_cpu="arm64"
  mac_use_ios_backend=true
  use_xcode_clang=true
  graphic_2d_feature_enable_vulkan=false
  skia_feature_use_vulkan=false
  skia_enable_fontmgr_ohos=false
  skia_use_fonthost_mac=false '
# 或 gn gen 后:ninja -C out/arkui-x libace_static_mac   # 整框架
#              ninja -C out/arkui-x ace_macos            # 可执行(M1)
```

---

## 改动范围(14 仓,third_party 仅 1 处必要 skcms 去重)

| 仓 | patch | 说明 |
|--|--|--|
| ace_engine | ace_engine.patch | **adapter/macos 窗口层 + 整框架 mac 适配**(主体,167 文件) |
| appframework | appframework.patch | macos 图形后端 + window_manager/ability cross-platform mac 化 |
| graphic_2d | graphic_2d.patch | 平台路由 / EGL-shim / rosen mac / config |
| build / build_plugins | build*.patch | BUILDCONFIG mac 分支 / toolchain/mac / find_sdk |
| image_framework | image_framework.patch | mac-as-ios include / mock 头去冲突 / ffmpeg gate |
| napi | napi.patch | mac 非 PREVIEW(is_arkui_x)+ 引擎 Linux-ism 走 iOS 分支 |
| input | input.patch | mmi proxy mac 加 IOS_PLATFORM(避 `<linux/types.h>`) |
| ets_frontend / runtime_core | *.patch | ets2panda copy 跨 toolchain 去重 |
| skia | skia.patch | **唯一 third_party 例外**:skcms.o 重复规则去重(单 if 分支) |
| sdk-js / hilog / c_utils | *.patch | api/arkts/kits 去重 / mac CFRunLoop 分支 / mac 适配 |

完整设计与逐文件改写见 **`施工图.md`**;libace 移植错误大类速查见随仓 memory 笔记。

---

## 许可

基于 OpenHarmony / ArkUI-X(Apache-2.0)二次开发,本仓以 **Apache-2.0** 发布,仅含改动补丁,不再分发上游源码。
