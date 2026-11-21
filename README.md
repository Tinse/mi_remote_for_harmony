# RCProbe —— 小米蓝牙遥控器 2 Pro（RC003）按键拦截验证工程

HarmonyOS NEXT / API 26（HarmonyOS 7）· Stage 模型 · 纯 ArkTS · 只用公开 API。

本工程的目的不是"做一个能用的遥控器 App"，而是**用可复核的证据回答一个问题**：
这颗标准 BLE HID 键盘遥控器的每一个键，在「前台 / 后台 / 输入法」三种形态下，
到底是被系统在更早环节吃掉了、被 App 收到了但没拦住、还是被 App 真正拦住了。

---

## 0. 结论摘要（先看这里）

| 形态 | 通道 | 结论 | 依据等级 |
|---|---|---|---|
| M1 前台 | ArkUI `onKeyPreIme` | 可用。返回 `true` 即消费，系统默认行为（音量条 / 返回 / 焦点移动）被抑制 | 文档 + 可实测 |
| M1 前台 | `inputConsumer.on('keyPressed')` | 可用，但**只覆盖**音量±（API 21 起媒体键），且订阅即屏蔽系统默认行为；只在窗口是前台焦点窗口时生效 | 文档 + 可实测 |
| M2 后台 | 普通后台 + `inputConsumer` | **不可用**。API 原文限定"当前应用窗口为前台焦点窗口"，后台不满足 | 文档 + 日志可证 |
| M2 后台 | `KEEP_BACKGROUND_RUNNING` + `bluetoothInteraction` 连续任务 | **不可用**。长时任务只保证进程不被冻结，不改变输入事件的派发目标（后台窗口不在派发链上） | 文档推导 + 日志可证（待真机确认） |
| M2 后台 | `AVSession` 媒体键回调 | **唯一可能成功的通道**，且只覆盖媒体键。遥控器若不发媒体键 → 本设备无法验证（不要伪造结论） | 文档 + 待真机 |
| M3 输入法 | `KeyboardDelegate.on('keyDown')` | 可用。输入法这一环能拿到物理键，回调返回 `true` 即消费 | 文档 + 可实测 |
| M3 输入法 | `InputClient.insertText / insertTextSync` | 可用。**API 里没有 `commitText`**，等价能力就是这两个 | 文档 + 可实测 |
| 全局 | `AccessibilityExtensionAbility.onKeyEvent` | **不可用**。该 API 自 API 12 起整体 `@deprecated` | d.ts 标注 |
| 全局 | `inputEventClient` | **不可用（也不该用）**。它是"事件注入"不是"拦截"，且要 `ohos.permission.CONTROL_DEVICE`（system_basic + manual_settings + deviceTypes 仅 2in1） | d.ts + `PermissionDefinitions.json` |
| 全局 | `ohos.permission.INPUT_MONITORING` | **不可用**。system_basic 受限权限，且只对录屏类应用开放，只能监听不能消费 | `PermissionDefinitions.json` |
| 全局 | `HOOK_INPUT_EVENT` / `INTERCEPT_INPUT_EVENT` | 未申请、也未使用。商用机拿不到，申请会让工程装不上 | 需求约束 |

> "文档依据"在 §9 接口核对表和 §10 不可行项里逐条给了 SDK 路径 / 官方链接。

### 0.1 模拟器实测（2026-11-21，HarmonyOS 7.0.0 / API 26，实例 `HGHUB_API26`）

> 完整报告与截图见 **[`TEST-EMULATOR.md`](TEST-EMULATOR.md)**、`docs/screenshots/`。
> 先说边界：模拟器上按键由 `uinput` 注入，是**虚拟键盘**（`keySource=Keyboard`、`deviceId=-1`），
> 不是 BLE HID 遥控器。所以下面结论只证明"代码链路 / 通道成不成立"，**不证明 RC003 的固件行为**。

| 项 | 模拟器结果 |
|---|---|
| M1 音量± | 只收到 **Up**（Down 被更早消费）；`onKeyPreIme` 消费后 dispatch 消失，但**音量条仍弹** → 收到但未消费 |
| M1 返回 | 只收到 Up；消费 ON 时不退出、OFF 时退出 → 收到并消费 / 收到但未消费 |
| M1 方向键 | Down+Up 都到 preIme；消费 ON 无 dispatch、页签不动；OFF 时焦点移动 → 收到并消费 |
| M1 电源 / 主页 | **零事件**，灭屏 / 回桌面照常 → 未收到 |
| M1 `inputConsumer` | 订阅后音量条**不再弹出**，回调拿到 `Action(1)` → 有效（仅音量±/媒体键） |
| M2a 普通后台 + inputConsumer | 零事件，音量条照弹 → 未收到 |
| M2b `bluetoothInteraction` 连续任务 | **启动即失败**：`9800005 The bgMode is invalid` → 模拟器无法验证，需真机 |
| M2c `AVSession` | 后台按媒体键 → `ch=avsession.play` 命中（后台唯一成功通道；音量键仍零事件） |
| M3 输入法截获 | 方向 4 键 / OK / 菜单 / 语音 → `ime.delegate.keydown` 命中；返回 → 仅 Up；音量±/媒体/电源/主页 → 收不到 |
| M3 变文字 | 7 个键都成功：`insertTextSync ok: <方向下>`，输入框出现 `<方向上>…<语音>`（截图 `docs/screenshots/m3_all_keys.jpeg`） |
| M3 IME 在位时 M1 | preIme 与 keyboardDelegate **都能收到**（preIme 在前）；preIme 返回 true 后 IME 收不到 → **流水线，不是互斥** |
| M3 自绘软键盘面板 | `createPanel` 抛 `code=1 error is out of definition`（带/不带 flag 均失败）→ **模拟器不可用**，需真机 |

