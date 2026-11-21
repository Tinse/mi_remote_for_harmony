# 模拟器实测报告（HarmonyOS 7 / API 26）

测试日期：2026-11-21 · 设备：DevEco 模拟器实例 `HGHUB_API26`
系统：HarmonyOS 7.0.0.107(SP8DEVC00E999R4P11)，`const.ohos.apiversion=26`
工程：`com.rcprobe.probe`（entry + ime 两个 HAP，**未签名**也能装：模拟器镜像不做签名校验）

> 一句话结论：**模拟器足以验证「代码链路」和「前台/后台/输入法三条通道是否收得到键」，
> 但不足以下「小米遥控器 RC003 能不能被拦」的结论** —— uinput 注入的是虚拟键盘（`deviceId=-1`、`keySource=Keyboard`），
> 不是 BLE HID 遥控器；且本模拟器有两个能力直接不可用（`createPanel`、`bluetoothInteraction` 连续任务）。

---

## 0. 结论速览

| 项 | 模拟器结果 | 能否当最终结论 |
|---|---|---|
| M1 音量±（`onKeyPreIme` 收 + 消费） | **收到但未消费**：音量条照样弹 | 可（机制层面），但 RC003 是否同样只送 Up 需真机确认 |
| M1 返回（`onKeyPreIme` 消费） | **收到并消费**：消费后 App 不退出 | 可 |
| M1 方向键（`onKeyPreIme` 消费） | **收到并消费**：dispatch 被截断、焦点/页签不动 | 可 |
| M1 电源 / 主页 | **未收到**：系统行为照常（灭屏 / 回桌面） | 可 |
| M1 OK / 菜单 / 语音 | 收到；该键在本页**没有可观测的系统默认行为** | 只能证明"收得到、能被消费"，不能判"拦住了什么" |
| M1 `inputConsumer`（音量±） | **可用**：订阅后音量条不再弹出，且回调拿到 `Action(1)` | 可 |
| M2a 后台 + `inputConsumer` | **未收到**（0 条 EVT），音量条照常弹 | 可（模拟器已验证限制成立） |
| M2b 连续任务 `bluetoothInteraction` | **不可行/不可验证**：`startBackgroundRunning` 直接 `9800005 The bgMode is invalid` | 需真机（模拟器根本没走到"进程活着"这一步） |
| M2c `AVSession` 后台媒体键 | **可用**：后台按媒体键 → `ch=avsession.play` 命中 2 次 | 可（通道成立）；RC003 是否发媒体键仍需真机 |
| M3 输入法截获物理键 | **分键而定**：方向 4 键 / OK / 菜单 / 语音 → 收到；返回 → 只收到 Up；音量±/媒体 → 收不到；电源/主页 → 收不到（会话被打断） | 可 |
| M3 按键变文字 | **能**：`insertTextSync` 成功，7 个键各插入 `<键名>`（截图 `m3_all_keys.jpeg`） | 可 |
| M3 IME 在位时 M1 是否仍生效 | **仍生效**（preIme 先执行）；preIme 返回 true 会让 IME 收不到 → **流水线而非互斥** | 可 |
| M3 自绘软键盘面板 | **模拟器不可用**：`createPanel` 抛 `code=1`（带 flag / 不带 flag 都失败） | 需真机 |

---

## 1. 测试环境与方法

| 项 | 值 |
|---|---|
| 模拟器实例 | `C:\Users\Tinse\AppData\Local\Huawei\Emulator\deployed\HGHUB_API26` |
| 启动命令 | `Emulator.exe -hvd HGHUB_API26`（`-instance` 无效，实测只有 `-hvd` 能起来） |
| 连接 | `hdc list targets` → `127.0.0.1:5617` |
| 机型参数 | `param get const.product.model` → `emulator`；API 26；1080×1920 |
| 输入注入 | `uinput -K -d <keyCode> -i 300 -u <keyCode>`（虚拟键盘，deviceId 恒为 -1） |
| UI 操作 | `uitest uiInput click x y` / `swipe`；`uitest screenCap -p /data/local/tmp/x.jpeg` |
| 系统键 | `power-shell wakeup`、`ime -e/-s/-g/-l` |
| 日志 | `hilog -r` 清空 → 操作 → `hilog -T RCProbe -x`（tag=RCProbe） |

**安装**：`hdc install -r entry-default-unsigned.hap` 与 `ime-default-unsigned.hap` 均返回
`install bundle successfully` —— 模拟器镜像未启用签名校验，真机必须签名。

