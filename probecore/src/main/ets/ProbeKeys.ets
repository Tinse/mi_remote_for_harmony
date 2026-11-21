/**
 * probecore / ProbeKeys.ets
 *
 * 13 个待测键 + API 26 新增键的登记表。
 * 约束：键值一律引用 KeyCode 枚举成员，不出现裸整数。
 * API 26 新增键（KEYCODE_XKEY / KEYCODE_FINGERPRINT_SLIDE_UP / _DOWN）用
 * canIUse + sdkApiVersion 兜底，老设备上不登记、不打日志、不参与判定。
 *
 * 注：API 26 SDK 的 KeyCode 公开枚举里 3232–3243 只落地了 3232/3233/3234 三个，
 * 其余（3235–3243）在该版本 SDK 中并不存在，因此这里也不登记。
 */
import { KeyCode } from '@kit.InputKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ProbeKeyDesc } from './ProbeTypes';

/** 遥控器实测可用的 12 键 + 媒体键（M2c 通道用），共 13 行 */
export const CORE_KEYS: ProbeKeyDesc[] = [
  new ProbeKeyDesc('音量+', KeyCode.KEYCODE_VOLUME_UP, 'KEYCODE_VOLUME_UP', 'volume', false),
  new ProbeKeyDesc('音量-', KeyCode.KEYCODE_VOLUME_DOWN, 'KEYCODE_VOLUME_DOWN', 'volume', false),
  new ProbeKeyDesc('电源', KeyCode.KEYCODE_POWER, 'KEYCODE_POWER', 'system', false),
  new ProbeKeyDesc('返回', KeyCode.KEYCODE_BACK, 'KEYCODE_BACK', 'system', false),
  new ProbeKeyDesc('主页', KeyCode.KEYCODE_HOME, 'KEYCODE_HOME', 'system', false),
  new ProbeKeyDesc('方向上', KeyCode.KEYCODE_DPAD_UP, 'KEYCODE_DPAD_UP', 'dpad', false),
  new ProbeKeyDesc('方向下', KeyCode.KEYCODE_DPAD_DOWN, 'KEYCODE_DPAD_DOWN', 'dpad', false),
  new ProbeKeyDesc('方向左', KeyCode.KEYCODE_DPAD_LEFT, 'KEYCODE_DPAD_LEFT', 'dpad', false),
  new ProbeKeyDesc('方向右', KeyCode.KEYCODE_DPAD_RIGHT, 'KEYCODE_DPAD_RIGHT', 'dpad', false),
  new ProbeKeyDesc('OK', KeyCode.KEYCODE_ENTER, 'KEYCODE_ENTER', 'ok', false),
  new ProbeKeyDesc('菜单', KeyCode.KEYCODE_MENU, 'KEYCODE_MENU', 'menu', false),
  new ProbeKeyDesc('语音', KeyCode.KEYCODE_F5, 'KEYCODE_F5', 'voice', false),
  new ProbeKeyDesc('媒体播放/暂停', KeyCode.KEYCODE_MEDIA_PLAY_PAUSE, 'KEYCODE_MEDIA_PLAY_PAUSE', 'media', false)
];

/** 媒体上一首 / 下一首：M2c 里和播放/暂停一起订阅，单独成行会超出 13 行，仅作附带记录 */
export const EXTRA_MEDIA_KEYS: ProbeKeyDesc[] = [
  new ProbeKeyDesc('媒体上一首', KeyCode.KEYCODE_MEDIA_PREVIOUS, 'KEYCODE_MEDIA_PREVIOUS', 'media', false),
  new ProbeKeyDesc('媒体下一首', KeyCode.KEYCODE_MEDIA_NEXT, 'KEYCODE_MEDIA_NEXT', 'media', false)
];

/**
 * API 26 新增键（需兜底）。
 * 判定依据：sdkApiVersion >= 26 且设备上报了 MultimodalInput.Input.Core 能力。
 */
export function api26Keys(): ProbeKeyDesc[] {
  const supported: boolean = canIUse('SystemCapability.MultimodalInput.Input.Core')
    && deviceInfo.sdkApiVersion >= 26;
  if (!supported) {
    return [];
  }
  return [
    new ProbeKeyDesc('自定义热键 XKEY', KeyCode.KEYCODE_XKEY, 'KEYCODE_XKEY', 'api26', true),
    new ProbeKeyDesc('智控键上滑', KeyCode.KEYCODE_FINGERPRINT_SLIDE_UP, 'KEYCODE_FINGERPRINT_SLIDE_UP', 'api26', true),
    new ProbeKeyDesc('智控键下滑', KeyCode.KEYCODE_FINGERPRINT_SLIDE_DOWN, 'KEYCODE_FINGERPRINT_SLIDE_DOWN', 'api26', true)
  ];
}

/** 按 keyCode 找登记项，找不到返回 null（说明是表外键，仍要打日志） */
export function findKey(code: number): ProbeKeyDesc | null {
  for (let i = 0; i < CORE_KEYS.length; i++) {
    if (CORE_KEYS[i].code === code) {
      return CORE_KEYS[i];
    }
  }
  for (let i = 0; i < EXTRA_MEDIA_KEYS.length; i++) {
    if (EXTRA_MEDIA_KEYS[i].code === code) {
      return EXTRA_MEDIA_KEYS[i];
    }
  }
  const extra: ProbeKeyDesc[] = api26Keys();
  for (let i = 0; i < extra.length; i++) {
    if (extra[i].code === code) {
      return extra[i];
    }
  }
  return null;
}

/** 键名：表内用中文名，表外用 KEYCODE_<n> */
export function keyNameOf(code: number): string {
  const desc: ProbeKeyDesc | null = findKey(code);
  return desc === null ? `KEYCODE_${code}` : desc.label;
}

/** 枚举名：表内用枚举成员名，表外给 unknown */
export function enumNameOf(code: number): string {
  const desc: ProbeKeyDesc | null = findKey(code);
  return desc === null ? 'UNKNOWN' : desc.enumName;
}
