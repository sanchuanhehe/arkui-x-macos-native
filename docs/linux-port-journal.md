# Linux/Wayland 移植 · 实证日志与方法论

> 与 `linux-wayland-plan.md`(前瞻计划)互补:本文记录**实际做出来**的达成状态、
> 链接 0-undefined 方法论、Stage D bundle 的定义性根因,以及带官方 SDK 续接的最短路。
> adapter 代码侧的实现机制(呈现管线/事件循环/Stage 接线)见
> `arkui_for_linux/docs/实现笔记.md`。

## 0. 当前达成状态(2026-06-28)

| 阶段 | 状态 | 证据 |
|------|------|------|
| A 构建地基 + gn gen | ✅ | gn gen 通过 |
| B `libace_static_linux` 全编 | ✅ | 882→0 编译错误 |
| C `ace_linux` 链出 + 开窗截图 | ✅ | 105.6 MB aarch64 ELF,**0 undefined**;`screenshots/linux_ace_window_clearcolor.png` |
| C2-b RS→屏纹理呈现管线 | ✅ | `screenshots/linux_ace_testframe_bands.png`(青/品红/黄三条带正立) |
| 事件循环整合(ability 生命周期) | ✅ | DispatchOnCreate→OnForeground 端到端执行 |
| **D 真 .ets 上屏** | 🔶 卡 bundle | 见 §3,改用官方 SDK |
| #9 输入 / #10 窗口管理 | ⬜ | — |
| #11 CI 回归门 | ✅(渲染门) | `scripts/ci_linux_render_smoketest.sh` 退出码 0 |
| #12 打包 | ⬜ | — |

提交位:adapter(`arkui_for_linux` main)`230b361`;补丁(`port/linux-wayland`)`4d56a5d`。

## 1. 链接 0-undefined 方法论(C 阶段关键)

`ace_linux` 从 68 个 undefined 清零的可复用打法:

1. **lld 默认 error-limit=20** —— 逐次只报前 20 个 = 假象。必须提取链接命令
   `eval "$CMD -Wl,--error-limit=0"`(`out/arkui-x` 下重跑,~2-3min)拿全量。
2. **`-Wl,-z,defs` 是元凶**。arkui-x 的 .so(librender_service_base、libtext_napi_impl…)
   **故意留运行时解析符号**(trace/panda/symbol-config),照 android/ios 由主体可执行
   (ace_linux)在 load 时解析。`-z,defs` 把这些当 link-time-undefined 拒绝。
   → `build/config/compiler/BUILD.gn` 对 `is_arkui_x && target_os=="linux"` **gate 掉
   -z,defs**,只留 `--as-needed`;duplicate-symbol 仍会被抓(不依赖 -z,defs)。
   **⚠ 这条改动落在 `patches/linux-build.patch` 的 `config/compiler/BUILD.gn` 块**——
   见 §4 的"build vs build_config"教训:它曾因补丁命名孤儿化而没被一键脚本应用。
3. **集中桩** `adapter/linux/osal/linux_link_stubs.cpp`(镜像 mac,清一半;跳过 linux 已有的
   SkDebugf/TextInput*/log-bridge 避 dup)。
4. **rosen un-drop**:render_service_client 的 `rs_frame_rate_linker`/`rs_ui_mask_base`
   (linux 缺 ROSEN_ARKUI_X 故引用未裁)、`PlatformEventRunner` linux epoll 版、
   `ScrollBarController` cherry-pick。
5. **dup 清**:`symbol_gradient` 只留 skia_libtxt;`icu_font` 对 arkui-x 去掉(skia 已链 ICU74)。

## 2. 呈现管线 + 事件循环(摘要)

详见 adapter 仓实现笔记。两个最易踩的坑:
- `CreateSurfaceNode` 的 `additionalData` 必须传 `&WindowView::OnRsFrame`(真 OnRenderFunc),
  曾误传 `eglWindow_` 被 cast 调用 → 崩。
- 主循环必须**事件驱动**(wayland fd 订阅进 ability EventRunner 的 epoll),否则
  `AppMain::DispatchOnCreate` PostTask 的 ability 任务永不执行(OnRsFrame 恒 0)。
  **不要忙等 `while(Dispatch())`**。

## 3. ★ Stage D 真 .ets 上屏:定义性根因(从运行时源码锁定)

**症状**:`RunScriptBuffer`/`ExecuteModuleBuffer` 加载 ability `.abc` 失败。

**加载调用链**:
```
jsi_declarative_engine.cpp:1930/2135  ExecuteModuleBuffer(content, abcPath/urlName)
  → ark_js_runtime.cpp:249            ArkJSRuntime::ExecuteModuleBuffer
  → jsnapi_expo.cpp:6000              JSNApi::ExecuteModuleBuffer
  → js_pandafile_executor.cpp:155     JSPandaFileExecutor::ExecuteModuleBuffer
```

**决定 record 名解析路径的开关**(`ecma_vm.h:738`):
```cpp
// if pkgContextInfoList is empty, means use old ohmurl packing.
bool IsNormalizedOhmUrlPack() { return !pkgContextInfoList_.empty(); }
```
→ **有没有 `pkgContextInfo.json` 直接决定走 @normalized 还是旧 bundle-prefix 打包**。
`pkgContextInfoList_` 由 `js_runtime.cpp:290-293 SetpkgContextInfoList` 从 pkgContextInfo.json 喂。
手工 ets2bundle 产物缺它 → 旧打包分支 → 与模块相对 record 不匹配 →
`"Cannot find module '<entry>', which is application Entry Point"`。