---

## 1. 环境要求

| 项 | 要求 | 本工程实测环境 |
|---|---|---|
| IDE | DevEco Studio 26.x | 26.0.0.851 |
| SDK | HarmonyOS SDK API 26（`26.0.0` Release） | `sdk/default/openharmony/ets/oh-uni-package.json` → apiVersion 26 |
| 设备 | HarmonyOS 7（API 26）真机 | 已在 DevEco 模拟器 `HGHUB_API26`（7.0.0.107 / API 26）完成通道级验证，真机待测 |
| 命令行 | DevEco 自带 `hvigor` / `ohpm` / `hdc` | 均随 IDE 安装 |
| 签名 | 调试签名（自动签名需登录华为开发者账号） | 见 §3 |
| 遥控器 | 小米蓝牙遥控器 2 Pro（RC003） | 待测 |

本工程**不申请任何受限权限**，只申请：

- `ohos.permission.KEEP_BACKGROUND_RUNNING` —— normal / system_grant，安装即授予（M2b 用）。

---

## 2. 工程结构

```
RCProbe/
├─ AppScope/app.json5                 bundleName = com.rcprobe.probe
├─ build-profile.json5                target/compatible = 26.0.0；modules: entry / ime / probecore
├─ oh-package.json5
├─ local.properties                   nodejs.dir / hwsdk.dir（按本机路径改）
├─ hvigorw / hvigorw.bat / hvigor/     hvigor wrapper（deveco cli 入口）
├─ probecore/                         ★ 采集 + 上报内核（HAR，被 entry 与 ime 共同依赖）
│  ├─ Index.ets                        统一导出
│  └─ src/main/ets/
│     ├─ ProbeTypes.ets                 ProbeEvent / ProbeState / SysBehavior
│     ├─ ProbeKeys.ets                  13 键 + API 26 新键登记表（全用 KeyCode 枚举）
│     ├─ ProbeRecorder.ets              hilog(tag=RCProbe) + 内存环形缓冲 + UI 订阅
│     └─ ProbeVerdictStore.ets          三态判定规则（唯一口径）
├─ entry/                             主 HAP（M1 / M2 / 说明页）
│  └─ src/main/ets/pages/M1View.ets    M1 前台：onKeyPreIme / onKeyEventDispatch / onKeyEvent / inputConsumer
│  └─ src/main/ets/pages/M2View.ets    M2 后台：a) inputConsumer  b) 连续任务  c) AVSession
│  └─ src/main/ets/pages/M3View.ets    M3 主 App 侧测试台（TextInput + 三条结论登记）
│  └─ src/main/ets/common/KeyMatrix.ets 13 行 × 「系统行为发生 / 未发生」→ 自动算三态
└─ ime/                               输入法 HAP（独立 module，不与主 App 同 HAP）
   └─ src/main/ets/InputMethodExtensionAbility/
      ├─ InputMethodService.ets        InputMethodExtensionAbility 生命周期
      ├─ model/ImeController.ets       KeyboardDelegate + insertTextSync + Panel
      └─ pages/Index.ets               自绘软键盘（最小实现，不做完整输入法）
```

**为什么有 `probecore`**：需求要求"三个模式共用同一套采集 + 上报代码"。这里做成 HAR，
`entry` 与 `ime` 两个 HAP 都 `file:../probecore` 依赖同一份源码 —— 字段、日志格式、判定规则
物理上只有一份，不会因为两边各写一遍而产生实现差异。

**为什么输入法单独一个 module**：需求约束 + `InputMethodExtensionAbility` 的
`type: "inputMethod"` 扩展必须独立注册；同时输入法扩展运行在「基础访问模式」下
（只做打字、禁止网络），和主 App 的生命周期/权限模型完全不同，塞在一个 HAP 里会互相拖累。

---

## 3. 编译 / 安装（deveco cli）

本机 DevEco 路径按需替换（下面以 `D:\Program Files\Huawei\DevEco Studio` 为例）。

### 3.1 一次性准备

> `local.properties` 里写的是本机 SDK / node 路径，**不随包分发**（zip 里已剔除）。
> 首次用 DevEco Studio 打开工程时会自动生成；用纯命令行的话手工写两行即可：
> ```properties
> nodejs.dir=D:/Program Files/Huawei/DevEco Studio/tools/node
> hwsdk.dir=D:/Program Files/Huawei/DevEco Studio/sdk
> ```

```powershell
# 1) 依赖（本地 HAR 依赖，离线可完成）
& "D:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin\ohpm.bat" install --all

# 2) 编译（debug，未签名）
& "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" `
    assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

产物：

```
entry/build/default/outputs/default/entry-default-unsigned.hap
ime/build/default/outputs/default/ime-default-unsigned.hap
```

> 本工程验证过：API 26 SDK + DevEco 26.0.0.851 下 **BUILD SUCCESSFUL**，无 ArkTS 编译错误。

### 3.2 调试签名（必须做，否则装不上）

命令行不提供自动签名（需要华为开发者账号的证书链）。两种方式：

