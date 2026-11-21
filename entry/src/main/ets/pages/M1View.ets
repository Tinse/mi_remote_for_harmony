/**
 * entry / pages / M1View.ets  ——  M1 前台拦截
 *
 * 采集点：
 *   arkui.preime     onKeyPreIme（最早，返回值决定是否消费）
 *   arkui.dispatch   onKeyEventDispatch（preIme 未消费才会到）
 *   arkui.keyevent   onKeyEvent（未消费才会到）
 *   inputconsumer    inputConsumer.on('keyPressed')（音量± / 媒体键的「优先响应」通道）
 *
 * 关键事实（文档依据见 README 接口核对表）：
 *   - 事件先到 onKeyPreIme，返回 true 即视为消费，后续 keyboardShortcut / 输入法 /
 *     onKeyEventDispatch / onKeyEvent 都不再触发（common.d.ts onKeyPreIme 注释）；
 *   - 因此「消费事件」开关真正的作用点是 onKeyPreIme 的返回值，而不是 onKeyEvent；
 *   - inputConsumer.on('keyPressed') 一旦订阅成功，系统默认行为即被屏蔽，取消订阅才恢复，
 *     所以它本身就是「消费/不消费」的另一种开关，aria 只在窗口为前台焦点窗口时生效。
 */
// KeyEvent 在此处同时存在两个同名类型：ArkUI 全局的 KeyEvent（组件回调参数）和
// InputKit 的 KeyEvent（inputConsumer 回调参数）。后者必须改名，避免遮蔽。
import { KeyCode, KeyEvent as InputKeyEvent, inputConsumer } from '@kit.InputKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProbeEvent, ProbeKeyDesc, enumNameOf, findKey, keyNameOf, probe } from 'probecore';
import { KeyMatrix } from '../common/KeyMatrix';

@Component
export struct M1View {
  /** onKeyPreIme 的返回值：true = 消费，系统默认行为应被抑制 */
  @State consumePreIme: boolean = true;
  /** inputConsumer 是否已订阅（订阅即消费音量/媒体键的系统默认行为） */
  @State icArmed: boolean = false;
  @State feed: string[] = [];
  @State focusHint: string = '请让本页保持焦点（点一下「重新获取焦点」）';
  private sinkId: string = 'm1-feed';

  // inputConsumer 的回调必须是「每个键一个不同 callback」，否则订阅不生效（文档明示）
  private cbVolUp: (e: InputKeyEvent) => void = (e: InputKeyEvent) => {
    this.onInputConsumer(e, KeyCode.KEYCODE_VOLUME_UP);
  };
  private cbVolDown: (e: InputKeyEvent) => void = (e: InputKeyEvent) => {
    this.onInputConsumer(e, KeyCode.KEYCODE_VOLUME_DOWN);
  };
  private cbMediaPlayPause: (e: InputKeyEvent) => void = (e: InputKeyEvent) => {
    this.onInputConsumer(e, KeyCode.KEYCODE_MEDIA_PLAY_PAUSE);
  };

  aboutToAppear(): void {
    probe.subscribe(this.sinkId, (line: string) => {
      const next: string[] = this.feed.slice();
      next.push(line);
      while (next.length > 8) {
        next.shift();
      }
      this.feed = next;
    });
  }

  aboutToDisappear(): void {
    probe.unsubscribe(this.sinkId);
    this.disarmInputConsumer();
  }

  private typeName(t: KeyType): string {
    if (t === KeyType.Down) {
      return 'Down';
    }
    if (t === KeyType.Up) {
      return 'Up';
    }
    if (t === KeyType.CANCEL) {
      return 'Cancel';
    }
    return `KeyType(${t})`;
  }

  private sourceName(s: KeySource): string {
    if (s === KeySource.Unknown) {
      return 'Unknown';
    }
    if (s === KeySource.Keyboard) {
      return 'Keyboard';
    }
    if (s === KeySource.JOYSTICK) {
      return 'Joystick';
    }
    return `KeySource(${s})`;
  }

  /** 三种 ArkUI 通道共用这一处上报，保证字段一致 */
  private logArkui(channel: string, e: KeyEvent): void {
    const ev: ProbeEvent = new ProbeEvent('M1', channel, keyNameOf(e.keyCode), e.keyCode,
      enumNameOf(e.keyCode), this.typeName(e.type), this.sourceName(e.keySource), e.deviceId, e.timestamp, '');
    probe.record(ev);
  }

  private onPreIme(e: KeyEvent): boolean {
    this.logArkui('arkui.preime', e);
    return this.consumePreIme;
  }

  private onDispatch(e: KeyEvent): boolean {
    this.logArkui('arkui.dispatch', e);
    // 不在这一层消费：它只用来证明「preIme 没吃掉时事件确实继续下发了」
    return false;
  }

  private onKey(e: KeyEvent): void {
    this.logArkui('arkui.keyevent', e);
  }

  private onInputConsumer(e: InputKeyEvent, expect: number): void {
    const ev: ProbeEvent = new ProbeEvent('M1', 'inputconsumer', keyNameOf(expect), e.key.code,
      enumNameOf(e.key.code), `Action(${e.action})`, 'n/a', e.key.deviceId, e.key.pressedTime, `expect=${expect}`);
    probe.record(ev);
  }