**截图**：全部在 `docs/screenshots/`，文件名与本文小节一一对应。

---

## 2. 模拟器能测 / 不能测（先把边界说清楚）

能测：

- ArkUI 三条采集通道（`onKeyPreIme` / `onKeyEventDispatch` / `onKeyEvent`）是否收到事件、消费后是否截断后续。
- `inputConsumer` 是否订阅成功、是否屏蔽系统音量条。
- 后台是否还能收到（用日志零事件 + 系统行为照常双证据）。
- `AVSession` 媒体键回调是否在后台触发。
- 输入法 `KeyboardDelegate` 与 `insertTextSync` 链路。

不能测（必须真机）：

- **RC003 的固件行为**：它到底发不发媒体键、方向键发的是 DPAD 还是别的、音量键是否也只送 Up。
  模拟器 `uinput` 的 `dev=-1 / ksrc=Keyboard` 与 BLE HID 的 `deviceId≥0` 不是一回事。
- **蓝牙相关**：模拟器无蓝牙硬件，`bluetoothInteraction` 连续任务直接被系统拒绝（见 M2b）。
- **自绘软键盘面板**：`createPanel` 在本模拟器上恒失败（见 M3.4）。
- 任何"某 ROM 特判/厂商定制"的行为。

---

## 3. M1 前台拦截

### 3.1 逐键结果（`onKeyPreIme 消费 = true`，即拦截态）

| 键 | code | 收到的通道/类型 | 系统默认行为 | 判定 |
|---|---|---|---|---|
| 音量+ | 16 | `arkui.preime` **仅 Up**（无 Down） | 音量条**弹出** | 收到但未消费 |
| 音量- | 17 | `arkui.preime` **仅 Up** | 音量条**弹出** | 收到但未消费 |
| 电源 | 18 | 无 | 灭屏 | 未收到 |
| 返回 | 2 | `arkui.preime` **仅 Up** | 消费时**不退出**；不消费时退出 | 收到并消费 |
| 主页 | 1 | 无 | 回桌面 | 未收到 |
| 方向上 | 2012 | `preime` Down+Up | 消费时焦点不动 | 收到并消费 |
| 方向下 | 2013 | `preime` Down+Up | 同上 | 收到并消费 |
| 方向左 | 2014 | `preime` Down+Up | 同上 | 收到并消费 |
| 方向右 | 2015 | `preime` Down+Up | 不消费时焦点右移并切到 M2 页签 | 收到并消费 |
| OK | 2054 | `preime` Down+Up | 本页无可见动作 | 收到（默认行为不可观测） |
| 菜单 | 2067 | `preime` Down+Up | 无 | 收到（默认行为不可观测） |
| 语音(F5) | 2094 | `preime` Down+Up | 无 | 收到（默认行为不可观测） |
| 媒体播放/暂停 | 10 | `preime` **仅 Up** | 前台无活跃会话，无可见反应 | 收到（默认行为不可观测） |

### 3.2 关键证据（原始日志）

音量+，消费开（`wm=1795244445598`）：

```
RCProbe|EVT|m=M1|ch=arkui.preime|key=音量+|code=16|enum=KEYCODE_VOLUME_UP|type=Up|ksrc=Keyboard|dev=-1
```

→ 只有 `preime`，**没有 `arkui.dispatch`**，说明 `onKeyPreIme` 的 `return true` 确实消费掉了这一层；
但同一时刻系统音量条仍然出现（`m1_vol_consumeON.jpeg`）。原因：**音量键的 Down 在应用之前就被系统拿走了**，
应用只拿到 Up，消费 Up 已经来不及阻止面板。 → 这是 `收到但未消费` 的典型证据。

返回，消费开（`wm=1795244463090`）：只有 `preime Up`，`aa dump -l` 仍是 `FOREGROUND`；
返回，消费关（`wm=1795244558658`）：`preime Up` + `lifecycle.onBackground` → 页面退出。

方向右，消费开（`wm=1795244524632/4975`）：仅 `preime`，无 `tab changed`；
方向右，消费关（`wm=1795244546164~6512`）：`preime`+`dispatch`，随后
`RCProbe|NOTE|m=M1|msg=tab changed -> 1` → 焦点确实移动了。

主页（`wm=1795244470669` 段）：无 EVT，`lifecycle.onBackground` → 回桌面。
电源：无 EVT，截图全黑（`m1_power_consumeON.jpeg`）→ 灭屏。

