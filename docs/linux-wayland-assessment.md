# 把 ArkUI-X 引擎移植到 Linux Wayland · 可行性评估

> 本文基于对 ArkUI-X 源码树的实证调查(file:line 佐证)与已完成的 **macOS 原生移植(M1)** 经验,评估把同一套标准 ArkUI 引擎移植到 **Linux Wayland 桌面** 的可行性、可复用面、净新增工作与风险。结论可直接作为路线 A(真·stage app,与 mac 港对等)的起手依据。

## 结论先行

**可行,且大概率比 macOS 那次更省、风险更低。** 粗估 **M1 对等(在 Wayland 窗口里渲染 `.ets` 页面)的工作量约为 macOS 移植的 50~65%**。

核心判断:**macOS 移植里吃掉大半精力的三类坑,在 Linux 上直接消失**——因为 Linux 本就是 OpenHarmony 的母系统,EGL/fontconfig 是 skia 在 Linux 的原生正路,而 Android 已经提供了「客户端侧 EGL 渲染」的可跑参考。

---

## 一、为什么更容易:mac 三大痛点在 Linux 蒸发

| macOS 的坑(吃掉大半精力) | Linux Wayland | 依据 |
|--|--|--|
| **Xcode-clang 编不了 macOS SDK 的 ObjC 头** → 全栈换 clang + CFI/`-segprot`/BSD libtool/Carbon `Component` 撞名 | **消失**:原生 clang/gcc,无 ObjC、无 Carbon | `//build/toolchain/linux` 已存在 |
| **GL 共享组 pixel-format 不匹配(真凶,白屏)+ 离屏 FBO blit + Y 翻转** | **消失**:Linux 走 `eglCreateWindowSurface` 直接渲染到窗口 surface | `render_context_gl.cpp` 中 `#if defined(ROSEN_IOS)\|\|defined(ROSEN_MAC)` 才走离屏 FBO,否则真 EGL 窗口 surface |
| **CoreText 字体折腾**(gate 掉 OHOS fontconfig + 删 stub + 链 framework) | **消失**:freetype+fontconfig 是 skia 在 Linux 的原生正路 | `skia/m133/gn/skia.gni`:`skia_use_fontconfig = is_linux`、`skia_use_freetype = …\|\|is_linux` |
| **OS 原语 shim**:epoll→CFRunLoop、`<linux/types.h>` 缺失、eventfd 等 | **消失**:Linux 是 OHOS 母系统,epoll/eventfd/timerfd/pthread/fontconfig 全原生 | — |
| **RS 渲染管线五层坑**(RSUIDirector 不 Init / renderThreadClient 丢 commit / 一次性 vsync / 双 director) | **大部分消失**:这些源于 mac 复用 iOS 后端(`mac_use_ios_backend=true`)且 AppKit 没复刻 iOS 生命周期 | OHOS 正路 `rs_ui_director.cpp:85-131` 本就正确 `Init()`+`SetRenderThreadClient()`+`RSRenderThread::Instance().Start()` |

> 渲染管线五层坑的来源详见 macOS 移植笔记。要点:**第 1~4 层是 mac/iOS-backend 专属,第 5 层(GL 共享组)是 mac 独有**。Linux 应照 **Android**(成熟的 ArkUI-X EGL 客户端侧平台)而非 iOS/mac,可绕开其中至少四层。

---

## 二、能直接复用的(实证)

