# ArkUI-X macOS 原生移植 · 路线 B 全量 Roadmap(对齐 iOS/Android)

> **目标**:把 macOS 原生移植从「M1:渲染一帧」推到**与 iOS/Android 成熟 ArkUI-X 平台完全对齐**——`capability/` 能力插件层(12 个)+ `entrance/` 子系统(~10 个)全部落地,去掉所有「先跑起来」的 mac-gate hack,可一键打包成签名 `.app`,有测试与 CI。
>
> **完工定义(Definition of Done)**:`adapter/macos` 的能力面 ≈ `adapter/ios`;主流组件 / 动画 / 多页 / Web / Video / XComponent / IME / 无障碍 / i18n 均可用;`ace build mac` 直接产出可分发 `.app`;真构建 + 渲染回归进 CI。

## 基线(已完成)
- **M0 地基** ✅:GN `target_os=mac` 管线、macOS 图形后端(NSOpenGL/CALayer/桌面 FBO)、`libace` 全编通、`ace_macos` 链出、AppKit 开窗。
- **M1 渲染** ✅:标准 `.ets` 页面经 `ace build bundle` → 方舟运行时 → RenderService → CAOpenGLLayer 上屏;中英文文字(CoreText)+ 颜色 + 圆角 + 布局。

---

## 阶段总览

| 阶段 | 名称 | Goal(一句话) | 依赖 |
|--|--|--|--|
| **M2** | 核心交互 | 页面可交互:点击/滚动/键盘/文本输入(含 IME)都工作 | M1 |
| **M3** | 窗口/渲染完备 | 窗口像原生 app:resize 重排、暗色模式、子窗口、多屏;渲染脏区驱动(去 CPU 空转) | M2 |
| **M4** | 核心能力插件 | 日常组件依赖的能力齐活:图片(含 URL)、字体、剪贴板、存储、选择器、下载 | M2 |
| **M5** | 富媒体与原生载体 | XComponent / Web / Video / Canvas 跑起来 | M4 |
| **M6** | 组件广度 | 主流组件 + 动画 + 多页导航全部验证可用 | M2, M4 |
| **M7** | 系统 API / NAPI | 常用 `@ohos.*` 模块工作 + native module 加载 | M2 |
| **M8** | 无障碍 / i18n / 安全 | 可访问、国际化、安全合规 | M3 |
| **M9** | 打包与分发 | `ace build mac` → 可分发签名 `.app` | M4 |
| **M10** | 质量与硬化 | 去 hack、稳定、有测试、CI 跑真构建 | 全部 |

> **跨 Linux 复用**:M2(输入分发)、M3(脏区渲染)、M4/M5/M6(能力与组件,跨平台抽象部分)、M7(NAPI)在 macOS 做一遍,Linux Wayland 大半直接拿。**mac 专属**:NSPasteboard、NSAccessibility、NSTextInputClient IME、WKWebView、`.app` 签名公证、CoreText。详见 [`linux-wayland-assessment.md`](linux-wayland-assessment.md)。

---

## M2 · 核心交互
**Goal**:页面可交互——点击、滚动、键盘、文本输入(含中日韩 IME)都工作。
**Tasks**
- 鼠标事件:`WindowView.mouseDown/mouseDragged/mouseUp` → 建 `AcePointerDataPacket`(位置 × `backingScaleFactor`)→ `window->ProcessPointerEvent`(DOWN/MOVE/UP)。[iOS 参考:`adapter/ios` dispatchTouches] [跨 Linux]
- 右键 / 多指 / `scrollWheel`(滚动)/ `magnifyWithEvent`(捏合缩放)。[跨 Linux]
- 键盘:`keyDown/keyUp` → NSEvent keyCode + modifierFlags 映射 `Ace::KeyCode` → `ProcessKeyEvent`。[部分跨 Linux:keycode 映射表]
- **文本输入 IME**:接 `NSTextInputClient`,把组合输入/候选词喂给 `TextInput`/`TextArea`(中日韩)。[mac 专属;Linux 用 xkbcommon+text-input 协议]
- 焦点 / 光标 / 命中测试链路打通。
- **渲染硬化**:`rs_render_thread.cpp` 强制连续 `RequestNextVSync` → 改**脏区驱动**(仅 dirty 时渲),停 CPU 空转。[跨 Linux]