### 3.3 `inputConsumer` 对照

| 设置 | 音量+ | 音量条 | 结论 |
|---|---|---|---|
| 未订阅 | `preime Up` + `dispatch Up` | 弹出 | 系统自己处理 |
| 订阅后 | `ch=inputconsumer` `Action(1)` + 仍收到 `preime Up` | **不弹出** | 订阅即接管，生效 |

原始行：

```
RCProbe|EVT|m=M1|ch=inputconsumer|key=音量+|code=16|type=Action(1)|dev=-1|extra=expect=16
```

对应截图：`m1_inputconsumer_vol.jpeg`（右侧无音量条）。
另：`inputConsumer` 只覆盖音量±（API 21 起媒体键），方向键/OK/返回都不在它的支持列表里（`inputConsumer.d.ts` 原文）。

### 3.4 截图

| 文件 | 内容 |
|---|---|
| `m1_app.jpeg` | M1 页面初始态（消费开、订阅关） |
| `m1_vol_consumeOFF.jpeg` | 消费关 + 音量+ → 音量条弹出 |
| `m1_vol_consumeON.jpeg` | **消费开 + 音量+ → dispatch 被截断但音量条仍弹** |
| `m1_back_consumeON.jpeg` | 消费开 + 返回 → App 仍在 |
| `m1_back_consumeOFF.jpeg` | 消费关 + 返回 → 退回桌面 |
| `m1_dpad_consumeON.jpeg` | 消费开 + 方向右 → 仍停在 M1 |
| `m1_dpad_consumeOFF.jpeg` | 消费关 + 方向右 → 切到 M2 页签 |
| `m1_power_consumeON.jpeg` | 电源键 → 灭屏 |
| `m1_inputconsumer_vol.jpeg` | 订阅 inputConsumer 后音量条不弹 |

---

## 4. M2 后台拦截

### 4.1 a) 普通后台 + `inputConsumer`

操作：a) 启动 → 清空 M2 采集 → 按主页 → 注入 音量+ ×2、媒体键 ×1。

结果：**0 条 EVT**（只有一行 `lifecycle.onBackground`），且截图显示音量条照常弹出。

```
RCProbe|NOTE|m=M2|msg=lifecycle.onBackground: 已切到后台，开始计后台按键
（之后没有任何 EVT）
```

判定：**未收到**（在更早环节被系统消费）。
证据链完整：日志无事件 + 系统行为发生（`m2a_vol_panel.jpeg` 桌面上的音量条）。

### 4.2 b) `KEEP_BACKGROUND_RUNNING` + `bluetoothInteraction`

操作：b) 启动。

结果：直接失败，连"进程活着"都没进入：

```
RCProbe|NOTE|m=M2|msg=b) startBackgroundRunning FAILED code=9800005
msg=BussinessError 9800005: Continuous Task verification failed. The bgMode is invalid.
```

判定：**本模拟器无法验证 M2b**。这不是代码问题（权限 `KEEP_BACKGROUND_RUNNING` 已在
`module.json5` 声明，且是 normal/system_grant），而是模拟器镜像不接受 `bluetoothInteraction`
这个连续任务类型（无蓝牙硬件/未开放该类型）。真机上要重测，并且要看它是"启动成功但仍无 EVT"还是"启动失败"。

### 4.3 c) `AVSession`（后台唯一成功通道）

操作：c) 创建 → PLAY（`setAVPlaybackState play=true`）→ 清空 M2 采集 → 按主页 → 媒体键 ×2。

结果：**后台收到媒体键**：

```
RCProbe|NOTE|m=M2|msg=c) AVSession created + activated
RCProbe|NOTE|m=M2|msg=c) setAVPlaybackState play=true
RCProbe|NOTE|m=M2|msg=lifecycle.onBackground: 已切到后台，开始计后台按键
RCProbe|EVT|m=M2|ch=avsession.play|key=媒体播放/暂停|code=10|type=Cmd|extra=cmd=play
RCProbe|EVT|m=M2|ch=avsession.play|key=媒体播放/暂停|code=10|type=Cmd|extra=cmd=play
```

同一次后台里再注入 音量+：**依然 0 条 EVT** → AVSession 只覆盖媒体键，不覆盖普通按键。

