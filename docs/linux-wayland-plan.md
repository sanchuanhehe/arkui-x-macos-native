# ArkUI-X → Linux/Wayland 原生移植 · 正式计划

> 评估见 [`linux-wayland-assessment.md`](linux-wayland-assessment.md)(已在 master 源码逐条复核为真)。
> 本文锁定**最终目标、技术路线、仓库结构、分阶段计划**,作为正式工作的执行基线。
> **实证日志(实际达成状态 / 链接 0-undefined 方法论 / Stage D bundle 根因深析 / 补丁集规则)见
> [`linux-port-journal.md`](linux-port-journal.md)。** adapter 代码侧实现机制见
> `arkui_for_linux/docs/实现笔记.md`。

## 0. 锁定的决策

| 项 | 决定 |
|----|------|
| **最终目标** | **完整实现**(见 §0.1):ArkUI-X 在 Linux/Wayland 上的**完整可用原生桌面运行时**——渲染 + 输入 + 窗口管理 + 应用模型 + 打包,全部实现并在本机验证。**M1 对等(渲染 `.ets` 页面)是第一个里程碑,不是终点。** |

### 0.1 完整实现目标 · Definition of Done

全部实现并在本机(headless weston + 截图)验证:

1. **渲染**:标准 `.ets`(声明式 ArkUI)→ 方舟 `ets_runtime` → RS 客户端侧渲染树 → EGL window surface → Wayland 窗口。freetype/fontconfig 中英文文字、颜色、圆角、布局、动画。
2. **输入**:`wl_seat` 键盘(xkbcommon)/ 指针 / 触摸 全链路 → ArkUI 事件,页面有真实交互响应。
3. **窗口管理**:xdg_shell + libdecor 装饰、resize / 最小最大化、HiDPI + fractional-scale、多窗口(subwindow)。
4. **应用模型**:`ace` 可执行 + 完整 ability/AbilityStage 生命周期 + 官方 `ace build bundle` 加载标准 stage 工程 + 全套系统模块 `.abc`。
5. **工程化**:全部以 `linux-*.patch` 补丁集(本仓 `linux` 分支)+ `adapter/linux` 独立子仓([`arkui_for_linux`](https://github.com/sanchuanhehe/arkui_for_linux))落地,`apply_patches.sh` 一键复现。
6. **CI 回归**:本机/runner 的 headless weston 下**真编 → 真跑 → 截图回归**;`libace_static_linux` 全编通 + `ace_linux` 0 undefined。
7. **打包**:`.desktop` + AppImage(或 flatpak)可分发桌面应用。

> 任务分解见任务清单(阶段 A→B→C1→C2→D → 输入/窗口管理 → 工程化/CI → 打包)。
| **技术路线** | **路线 A**:专门 `adapter/linux` + 照 **Android `ROSEN_ARKUI_X` 客户端侧 EGL 渲染**;把 Linux 从 `rosen_preview`(GLFW)路由摘出。不做预览器路线 B。 |
| **工程仓** | 适配补丁集 + 脚本继续放本仓(`arkui-x-macos-native`),新增 `patches/linux-*.patch` 与 `apply_patches.sh` 的 linux 接线。 |
| **adapter 子仓** | 新建独立仓 **[`sanchuanhehe/arkui_for_linux`](https://github.com/sanchuanhehe/arkui_for_linux)**,对齐 `arkui_for_macos`/android/ios,克隆到 `ace_engine/adapter/linux/`。 |
| **构建/验证** | **本机(Linux aarch64)直接真编真跑**——环境已搭好(见 §2),每个里程碑都有可执行验证 + 截图,可 CI。 |

## 1. 为什么比 macOS 港更省(复核结论)

macOS 港吃掉大半精力的三类坑在 Linux 直接消失,均已在本仓源码 file:line 复核:

- **GL 共享组/离屏 FBO/Y 翻转(mac 白屏真凶)** → 消失。`render_context_gl.h:25/82/120` 的离屏 FBO 仅 `#if defined(ROSEN_IOS)||defined(ROSEN_MAC)`;Linux 走 `render_context_gl.cpp:279 eglCreateWindowSurface(nativeWindow_)` 真窗口 surface。
- **CoreText 字体考古** → 消失。`skia/m133/gn/skia.gni:59 skia_use_fontconfig=is_linux`、`:62 skia_use_freetype=…||is_linux`,freetype+fontconfig 是 skia 在 Linux 的原生正路。
- **OS 原语 shim / Xcode-clang / Carbon 撞名** → 消失。Linux 是 OHOS 母系统,epoll/eventfd/pthread/fontconfig 原生;原生 clang/gcc,无 ObjC/Carbon。
- **RS 渲染管线五层坑** → 大部分消失(源于 mac 复用 iOS 后端)。Linux 照 **Android** 客户端侧 `RSRenderThread`。

净新增主要就一块:**Wayland 协议胶水**(全树 `grep wl_/xdg_/wayland` = 0,完全 net-new 但边界清晰、低风险)。

## 2. 本机构建/运行环境(已就绪)

```bash
# 开发库(已装)
apt-get install -y libwayland-dev wayland-protocols libxkbcommon-dev \
  libegl-dev libgles-dev libgbm-dev libdrm-dev libdecor-0-dev \
  weston mesa-utils mesa-utils-extra pkg-config
```
- 已验证:wayland-client 1.22 / wayland-egl 18.1 / egl 1.5 / glesv2 3.2(Mesa **llvmpipe** 软渲染,GPU `card0` 亦在)/ xkbcommon 1.6 / libdecor 0.2.2;`weston`/`eglinfo`/`wayland-scanner` 齐。
- 运行验证:`weston --backend=headless --socket=wayland-9 --width=480 --height=800` 成功起 socket。
- 工具链:`prebuilts/clang/ohos/linux-aarch64` 已下;源码 + prebuilts 就绪。
- **截图验证手段**:headless weston + `weston-screenshooter`,或离屏 EGL `glReadPixels` 落 PNG。

## 3. 必须先做的架构解耦

`render_service_base/config.gni:37` 现把 Linux 归入预览路由:
```gni
rosen_preview = (rosen_is_mac && !mac_use_ios_backend) || rosen_is_win || rosen_is_linux
```
**动作**:加 `linux_use_wayland_backend`(或复用 `is_arkui_x`)开关,把 arkui-x 的 Linux 从 `rosen_preview` 摘出 → 走 `ROSEN_ARKUI_X` 客户端侧 EGL。已有 `ROSEN_LINUX` 宏(`config.gni:97`)可借力。

## 4. 分阶段计划(路线 A · M1 对等)

> 每阶段 = 一个可验证硬节点,在本机真编真验。

### 阶段 A — 构建地基
- 新增 `arkui-x` 的 Linux desktop product(对照 mac product),复用现有 `//build/toolchain/linux`(无需像 mac 新建 toolchain/find_sdk)。
- `adapter/linux/build:ace_linux` 骨架 + `build/core/gn/BUILD.gn` 的 `target_os=="linux"` 分支 + `ace_config.gni`/`config.gni` 路由开关。
- **验证**:`gn gen` 通过,`ninja` 能加载(无重复规则)。

### 阶段 B — libace 编通(`libace_static_linux`)
- `is_arkui_x` gating + §3 的 preview 路由摘除;预计修复点**远少于 mac**(原生 OS/字体/工具链)。
- **验证**:`ninja libace_static_linux` 全编通(对标 mac 的 7224 .o 节点)。

### 阶段 C — `adapter/linux`(净新增大头,低风险)→ 落 `arkui_for_linux`
1. **窗口层** `virtual_rs_window`:`wl_display`/`wl_registry`/`wl_compositor`/`xdg_shell`(`xdg_surface`+`xdg_toplevel`)/`wl_egl_window`→`EGLSurface`;CSD 装饰用 **libdecor**。实现接口清单见 `adapter/macos/entrance/virtual_rs_window.h:122-310`。
2. **vsync**:`wl_surface.frame` 回调驱动 `RequestNextVsync`(替代 OHOS 走 IPC 的 `RSVsyncClientOhos`;位置同 mac 的 CVDisplayLink driver,但无共享组)。
3. **输入**:`wl_seat`(`wl_keyboard`/`wl_pointer`/`wl_touch`)+ **xkbcommon** keysym → `Window::ProcessPointerEvent/KeyEvent` → `UIContentImpl` → `AceViewSG::DispatchTouchEvent`。keycode 表抄 `adapter/android/entrance/java/jni/virtual_rs_window.cpp`。
- **验证**:`ace_linux` 链出 0 undefined;起 Wayland 窗口(weston headless 下 `weston-info`/截图可见 surface)。

### 阶段 D — 上屏(M1 对等达成)
- `ace` 可执行 + 完整 ability 生命周期 + 官方 `ace build bundle` 产 `.abc` → RS 客户端侧渲染树 → EGL window surface → **Wayland 窗口显示 `.ets` 页面**(中英文 freetype/fontconfig 文字)。
- **验证**:headless weston 截图显示标准 ArkUI 页面(对标 mac 的 `M1_arkui_rendered.png`)。

## 5. 仓库结构(对齐 macOS 港)

```
arkui-x-macos-native/                 # 工程仓(补丁 + 脚本)
  patches/linux-*.patch               # 阶段 A/B/C 的 mac-gate 等价物(linux-gate)
  scripts/apply_patches.sh            # 末尾加:git clone arkui_for_linux → adapter/linux/
  docs/linux-wayland-plan.md          # 本文

arkui_for_linux (独立 GitHub 仓)       # adapter/linux 窗口层/osal/stage/build
  → 克隆到 foundation/arkui/ace_engine/adapter/linux/(被 ace_engine .gitignore: adapter/* 忽略)
```

## 6. 风险(有界)

1. **preview 路由解耦**:设计决策,非阻塞(§3)。
2. **桌面无 RenderService 守护进程**:确认 Android 式客户端侧 `RSRenderThread`+EGL 在桌面 work(Android 即如此);vsync/director 接线可能少量复刻(有 Android 参考)。
3. **Wayland 协议面**:xdg-shell / libdecor 装饰 / fractional-scale / dmabuf——真实但有界。
4. **软渲染**:本机默认 llvmpipe(无 GPU 加速);功能验证足够,性能另说。GPU `card0` 可后续启用。

## 7. 关键文件索引(起手即用,已复核)

| 主题 | 文件:行 |
|------|---------|
| linux 平台布尔 | `build/config/BUILDCONFIG.gn:355`(is_desktop_linux)、`ace_config.gni:113`(use_linux) |
| EGL 窗口 surface(复用) | `…/render_context_gl.cpp:279`、wayland 探测常量 `:30-31` |
| 离屏 FBO 仅 ios/mac | `…/render_context_gl.h:25/82/120` |
| preview 路由开关 | `…/render_service_base/config.gni:37`(摘 linux)、`:97`(ROSEN_LINUX) |
| 字体原生路 | `third_party/skia/m133/gn/skia.gni:59/62` |
| 窗口接口清单 | `adapter/macos/entrance/virtual_rs_window.h:122-310` |
| 输入注入链 | `adapter/macos/stage/uicontent/ace_view_sg.cpp`(DispatchTouchEvent) |
| Android keycode(可抄) | `adapter/android/entrance/java/jni/virtual_rs_window.cpp` |

---
> 一句话:**顺着系统走**——OHOS 原生母系统 + 原生 EGL/fontconfig + Android 现成客户端侧渲染,只剩一块边界清晰的 Wayland 窗口/输入胶水。且本机可真编真跑真截图,迭代可预测。
