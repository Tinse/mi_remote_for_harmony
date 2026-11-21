/**
 * probecore / ProbeTypes.ets
 *
 * 三种形态（M1 前台 / M2 后台 / M3 输入法）共用的数据类型定义。
 * 任何形态都不允许自己造一套字段，避免实现差异污染结论。
 */

/** 测试形态 */
export enum ProbeMode {
  M1 = 'M1',
  M2 = 'M2',
  M3 = 'M3'
}

/**
 * 判定三态（README「判定标准」一节）。
 * 只允许这三种结论；INCONCLUSIVE 是给测试者的辅助态（说明证据不足，不能入矩阵）。
 */
export enum ProbeState {
  PENDING = 'PENDING',
  NOT_RECEIVED = 'NOT_RECEIVED',
  RECEIVED_NOT_CONSUMED = 'RECEIVED_NOT_CONSUMED',
  RECEIVED_CONSUMED = 'RECEIVED_CONSUMED',
  INCONCLUSIVE = 'INCONCLUSIVE'
}

/** 该按键的「系统默认行为」是否肉眼可见地发生了（音量条/页面返回/锁屏…） */
export enum SysBehavior {
  UNSET = 'UNSET',
  HAPPENED = 'HAPPENED',
  ABSENT = 'ABSENT'
}

/** 一个待测键 */
export class ProbeKeyDesc {
  /** 展示名，例如「音量+」 */
  readonly label: string;
  /** KeyCode 枚举值，禁止硬编码整数 */
  readonly code: number;
  /** 枚举成员名，写日志用，便于和 KeyCode 文档对照 */
  readonly enumName: string;
  /** 分组：volume / system / dpad / ok / menu / voice / media / api26 */
  readonly group: string;
  /** 是否 API 26 新增键（需 canIUse 兜底） */
  readonly api26: boolean;

  constructor(label: string, code: number, enumName: string, group: string, api26: boolean) {
    this.label = label;
    this.code = code;
    this.enumName = enumName;
    this.group = group;
    this.api26 = api26;
  }
}

/** 一条采集记录（所有形态都产出这个结构） */
export class ProbeEvent {
  mode: string = '';
  /** 采集通道，例如 arkui.preime / arkui.keyevent / inputconsumer / avsession.play / ime.delegate */
  channel: string = '';
  keyLabel: string = '';
  keyCode: number = 0;
  enumName: string = '';
  /** Down / Up / Cancel */
  type: string = '';
  /** KeySource 名称或 'n/a' */
  source: string = '';
  deviceId: number = -1;
  /** 事件时间戳（纳秒，来自系统事件） */
  timestampNs: number = 0;
  /** 采集到该事件的本机时刻（毫秒） */
  wallClockMs: number = 0;
  extra: string = '';

  constructor(mode: string, channel: string, keyLabel: string, keyCode: number, enumName: string,
              type: string, source: string, deviceId: number, timestampNs: number, extra: string) {
    this.mode = mode;
    this.channel = channel;
    this.keyLabel = keyLabel;
    this.keyCode = keyCode;
    this.enumName = enumName;
    this.type = type;
    this.source = source;
    this.deviceId = deviceId;
    this.timestampNs = timestampNs;
    this.wallClockMs = Date.now();
    this.extra = extra;
  }
}