判定：M2c = **收到（AVSession 通道）**；系统把媒体键路由给活跃会话，本工程会话接管，没有额外的系统动作。
注意：这台模拟器没有真实媒体播放，所以"消费"只能理解为"会话接管了这条媒体键"，不代表能在真机上抢过系统音乐 App。

### 4.4 截图

| 文件 | 内容 |
|---|---|
| `m2_page.jpeg` | M2 页面（a/b/c 三个开关 + 清空/导出） |
| `m2a_background.jpeg` | 后台态（桌面），此时注入无任何 EVT |
| `m2a_vol_panel.jpeg` | **后台按音量+：音量条照弹，RCProbe 无日志** |
| `m2b_arm.jpeg` | b) 启动失败后的页面（feed 里是 9800005） |
| `m2c_create.jpeg` | c) 创建 + PLAY 成功 |
| `m2c_background.jpeg` | 后台按媒体键后的桌面 |
| `m2_final.jpeg` | b 失败 + c 成功的同屏证据 |

---

## 5. M3 输入法 / 键盘形态

### 5.1 启用输入法（不需要点设置界面）

```powershell
hdc shell "ime -e com.rcprobe.probe"   # Succeeded in enabling IME. status:BASIC_MODE
hdc shell "ime -s com.rcprobe.probe"   # Succeeded in switching the input method
hdc shell "ime -g"                     # com.rcprobe.probe, status: BASIC_MODE
```

`status: BASIC_MODE` 与文档一致（基础访问模式：只打字、禁联网）。

### 5.2 检查 1：输入法能否截获物理键 → **分键而定**

逐个注入 13 个键（输入框保持焦点，`ime -g` 确认输入法是 RCProbe）：

| 键 | preIme 收到 | `ime.delegate` 收到 | 变文字 | 备注 |
|---|---|---|---|---|
| 音量+ / 音量- | Up ×1 | **0** | — | 输入法拿不到；音量在更前面被系统处理 |
| 电源 | 0 | 0 | — | 灭屏，输入法一并失去焦点 |
| 返回 | Up ×1 | **Up ×1（无 Down）** | — | 只有 Up；消费后 App 未退出（`aa dump -l` 仍 FOREGROUND） |
| 主页 | 0 | 0 | — | 回桌面，`lifecycle.onBackground` |
| 方向 4 键 | Down+Up | Down+Up | `<方向上>` `<方向下>` `<方向左>` `<方向右>` | 全链路通过 |
| OK / 菜单 / 语音 | Down+Up | Down+Up | `<OK>` `<菜单>` `<语音>` | 全链路通过 |
| 媒体播放/暂停 | Up ×1 | **0** | — | 与音量同型：输入法拿不到 |

两条链路同时命中的原始行（方向下）：

```
RCProbe|EVT|m=M3|ch=arkui.preime|key=方向下|code=2013|type=Observed|extra=check3
RCProbe|EVT|m=M3|ch=ime.delegate.keydown|key=方向下|code=2013|type=Down|extra=consume=true toText=true
```

截图：`m3_all_keys.jpeg`（输入框里累计出现 7 个 `<键名>`，即方向 4 键 + OK + 菜单 + 语音）。

### 5.3 检查 2：能否把按键变文字 → **能**

```
RCProbe|NOTE|m=M3|msg=insertTextSync ok: <方向下>
```

输入框里真的出现了 `<方向下>`（截图 `m3_key.jpeg`、`m3_final.jpeg`）。
API 里没有 `commitText`，这里用的就是官方等价接口 `InputClient.insertTextSync`。

### 5.4 检查 3：IME 在位时 M1 是否仍生效 → **仍收到；但 preIme 先消费会截断 IME**

同一次按键，两条链路都命中（时间戳 11.721 → 11.724，**preIme 在前**）：

```
RCProbe|EVT|m=M3|ch=arkui.preime|key=方向下|...|type=Observed|extra=check3
RCProbe|EVT|m=M3|ch=ime.delegate.keydown|key=方向下|...|type=Down
```

把本页 `onKeyPreIme 消费` 打开后再按同一个键：**只有 `arkui.preime`，没有任何 `ime.delegate`**。

结论：不是"两条链路互斥"，而是**流水线**：
`onKeyPreIme` → 输入法 → `onKeyEventDispatch/onKeyEvent`，前面消费了后面就收不到。
所以：
- 输入法在位**不会**让 M1 失效（M1 在输入法之前）；
- 但 M1 开消费会**让输入法收不到**按键。

### 5.5 自绘软键盘面板：**模拟器不可用**

