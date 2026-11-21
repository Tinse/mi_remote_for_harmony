/**
 * ime / InputMethodExtensionAbility / InputMethodService.ets
 * 生命周期只做转发，真正的逻辑在 ImeController（与主 App 共用 probecore）。
 */
import { InputMethodExtensionAbility } from '@kit.IMEKit';
import { Want } from '@kit.AbilityKit';
import { probe } from 'probecore';
import { imeController } from './model/ImeController';

export default class InputMethodService extends InputMethodExtensionAbility {
  onCreate(want: Want): void {
    probe.note('M3', `InputMethodService.onCreate want.bundle=${want.bundleName ?? 'n/a'}`);
    imeController.init(this.context);
  }

  onDestroy(): void {
    probe.note('M3', 'InputMethodService.onDestroy');
    imeController.release();
  }
}