1. **DevEco Studio（推荐）**：打开本工程 → `File > Project Structure > Signing Configs`
   → 勾选 `Automatically generate signature` → 登录账号 → Apply。
   生成的 `signingConfigs` 会写回 `build-profile.json5`，之后 `Run` 一次会把
   `entry` 与 `ime` 两个 HAP 一起装进设备。
2. **手工签名**：用 `hap-sign-tool.jar` + 自己的 p12/cer/profile 对两个 HAP 签名，
   注意**两个 HAP 必须同一张证书**，否则同一 bundle 无法共存。

### 3.3 安装

```powershell
# 设备连接确认
& "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" list targets

# 安装（两个 HAP 必须一起装；hdc 版本不支持多包时改用 DevEco Run）
& "...\hdc.exe" install -r entry-default-signed.hap ime-default-signed.hap
```

装完在桌面能看到 **RCProbe**。

---

## 4. 遥控器配对（一次性）

1. 手机：设置 → 蓝牙 → 打开蓝牙。
2. 遥控器：**同时按住「主页 + 菜单」3–5 秒**。
   - 没有灯、没有声音是正常的，不要以为没进入配对。
3. 手机上「可用设备」列表里出现设备后点配对，系统会把它当**外接键盘**接入。
4. 验证：在任意输入框按方向键能移动光标 / 按 OK 能回车 → 说明 HID 通道正常。

排查：

- 列表里一直不出现：把遥控器贴近手机、换新电池、确认按的是「主页 + 菜单」而不是「主页 + 返回」。
- 已配对但按键无反应：设置 → 蓝牙 → 该设备 → 忽略此设备，重配一次。
- 想看系统识别成了什么：`hdc shell hidumper -s 3101 -a -d`（多模输入设备列表），
  能确认它作为 keyboard 类型的输入设备存在。

---

## 5. 日志怎么看（所有结论的唯一证据来源）

固定 tag：**RCProbe**（domain `0x0001`），行格式竖线分隔，便于 grep：

```
RCProbe|EVT|m=M1|ch=arkui.preime|key=音量+|code=16|enum=KEYCODE_VOLUME_UP|type=Down|ksrc=Keyboard|dev=3|ts=123456789|wm=1763...|extra=
RCProbe|VERDICT|m=M1|key=音量+|code=16|state=RECEIVED_CONSUMED|sys=ABSENT|ev=cap=1
RCProbe|NOTE|m=M2|msg=lifecycle.onBackground: 已切到后台，开始计后台按键
```

字段：

| 字段 | 含义 |
|---|---|
| `m` | M1 / M2 / M3 |
| `ch` | 采集通道：`arkui.preime` / `arkui.dispatch` / `arkui.keyevent` / `inputconsumer` / `avsession.play` … / `ime.delegate.keydown` |
| `key` / `code` / `enum` | 中文名 / KeyCode 数值 / 枚举成员名（三者可交叉核对） |
| `type` | Down / Up / Cancel |
| `ksrc` / `dev` | ArkUI `keySource` / `deviceId`（用来确认事件真的来自这颗遥控器） |
| `ts` / `wm` | 系统事件时间戳（纳秒）/ 采集时刻（毫秒） |
| `state` | 三态之一 |
| `sys` | 系统默认行为：`HAPPENED` / `ABSENT` / `UNSET` |

抓取命令（四选一，按现场方便）：

```powershell
# A. 实时看（PowerShell）
& "...\hdc.exe" hilog | Select-String "RCProbe"

# B. 只按 tag 过滤（设备侧过滤，量大时更快）
& "...\hdc.exe" shell hilog -T RCProbe

# C. 先清空再抓（每次测试前推荐，保证日志干净）
& "...\hdc.exe" shell hilog -r

# D. 落盘，方便贴进 RESULT.md
& "...\hdc.exe" shell hilog -T RCProbe > rcprobe-M1-20261121.log
```

判读要点：**先看有没有 `EVT`，再看 `VERDICT` 的 `sys`。**
日志里没有任何 `EVT` 行 = 这条链路根本没收到事件，此时"系统行为却发生了"才等于「未收到」。

---

## 6. M1 真机操作步骤（前台拦截）

前置：App 在前台、窗口获焦（点一下页面空白，或点「重新获取焦点」）。

1. 打开 App → `M1 前台` 页签。
2. **先测"不消费"基线**：把 `onKeyPreIme 消费` 关掉 → 逐个按 13 个键。
   - 每个键按完，观察系统默认行为是否发生（音量条 / 返回 / 焦点移动 / 锁屏）。
   - 回到 App，在该键那一行点「行为发生」或「行为未发生」。
   - 点「把本模式全部判定写入 hilog」→ 日志里会有 13 条 `VERDICT`。
3. **再测"消费"**：把 `onKeyPreIme 消费` 打开 → 重复上面 13 个键。
   - 重点看：音量条是否还在弹？返回是否还退？方向键是否还移动焦点？
   - 同一按键在两种设置下的差异，就是"拦截是否真的生效"的唯一判据。
4. **单独测 `inputConsumer`**：把 `inputConsumer 订阅` 打开 → 只按 音量+ / 音量- /（若遥控器有）媒体键。
   - 观察：音量条**不再出现**（订阅即屏蔽系统默认行为）。
   - 关掉订阅 → 音量条恢复。这两步能证明"优先响应"确实劫持了系统默认行为。
