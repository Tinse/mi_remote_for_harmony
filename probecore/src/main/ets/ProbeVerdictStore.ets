/**
 * probecore / ProbeVerdictStore.ets
 *
 * 「键 × 模式」判定单元。判定规则严格按 README 的三态定义：
 *
 *   captured > 0 且 系统行为发生   -> 收到但未消费
 *   captured > 0 且 系统行为未发生 -> 收到并消费
 *   captured = 0 且 系统行为发生   -> 未收到（在更早环节被系统消费）
 *   captured = 0 且 系统行为未发生 -> 证据不足（键没按到 / 遥控器没连上，不能当结论）
 *
 * 所以「系统行为是否发生」是必填项，缺了它就只能是 PENDING。
 */
import { ProbeKeyDesc, ProbeState, SysBehavior } from './ProbeTypes';

export class VerdictCell {
  readonly mode: string;
  readonly key: ProbeKeyDesc;
  sys: SysBehavior = SysBehavior.UNSET;
  evidence: string = '';

  constructor(mode: string, key: ProbeKeyDesc) {
    this.mode = mode;
    this.key = key;
  }
}

export class ProbeVerdictStore {
  private static readonly holder: ProbeVerdictStore = new ProbeVerdictStore();
  private cells: Map<string, VerdictCell> = new Map<string, VerdictCell>();

  static get(): ProbeVerdictStore {
    return ProbeVerdictStore.holder;
  }

  private id(mode: string, code: number): string {
    return `${mode}:${code}`;
  }

  cell(mode: string, key: ProbeKeyDesc): VerdictCell {
    const id: string = this.id(mode, key.code);
    let c: VerdictCell | undefined = this.cells.get(id);
    if (c === undefined) {
      c = new VerdictCell(mode, key);
      this.cells.set(id, c);
    }
    return c;
  }

  setSys(mode: string, key: ProbeKeyDesc, sys: SysBehavior, evidence: string): VerdictCell {
    const c: VerdictCell = this.cell(mode, key);
    c.sys = sys;
    c.evidence = evidence;
    return c;
  }

  state(mode: string, key: ProbeKeyDesc, captured: number): ProbeState {
    const c: VerdictCell = this.cell(mode, key);
    const has: boolean = captured > 0;
    if (c.sys === SysBehavior.UNSET) {
      return ProbeState.PENDING;
    }
    if (has && c.sys === SysBehavior.HAPPENED) {
      return ProbeState.RECEIVED_NOT_CONSUMED;
    }
    if (has && c.sys === SysBehavior.ABSENT) {
      return ProbeState.RECEIVED_CONSUMED;
    }
    if (!has && c.sys === SysBehavior.HAPPENED) {
      return ProbeState.NOT_RECEIVED;
    }
    return ProbeState.INCONCLUSIVE;
  }

  /** 导出某形态所有单元格（写日志 / 填 RESULT.md 用） */
  all(mode: string): VerdictCell[] {
    const out: VerdictCell[] = [];
    this.cells.forEach((c: VerdictCell) => {
      if (c.mode === mode) {
        out.push(c);
      }
    });
    return out;
  }
}

export const verdicts: ProbeVerdictStore = ProbeVerdictStore.get();

/** 判定态的中文文案，UI 和文档共用一套 */
export function stateText(s: ProbeState): string {
  if (s === ProbeState.NOT_RECEIVED) {
    return '未收到';
  }
  if (s === ProbeState.RECEIVED_NOT_CONSUMED) {
    return '收到但未消费';
  }
  if (s === ProbeState.RECEIVED_CONSUMED) {
    return '收到并消费';
  }
  if (s === ProbeState.INCONCLUSIVE) {
    return '证据不足';
  }
  return '待测';
}

/** 判定态对应的展示颜色 */
export function stateColor(s: ProbeState): string {
  if (s === ProbeState.NOT_RECEIVED) {
    return '#8A8F98';
  }
  if (s === ProbeState.RECEIVED_NOT_CONSUMED) {
    return '#E8A33D';
  }
  if (s === ProbeState.RECEIVED_CONSUMED) {
    return '#39B36A';
  }
  if (s === ProbeState.INCONCLUSIVE) {
    return '#C4553D';
  }
  return '#4A5568';
}