- **构建系统**:`target_os == "linux"` 分支 + `//build/toolchain/linux` + `use_linux` / `is_desktop_linux` **已存在**(`build/config/BUILDCONFIG.gn:547`、`ace_config.gni:113`)。不必像 mac 那样新建整套 `build_plugins/toolchain/mac` + `find_sdk`。
- **EGL render_context**:统一的 `foundation/graphic/graphic_2d/rosen/modules/2d_graphics/src/render_context/new_render_context/render_context_gl.{h,cpp}` 已支持 EGL 窗口 surface,**且已含 `EGL_EXT_platform_wayland` 平台探测代码**。窗口 surface 创建路径几乎现成。
- **RS 客户端侧渲染**:**Android** 就是「EGL 直接渲染到窗口 + 客户端 `RSRenderThread`、无 RenderService 守护进程」的 ArkUI-X 模型(`ROSEN_ARKUI_X`)。Linux 照搬 Android 即可——是「抄一个能跑的参考」,而非 mac 那样「从白屏倒推真因」。
- **adapter 脚手架**:`adapter/linux` 的 `osal`/`stage`/`uicontent`/`entrance` 结构可对照 `adapter/macos`(现已是已知量)与 `adapter/android`。
- **字体/输入参考**:Android 路径(`adapter/android/entrance/java/jni/virtual_rs_window.cpp`)有完整 keycode 映射可抄。

---

## 三、净新增工作(主要就这一块)

**Wayland 协议胶水**——全树无 `wl_` / `xdg_` / X11 引用,完全 net-new,但都是成熟领域(每个 GUI 工具包都有 Wayland 后端):

1. **窗口层 `adapter/linux`**:`wl_display` / `wl_registry` / `wl_compositor` / `xdg_shell`(`xdg_surface`+`xdg_toplevel`)/ `wl_egl_window` → `EGLSurface`,实现 `virtual_rs_window` 接口(`Create` / `CreateSurfaceNode` / `Show` / `Hide` / `Foreground` / `Resize`)。比 NSWindow 啰嗦些:异步 roundtrip 协议模型,且 Wayland 客户端自绘装饰(标题栏)需 **libdecor** 或 CSD。
2. **vsync 驱动**:`wl_surface.frame` 回调驱动 `RequestNextVsync` —— 与 mac 的 CVDisplayLink driver 同位置,但更简单(无共享组)。
   - 注意:OHOS 的 `RSVsyncClientOhos`(`render_service_base/src/platform/ohos/rs_vsync_client_ohos.cpp`)走 IPC 连 RenderService;桌面独立客户端没有该守护进程,故此处要像 mac/Android 自带一个 frame-callback 驱动。
3. **输入**:`wl_seat`(`wl_keyboard` / `wl_pointer` / `wl_touch`)+ **xkbcommon** 把 keycode 转 keysym → `Window::ProcessPointerEvent` / `Window::ProcessKeyEvent` → `UIContentImpl` → `AceViewSG::DispatchTouchEvent`。
4. **构建接线**:`adapter/linux/build:ace_linux` + `build/core/gn/BUILD.gn` 加 `target_os == "linux"` 分支 + `ace_config.gni` / `config.gni` 路由开关。

---

## 四、一个必须先定的架构决策

`foundation/graphic/graphic_2d/rosen/modules/render_service_base/config.gni:37` 现在把 Linux 归进 `rosen_preview`(GLFW 预览器路径):

```gni
rosen_preview = (rosen_is_mac && !mac_use_ios_backend) || rosen_is_win || rosen_is_linux
```

需要决定:

- **路线 A(推荐,与 mac 港对等)**:专门的 `adapter/linux` + **照 Android 的 `ROSEN_ARKUI_X` 客户端侧 EGL 渲染**,把 Linux 从 preview 路由摘出来。产出是**真·stage app**:`ace` 可执行 + 完整 ability 生命周期 + 官方 `ace build bundle`,与 mac 港一个级别。
- **路线 B(近乎免费,但受限)**:预览器本就用 GLFW,而 **GLFW 在 Linux 下就是跑 Wayland**——所以「让 ArkUI 在 Wayland 窗口里出现」几乎现成。但它是单页预览器,没有完整 app 运行模型。等价于 mac 上「没做预览器、做了真 app」的取舍。

---

## 五、里程碑 + 工作量(路线 A · M1 对等)