5. **清空重来**：矩阵底部有「清空采集」按钮 → 只清**本模式**（M1）的事件计数，
   已登记的「系统行为」判定会保留；不会影响 M2/M3 已采集的数据。

注意事项：

- **电源键 / 主页键大概率拿不到**。它们在系统更早的环节就被消费（灭屏 / 回桌面），
  ArkUI 根本收不到。这类键在 M1 的结论通常是「未收到」+ 系统行为「发生」。
- 音量键在 `onKeyPreIme` 里**能收到**（这也是这套方案能成立的前提）；如果实测收不到，
  说明该机型把音量键在更早环节吃掉了，此时只剩 `inputConsumer` 一条路。
- 焦点被抢走的表现：所有键都没有 `EVT`，但系统行为正常。先点「重新获取焦点」再测。

---

## 7. M2 真机操作步骤（后台拦截）

通用流程（每条通道都跑一遍）：

```
启动通道 → 点「清空 M2 采集」→ 按「主页」切后台 → 按遥控器（每个键 2 次）
→ 回 App（点最近任务里的 RCProbe）→ 看矩阵计数 → 填「系统行为」→ 导出判定
```

`清空 M2 采集` 很关键：它保证矩阵里的计数**只包含切后台之后**的事件，
否则前台那几次按键会把结论污染成"后台也能收到"。

### a) 普通后台 + inputConsumer

1. 点 `a) 普通后台 + inputConsumer` 的「启动」→ 日志出现
   `NOTE|a) inputconsumer armed ...`。
2. 清空 → 按主页 → 按 音量+ / 音量-。
3. 预期：**没有任何 `EVT|ch=inputconsumer`**；音量条正常弹出（说明系统自己处理了）。
4. **这就是"预期失败"的证据**：不是"我以为不行"，是日志里一条都没有。

### b) KEEP_BACKGROUND_RUNNING + 蓝牙类连续任务

1. 点 `b) 连续任务 bluetoothInteraction` 的「启动」。
2. 日志应出现 `NOTE|b) startBackgroundRunning(bluetoothInteraction) ok`；
   失败会打 `FAILED code=... msg=...`（常见 9800005 / 9800006 / 201）。
3. 清空 → 按主页 → 按遥控器全键。
4. 预期：进程活着（回到 App 计数不丢），但**仍然没有任何按键 `EVT`**。
   → 证明"进程活着 ≠ 收得到按键"。

### c) AVSession（后台唯一可能成功的通道）

1. 点「创建」→ 日志 `NOTE|c) AVSession created + activated`。
2. 点「PLAY」（把播放态伪装成播放中，系统才更可能把媒体键路由给本会话）。
   > 注意：这是探针行为，会让系统媒体面板显示"正在播放"。测完点「销毁」。
3. 清空 → 按主页 → 按遥控器的 播放/暂停（以及上一首/下一首，如果它有）。
4. 看日志有没有 `EVT|ch=avsession.play` / `avsession.pause` / `avsession.playNext` / `avsession.playPrevious`。
5. **如果遥控器压根不发媒体键**（按了没有任何反应、日志也没有）：
   点「标注 M2c：本设备无法验证」，并在 RESULT.md 的 M2c 备注写
   `本设备无法验证（无媒体键输入源）`。**不要**写成"未收到"——那是伪造结论。

> 若手上另有能发媒体键的输入源（例如蓝牙耳机线控、另一把电视遥控器），
> 用它测 M2c 才能得到有效结论；否则 M2c 永远是"无法验证"。

---

## 8. M3 真机操作步骤（输入法 / 键盘形态）

### 8.1 启用输入法

1. 安装后：设置 → 系统和更新 → 语言与输入法 → 当前输入法 → 选择 **RCProbe Ime**。
   （不同 ROM 路径略有差异，找"输入法管理 / 默认输入法"即可。）
2. 若列表里没有：确认 `ime` 这个 HAP 也装上了（`hdc shell bm dump -n com.rcprobe.probe`
   能看到 `InputMethodService` 这个 extension）。

### 8.2 三个验证点

1. 打开 App → `M3 输入法` 页签 → 点一下页面里的 `TextInput` 把键盘拉起来。
2. **验证点 1（能否截获物理键）**：按遥控器任意键。
   - 看 hilog 是否有 `EVT|m=M3|ch=ime.delegate.keydown`。
   - 有 → 输入法这一环拿到了物理键；没有 → 被更早环节消费（或输入法未真正成为当前输入法）。
3. **验证点 2（能否把按键变成文字）**：保持「物理键转文字」开着，按遥控器键。
   - 输入框里应出现 `<音量+>` 这类文本（实现用 `insertTextSync`）。
   - **API 里没有 `commitText`**，需求里说的 commitText 对应 `InputClient.insertText / insertTextSync`。
   - 软键盘上的自绘按键也能验证同一条链路（点 `a` 看输入框是否出现 `a`）。
4. **验证点 3（IME 在位时 M1 是否仍生效）**：保持当前输入法是 RCProbe Ime，输入框获焦。
   - 按遥控器 → 看有没有 `EVT|m=M3|ch=arkui.preime`。
   - 判读：
     - 只有 `ime.delegate` 有日志、`arkui.preime` 没有 → 输入法把事件吃掉了，**M1 被截断**。
     - 两条都有 → 输入法没消费，事件继续下发到 App，**M1 仍生效**。
     - `arkui.preime` 没有、`ime.delegate` 也没有 → 更早环节消费（与输入法无关）。
   - 输入框获焦时若 `preime` 无日志，先点页面空白让根节点获焦再试一次；
     两次都无日志才能判"被截断"（排除焦点干扰）。