**旧打包分支理论上可行(免 SDK 旁路,未及验证)** —— `js_pandafile_executor.cpp:178`:
```cpp
if (!vm->IsNormalizedOhmUrlPack() && !jsPandaFile->IsBundlePack()) {
    jsPandaFile->CheckIsRecordWithBundleName(entry);   // js_pandafile.cpp:131
    if (!jsPandaFile->IsRecordWithBundleName())
        PathHelper::AdaptOldIsaRecord(entry);          // 剥 bundleName 前缀
}
```
- 我们 HelloWorld 是 **esmodule → abc 含 `MODULE_RECORD_IDX` → `CheckIsBundlePack`
  (js_pandafile.cpp:121)置 `isBundlePack_=false`** → 该分支**会跑**。
- `ParseAbcPathAndOhmUrl`(module_path_helper.cpp:163)对 `@bundle:` 前缀产
  `bundleName/moduleName/ets/...`;`AdaptOldIsaRecord` 剥后 → `entry/ets/...`,应匹配
  arkui-x 共享 runtime 要的模块相对 record(`module_profile.cpp:760 package=moduleName`)。
- **即:理论上纯 es2abc + 模块相对 record、无需 pkgContextInfo 就能过旧分支**。之前失败疑似
  urlName 形态或 record 当时未真模块相对——**值得回头用官方 bundle 对照后再定**。

**es2abc/abc 版本不是问题**:mac systemres abc 头 `18 00 00 00`=24.0.0.0,es2abc 默认产同版本且能渲染。

**为什么手搓 normalized 走不通(改用官方 SDK 的直接原因)**:normalized 模式需 **rollup 版
ets-loader**,本树 `developtools/ace_ets2bundle` 的 ets-loader node_modules 只配了 webpack
(缺 rollup core + 插件)= 死胡同。(源码树里有未提交的实验:main.js 加 `[linux-port]` 读
`aceBuildJson.pkgContextInfo` 切 normalized,干净、与根因一致,日后可复用。)

**带官方 SDK 回来的最短路**:
1. 用 SDK 的 hvigor 产正规 HelloWorld bundle(自带 @normalized records + pkgContextInfo.json)。
2. 放 `<exeDir>/arkui-x/<module>/`(含 `module.json` 带 `"compileMode":"esmodule"` +
   `modules.abc` + `resources.index`);系统模块 abc 放 `<exeDir>/arkui-x/systemres/abc/`。
3. `ACE_STAGE_LAUNCH=1` 跑 `ace_linux`。
4. 验 `ace.log` 里 `OnRsFrame>0` + 蓝底 HelloWorld 截图。
   呈现管线(C2-b)+ ability 生命周期(事件循环)都已通,只差这个 bundle。

**bundle 结构坑**:`module.json` 必须 `"compileMode":"esmodule"`,否则
`esmodule=(compileMode==ES_MODULE)`=false → `GetModuleAbilityABC` 走非合并分支找
`AbilityStage.abc`/abilityName 文件 → 匹配不到合并 `modules.abc` → 空 buffer。

## 4. 补丁集工作流 + 一致性规则

- **改动分界**:`adapter/linux` 内容 → `arkui_for_linux` 子仓 main;大仓其他仓的适配 →
  `patches/linux-<name>.patch`,提交 `port/linux-wayland`,**不直推 main**。
- **一键复现**:`scripts/apply_patches.sh <src> linux`(克隆子仓 + 应用 linux 补丁,幂等)。
- **MAP 命名规则(易踩)**:`apply_patches.sh` 的 linux MAP `"<repo路径>:<前缀>"`,对每个仓收
  `linux-<前缀>.patch`(单)与 `linux-<前缀>-*.patch`(**连字符**拆分,按名排序)。
  → 拆分补丁用 **连字符** `linux-build-xxx.patch`,**不要下划线**——`linux-build_config.patch`
  两不沾会变孤儿、永不被应用。(本会话就修了这个:`linux-build_config.patch` 是
  `linux-build.patch` 的超集[多 -z,defs gate],已合并入 `linux-build.patch` 并删孤儿。)
- **自检门**:`scripts/check_patches.sh` 必须全绿——① 每 patch 可解析非空;② 每仓有补丁且
  `BASE_COMMITS.txt` 有基线行;③ 无孤儿 patch。每仓的 BASE_COMMITS = 该仓 `linux-port`
  分支的 pristine HEAD(补丁是其上的工作区 diff)。
- **CI 渲染回归门**:`scripts/ci_linux_render_smoketest.sh` —— 编 `arkui_for_linux` 的独立
  Wayland+EGL smoketest,headless weston(独立 `wl-ci` socket)下开窗、glReadPixels 落帧、
  校验三条带 + 背景。轻量、不需全 ace_linux、与主跑隔离。

## 5. 根因方法论(为什么 gn-gen 阶段那么多坑)

树期望 **newer gn**,但本机只有 old gn(2021,无 `path_exists`、严格 `assignment-had-no-effect`)
→ 一批 toolchain 评估假报错,逐个 in-tree gate。下载 newer gn 被安全策略拦(外部二进制)。
组件级 `component not found` 的系统性根因:`productdefine/common/products/arkui-x.json` 只列
16 个组件,框架却引用大量其他 OHOS 组件(graphic_surface/ipc/access_token/c_utils…)——
**mac 港正是用它的 15 仓补丁集让这些引用对跨平台可 gate**,linux 系统性镜像即可。