**完成判据**:demo 含可点 `Button`(点了变色/计数)、可滚 `List`、可输中英文的 `TextInput`;空闲时 CPU≈0。

## M3 · 窗口 / 渲染完备
**Goal**:窗口行为像原生 app。
**Tasks**
- 窗口 `resize` → 根 `SetRootRect` 更新 → 布局重排(去掉固定尺寸 hack)。
- Retina / `backingScaleFactor` 变化(拖到不同 DPI 屏)。
- **暗色模式**:`SettingDataManager` 接 `NSApp.effectiveAppearance` + `NSAppearance` KVO → 主题切换。
- **子窗口**:`SubwindowManager` 接 AppKit → `Dialog` / `Menu` / `Popup` / `Toast` / 下拉。
- 多窗口、多显示器坐标、色彩管理/HDR。

**完成判据**:窗口可拉伸重排;切系统暗色模式页面跟随;弹窗/菜单/Toast 正常。

**实测(2026-06-28)** 🔶 暗色模式 ✅:`WindowView -viewDidChangeEffectiveAppearance` 把 `NSApp.effectiveAppearance`(Aqua/DarkAqua)映射成 `ohos.system.colorMode` 配置 → `window->UpdateConfiguration` 实时切换;`StageViewController initColorMode` 启动时也改为读 `currentColorMode`(原硬编码 Light,Dark 下启动会渲成浅色)。端到端实证:Light 截图(白底/colorMode=LIGHT/☀️)vs Dark 截图(深底 #1E1E1E/colorMode=DARK/🌙),`@ohos.mediaquery '(dark-mode: true)'` 正确匹配。

**实测(2026-06-28)** 🔶 resize ✅:窗口拉伸链路 `WindowView -layout` → `NotifySurfaceChanged` → `Window::NotifySurfaceChanged` → `uiContent_->UpdateViewportConfig(RESIZE)` 已通。端到端实证:窗口从 1024×768 拉到 1500×950,`onAreaChange` 报 `view 1024×768 → 1370×844 vp`,`width('80%')`/`width('50%')` 的色条同步变宽(截图前后对比)。

**实测(2026-06-28)** 🔶 子窗口 NSPanel 框架(WIP):**根因**——`Window::ShowWindow` 原先对子窗口也走 `[windowView_ showOnView:mainWindowView.superview]`,把子窗口 addSubview 进**主窗口 view 层级**,所以 Menu/Popup/Dialog 全困在主窗口边界内(桌面上不合理)。**已改**:`WINDOW_TYPE_APP_SUB_WINDOW` 走独立 `NSPanel`(borderless + `addChildWindow` 挂主窗口,可超出边界);Move/Resize/Hide 映射到 panel 屏幕坐标;未定尺寸时 fallback 全屏(引擎按全屏透明容器建模,iOS 同)。框架实证:panel 全屏创建成功(`frame=(0,0 1470x956) childOf main`),主窗口路径不变且稳定。**渲染管线攻坚(2026-06-28)**:用 workflow 系统调查渲染管线后定位**根因=`RenderContextGL` 把 colorbuffer 写进 static 全局**("最后 MakeCurrent 赢",两个 WindowGLLayer 读同一 static → 子窗口显示主窗口内容/冲突)。**已修(核心 race)**:`render_context_gl.h` 加 per-instance accessor;`RSSurfaceGPU::FlushFrame` 把自己实例的 colorbuffer 经 KVC 推到自己的 WindowGLLayer;layer blit 自己的 `sourceColorbuffer`(非 static)+ 子窗口 alpha-clear 透明。`SubwindowIos::ShowWindow` 先 `ResizeWindow` 设全屏。**主窗口验证稳定**(截图实证),且这个 per-layer surface 能力是 **M5 XComponent/Web 原生子 surface 的同源基础**。**剩(窗口管理层,非渲染)**:全屏透明 `NSPanel`(覆盖主窗口)+ `NonactivatingPanel` + `addChildWindow` 使打包 .app 跑子窗口时 graceful 退出(无崩溃)——主窗口被全屏子窗口盖住后 NSApp 退出,待调焦点/生命周期。**余**:Retina DPI、多屏 待验证。

**可拖动子窗口 + 渲染隔离彻底打通(2026-06-29)** ✅:@ohos.window `createSubWindow` + `setUIContent` + `moveWindowTo` 端到端工作,子窗口渲染自己的页面、可拖动、可超出主窗口。修掉两个真因:① **主窗口频闪 + 子窗口内容画到主窗口** 的根因比上一轮更深——`RSRenderThread` 只持有**一个全局 RenderContext**(`rs_render_thread_visitor.cpp` 把同一 context 赋给每个 surface),所以 KVC per-instance colorbuffer 形同虚设(只有一个实例),单个 renderbuffer 还在主/子窗尺寸间每帧 `glRenderbufferStorage` realloc。**已修**:`RenderContextGL` 改为**按 CALayer 维护 per-layer 的 FBO+colorbuffer**(`layerTargets_` map),`framebuffer_/colorbuffer_` 降级为"当前 layer 目标"的镜像,每窗口渲染到各自离屏目标(`render_context_gl.h` + `appframework/.../render_context.mm`)。② **子窗口完全空白** 的根因——`startBaseDisplayLink` 只被 `StageViewController`(主窗口)调用,子窗口的 `CAOpenGLLayer`(`asynchronous=NO`)永不收到 `setNeedsDisplay` → `drawInCGLContext` 不跑 → 透明/空白。**已修**:`Window::ShowWindow` 子窗口分支给子窗口 WindowView 启动自己的 CVDisplayLink。可拖动经 `WindowView mouseDown → performWindowDragWithEvent`(实测拖拽位移与输入精确一致)。附:`log_wrapper` 加 `ACE_LOG_STDERR=1` 明文 stderr 镜像(绕开 os_log `<private>`,是这次定位的关键工具)。**遗留小瑕疵**:`createSubWindow` 会多出一个 500x500 空白窗口(改动前即存在,AppKit/CA 隐式产物,待查)。

## M4 · 核心能力插件(`capability/` 大头)
**Goal**:日常组件依赖的平台能力齐活。
**Tasks**(新建 `adapter/macos/capability/` + `entrance/` 子系统)
- **DownloadManager**(`entrance/`,现 stub 返回 nullptr)→ URLSession 实现 → 解锁 **URL 图片 / 远程资源**。[跨 Linux]
- **Image 完整**:本地解码(`image_source_ios` 复用核对)+ URL + 缓存 + `$r` 资源。
- **clipboard**:`MultiTypeRecordImpl` + NSPasteboard(文本/图片/HTML)。[mac 专属]
- **font**:自定义字体注册(`@font-face` / `registerFont`)→ CTFontManager。[mac 专属后端]
- **storage**:本地存储 / preferences。[跨 Linux 抽象]
- **picker**:文件/图片/日期选择器 → `NSOpenPanel`/`NSSavePanel`。[mac 专属]
- **environment** / **resource register**。

**完成判据**:`Image`(本地+URL)显示;复制粘贴可用;自定义字体生效;文件选择器弹出。

## M5 · 富媒体与原生载体
**Goal**:XComponent / Web / Video / Canvas 可用。
**Tasks**
- **surface / texture**:`AceSurfaceHolder` / `AceTextureHolder`(XComponent 的原生 surface/纹理载体)。[mac 专属:IOSurface/CVPixelBuffer]
- **platformview**:原生视图内嵌。
- **web**:`Web` 组件 → WKWebView。[mac 专属]
- **video**:媒体播放 → AVFoundation。[mac 专属]
- **Canvas** 2D 路径验证。

**完成判据**:`XComponent` 拿到 GL/native surface;`Web` 加载网页;`Video` 播放。

**实测(2026-06-29)**:🟢 **Canvas 2D ✅ 端到端可用**——`fillRect` / `createLinearGradient`+`arc`+`fill`(线性渐变圆) / `strokeRect` / `fillText`(含中文,CoreText) / `moveTo`+`lineTo`+`stroke`(折线)全部正确渲染(截图实证)。Canvas 走标准 Skia 管线,在新 per-layer surface 上直接可用,无需原生子 surface。🟢 **Retina 高 DPI ✅ 隐式验证**——全程 2x backingScale 锐利渲染。🔶 **Web / Video / XComponent**:跨平台抽象层齐全,iOS 适配完整(`adapter/ios/capability/web` WKWebView 138KB、`video` AVPlayer、`texture` XComponent),但 **mac adapter 完全缺这三个 capability 目录**;`graphic_2d/macos/rs_surface_gpu.mm` 的 `CreateSurfaceExt` 明确返回 nullptr(XComponent 图形层未实现)。Web/Video 可移植(WKWebView/AVPlayer 在 mac 同样可用,UIKit→AppKit),XComponent 需补图形层 SurfaceExt。

## M6 · 组件广度
**Goal**:主流组件 + 动画 + 多页全部验证可用。
**Tasks**
- `List` / `Grid` / `Scroll` / `Swiper`(依赖 M2 输入 + 脏区渲染)。
- 动画 / 转场 / 共享元素。
- `router` 多页导航(`pushUrl`/`back`/`replaceUrl`)。
- `Dialog` / `Menu` / `Popup` / `Toast`(依赖 M3 子窗口)。
- 逐组件兼容性扫描,记录差异。

**完成判据**:一个多页 demo(导航 + 列表滚动 + 动画 + 弹窗)端到端跑通。

**实测(2026-06-29)**:🟢 **非动态组件广度 ✅**——`Button` / `Image` / `Progress`(Linear+Ring) / `LoadingProgress` / `List`+`ForEach`+`ListItem` / `Column`/`Row`/`Stack`/`Flex` / `Text` / `Canvas` 全部渲染正常(截图实证);叠加既往已验证的 `animateTo` / `Dialog`(独立 NSPanel)/ 多页导航。🔴 **动态模块组件(~22 个)被刻意桩成 null**——`Slider`/`Checkbox`/`Toggle`/`Rating`/`Radio`/`Stepper`/`Gauge`/`WaterFlow`/`QRCode`/`Search`/`TimePicker`/`Richeditor` 等走 `DynamicModuleHelper::GetDynamicModule()` 懒加载,iOS 编成 per-component dylib framework,**mac 在 `mac_link_stubs.cpp` 把 `OHOS_ACE_DynamicModule_Create_Slider()` 等全返回 nullptr 仅为链接通过**(同 Menu/MenuItem)。要真用需把每个组件的 `*_dynamic_module.cpp` + `arkts_native_*_bridge.cpp` + `node_*_modifier.cpp`(arkoala 层,与已静态化的 Text/Button bridge 同源)编进 ace_macos 并在 `dynamic_module_helper.mm` 返回真实模块——较大但路径明确(arkoala bridge 在 mac 已可编,Text/Button 即证)。

**动态模块表单组件打通(2026-06-29)** ✅ **Slider / Checkbox / Rating 端到端渲染**(截图实证:滑轨/勾选框/星级)。这些组件走 `DynamicModuleHelper` 懒加载,iOS 编成 per-component dylib;mac 上 dylib 方案撞两堵墙——① 组件 dylib 与静态 host 各持一份 inline 单例 → **C++ 全局状态分裂**,渲染时 SIGSEGV(`-undefined dynamic_lookup`/flat 都没解决,lldb 不复现=典型 TLS/未初始化);② 共享 libace.dylib 撞**原作者注释记录的 123 dead-ref 符号**(`RSRenderServiceClient`/`ImageAnalyzerMgr`,静态 + dead-strip 能丢、dylib 丢不掉)。**正解=静态链接**:`adapter/macos/build/BUILD.gn` 给 `ace_macos` deps 加各组件 `*_pattern_ng_mac` source_set(含 pattern + arkts bridge,暴露 `OHOS_ACE_DynamicModule_Create_<C>()`),`dynamic_module_helper.mm` 照 Menu 加 `g_*Module`+`GetStaticModule` 返回真实模块。单一二进制 → **链接器自动合并弱符号(无分裂)+ dead-strip 自动丢 dead-ref(无墙)**。唯一代价:per-component 重复 helper(`GetNativeNode`/`IsJsView`/`CreateFrameNode`/`SetOnChangeEvent` 在各组件 bridge 各定义一份,与已链接的 qrcode 撞)需加 `static` 内部链接隔离(slider/rating 各几处;checkbox/slider 的部分本就在匿名命名空间)。**可扩展到 soMap 全部 ~22 个组件**,逐个加 dep + 隔离重复 helper 即可。

**框架级修复(2026-06-29)** ✅ **preload abc 双重执行**:跨平台共享 runtime 下 `InitAceModule`(页面引擎)与 `PreloadAceModule`(全局 runtime)对同一 runtime 各跑一遍 preload,而 `arkCommon.abc`(`const arkUINativeModule`)/`stateMgmt.abc`(`class stateMgmtConsole`)/`jsEnumStyle.abc` 等有顶层 lexical 声明,第二次 "Duplicate identifier" 中断 `func_main_0` → `LogTag` 等全局半初始化 → 表单组件创建崩,且被 `LogTag` undefined 的二次错误掩盖成 "Cannot read property STATE_MGMT of undefined"(即 memory 记的「LogTag 掩盖崩」)。**修复**:`jsi_declarative_engine.cpp` 加 `PreloadAbcOnce` 模板(global 上哨兵属性,**每 runtime 只执行一次**),套用全部 6 个 preload。实测:所有 `Cannot execute ark buffer` 归零、掩盖消失、真错误现形(揭示动态模块桩问题)。这是 M6 调试硬化 + M10 去 hack 的实质改进。

## M7 · 系统 API / NAPI 覆盖
**Goal**:常用 `@ohos.*` 模块工作。
**Tasks**
- `@ohos.router` / `@ohos.promptAction`(Toast/Dialog/Menu)。
- `@ohos.data.preferences` / storage。
- `@ohos.net.http` / connection。
- 设备 / sensor / 媒体类 API(按需)。
- native module / plugin 动态加载(`plugin_lifecycle`)。

**完成判据**:demo 调 router/prompt/http/preferences 均成功。

**实测(2026-06-28)** ✅:23 个 `@ohos.*` NAPI kit 静态链接进 `ace_macos`——每个 kit 经 `__attribute__((constructor))` → `napi_module_register` 自注册(对齐 iOS 的 `_static_<platform>` source_set 聚合,无需 dylib)。`prompt`/`drawabledescriptor` 因与 libace 重复符号排除;`componentUtils`/`animator`/`dragController` 修复重复 base 源后恢复。

## M8 · 无障碍 / i18n / 安全
**Goal**:可访问、国际化、安全合规。
**Tasks**
- **accessibility**:`ExecuteActionOC`/`UpdateNodesOC`(现 stub)→ NSAccessibility / VoiceOver。[mac 专属]
- i18n / RTL / 本地化资源。
- 沙箱 / 权限(相机/麦克风/文件,Info.plist usage descriptions)。
- 安全存储(Keychain)、UDMF 拖拽数据。

**完成判据**:VoiceOver 可读 UI;RTL 布局正确;权限弹窗合规。

**实测(2026-06-28)** ✅ i18n 完全打通:`@ohos.i18n` / `@ohos.intl` 静态链接进 `ace_macos`,系统 API + ICU 格式化全部工作。截图实证:i18n:OK intl:OK language=zh-Hans-CN region=CN locale=zh-Hans-CN **date=2026年6月28日星期日 14:30**(DateTimeFormat)**currency=¥123,456.79**(NumberFormat)。
- **平台层**:两个 plugin 的 mac 实现复用 iOS Foundation-only impl(`NSLocale`/`NSTimeZone`,`intl` 的 `UIDevice`/`getDeviceType` 用 `MAC_PLATFORM` 守卫返回 `"pc"`)。
- **ODR**:`i18n`/`intl` 各 fork 一份 `OHOS::Global::I18n::LocaleConfig`(static 成员 `I18N*` vs `INTL*`)——iOS 各自 dylib 隔离,mac 静态链进单 exe 触发 37 dup;解法 intl 复用 i18n 的核心 + i18n 补 intl 特有的 3 个方法(`locale_config_intl_ext.cpp`)。
- **ICU data**:build 链 ICU stubdata(空 `U_ICUDATA_ENTRY_POINT`)→ 所有 format 返回空;mac 改为运行时 mmap 真实 31MB `icudt74l.dat`(`package_app.sh` 打包进 `Resources/icu/`)喂 `udata_setCommonDataAfterClean`。
- **关键教训**:dylib + flat-namespace 路线行不通——阻止 dead-strip,强制解析 123 个死引用符号;静态链接 + dead-strip 才是 mac 正道。

**无障碍(2026-06-28)** ✅:`mac_accessibility_bridge.{h,mm}` 把引擎 `NG::FrameNode` a11y 树(经 `AceEngine` container → `NG::PipelineContext::GetRootElement`)抽成扁平节点(role/label/value/frame/checkable);`WindowView` 实现 `NSAccessibility` 协议——作为容器,`accessibilityChildren` 把树镜像成 `NSAccessibilityElement`,ArkUI tag 映射 AppKit role(Text→StaticText / Button→Button / TextInput→TextField / Toggle→CheckBox),引擎 window-px 矩形转屏幕坐标。`StageViewController` 把 instanceId 传给 WindowView。实证:Text 页暴露 12 节点,label('i18n: OK'/'language=zh-Hans-CN'...)+ 几何正确,VoiceOver/Accessibility Inspector 可读。

**M8 余下**:Keychain 安全存储、UDMF 拖拽数据。

## M9 · 打包与分发
**Goal**:一键产出可分发签名 `.app`。
**Tasks**
- **`ace build mac`**:`ace_tools` 直接产出 `.app`(替掉手动拷 abc + `MacAppDelegate` 硬编码 BUNDLE/MODULE/ABILITY)。
- `.app` bundle:Info.plist、图标、资源、systemres abc 自动打包。
- **代码签名 + 公证**(notarization),否则他人下载打不开。
- 崩溃上报 / 符号化。

**完成判据**:`ace build mac` 一条命令出 `.app`;双击即开;Gatekeeper 放行。

**实测(2026-06-28)** 🔶:`package_app.sh` 组装可运行 `.app`(install_name_tool 修 dylib 路径、资源进 `Contents/Resources`、Info.plist、自底向上 codesign)。修复双击启动时弹一堆目录授权的 **TCC 隐私权限风暴**——真因是 GUI 启动 `cwd=/`(LaunchServices 不继承 shell cwd)+ 相对路径 `opendir` 递归遍历整盘,触发每个 folder service;解法 = constructor `chdir` 到 bundle + asset 扫描守卫(空/`/` 路径直接 bail)。**剩**:Developer-ID 签名 + 公证(notarization)需 Apple 开发者证书。

## M10 · 质量与硬化
**Goal**:去 hack、稳定、有测试、CI 跑真构建。
**Tasks**
- 审计并替换**所有 mac-gate hack**(forced FlushVsync / forced mark-dirty / 连续 vsync / mac_link_stubs 残留)为正确实现。
- 内存 / 生命周期(窗口关闭 teardown)/ 多实例 / 无泄漏。
- 性能调优(GPU 路径、离屏 FBO 开销、启动时延)。
- 测试体系:单测 + UI 自动化(合成输入)+ 渲染回归(截图比对)+ 兼容性。
- **CI 跑真构建**(可能用 macOS runner / 自托管)+ 渲染回归。

**完成判据**:0 mac-gate hack;关窗无泄漏;CI 绿(编译 + 渲染回归)。

---

## 依赖与排期建议
```
M2 ──┬─→ M3 ──→ M8
     ├─→ M4 ──┬─→ M5
     │        └─→ M6 ──→(并入 M10）
     └─→ M7
            M4 ──→ M9
   全部 ──────────→ M10
```
- **先做 M2**(解锁交互 + 给 Linux 留参考)+ 顺手 M2 里的渲染硬化。
- M3 / M4 / M7 可在 M2 后**并行**。
- M5 依赖 M4(surface/texture);M6 依赖 M2+M4。
- M9 在 M4 后可随时做;M10 收尾。

## 规模与现实预期
- M1 是「点亮」,占完整工作量一小部分;**路线 B 是团队级、季度级工程**(capability ~12 + entrance ~10 + 去 hack + 广度 + 打包 + 测试)。
- 但**高度可增量、可并行**,每个 capability/entrance 子系统独立可加,有 iOS `.mm` 逐文件参考。
- 进度在仓内 task 列表跟踪(每阶段一个 task,goal 见上)。

---

## 实测进度(本会话已实现并验证)

> 以下均在 mac 本地 编→跑→截图/注入输入 自验证,已提交本地 arkui-x。

### M2 核心交互 — 大部分完成
- **鼠标点击** ✅:NSEvent→AcePointerData→ProcessPointerEvent;注入点击 0→3 计数验证。
- **坐标修复** ✅(根因):`WindowView.isFlipped=YES`,`inView.y` 已是顶部原点,原代码又 `height-y` **双重翻转** → 点击位置上下颠倒 + 拖动方向反。去掉手动翻转后:上部点击选中 Item 2(原 Item 8)、手指上移露出 Item 10-21。
- **键盘** ✅:macOS 虚拟键码→HID usage 表→ProcessKeyEvent(+修饰键)。
- **滚轮/触控板** ✅:`scrollWheel:` 合成触摸 pan(含动量);方向正确(用户确认)。
- **渲染硬化** ✅:RS 连续 vsync→有界预热(240帧)+提交驱动 re-arm;idle CPU 满速→**1.2%**,交互保留。
- 待续:**IME**(NSTextInputClient,中日韩组合输入)。

### M3 窗口/渲染完备 — 部分(本就接好)
- **resize→布局重排** ✅:窗口拉到 760×600,百分比布局自适应(`-layout`→notifySurfaceChanged 已接)。
- **Retina/scale 变化** ✅:`viewDidChangeBackingProperties` 已接。
- 待续:暗色模式、子窗口(Dialog/Menu/Popup/Toast)、多窗口/多屏。

### M4 核心能力插件 — 起步
- **DownloadManager** ✅:NSURLSession 实现 mac 版(替 null stub),修 `GetInstance()` null 解引用,下载 API 可用。
- 待续:**URL Image 端到端渲染**(DownloadManager 之上,image-provider/napi 路径还有更深的崩溃点,需后续);clipboard / font / storage / picker。

### M6 组件广度 — 关键基础打通
- **systemres 主题资源修复** ✅(高杠杆):restool 编 `resources.index`(含 dark 暗色)装入运行时 → 主题色解析恢复。**修复前所有默认样式组件渲黑(Button 黑框)**,修复后 Button(蓝底白字)、List/ForEach/ListItem/Text 全部正常渲染。脚本:`scripts/build_systemres.sh`。
- **List 滚动** ✅:触控板/滚轮 + 拖动均可滚,方向正确。
- 待续:动画/转场、router 多页导航、Dialog/Menu/Popup、更多组件逐项验证。

### 仍未动 / 受外部限制
- **M5**(Web/Video/XComponent)、**M7**(系统 API/NAPI)、**M8**(无障碍/i18n/安全)、**M10**(去 hack/测试/CI):大量未动。
- **M9 打包**:`ace build mac` 集成可做;**代码签名 + 公证需 Apple 开发者证书(外部依赖,本环境无法完成)**。

> 结论保持不变:路线 B 全量是团队级/季度级工程。本会话在 M2/M3/M4/M6 的核心上做出了真实可验证的推进。