5. 三条结论在页面上点按钮登记（会写 `NOTE|check1=...` 到 hilog），再填进 RESULT.md 的 M3 附表。

### 8.3 输入法的先天限制（必须知道）

- 输入法扩展运行在**基础访问模式**：只做打字，**禁止网络交互**。所以 M3 的日志只能靠 hilog，
  不要指望它在扩展里上报到服务器。
- `createPanel` / `Panel` 只能由 `InputMethodExtensionAbility` 调用（`12800004 not an input method application`）。
- 输入法只在**有输入框连接**（`inputStart` 之后）时才稳定拿到物理键；桌面上没有输入框时
  收不到是正常的，不代表"输入法不能截获"。

---

## 9. 接口核对表（起始版本 / 权限 / 是否系统接口）

依据：本机 SDK `sdk/default/openharmony/ets/api/*.d.ts` 的 JSDoc 标注（API 26 Release），
以及 `sdk/default/openharmony/toolchains/lib/PermissionDefinitions.json` 的权限等级。
"是否系统接口"= 是否需要 `@systemapi` / system_basic 及以上权限 / 是否打 `@systemapi` 标记。

| # | 接口 | 起始版本 | 权限 | 是否系统接口 | 本工程用途 |
|---|---|---|---|---|---|
| 1 | `inputConsumer.on('keyPressed')` | 16（模块 14） | 无 | 否（三方可用） | M1 音量±/媒体键优先响应；M2a 对照 |
| 2 | `inputConsumer.off('keyPressed')` | 16 | 无 | 否 | 恢复系统默认行为 |
| 3 | `inputConsumer.on('hotkeyChange')` | 14 | 无 | 否 | 未使用（组合键，不适用单键遥控器） |
| 4 | `inputConsumer.KeyPressedConfig` | 16（`key` 支持范围随 21/26 扩） | — | — | 订阅参数 |
| 5 | ArkUI `onKeyPreIme` | 12 | 无 | 否 | M1 主采集点 + 消费开关 |
| 6 | ArkUI `onKeyEventDispatch` | 15 | 无 | 否 | M1 观察"preIme 没吃掉时是否继续下发" |
| 7 | ArkUI `onKeyEvent` | 7（`(event: KeyEvent) => void` 重载）/ **15**（`Callback<KeyEvent, boolean>` 重载，返回 true 才算已处理） | 无 | 否 | M1 兜底观察（本工程用 void 重载，只观察不消费） |
| 8 | ArkUI `KeyEvent.keySource / deviceId / timestamp` | 7 | 无 | 否 | 记录事件来源与时间 |
| 9 | `@ohos.multimodalInput.inputEventClient` | **26.0.0**（重写为事件注入） | `ohos.permission.CONTROL_DEVICE`（system_basic + **manual_settings**，`deviceTypes` 仅 `2in1`） | 是（受限，普通手机应用拿不到） | **不使用**，只在文档里论证"它不能用来拦截" |
| 10 | `@ohos.application.AccessibilityExtensionAbility.onKeyEvent` | 9，**@deprecated since 12** | 无（但要用户在无障碍里手动启用） | 否，但已废弃 | **不使用**（API 26 不可用） |
| 11 | `inputMethodEngine.KeyboardDelegate.on('keyDown'\|'keyUp')` | 8 | 无 | 否 | M3 输入法链路采集 + 消费 |
| 12 | `inputMethodEngine.getInputMethodAbility()` | 9 | 无 | 否（仅输入法应用可调） | M3 拿 InputMethodAbility |
| 13 | `InputMethodAbility.createPanel` / `Panel.setUiContent` / `resize` / `show` | 10 | 无 | 否（仅 InputMethodExtensionAbility 内可调） | M3 自绘软键盘面板 |
| 14 | `InputClient.insertText`（callback / Promise 两个重载）/ `insertTextSync` | 9 / **10** | 无 | 否 | M3 把按键变文字（**替代 commitText**；InputClient 上没有 commitText） |
| 15 | `InputClient.deleteForwardSync` | 10 | 无 | 否 | 面板退格 |
| 16 | `InputMethodExtensionAbility` | 9 | 无 | 否 | M3 扩展入口 |
| 17 | `avSession.createAVSession` | 10 | 无 | 否 | M2c 建会话 |
| 18 | `AVSession.on('play'\|'pause'\|'stop'\|'playNext'\|'playPrevious')` | 10 | 无 | 否 | M2c 媒体键回调 |
| 19 | `AVSession.activate` / `setAVPlaybackState` / `destroy` | 10 | 无 | 否 | M2c 激活/伪装播放态/销毁 |
| 20 | `backgroundTaskManager.startBackgroundRunning(context, bgModes: string[], wantAgent)` | **12** | `ohos.permission.KEEP_BACKGROUND_RUNNING`（**normal / system_grant**） | 否 | M2b 连续任务 |
| 21 | `backgroundTaskManager.stopBackgroundRunning` | 9 | 同上 | 否 | M2b 停止 |
| 22 | `KeyCode`（KEYCODE_*） | 7 起逐步新增 | 无 | 否 | 全工程键值（不硬编码数字） |
| 23 | `KeyCode.KEYCODE_XKEY` / `FINGERPRINT_SLIDE_UP` / `_DOWN` | **26.0.0** | 无 | 否（`@stagemodelonly`） | API 26 附加观察键，用 `canIUse` + `sdkApiVersion` 兜底 |
| 24 | `@ohos.deviceInfo`（productModel / sdkApiVersion 等） | 6 / 7 | 无 | 否 | 说明页自检 + API 26 判定 |

