/**
 * entry / entryability / EntryAbility.ets
 * 只做三件事：加载页面、在前后台切换时打 NOTE 日志（M2 的证据基线）、不做任何按键消费。
 */
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { probe } from 'probecore';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    probe.note('M1', 'EntryAbility.onCreate');
  }

  onForeground(): void {
    // 回到前台时刻：用于给后台日志切一刀基线
    probe.note('M2', 'lifecycle.onForeground: 现在在前台');
  }

  onBackground(): void {
    // 切后台时刻：之后再按遥控器，日志里若没有 EVT 行即证明后台链路未送达
    probe.note('M2', 'lifecycle.onBackground: 已切到后台，开始计后台按键');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        probe.note('M1', `loadContent failed code=${err.code} msg=${err.message}`);
        return;
      }
      probe.note('M1', 'loadContent ok');
    });
  }
}
