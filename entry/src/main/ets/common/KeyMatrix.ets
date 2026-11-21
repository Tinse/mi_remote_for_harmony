/**
 * entry / common / KeyMatrix.ets
 *
 * 「键 × 模式」矩阵的单格交互控件：13 行，每行两个按钮（系统行为 发生 / 未发生）。
 * 判定不是手填的，而是由 ProbeVerdictStore 按三态规则算出来的：
 *   捕获次数 > 0 + 系统行为发生   = 收到但未消费
 *   捕获次数 > 0 + 系统行为未发生 = 收到并消费
 *   捕获次数 = 0 + 系统行为发生   = 未收到
 *   捕获次数 = 0 + 系统行为未发生 = 证据不足（该键这次根本没触发任何东西）
 */
import { CORE_KEYS, ProbeKeyDesc, ProbeState, SysBehavior, api26Keys, probe, stateColor, stateText,
  verdicts } from 'probecore';
import { KeyRowVM } from './KeyRowVM';

let matrixSeq: number = 0;

@Component
export struct KeyMatrix {
  /** M1 / M2 / M3 */
  mode: string = 'M1';
  /** 只统计以此前缀开头的通道；空串 = 本模式收到的任意通道都算 */
  channelPrefix: string = '';
  /** 是否把 API 26 新增键（3232–3234）也列出来 */
  showApi26: boolean = false;
  @State rows: KeyRowVM[] = [];
  private sinkId: string = '';

  aboutToAppear(): void {
    matrixSeq += 1;
    this.sinkId = `matrix-${this.mode}-${matrixSeq}`;
    probe.subscribe(this.sinkId, (line: string) => {
      this.refresh();
    });
    this.refresh();
  }

  aboutToDisappear(): void {
    probe.unsubscribe(this.sinkId);
  }

  refresh(): void {
    this.rows = this.buildRows();
  }

  private buildRows(): KeyRowVM[] {
    const out: KeyRowVM[] = [];
    for (let i = 0; i < CORE_KEYS.length; i++) {
      out.push(this.toRow(CORE_KEYS[i]));
    }
    if (this.showApi26) {
      const extra: ProbeKeyDesc[] = api26Keys();
      for (let i = 0; i < extra.length; i++) {
        out.push(this.toRow(extra[i]));
      }
    }
    return out;
  }

  private toRow(k: ProbeKeyDesc): KeyRowVM {
    const count: number = probe.count(this.mode, this.channelPrefix, k.code);
    const state: ProbeState = verdicts.state(this.mode, k, count);
    const cellSys: SysBehavior = verdicts.cell(this.mode, k).sys;
    return new KeyRowVM(k.label, k.code, k.enumName, count, cellSys, stateText(state), stateColor(state), k.api26);
  }

  private mark(k: ProbeKeyDesc, sys: SysBehavior): void {
    const count: number = probe.count(this.mode, this.channelPrefix, k.code);
    verdicts.setSys(this.mode, k, sys, `cap=${count}`);
    probe.verdict(this.mode, k.label, k.code, verdicts.state(this.mode, k, count), sys, `cap=${count}`);
    this.refresh();
  }

  /** 一次性把本模式所有行的判定写进 hilog，方便 RESULT.md 直接对照 */
  private dumpAll(): void {
    const keys: ProbeKeyDesc[] = CORE_KEYS;
    for (let i = 0; i < keys.length; i++) {
      const k: ProbeKeyDesc = keys[i];
      const count: number = probe.count(this.mode, this.channelPrefix, k.code);
      const state: ProbeState = verdicts.state(this.mode, k, count);
      probe.verdict(this.mode, k.label, k.code, state, verdicts.cell(this.mode, k).sys,
        `dump cap=${count} ch=${this.channelPrefix.length === 0 ? 'any' : this.channelPrefix}`);
    }
    probe.note(this.mode, 'dump done: 13 rows written to hilog');
  }

  @Builder
  rowView(r: KeyRowVM) {
    Row({ space: 6 }) {
      Column({ space: 2 }) {
        Text(r.label)
          .fontSize(13)
          .fontColor('#E6E9EF')
        Text(r.enumName.replace('KEYCODE_', '') + '  ' + r.code.toString())
          .fontSize(10)
          .fontColor('#7A8391')
      }
      .alignItems(HorizontalAlign.Start)
      .width(92)

      Text('捕获 ' + r.count.toString())
        .fontSize(12)
        .fontColor(r.count > 0 ? '#6FA8FF' : '#5A6270')
        .width(56)

      Row({ space: 4 }) {
        Button('行为发生')
          .focusable(false)
          .fontSize(11)
          .height(26)
          .padding({ left: 8, right: 8 })
          .backgroundColor(r.sys === SysBehavior.HAPPENED ? '#3D6EA8' : '#232A35')
          .onClick(() => this.mark(this.keyOf(r), SysBehavior.HAPPENED))
        Button('行为未发生')
          .focusable(false)
          .fontSize(11)
          .height(26)
          .padding({ left: 8, right: 8 })
          .backgroundColor(r.sys === SysBehavior.ABSENT ? '#3D6EA8' : '#232A35')
          .onClick(() => this.mark(this.keyOf(r), SysBehavior.ABSENT))
      }
      .width(150)

      Blank()

      Text(r.verdict)
        .fontSize(12)
        .fontColor(r.verdictColor)
        .textAlign(TextAlign.End)
        .width(84)
    }
    .width('100%')
    .height(38)
    .padding({ left: 8, right: 8 })
  }

  private keyOf(r: KeyRowVM): ProbeKeyDesc {
    const all: ProbeKeyDesc[] = CORE_KEYS;
    for (let i = 0; i < all.length; i++) {
      if (all[i].code === r.code) {
        return all[i];
      }
    }
    const extra: ProbeKeyDesc[] = api26Keys();
    for (let i = 0; i < extra.length; i++) {
      if (extra[i].code === r.code) {
        return extra[i];
      }
    }
    return all[0];
  }

  build() {
    Column({ space: 0 }) {
      Row() {
        Text('键').fontSize(11).fontColor('#6B7480').width(92)
        Text('采集').fontSize(11).fontColor('#6B7480').width(56)
        Text('系统默认行为').fontSize(11).fontColor('#6B7480').width(150)
        Blank()
        Text('判定').fontSize(11).fontColor('#6B7480').width(84).textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: 4 })

      Divider().color('#1E2530')

      ForEach(this.rows, (r: KeyRowVM) => {
        this.rowView(r)
        Divider().color('#151B24')
      }, (r: KeyRowVM) => `${this.mode}-${r.code}-${r.id()}`)

      Row({ space: 8 }) {
        Button('清空采集')
          .focusable(false)
          .layoutWeight(1)
          .fontSize(12)
          .height(32)
          .backgroundColor('#1C2531')
          .fontColor('#9FB3CC')
          .margin({ top: 8 })
          .onClick(() => {
            // 采集缓冲三模式共用，但 clear(mode) 只清本模式的事件：
            // 判定（VerdictCell）是另一套存储，同样不受影响。
            probe.clear(this.mode);
            probe.note(this.mode, 'matrix clear: 本模式采集已清空（判定保留）');
            this.refresh();
          })
        Button('全部写入 hilog')
          .focusable(false)
          .layoutWeight(1)
          .fontSize(12)
          .height(32)
          .backgroundColor('#1C2531')
          .fontColor('#9FB3CC')
          .margin({ top: 8 })
          .onClick(() => this.dumpAll())
      }
      .width('100%')
    }
    .width('100%')
  }
}
