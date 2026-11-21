/**
 * probecore / ProbeRecorder.ets
 *
 * 统一采集 + 上报。M1/M2（主 HAP）与 M3（输入法 HAP）全部调用这里，
 * 保证三种形态的字段、日志格式、判定口径完全一致（避免实现差异污染结论）。
 *
 * 日志一律走 hilog，固定 tag = RCProbe，可以用
 *   hdc hilog | Select-String "RCProbe"
 * 直接拉出来。
 *
 * 行格式（竖线分隔，便于 grep / awk）：
 *   RCProbe|EVT|m=M1|ch=arkui.preime|key=音量+|code=16|enum=KEYCODE_VOLUME_UP|type=Down|ksrc=KEYBOARD|dev=4|ts=123456|wm=1700000000000|extra=...
 *   RCProbe|VERDICT|m=M1|key=音量+|code=16|state=RECEIVED_CONSUMED|sys=ABSENT|ev=cap=1
 *   RCProbe|NOTE|m=M2|msg=...
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProbeEvent, ProbeState, SysBehavior } from './ProbeTypes';

export const RC_TAG: string = 'RCProbe';
export const RC_DOMAIN: number = 0x0001;

/** UI 侧订阅回调 */
export type RcSink = (line: string) => void;

export class ProbeRecorder {
  private static readonly holder: ProbeRecorder = new ProbeRecorder();
  private events: ProbeEvent[] = [];
  private readonly maxEvents: number = 400;
  private seq: number = 0;
  private sinks: Map<string, RcSink> = new Map<string, RcSink>();

  static get(): ProbeRecorder {
    return ProbeRecorder.holder;
  }

  /** 采集一条按键事件：入库 + 打日志 + 通知 UI */
  record(ev: ProbeEvent): void {
    this.seq += 1;
    this.events.push(ev);
    if (this.events.length > this.maxEvents) {
      this.events.splice(0, this.events.length - this.maxEvents);
    }
    const line: string = `RCProbe|EVT|m=${ev.mode}|ch=${ev.channel}|key=${ev.keyLabel}|code=${ev.keyCode}` +
      `|enum=${ev.enumName}|type=${ev.type}|ksrc=${ev.source}|dev=${ev.deviceId}|ts=${ev.timestampNs}` +
      `|wm=${ev.wallClockMs}|extra=${ev.extra}`;
    hilog.info(RC_DOMAIN, RC_TAG, '%{public}s', line);
    this.broadcast(line);
  }

  /** 过程性日志（订阅成功/失败、生命周期、能力开关…） */
  note(mode: string, msg: string): void {
    const line: string = `RCProbe|NOTE|m=${mode}|msg=${msg}`;
    hilog.info(RC_DOMAIN, RC_TAG, '%{public}s', line);
    this.broadcast(line);
  }

  /** 写入一条判定（同时落日志，RESULT.md 的内容应以 hilog 为准） */
  verdict(mode: string, keyLabel: string, keyCode: number, state: ProbeState, sys: SysBehavior,
          evidence: string): void {
    const line: string = `RCProbe|VERDICT|m=${mode}|key=${keyLabel}|code=${keyCode}|state=${state}` +
      `|sys=${sys}|ev=${evidence}`;
    hilog.info(RC_DOMAIN, RC_TAG, '%{public}s', line);
    this.broadcast(line);
  }

  /** 某形态下、某通道前缀的全部事件（按时间升序，最多 400 条） */
  eventsOf(mode: string, channelPrefix: string): ProbeEvent[] {
    const out: ProbeEvent[] = [];
    for (let i = 0; i < this.events.length; i++) {
      const e: ProbeEvent = this.events[i];
      if (e.mode !== mode) {
        continue;
      }
      if (channelPrefix.length > 0 && !e.channel.startsWith(channelPrefix)) {
        continue;
      }
      out.push(e);
    }
    return out;
  }

  /** 某形态 + 某通道前缀 + 某键 的采集条数 */
  count(mode: string, channelPrefix: string, keyCode: number): number {
    let n: number = 0;
    for (let i = 0; i < this.events.length; i++) {
      const e: ProbeEvent = this.events[i];
      if (e.mode === mode && e.keyCode === keyCode && (channelPrefix.length === 0 || e.channel.startsWith(channelPrefix))) {
        n += 1;
      }
    }
    return n;
  }

  /** 某形态下所有出现过的通道名（去重），用于确认「哪条链路真的来过」 */
  channels(mode: string): string[] {
    const out: string[] = [];
    for (let i = 0; i < this.events.length; i++) {
      const e: ProbeEvent = this.events[i];
      if (e.mode === mode && out.indexOf(e.channel) < 0) {
        out.push(e.channel);
      }
    }
    return out;
  }

  clear(mode: string): void {
    const kept: ProbeEvent[] = [];
    for (let i = 0; i < this.events.length; i++) {
      if (this.events[i].mode !== mode) {
        kept.push(this.events[i]);
      }
    }
    this.events = kept;
  }

  subscribe(id: string, sink: RcSink): void {
    this.sinks.set(id, sink);
  }

  unsubscribe(id: string): void {
    this.sinks.delete(id);
  }

  private broadcast(line: string): void {
    this.sinks.forEach((sink: RcSink) => {
      sink(line);
    });
  }
}

/** 全局单例，直接 import 使用 */
export const probe: ProbeRecorder = ProbeRecorder.get();