### 9.1 关键行为（写代码时踩的坑，原文摘要）

- `inputConsumer.on('keyPressed')`：「**若当前应用窗口为前台焦点窗口**，用户按下指定按键，会触发回调。
  订阅成功后，该按键事件的系统默认行为将被屏蔽……要恢复系统响应，请使用 off 方法取消订阅。」
  → 这同时解释了 M1 的可用性 和 M2a 的不可行性。
- `KeyPressedConfig.key` 的可支持范围：API 20 及以前**只有** `KEYCODE_VOLUME_UP/DOWN`；
  API 21 起新增 `MEDIA_PLAY_PAUSE / MEDIA_NEXT / MEDIA_PREVIOUS`；API 26.0.0 起新增智控键上/下滑。
  → 所以"用 inputConsumer 拦返回键/OK 键"是**做不到**的，不是配置问题。
- `onKeyPreIme`：「返回 true 视为消费，后续 keyboardShortcut、输入法、onKeyEventDispatch、
  onKeyEvent 都不再触发」。
- `onKeyEvent` 有两个重载：`since 7` 的 `(event: KeyEvent) => void`（只能观察）；
  `since 15` 的 `Callback<KeyEvent, boolean>`（「If the callback returns **true**, the key event is
  considered handled」）。本工程故意用 void 重载 —— 消费只发生在 `onKeyPreIme` 一处，
  这样"消费/不消费"的差异只由一个开关控制，不会两个通道同时吃事件导致结论说不清。
- 按键三次派发顺序（官方故障排查文档）：「先 onKeyPreIme 与页面快捷键 → 再输入法 → 再
  onKeyEventDispatch/onKeyEvent 与走焦；一旦被消费即跳过后续」。
  → 这就是 M3 检查 3 判"是否互斥"的理论依据：不是互斥，是流水线，前面消费了后面就收不到。
- `KeyboardDelegate.on('keyDown')`：「回调返回 true 表示事件被订阅者消费」。
- 输入法约束：「基础访问模式……仅提供基础打字功能，不应提供任何形式与网络交互相关的功能」。

---

## 10. 确认不可行的路径（结论 + 文档依据 + 需要什么证据）

### 10.1 无障碍（AccessibilityExtensionAbility）全局拦截 —— 不可行

- **结论**：API 26 上不能用它拦按键。
- **依据**：`@ohos.application.AccessibilityExtensionAbility.d.ts` 中
  `onKeyEvent(keyEvent: KeyEvent): boolean` 标注 `@since 9` + **`@deprecated since 12`**；
  整个类（`onConnect` / `onDisconnect` / `onAccessibilityEvent` / `onKeyEvent`）都在 12 起废弃。
- **需要什么证据才算"可行"**：在 API 26 设备上找到一个未废弃、且能返回「是否消费」的
  无障碍按键回调。目前 SDK 里没有。

### 10.2 inputEventClient —— 不是拦截，且权限拿不到

- **结论**：不用于本需求。
- **依据**：
  - API 26 的 `@ohos.multimodalInput.inputEventClient.d.ts` 已重写为
    `createKeyboardController()` / `pressKey` / `releaseKey` —— 这是**注入**事件，
    不是拦截系统事件；模块 syscap 变成 `Input.InputSimulator`。
  - 每个方法都要 `ohos.permission.CONTROL_DEVICE`；`PermissionDefinitions.json` 里该权限是
    `grantMode: manual_settings`、`availableLevel: system_basic`、`deviceTypes: ["2in1"]`。
  - 商用手机上的普通三方应用既拿不到 system_basic，也不在 2in1 设备类型里。
- **需要什么证据**：设备是 2in1 且能人工授予 CONTROL_DEVICE；即使如此，它也只能"模拟按键"，
  仍然不能"阻止系统响应"。

### 10.3 INPUT_MONITORING / 录屏类监听 —— 不可用

- **结论**：不能用它做拦截。
- **依据**：`PermissionDefinitions.json` → `grantMode: system_grant`、
  `availableLevel: system_basic`；官方《事件监听开发指导(C/C++)》明确"当前仅支持录屏类应用"，
  且接口只有 `OH_Input_AddKeyEventMonitor`（监听），没有消费/拦截语义。
- **需要什么证据**：system_basic 签名的系统应用 + 录屏场景授权。

### 10.4 M2 后台收按键 —— 只可能靠媒体键

- **结论**：普通按键在后台必然收不到；媒体键只能靠 AVSession。
- **依据**：
  - `inputConsumer` 的前台焦点窗口限定（§9.1）。
  - 按键事件派发目标是"当前获焦窗口"，后台应用没有获焦窗口。
  - 连续任务（`bluetoothInteraction`）只解决"进程不被冻结/不被回收"，不改变输入派发目标。
- **需要什么证据**：M2a/M2b 在 `hilog` 里零 `EVT`，而同一时刻系统行为正常发生
  （音量条弹出 / 页面返回），二者同时成立才叫"未收到"。

