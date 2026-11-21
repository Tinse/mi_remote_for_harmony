/**
 * ime / InputMethodExtensionAbility / pages / Index.ets
 * 自绘软键盘（最小实现）。它不做完整输入法，只负责三件事：
 *   1) 把「物理键消费 / 物理键转文字」两个开关暴露出来；
 *   2) 显示输入法链路收到的物理键（与 hilog 同源）；
 *   3) 用自绘按键验证 insertTextSync —— 需求里说的 commitText 在 API 里并不存在。
 */
import { probe } from 'probecore';
import { imeController } from '../model/ImeController';

const ROW1: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
const ROW2: string[] = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
const ROW3: string[] = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
const ROW4: string[] = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

@Entry
@Component
struct Index {
  @State consume: boolean = true;
  @State toText: boolean = true;
  @State logs: string[] = [];
  @State clientBound: boolean = false;
  private sinkId: string = 'ime-panel';

  aboutToAppear(): void {
    this.consume = imeController.consumeKey;
    this.toText = imeController.toText;
    this.clientBound = imeController.hasClient();
    probe.subscribe(this.sinkId, (line: string) => {
      const next: string[] = this.logs.slice();
      next.push(line);
      while (next.length > 5) {
        next.shift();
      }
      this.logs = next;
      this.clientBound = imeController.hasClient();
    });
  }

  aboutToDisappear(): void {
    probe.unsubscribe(this.sinkId);
  }

  @Builder
  keyRow(items: string[]) {
    Row({ space: 4 }) {
      ForEach(items, (k: string) => {
        Button(k)
          .fontSize(12)
          .height(30)
          .layoutWeight(1)
          .padding(0)
          .backgroundColor('#242C38')
          .fontColor('#D5DCE6')
          .onClick(() => imeController.insertChar(k))
      }, (k: string) => k)
    }
    .width('100%')
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text('RCProbe 探针键盘')
          .fontSize(12)
          .fontColor('#E6E9EF')
          .layoutWeight(1)
        Text(this.clientBound ? '已连接输入框' : '未连接输入框')
          .fontSize(10)
          .fontColor(this.clientBound ? '#39B36A' : '#C4553D')
      }
      .width('100%')

      Row({ space: 10 }) {
        Row({ space: 4 }) {
          Text('消费物理键').fontSize(10).fontColor('#9FB3CC')
          Toggle({ type: ToggleType.Switch, isOn: this.consume })
            .onChange((on: boolean) => {
              this.consume = on;
              imeController.consumeKey = on;
              probe.note('M3', `ime consumeKey=${on}`);
            })
        }
        Row({ space: 4 }) {
          Text('物理键转文字').fontSize(10).fontColor('#9FB3CC')
          Toggle({ type: ToggleType.Switch, isOn: this.toText })
            .onChange((on: boolean) => {
              this.toText = on;
              imeController.toText = on;
              probe.note('M3', `ime toText=${on}`);
            })
        }
      }
      .width('100%')

      Column({ space: 1 }) {
        ForEach(this.logs, (line: string) => {
          Text(line).fontSize(8).fontColor('#8A93A0').maxLines(1).width('100%')
        }, (line: string, i: number) => `${i}-${line}`)
        if (this.logs.length === 0) {
          Text('（还没有物理键事件）').fontSize(8).fontColor('#5A6270')
        }
      }
      .padding(4)
      .backgroundColor('#0F141B')
      .borderRadius(4)
      .width('100%')
      .height(48)

      this.keyRow(ROW1)
      this.keyRow(ROW2)
      this.keyRow(ROW3)

      Row({ space: 4 }) {
        ForEach(ROW4, (k: string) => {
          Button(k)
            .fontSize(12)
            .height(30)
            .layoutWeight(1)
            .padding(0)
            .backgroundColor('#242C38')
            .fontColor('#D5DCE6')
            .onClick(() => imeController.insertChar(k))
        }, (k: string) => k)
        Button('⌫')
          .fontSize(12)
          .height(30)
          .width(52)
          .padding(0)
          .backgroundColor('#3A2A2A')
          .fontColor('#E0B0A0')
          .onClick(() => imeController.deleteBack())
        Button('␣')
          .fontSize(12)
          .height(30)
          .width(52)
          .padding(0)
          .backgroundColor('#242C38')
          .fontColor('#D5DCE6')
          .onClick(() => imeController.insertChar(' '))
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(8)
    .backgroundColor('#0B0F14')
  }
}