  private armInputConsumer(): void {
    if (this.icArmed) {
      this.disarmInputConsumer();
      return;
    }
    try {
      const up: inputConsumer.KeyPressedConfig = {
        key: KeyCode.KEYCODE_VOLUME_UP, action: 1, isRepeat: false
      };
      // 文档：订阅成功后该按键的系统默认行为将被屏蔽（音量条不再出现），off 才恢复
      inputConsumer.on('keyPressed', up, this.cbVolUp);
      const down: inputConsumer.KeyPressedConfig = {
        key: KeyCode.KEYCODE_VOLUME_DOWN, action: 1, isRepeat: false
      };
      inputConsumer.on('keyPressed', down, this.cbVolDown);
      const media: inputConsumer.KeyPressedConfig = {
        key: KeyCode.KEYCODE_MEDIA_PLAY_PAUSE, action: 1, isRepeat: false
      };
      inputConsumer.on('keyPressed', media, this.cbMediaPlayPause);
      this.icArmed = true;
      probe.note('M1', 'inputconsumer armed: VOLUME_UP/VOLUME_DOWN/MEDIA_PLAY_PAUSE (系统默认行为应被屏蔽)');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      // 预期失败点：老设备/不支持机型返回 801；纯三方应用没有权限问题时才会成功
      probe.note('M1', `inputconsumer arm FAILED code=${e.code} msg=${e.message}`);
      this.icArmed = false;
    }
  }

  private disarmInputConsumer(): void {
    if (!this.icArmed) {
      return;
    }
    try {
      inputConsumer.off('keyPressed', this.cbVolUp);
      inputConsumer.off('keyPressed', this.cbVolDown);
      inputConsumer.off('keyPressed', this.cbMediaPlayPause);
      probe.note('M1', 'inputconsumer off: 系统默认行为恢复');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      probe.note('M1', `inputconsumer off FAILED code=${e.code} msg=${e.message}`);
    }
    this.icArmed = false;
  }

  private focusRoot(): void {
    try {
      this.getUIContext().getFocusController().requestFocus('m1root');
      this.focusHint = '已请求焦点（若无反应，先点一下页面空白处）';
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.focusHint = `请求焦点失败 code=${e.code} msg=${e.message}`;
    }
  }

  build() {
    Column({ space: 10 }) {
      Text('M1 前台拦截')
        .fontSize(16)
        .fontColor('#E6E9EF')
        .width('100%')

      Text('① 让本页保持焦点；② 按遥控器；③ 每个键按两下，告诉 App「系统默认行为」有没有发生。')
        .fontSize(12)
        .fontColor('#8A93A0')
        .width('100%')

      // 消费开关（ArkUI 层）
      Row({ space: 8 }) {
        Text('onKeyPreIme 消费')
          .fontSize(13)
          .fontColor('#C8D0DC')
        Toggle({ type: ToggleType.Switch, isOn: this.consumePreIme })
          .onChange((on: boolean) => {
            this.consumePreIme = on;
            probe.note('M1', `onKeyPreIme consume=${on}`);
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Text('inputConsumer 订阅（音量±/媒体键）')
          .fontSize(13)
          .fontColor('#C8D0DC')
        Toggle({ type: ToggleType.Switch, isOn: this.icArmed })
          .onChange((on: boolean) => {
            this.armInputConsumer();
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(this.focusHint)
          .fontSize(11)
          .fontColor('#7A8391')
          .layoutWeight(1)
        Button('重新获取焦点')
          .fontSize(11)
          .height(28)
          .backgroundColor('#1C2531')
          .fontColor('#9FB3CC')
          .onClick(() => this.focusRoot())
      }
      .width('100%')

      // 实时日志（同一份 hilog 内容）
      Column({ space: 2 }) {
        Text('最近事件（hilog tag=RCProbe）')
          .fontSize(11)
          .fontColor('#6B7480')
          .width('100%')
        ForEach(this.feed, (line: string) => {
          Text(line)
            .fontSize(9)
            .fontColor('#93A0B4')
            .maxLines(2)
            .width('100%')
        }, (line: string, idx: number) => `${idx}-${line}`)
        if (this.feed.length === 0) {
          Text('（还没有事件。检查：遥控器已配对？页面有焦点？）')
            .fontSize(10)
            .fontColor('#5A6270')
        }
      }
      .padding(8)
      .backgroundColor('#121821')
      .borderRadius(6)
      .width('100%')

      Scroll() {
        Column() {
          // channelPrefix='arkui.'：M1 的矩阵只认 ArkUI 分发链路是否收到
          KeyMatrix({ mode: 'M1', channelPrefix: 'arkui.', showApi26: true })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#0B0F14')
    .focusable(true)
    .defaultFocus(true)
    .id('m1root')
    .onKeyPreIme((e: KeyEvent) => this.onPreIme(e))
    .onKeyEventDispatch((e: KeyEvent) => this.onDispatch(e))
    .onKeyEvent((e: KeyEvent) => this.onKey(e))
  }
}
