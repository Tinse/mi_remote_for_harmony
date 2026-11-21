/**
 * entry / pages / M2View.ets  ——  M2 后台拦截
 *
 * 三条合法路径，各自独立开关，结果分开记：
 *   a) 普通后台 + inputConsumer        预期失效（窗口不在前台焦点，回调不触发）
 *   b) KEEP_BACKGROUND_RUNNING + 蓝牙类连续任务（bluetoothInteraction）
 *                                     预期能让进程活着，但按键依然不会派发到后台窗口
 *   c) AVSession 成为活跃会话，用媒体键回调接收
 *                                      后台唯一可能成功的通道；遥控器若不发媒体键则无法验证
 *
 * 取证方式：hilog tag=RCProbe + 本页矩阵。切后台前先点一次「清空 M2 采集」，
 * 这样矩阵里的计数只包含「已在后台」之后发生的事件。
 */
import { KeyCode, inputConsumer } from '@kit.InputKit';
import { KeyEvent as InputKeyEvent } from '@kit.InputKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProbeEvent, ProbeState, SysBehavior, enumNameOf, keyNameOf, probe, verdicts } from 'probecore';
import { KeyMatrix } from '../common/KeyMatrix';

const BUNDLE: string = 'com.rcprobe.probe';
const ABILITY: string = 'EntryAbility';

