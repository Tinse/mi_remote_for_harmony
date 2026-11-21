/**
 * entry / common / KeyRowVM.ets
 * KeyMatrix 的行视图模型：把「采集次数 + 系统行为标记」算成一行展示数据。
 */
import { SysBehavior } from 'probecore';

export class KeyRowVM {
  readonly label: string;
  readonly code: number;
  readonly enumName: string;
  readonly count: number;
  readonly sys: SysBehavior;
  readonly verdict: string;
  readonly verdictColor: string;
  readonly api26: boolean;

  constructor(label: string, code: number, enumName: string, count: number, sys: SysBehavior,
              verdict: string, verdictColor: string, api26: boolean) {
    this.label = label;
    this.code = code;
    this.enumName = enumName;
    this.count = count;
    this.sys = sys;
    this.verdict = verdict;
    this.verdictColor = verdictColor;
    this.api26 = api26;
  }

  /** ForEach 的 key：任一字段变化都要重建这一行（count 必须参与，否则计数不会刷新） */
  id(): string {
    return `${this.count}|${this.sys}|${this.verdict}`;
  }
}
