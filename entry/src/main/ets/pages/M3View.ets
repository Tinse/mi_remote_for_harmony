/**
 * entry / pages / M3View.ets  ——  M3 输入法 / 键盘形态（主 App 侧的测试台）
 *
 * 输入法本体在独立 HAP（module: ime），本页只负责：
 *   1) 给一个真实 TextInput，把当前输入法切成本工程输入法后把键盘拉起来；
 *   2) 提供三条结论的登记按钮；
 *   3) 用本页的 onKeyPreIme 验证「输入法为当前输入法时，M1 的前台拦截是否仍生效」。
 *
 * 文档事实（README 里有完整引用）：
 *   按键派发顺序 = onKeyPreIme -> 输入法 -> onKeyEventDispatch/onKeyEvent，
 *   一旦某一环消费即中断后续。所以「输入法消费了」和「App 还收得到」天然互斥，
 *   但「输入法没消费」时 App 仍能收到 —— 这两条链路不是并列关系，是流水线关系。
 */
import { ProbeEvent, enumNameOf, keyNameOf, probe } from 'probecore';
import { KeyMatrix } from '../common/KeyMatrix';

@Component
export struct M3View {
  @State consumePreIme: boolean = false;
  @State feed: string[] = [];
  @State c1: string = '待测';
  @State c2: string = '待测';
  @State c3: string = '待测';
  @State inputText: string = '';
  private sinkId: string = 'm3-feed';

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

  private onPreIme(e: KeyEvent): boolean {
    const ev: ProbeEvent = new ProbeEvent('M3', 'arkui.preime', keyNameOf(e.keyCode), e.keyCode,
      enumNameOf(e.keyCode), 'Observed', 'n/a', e.deviceId, e.timestamp,
      'check3: IME 为当前输入法时 App 是否仍拿到 preIme');
    probe.record(ev);
    return this.consumePreIme;
  }

  private mark(which: number, value: string): void {
    if (which === 1) {
      this.c1 = value;
    } else if (which === 2) {
      this.c2 = value;
    } else {
      this.c3 = value;
    }
    probe.note('M3', `check${which}=${value}`);
  }

  build() {
    Column({ space: 8 }) {
      Text('M3 输入法 / 键盘形态')
        .fontSize(16)
        .fontColor('#E6E9EF')
        .width('100%')
      Text('先在系统设置里把「RCProbe Ime」设为当前输入法，再回来点下面的输入框拉起键盘。')
        .fontSize(11)
        .fontColor('#8A93A0')
        .width('100%')

      TextInput({ placeholder: '点这里拉起输入法（物理键应被输入法优先拿到）', text: this.inputText })
        .id('m3input')
        .height(44)
        .fontSize(12)
        .backgroundColor('#121821')
        .fontColor('#C8D0DC')
        .onChange((v: string) => {
          this.inputText = v;
        })

      Row({ space: 8 }) {
        Text('本页 onKeyPreIme 消费（用于检查 3）')
          .fontSize(12)
          .fontColor('#C8D0DC')
        Toggle({ type: ToggleType.Switch, isOn: this.consumePreIme })
          .onChange((on: boolean) => {
            this.consumePreIme = on;
            probe.note('M3', `arkui preIme consume=${on}`);
          })
      }
      .width('100%')

      // 三条结论登记
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text('1. 输入法能否截获物理键')
            .fontSize(12)
            .fontColor('#C8D0DC')
            .layoutWeight(1)
          Text(this.c1).fontSize(11).fontColor('#8FB3E0')
          Button('能').fontSize(10).height(24).backgroundColor('#1C2531')
            .onClick(() => this.mark(1, '能截获'))
          Button('不能').fontSize(10).height(24).backgroundColor('#2A1F1F')
            .onClick(() => this.mark(1, '不能截获'))
        }
        .width('100%')

        Row({ space: 6 }) {
          Text('2. 能否 insertText 变文字')
            .fontSize(12)
            .fontColor('#C8D0DC')
            .layoutWeight(1)
          Text(this.c2).fontSize(11).fontColor('#8FB3E0')
          Button('能').fontSize(10).height(24).backgroundColor('#1C2531')
            .onClick(() => this.mark(2, '能变文字'))
          Button('不能').fontSize(10).height(24).backgroundColor('#2A1F1F')
            .onClick(() => this.mark(2, '不能变文字'))
        }
        .width('100%')

        Row({ space: 6 }) {
          Text('3. IME 在位时 M1 仍生效')
            .fontSize(12)
            .fontColor('#C8D0DC')
            .layoutWeight(1)
          Text(this.c3).fontSize(11).fontColor('#8FB3E0')
          Button('仍收到').fontSize(10).height(24).backgroundColor('#1C2531')
            .onClick(() => this.mark(3, 'preIme 仍收到'))
          Button('被截断').fontSize(10).height(24).backgroundColor('#2A1F1F')
            .onClick(() => this.mark(3, 'preIme 收不到'))
        }
        .width('100%')

        Text('注：API 里没有 commitText；等价能力是 inputMethodEngine.InputClient.insertText / insertTextSync。')
          .fontSize(9)
          .fontColor('#6B7480')
          .width('100%')
      }
      .padding(8)
      .backgroundColor('#121821')
      .borderRadius(6)
      .width('100%')

      Column({ space: 2 }) {
        ForEach(this.feed, (line: string) => {
          Text(line).fontSize(9).fontColor('#93A0B4').maxLines(2).width('100%')
        }, (line: string, idx: number) => `${idx}-${line}`)
        if (this.feed.length === 0) {
          Text('（还没有日志）').fontSize(10).fontColor('#5A6270')
        }
      }
      .padding(6)
      .backgroundColor('#0F141B')
      .borderRadius(6)
      .width('100%')
      .height(64)

      Scroll() {
        Column() {
          // M3 的矩阵只统计输入法链路（channelPrefix='ime.'）
          KeyMatrix({ mode: 'M3', channelPrefix: 'ime.', showApi26: false })
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
    .onKeyPreIme((e: KeyEvent) => this.onPreIme(e))
  }
}