### 10.5 M2c 的"无法验证"边界

- **结论**：遥控器不发媒体键时，M2c 在本设备上**无法验证**。
- **依据**：AVSession 的 `play/pause/playNext/playPrevious` 回调只在系统把媒体键路由给
  活跃会话时才触发；没有媒体键输入源就不存在这个输入。
- **需要什么证据**：换一个确定能发媒体键的输入源（蓝牙耳机线控 / 另一把遥控器），
  或在同一台设备上用 `hdc shell hidumper -s 3101 -a -d` 确认该设备上报了媒体键能力。

---

## 11. 代码里所有「预期失败」位置（含原因 + 依据）

| 位置 | 预期现象 | 原因 | 依据 |
|---|---|---|---|
| `M1View.armInputConsumer()` 的 `catch` | 老设备/不支持机型抛 `801` | 能力不支持 | `inputConsumer.d.ts` `@throws 801 Capability not supported` |
| `M1View.onPreIme` 对 `KEYCODE_POWER` / `KEYCODE_HOME` | 永远没有 `EVT` | 这两个键在系统更早环节被消费（灭屏/回桌面），不会派发到应用窗口 | 官方《物理键盘输入异常分析》的按键三次派发流程；`KEYCODE_HOME=1` 属系统键 |
| `M2View.toggleA()` 之后的 `onInputConsumer` 回调 | 后台**零回调** | `keyPressed` 只在"前台焦点窗口"触发 | `inputConsumer.d.ts` 原文（§9.1） |
| `M2View.toggleB()` | `9800005`（连续任务校验失败）/`9800006`（通知校验失败）或 `201` | 未声明 `KEEP_BACKGROUND_RUNNING`（本工程已声明，故正常应成功）；系统要求连续任务有合法通知 | `backgroundTaskManager.d.ts` 错误码注释 |
| `M2View.toggleB()` 成功后按遥控器 | 仍**零 `EVT`** | 长时任务不改变输入派发目标 | 见 §10.4 |
| `M2View.createSession()` | `6600101` / `6600102` | 会话服务异常 / 会话不存在 | `avsession.d.ts` |
| `M2View` 的五个 `avsession.*` 回调 | 可能**永远不触发** | 遥控器不发媒体键；或会话不是被系统选中的活跃媒体会话 | 见 §10.5 |
| `ImeController.init()` | `12800004` | 不是输入法应用（扩展未正确注册 / 未成为当前输入法） | `inputMethodEngine.d.ts` |
| `ImeController.onPhysicalKey()` | 输入法收不到 `BACK` / `HOME` / `POWER` | 系统级键在派发到输入法之前已被消费 | 派发顺序：系统键先于 IME |
| `ImeController.onPhysicalKey()` 的 `insertTextSync` | `12800005` 等失败 | 没有 `inputStart`（输入框没连接） | `InputClient` 前置条件注释 |
| `M3View.onPreIme`（检查 3） | 输入框获焦时可能没有 `arkui.preime` | 输入法先消费了，ArkUI 这一环被截断 | 派发顺序（§9.1） |

---

## 12. 已知限制 / 待真机验证清单

| 项 | 状态 | 说明 |
|---|---|---|
| 音量± 在 `onKeyPreIme` 能否收到 | **待真机验证** | 已实测系统层面可用（音量可调），但是否派发到应用窗口取决于机型策略 |
| 返回键能否被 `onKeyPreIme` 消费 | **待真机验证** | 若系统在应用之前处理 BACK（导航栏手势），应用收不到 |
| `inputConsumer` 能否在"音量键"上稳定生效 | **待真机验证** | 若被系统快捷键占用，可能返回 `4200002/4200003`（那是 hotkeyChange 的错误码，keyPressed 主要是 401/801） |
| 连续任务是否被系统真的授予 | **待真机验证** | 部分 ROM 对 `bluetoothInteraction` 有额外校验 |
| AVSession 后台是否保活 | **待真机验证** | 只建会话、不真正播音，可能被判定为空闲会话而不接收媒体键 |
| 输入法扩展是否为"基础访问模式" | **待真机验证** | 若被系统判定违规，扩展可能被限制启动 |
| 遥控器是否上报媒体键 | **待真机验证** | 决定 M2c 是"未收到"还是"无法验证" |
| API 26 的 3232–3243 | 已核对 | 该 SDK 公开枚举里只有 `3232/3233/3234` 三个，3235–3243 **不存在**，代码里也不登记 |

---

## 13. 判定三态规则（唯一口径，代码在 `ProbeVerdictStore`）

| 采集到事件 | 系统默认行为 | 判定 |
|---|---|---|
| 有 | 发生 | **收到但未消费** |
| 有 | 未发生 | **收到并消费** |
| 无 | 发生 | **未收到**（在更早环节被系统消费） |
| 无 | 未发生 | 证据不足（键没按到 / 遥控器没连上 / 页面没焦点），**不能入矩阵** |

"系统默认行为"必须逐键人工确认（音量条 / 页面返回 / 焦点移动 / 灭屏 / 媒体面板变化），
因为没有任何公开 API 能告诉你"系统替我处理了这个键"。这就是矩阵里每行都有
「行为发生 / 行为未发生」两个按钮的原因。

---

## 14. 常见问题