| 阶段 | 内容 | 相对 mac |
|--|--|--|
| **A 构建地基** | linux-arkui-x 桌面 product + 复用 `toolchain/linux` | **远少于** mac(toolchain 已有) |
| **B libace 编通** | `is_arkui_x` gating + 摘开 preview 路由;预计修复点远少于 mac(原生 OS、原生字体) | **少** |
| **C `adapter/linux`** | wl 窗口 + EGL 窗口 surface + wl-frame vsync + wl_seat 输入 | **新增大头,但低风险** |
| **D 上屏** | `ace` 可执行 + Wayland 窗口 + 渲染 `.ets` | **无 GL 共享组 / 字体 archaeology** |

mac 那次约 30+ 轮编译、大半耗在渲染倒推;Linux 的 Wayland 胶水是**可预先编码**的(少 archaeology),迭代次数应明显更少。

---

## 六、风险(老实说)

1. **preview 路由解耦**:Linux 当前被 `rosen_preview` 捕获,要干净地分出「Wayland 真适配」vs「GLFW 预览」——设计决策,非阻塞。
2. **桌面无 RenderService 守护进程**:确认 Android 式客户端侧 `RSRenderThread` + EGL 在 Linux 桌面 work(Android 正是这么干的,理应可行);vsync/director 接线可能要少量复刻(有 Android 作可跑参考)。
3. **Wayland 协议面**:xdg-shell、libdecor 装饰、分数缩放(fractional-scale)、dmabuf——真实但有界。
4. **Mesa/驱动差异**:Intel/AMD/NVIDIA 的 EGL/GL 行为矩阵,标准测试范畴。

---

## 七、关键文件索引(起手即用)

| 主题 | 文件 | 要点 |
|--|--|--|
| target_os=linux 分支 | `build/config/BUILDCONFIG.gn:547` | linux 工具链分支已存在 |
| use_linux / is_desktop_linux | `foundation/arkui/ace_engine/ace_config.gni:113`、`BUILDCONFIG.gn:355` | 平台布尔已定义 |
| EGL 窗口 surface(可复用) | `…/2d_graphics/src/render_context/new_render_context/render_context_gl.{h,cpp}` | `eglCreateWindowSurface` 直接上屏;含 `EGL_EXT_platform_wayland` 探测 |
| 离屏 FBO 仅限 ios/mac | `render_context_gl.h` 的 `#if defined(ROSEN_IOS)\|\|defined(ROSEN_MAC)` | Linux 不走离屏 FBO,无共享组问题 |
| RS 正路 Init | `…/render_service_client/core/ui/rs_ui_director.cpp:85-131` | OHOS 路径本就正确 Init+设 client+起线程 |
| OHOS vsync(走 IPC) | `…/render_service_base/src/platform/ohos/rs_vsync_client_ohos.cpp:24-56` | 桌面需自带 frame-callback 驱动替代 |
| 字体原生路 | `third_party/skia/m133/gn/skia.gni`(`skia_use_fontconfig=is_linux`) | freetype+fontconfig,无需 CoreText |
| 窗口接口 | `adapter/macos/entrance/virtual_rs_window.h:122-310` | 新 wayland 实现要落的方法清单 |
| 输入注入链 | `adapter/macos/stage/uicontent/ace_view_sg.cpp`(`DispatchTouchEvent`) | wl_seat → ProcessPointerEvent/KeyEvent → 此处 |
| Android keycode 映射(可抄) | `adapter/android/entrance/java/jni/virtual_rs_window.cpp` | 完整 keycode 表 |
| preview 路由开关 | `…/render_service_base/config.gni:37` | 需把 linux 从 rosen_preview 摘开 |

---

> 一句话:macOS 那次是「逆着系统走」(把 iOS/AppKit 凑成桌面,跟 GL/字体/工具链死磕);**Linux Wayland 是「顺着系统走」**——OHOS 的原生母系统 + 原生 EGL/fontconfig + Android 现成的客户端侧渲染参考,只剩一块边界清晰的 Wayland 窗口/输入胶水。**更省、更稳、更可预测。**