@Component
export struct M2View {
  @State aArmed: boolean = false;
  @State bRunning: boolean = false;
  @State cSession: boolean = false;
  @State cState: string = '未创建';
  @State feed: string[] = [];
  private sinkId: string = 'm2-feed';
  private loudSession: avSession.AVSession | null = null;

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
  }

  private ctx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private onInputConsumer(e: InputKeyEvent, expect: number): void {
    const ev: ProbeEvent = new ProbeEvent('M2', 'inputconsumer', keyNameOf(expect), e.key.code,
      enumNameOf(e.key.code), `Action(${e.action})`, 'n/a', e.key.deviceId, e.key.pressedTime, `expect=${expect}`);
    probe.record(ev);
  }

  // ---------------- (a) 普通后台 + inputConsumer ----------------
  private toggleA(): void {
    if (this.aArmed) {
      inputConsumer.off('keyPressed', this.cbVolUp);
      inputConsumer.off('keyPressed', this.cbVolDown);
      inputConsumer.off('keyPressed', this.cbMediaPlayPause);
      this.aArmed = false;
      probe.note('M2', 'a) inputconsumer off');
      return;
    }
    try {
      const up: inputConsumer.KeyPressedConfig = { key: KeyCode.KEYCODE_VOLUME_UP, action: 1, isRepeat: false };
      const down: inputConsumer.KeyPressedConfig = { key: KeyCode.KEYCODE_VOLUME_DOWN, action: 1, isRepeat: false };
      const media: inputConsumer.KeyPressedConfig = {
        key: KeyCode.KEYCODE_MEDIA_PLAY_PAUSE, action: 1, isRepeat: false
      };
      inputConsumer.on('keyPressed', up, this.cbVolUp);
      inputConsumer.on('keyPressed', down, this.cbVolDown);
      inputConsumer.on('keyPressed', media, this.cbMediaPlayPause);
      this.aArmed = true;
      probe.note('M2', 'a) inputconsumer armed (仅前台焦点窗口有效，切后台后预期无回调)');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      probe.note('M2', `a) inputconsumer arm FAILED code=${e.code} msg=${e.message}`);
      this.aArmed = false;
    }
  }

  // ---------------- (b) 连续任务 ----------------
  private async toggleB(): Promise<void> {
    if (this.bRunning) {
      try {
        await backgroundTaskManager.stopBackgroundRunning(this.ctx());
        this.bRunning = false;
        probe.note('M2', 'b) stopBackgroundRunning ok');
      } catch (err) {
        const e: BusinessError = err as BusinessError;
        probe.note('M2', `b) stopBackgroundRunning FAILED code=${e.code} msg=${e.message}`);
      }
      return;
    }
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: BUNDLE, abilityName: ABILITY }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent: WantAgent = await wantAgent.getWantAgent(info);
      // bluetoothInteraction：与 BLE HID 遥控器场景最接近的连续任务类型
      await backgroundTaskManager.startBackgroundRunning(this.ctx(), ['bluetoothInteraction'], agent);
      this.bRunning = true;
      probe.note('M2', 'b) startBackgroundRunning(bluetoothInteraction) ok');
    } catch (err) {
      // 预期失败点：未声明 ohos.permission.KEEP_BACKGROUND_RUNNING、或机型不支持该 bgMode
      const e: BusinessError = err as BusinessError;
      probe.note('M2', `b) startBackgroundRunning FAILED code=${e.code} msg=${e.message}`);
      this.bRunning = false;
    }
  }

  // ---------------- (c) AVSession ----------------
  private async createSession(): Promise<void> {
    if (this.cSession) {
      return;
    }
    try {
      const s: avSession.AVSession = await avSession.createAVSession(this.ctx(), 'RCProbeSession', 'audio');
      const meta: avSession.AVMetadata = {
        assetId: 'rcprobe-probe',
        title: 'RCProbe media-key probe',
        artist: 'RCProbe'
      };
      await s.setAVMetadata(meta);
      s.on('play', () => {
        this.onAv('play', KeyCode.KEYCODE_MEDIA_PLAY_PAUSE);
      });
      s.on('pause', () => {
        this.onAv('pause', KeyCode.KEYCODE_MEDIA_PLAY_PAUSE);
      });
      s.on('stop', () => {
        this.onAv('stop', KeyCode.KEYCODE_MEDIA_PLAY_PAUSE);
      });
      s.on('playNext', () => {
        this.onAv('playNext', KeyCode.KEYCODE_MEDIA_NEXT);
      });
      s.on('playPrevious', () => {
        this.onAv('playPrevious', KeyCode.KEYCODE_MEDIA_PREVIOUS);
      });
      await s.activate();
      this.loudSession = s;
      this.cSession = true;
      this.cState = '已创建并激活（播放态未设，媒体键可能不路由）';
      probe.note('M2', 'c) AVSession created + activated');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      probe.note('M2', `c) createAVSession FAILED code=${e.code} msg=${e.message}`);
    }
  }

  private onAv(cmd: string, key: number): void {
    const ev: ProbeEvent = new ProbeEvent('M2', `avsession.${cmd}`, keyNameOf(key), key,
      enumNameOf(key), 'Cmd', 'n/a', -1, 0, `cmd=${cmd}`);
    probe.record(ev);
  }

  private async setPlayState(play: boolean): Promise<void> {
    const s: avSession.AVSession | null = this.loudSession;
    if (s === null) {
      return;
    }
    try {
      const st: avSession.AVPlaybackState = {
        state: play ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE
      };
      await s.setAVPlaybackState(st);
      this.cState = play ? '播放态=PLAY（媒体键最可能路由到本会话）' : '播放态=PAUSE';
      probe.note('M2', `c) setAVPlaybackState play=${play}`);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      probe.note('M2', `c) setAVPlaybackState FAILED code=${e.code} msg=${e.message}`);
    }
  }

  private async destroySession(): Promise<void> {
    const s: avSession.AVSession | null = this.loudSession;
    if (s === null) {
      return;
    }
    try {
      await s.deactivate();
      await s.destroy();
      probe.note('M2', 'c) AVSession deactivate + destroy ok');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      probe.note('M2', `c) destroy FAILED code=${e.code} msg=${e.message}`);
    }
    this.loudSession = null;
    this.cSession = false;
    this.cState = '未创建';
  }

  /** M2c 若遥控器不发媒体键：明确标注「本设备无法验证」，不要伪造结论 */
  private markUnverifiable(): void {
    probe.note('M2', 'c) 标注：本设备无法验证（遥控器未发出媒体键，且现场无其他媒体键输入源）');
    probe.note('M2', 'c) 写入 RESULT.md 时须同时记录：证据=AVSession 五个回调在 hilog 中零命中');
  }

  build() {
    Column({ space: 8 }) {
      Text('M2 后台拦截')
        .fontSize(16)
        .fontColor('#E6E9EF')
        .width('100%')
      Text('顺序：启动 a/b/c → 点「清空 M2 采集」→ 按主页切后台 → 按遥控器 → 回本页看矩阵')
        .fontSize(11)
        .fontColor('#8A93A0')
        .width('100%')

      // a
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text('a) 普通后台 + inputConsumer')
            .fontSize(13)
            .fontColor('#C8D0DC')
            .layoutWeight(1)
          Button(this.aArmed ? '关闭' : '启动')
            .fontSize(11)
            .height(26)
            .backgroundColor('#1C2531')
            .fontColor('#9FB3CC')
            .onClick(() => this.toggleA())
        }
        .width('100%')
        Text('预期失效：keyPressed 仅在「前台焦点窗口」触发（inputConsumer.d.ts 原文）')
          .fontSize(10)
          .fontColor('#6B7480')
          .width('100%')
      }
      .padding(8)
      .backgroundColor('#121821')
      .borderRadius(6)
      .width('100%')

      // b
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text('b) 连续任务 bluetoothInteraction')
            .fontSize(13)
            .fontColor('#C8D0DC')
            .layoutWeight(1)
          Button(this.bRunning ? '停止' : '启动')
            .fontSize(11)
            .height(26)
            .backgroundColor('#1C2531')
            .fontColor('#9FB3CC')
            .onClick(() => {
              this.toggleB();
            })
        }
        .width('100%')
        Text('预期：进程活着，但后台窗口仍收不到按键（长时任务不改变输入派发目标）')
          .fontSize(10)
          .fontColor('#6B7480')
          .width('100%')
      }
      .padding(8)
      .backgroundColor('#121821')
      .borderRadius(6)
      .width('100%')

      // c
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text('c) AVSession 媒体键')
            .fontSize(13)
            .fontColor('#C8D0DC')
            .layoutWeight(1)
          Button('创建')
            .fontSize(11)
            .height(26)
            .backgroundColor('#1C2531')
            .fontColor('#9FB3CC')
            .onClick(() => {
              this.createSession();
            })
          Button('PLAY')
            .fontSize(11)
            .height(26)
            .backgroundColor('#1C2531')
            .fontColor('#9FB3CC')
            .onClick(() => {
              this.setPlayState(true);
            })
          Button('PAUSE')
            .fontSize(11)
            .height(26)
            .backgroundColor('#1C2531')
            .fontColor('#9FB3CC')
            .onClick(() => {
              this.setPlayState(false);
            })
          Button('销毁')
            .fontSize(11)
            .height(26)
            .backgroundColor('#1C2531')
            .fontColor('#9FB3CC')
            .onClick(() => {
              this.destroySession();
            })
        }
        .width('100%')
        Text(this.cState)
          .fontSize(10)
          .fontColor('#6B7480')
          .width('100%')
        Text('后台唯一可能成功的通道：系统把媒体键投给「活跃会话」。遥控器不发媒体键时本项无法验证。')
          .fontSize(10)
          .fontColor('#6B7480')
          .width('100%')
        Button('标注 M2c：本设备无法验证')
          .fontSize(10)
          .height(24)
          .backgroundColor('#2A1F1F')
          .fontColor('#C48A7A')
          .onClick(() => this.markUnverifiable())
      }
      .padding(8)
      .backgroundColor('#121821')
      .borderRadius(6)
      .width('100%')

      Row({ space: 8 }) {
        Button('清空 M2 采集')
          .fontSize(11)
          .height(28)
          .backgroundColor('#2A3442')
          .fontColor('#C8D0DC')
          .onClick(() => {
            probe.clear('M2');
            probe.note('M2', 'cleared: 从现在开始只统计后台事件');
          })
        Button('导出 M2 判定')
          .fontSize(11)
          .height(28)
          .backgroundColor('#1C2531')
          .fontColor('#9FB3CC')
          .onClick(() => {
            probe.note('M2', `channels=${probe.channels('M2').join(',')}`);
            verdicts.all('M2').forEach((c) => {
              probe.verdict('M2', c.key.label, c.key.code, verdicts.state('M2', c.key,
                probe.count('M2', '', c.key.code)), c.sys, 'manual-dump');
            });
          })
      }
      .width('100%')

      Column({ space: 2 }) {
        ForEach(this.feed, (line: string) => {
          Text(line)
            .fontSize(9)
            .fontColor('#93A0B4')
            .maxLines(2)
            .width('100%')
        }, (line: string, idx: number) => `${idx}-${line}`)
        if (this.feed.length === 0) {
          Text('（还没有日志）')
            .fontSize(10)
            .fontColor('#5A6270')
        }
      }
      .padding(6)
      .backgroundColor('#0F141B')
      .borderRadius(6)
      .width('100%')
      .height(64)

      Scroll() {
        Column() {
          // channelPrefix=''：M2 的矩阵认任意通道（a/b/c 都算），因为后台只有这些通道可能来
          KeyMatrix({ mode: 'M2', channelPrefix: '', showApi26: false })
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
  }
}