**Q：按了键，App 里计数一直是 0，日志也没有 `EVT`。**
A：按顺序查：① 遥控器还连着吗（设置→蓝牙）；② 页面有焦点吗（点「重新获取焦点」）；
③ 这个键是不是系统键（电源/主页）；④ `hdc shell hidumper -s 3101 -a -d` 看设备是否还在。

**Q：`VERDICT` 里 `sys=UNSET` 是什么意思？**
A：还没告诉 App「系统行为有没有发生」。这种行不能进 RESULT.md。

**Q：M2 切后台后回到 App，矩阵计数是 0，但我不确定是不是被系统杀了。**
A：看 `NOTE|lifecycle.onBackground` 之后有没有 `lifecycle.onForeground`。若进程被杀，
回来时 `EntryAbility.onCreate` 会重新打一条；这时 M2 结论要写"进程被回收"而不是"未收到"。

**Q：能不能不改代码，直接用 `hdc shell input keyevent` 模拟？**
A：可以，但**只能验证通道，不能代表遥控器**。`input keyevent` 走的是注入路径，
不经过 BLE HID 驱动，`deviceId`/`keySource` 会和遥控器不同，别拿它替代真机结论。

**Q：为什么 M1 的矩阵只统计 `arkui.` 前缀的通道？**
A：因为 M1 这一列问的是"前台时 App 的按键分发链路是否收到"。`inputConsumer` 是另一条
独立通道（且只覆盖音量±/媒体键），它的结论单独在 §6 第 4 步和 RESULT.md 的附表中记录。

---

## 15. 参考文档

- `@ohos.multimodalInput.inputConsumer`：<https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-inputconsumer>
- 优先响应系统功能键开发指导：<https://device.harmonyos.com/cn/docs/apiref/harmonyos-guides/keypressed-guidelines>
- 物理键盘输入异常分析（按键三次派发顺序）：<https://developer.huawei.com/consumer/cn/doc/harmonyOS-faqs/input-troubleshooting-0001>
- 事件监听开发指导（C/C++，录屏类）：<https://device.harmonyos.com/cn/docs/apiref/harmonyos-guides/monitor-guidelines>
- 实现一个输入法应用（InputMethodExtensionAbility / 基础访问模式）：<https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/inputmethod-application-guide>
- 输入法子类型开发指南（`input_method_config.json` 格式）：<https://device.harmonyos.com/cn/docs/apiref/harmonyos-guides/input-method-subtype-guide>
- `@ohos.multimodalInput.keyEvent`：<https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-keyevent>
- 本机 SDK 类型定义：`sdk/default/openharmony/ets/api/*.d.ts`（API 26 Release）
- 权限等级：`sdk/default/openharmony/toolchains/lib/PermissionDefinitions.json`

---

## 16. 模拟器实测：怎么跑、能跑到哪一步

> 结论表在 §0.1，完整过程与原始日志在 [`TEST-EMULATOR.md`](TEST-EMULATOR.md)。
> 本节只写"复现要点"，方便换一台机器照着做。

**1) 起模拟器。** 实例名 `HGHUB_API26`，启动参数必须是 `-hvd`：

```powershell
Start-Process 'D:\Program Files\Huawei\DevEco Studio\tools\emulator\Emulator.exe' -ArgumentList '-hvd','HGHUB_API26'
# 约 90s 后 hdc list targets 出现 127.0.0.1:5617
```

**2) 装包。** 模拟器镜像不做签名校验，`unsigned` HAP 可直接装：

```powershell
& $hdc -t 127.0.0.1:5617 install -r entry-default-unsigned.hap
& $hdc -t 127.0.0.1:5617 install -r ime-default-unsigned.hap
```

**3) 注入按键。** 没有蓝牙硬件，用系统自带 `uinput`（虚拟键盘）：

```powershell
& $hdc -t 127.0.0.1:5617 shell "uinput -K -d 16 -i 300 -u 16"   # 音量+
& $hdc -t 127.0.0.1:5617 shell "hilog -T RCProbe -x"
```

**4) 截图。** `snapshot_display -i 0` 在模拟器返回全黑，只能用 `uitest`：

```powershell
& $hdc -t 127.0.0.1:5617 shell "uitest screenCap -p /data/local/tmp/x.jpeg"
& $hdc -t 127.0.0.1:5617 file recv /data/local/tmp/x.jpeg .\x.jpeg
```

**5) 切输入法（M3）。** 不用点系统设置：

```powershell
& $hdc -t 127.0.0.1:5617 shell "ime -e com.rcprobe.probe"
& $hdc -t 127.0.0.1:5617 shell "ime -s com.rcprobe.probe"
& $hdc -t 127.0.0.1:5617 shell "ime -g"          # status: BASIC_MODE
```

**6) 模拟器上明确做不到的两件事（不是代码问题）：**

| 现象 | 原文 | 影响 |
|---|---|---|
| `startBackgroundRunning(['bluetoothInteraction'])` 失败 | `BussinessError 9800005: Continuous Task verification failed. The bgMode is invalid.` | M2b 无法在模拟器验证 |
| `createPanel` 失败 | `code=1 msg=error is out of definition` | M3 的自绘软键盘面板无法在模拟器验证 |

**7) 模拟器结论与真机结论的唯一区别：** 注入事件的 `deviceId=-1`、`keySource=Keyboard`；
BLE HID 遥控器是 `deviceId≥0`。所以"键值本身会不会来、是不是只来 Up"必须真机复核。
