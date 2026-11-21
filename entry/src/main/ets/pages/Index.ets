/**
 * entry / pages / Index.ets
 * 四个页签：M1 前台 / M2 后台 / M3 输入法 / 说明（能力自检）。
 * 三个测试页共用 probecore 的采集与上报，界面只负责「让测试者按两下按钮」。
 */
import { deviceInfo } from '@kit.BasicServicesKit';
import { probe } from 'probecore';
import { M1View } from './M1View';
import { M2View } from './M2View';
import { M3View } from './M3View';

@Component
struct HelpView {
  @State lines: string[] = [];

  aboutToAppear(): void {
    const rows: string[] = [];
    rows.push(`osFullName=${deviceInfo.osFullName ?? 'n/a'}`);
    rows.push(`sdkApiVersion=${deviceInfo.sdkApiVersion}`);
    rows.push(`model=${deviceInfo.productModel}`);
    rows.push(`brand=${deviceInfo.brand}`);
    rows.push('');
    rows.push('能力探测（canIUse）：');
    rows.push(`Input.InputConsumer = ${canIUse('SystemCapability.MultimodalInput.Input.InputConsumer')}`);
    rows.push(`Input.Core = ${canIUse('SystemCapability.MultimodalInput.Input.Core')}`);
    rows.push(`Input.InputSimulator = ${canIUse('SystemCapability.MultimodalInput.Input.InputSimulator')}`);
    rows.push(`Multimedia.AVSession.Core = ${canIUse('SystemCapability.Multimedia.AVSession.Core')}`);
    rows.push(`MiscServices.InputMethodFramework = ${canIUse('SystemCapability.MiscServices.InputMethodFramework')}`);
    rows.push(`BarrierFree.Accessibility.Core = ${canIUse('SystemCapability.BarrierFree.Accessibility.Core')}`);
    this.lines = rows;
  }

  build() {
    Column({ space: 6 }) {
      Text('说明 / 能力自检').fontSize(16).fontColor('#E6E9EF').width('100%')
      Text('日志固定 tag=RCProbe。判定三态见 RESULT.md。').fontSize(11).fontColor('#8A93A0').width('100%')
      Scroll() {
        Column() {
          ForEach(this.lines, (l: string) => {
            Text(l).fontSize(11).fontColor('#9FB3CC').width('100%')
          }, (l: string, i: number) => `${i}-${l}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)

      Button('把设备信息写入 hilog')
        .fontSize(12)
        .height(32)
        .width('100%')
        .backgroundColor('#1C2531')
        .fontColor('#9FB3CC')
        .onClick(() => {
          for (let i = 0; i < this.lines.length; i++) {
            probe.note('M1', this.lines[i]);
          }
        })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#0B0F14')
  }
}

@Entry
@Component
struct Index {
  @State curTab: number = 0;

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.curTab }) {
      TabContent() {
        M1View()
      }
      .tabBar('M1 前台')

      TabContent() {
        M2View()
      }
      .tabBar('M2 后台')

      TabContent() {
        M3View()
      }
      .tabBar('M3 输入法')

      TabContent() {
        HelpView()
      }
      .tabBar('说明')
    }
    .onChange((index: number) => {
      this.curTab = index;
      probe.note('M1', `tab changed -> ${index}`);
    })
    .barHeight(52)
    .barMode(BarMode.Fixed)
  }
}