`createPanel` 在 `onCreate` 和 `inputStart` 两个时机都试过，带 `FLG_FIXED` 和不带 `flag` 各一次，全部失败：

```
RCProbe|NOTE|m=M3|msg=panel step1: about to createPanel type=SOFT_KEYBOARD flag=FLG_FIXED d=1080x1920
RCProbe|NOTE|m=M3|msg=createPanel FAILED (with flag) code=1 msg=error is out of definition.
RCProbe|NOTE|m=M3|msg=createPanel FAILED (without flag) code=1 msg=error is out of definition.
```

现象：输入框能获焦、系统弹出自己的"自动填充/小艺帮写"菜单，但**没有我们自绘的键盘面板**
（`m3_keyboard.jpeg`）。→ M3 的"自绘软键盘"这一半只能真机验证；
`KeyboardDelegate` + `insertTextSync` 这一半模拟器已经验证通过。

### 5.6 截图

| 文件 | 内容 |
|---|---|
| `m3_page.jpeg` | M3 页面 |
| `m3_key.jpeg` | 物理键 → 输入框出现 `<方向右>` |
| `m3_final.jpeg` | 物理键 → 输入框出现 `<方向下>`（含两类日志） |
| `m3_all_keys.jpeg` | **13 键逐个注入后**，输入框累计出现 7 个 `<键名>`（方向 4 + OK + 菜单 + 语音） |
| `m3_keyboard.jpeg` | createPanel 失败：无自绘面板 |
| `m3_preime_consume.jpeg` | preIme 消费后 IME 收不到（检查 3 的反向证据） |

---

## 6. 本轮顺手修掉的两个真问题

| 问题 | 现象 | 修法 |
|---|---|---|
| 矩阵「捕获」计数不刷新 | 日志有 EVT、feed 也更新，但行内计数恒为 0 | `KeyRowVM.id()` 的 ForEach key 里加上 `count`（`count|sys|verdict`），计数变化才会重建行 |
| 输入法面板创建失败 | `createPanel` 在 `onCreate` 抛 `code=1` | 面板改到 `inputStart`（输入框连接后）再建；并保留带/不带 flag 的两次尝试与逐步骤日志（失败原因写进 hilog，便于真机定位） |

---

## 7. 复现步骤（从零到本轮结果）

```powershell
$hdc = 'D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'

# 1. 启动模拟器
Start-Process 'D:\Program Files\Huawei\DevEco Studio\tools\emulator\Emulator.exe' -ArgumentList '-hvd','HGHUB_API26'
# 等 hdc list targets 出现 127.0.0.1:5617

# 2. 装包（未签名可装）
& $hdc -t 127.0.0.1:5617 install -r entry-default-unsigned.hap
& $hdc -t 127.0.0.1:5617 install -r ime-default-unsigned.hap

# 3. 起 App
& $hdc -t 127.0.0.1:5617 shell "aa start -a EntryAbility -b com.rcprobe.probe"

# 4. 注入按键（例：音量+ / 返回 / 方向右 / 媒体键）
& $hdc -t 127.0.0.1:5617 shell "uinput -K -d 16 -i 300 -u 16"
& $hdc -t 127.0.0.1:5617 shell "hilog -T RCProbe -x"

# 5. M3
& $hdc -t 127.0.0.1:5617 shell "ime -e com.rcprobe.probe; ime -s com.rcprobe.probe"
# 点 App 里的 TextInput 拉输入法，再注入按键

# 6. 截图
& $hdc -t 127.0.0.1:5617 shell "uitest screenCap -p /data/local/tmp/x.jpeg"
& $hdc -t 127.0.0.1:5617 file recv /data/local/tmp/x.jpeg .\x.jpeg
```

> 注意：`snapshot_display` 在模拟器上返回全黑（display 未合成），截图一律用 `uitest screenCap`。

---

## 8. 还差什么（真机必测清单）

1. RC003 的音量键/返回键是否同样**只送 Up**（决定 M1 的音量判定是否与模拟器一致）。
2. RC003 是否发媒体键（决定 M2c 是真结论还是"本设备无法验证"）。
3. `bluetoothInteraction` 连续任务在真机上能否启动（模拟器 9800005）。
4. `createPanel` 在真机上能否成功（模拟器 code=1）。
5. `uinput` 替换成真实 HID 后，`deviceId / keySource` 是否如预期（模拟器恒为 -1 / Keyboard）。
