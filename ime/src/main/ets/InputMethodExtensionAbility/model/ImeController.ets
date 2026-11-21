/**
 * ime / InputMethodExtensionAbility / model / ImeController.ets
 *
 * M3 的采集与上报全部走 probecore，和主 App 是同一套代码、同一个 tag。
 *
 * 关键文档事实：
 *   - 物理按键派发顺序：onKeyPreIme -> 输入法 -> onKeyEventDispatch/onKeyEvent；
 *     输入法这一环可以用 KeyboardDelegate 的 on('keyDown') 拿到，回调返回 true 即消费。
 *   - API 里没有 commitText；把「按键变成文字」的等价接口是
 *     inputMethodEngine.InputClient.insertText(text) / insertTextSync(text)。
 *   - 输入法扩展必须遵守「基础访问模式」：只做打字，不做任何网络交互。
 */
import { InputMethodExtensionContext, inputMethodEngine } from '@kit.IMEKit';
import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProbeEvent, enumNameOf, keyNameOf, probe } from 'probecore';

const M3: string = 'M3';

export class ImeController {
  private static readonly holder: ImeController = new ImeController();

  private ability: inputMethodEngine.InputMethodAbility | null = null;
  private panel: inputMethodEngine.Panel | null = null;
  private client: inputMethodEngine.InputClient | null = null;
  private delegate: inputMethodEngine.KeyboardDelegate | null = null;
  private ctx: InputMethodExtensionContext | null = null;
  private started: boolean = false;

  /** 是否消费物理键（true = KeyboardDelegate 回调返回 true，系统默认行为应被抑制） */
  consumeKey: boolean = true;
  /** 是否把物理键转成文字插进目标输入框（验证 insertText 链路） */
  toText: boolean = true;

  static get(): ImeController {
    return ImeController.holder;
  }

  async init(ctx: InputMethodExtensionContext): Promise<void> {
    if (this.started) {
      return;
    }
    try {
      this.ctx = ctx;
      this.ability = inputMethodEngine.getInputMethodAbility();
      this.registerAbilityEvents();
      this.registerKeyboardDelegate();
      // 面板不在 onCreate 阶段创建：此时系统侧还没完成输入法绑定，
      // createPanel 在模拟器上直接抛 code=1（error is out of definition）。
      // 改为 inputStart（目标输入框已连接）后再建面板，这是输入法的常规时机。
      this.started = true;
      probe.note(M3, 'ImeController.init ok: events + delegate ready (panel 延迟到 inputStart 创建)');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      // 预期失败点：不是输入法应用（12800004）或参数不合法（401）
      probe.note(M3, `ImeController.init FAILED code=${e.code} msg=${e.message}`);
    }
  }

  /** 首次 inputStart 时建面板；失败原因逐条打点，便于 RESULT 里写证据 */
  private async ensurePanel(): Promise<void> {
    if (this.panel !== null) {
      await this.panel.show();
      return;
    }
    const ctx: InputMethodExtensionContext | null = this.ctx;
    const ability: inputMethodEngine.InputMethodAbility | null = this.ability;
    if (ctx === null || ability === null) {
      probe.note(M3, 'ensurePanel skipped: ctx/ability null');
      return;
    }
    try {
      await this.createPanel(ctx, ability);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      // 预期失败点：基础访问模式 / 系统未开放面板能力时，createPanel 可能直接抛错
      probe.note(M3, `createPanel FAILED (with flag) code=${e.code} msg=${e.message}`);
      try {
        const panel: inputMethodEngine.Panel = await ability.createPanel(ctx,
          { type: inputMethodEngine.PanelType.SOFT_KEYBOARD });
        this.panel = panel;
        probe.note(M3, 'createPanel ok (without flag)');
        await panel.resize(display.getDefaultDisplaySync().width, 660);
        await panel.setUiContent('InputMethodExtensionAbility/pages/Index');
        await panel.show();
        probe.note(M3, 'panel shown (without flag)');
      } catch (err2) {
        const e2: BusinessError = err2 as BusinessError;
        probe.note(M3, `createPanel FAILED (without flag) code=${e2.code} msg=${e2.message}`);
      }
    }
  }

  private registerAbilityEvents(): void {
    const ability: inputMethodEngine.InputMethodAbility | null = this.ability;
    if (ability === null) {
      return;
    }
    ability.on('inputStart', (kb: inputMethodEngine.KeyboardController, client: inputMethodEngine.InputClient) => {
      this.client = client;
      probe.note(M3, 'inputStart: 目标输入框已连接，物理键从此可被输入法拿到');
      this.ensurePanel();
    });
    ability.on('inputStop', () => {
      this.client = null;
      probe.note(M3, 'inputStop: 目标输入框已断开');
    });
    ability.on('keyboardShow', () => {
      probe.note(M3, 'keyboardShow');
    });
    ability.on('keyboardHide', () => {
      probe.note(M3, 'keyboardHide');
    });
  }

  private registerKeyboardDelegate(): void {
    const delegate: inputMethodEngine.KeyboardDelegate = inputMethodEngine.getKeyboardDelegate();
    this.delegate = delegate;
    delegate.on('keyDown', (event: inputMethodEngine.KeyEvent) => {
      return this.onPhysicalKey('ime.delegate.keydown', 'Down', event.keyCode);
    });
    delegate.on('keyUp', (event: inputMethodEngine.KeyEvent) => {
      return this.onPhysicalKey('ime.delegate.keyup', 'Up', event.keyCode);
    });
    probe.note(M3, 'KeyboardDelegate registered: on(keyDown/keyUp)');
  }

  /** 输入法链路唯一采集点 */
  private onPhysicalKey(channel: string, type: string, keyCode: number): boolean {
    const ev: ProbeEvent = new ProbeEvent(M3, channel, keyNameOf(keyCode), keyCode, enumNameOf(keyCode),
      type, 'n/a', -1, 0, `consume=${this.consumeKey} toText=${this.toText}`);
    probe.record(ev);

    if (this.toText && this.client !== null && type === 'Down') {
      try {
        // 等价于需求里说的 commitText：InputClient 没有 commitText，只有 insertText/insertTextSync
        this.client.insertTextSync(`<${keyNameOf(keyCode)}>`);
        probe.note(M3, `insertTextSync ok: <${keyNameOf(keyCode)}>`);
      } catch (err) {
        const e: BusinessError = err as BusinessError;
        probe.note(M3, `insertTextSync FAILED code=${e.code} msg=${e.message}`);
      }
    }
    return this.consumeKey;
  }

  private async createPanel(ctx: InputMethodExtensionContext,
                            ability: inputMethodEngine.InputMethodAbility): Promise<void> {
    const d = display.getDefaultDisplaySync();
    const info: inputMethodEngine.PanelInfo = {
      type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
      flag: inputMethodEngine.PanelFlag.FLG_FIXED
    };
    probe.note(M3, `panel step1: about to createPanel type=SOFT_KEYBOARD flag=FLG_FIXED d=${d.width}x${d.height}`);
    const panel: inputMethodEngine.Panel = await ability.createPanel(ctx, info);
    this.panel = panel;
    probe.note(M3, 'panel step2: createPanel ok');
    await panel.resize(d.width, Math.round(d.height * 0.35));
    probe.note(M3, 'panel step3: resize ok');
    await panel.setUiContent('InputMethodExtensionAbility/pages/Index');
    probe.note(M3, 'panel step4: setUiContent ok');
    await panel.show();
    probe.note(M3, `panel created ${d.width}x${Math.round(d.height * 0.35)}`);
  }

  /** 软键盘上的自绘按键：唯一目的就是证明 insertText 能把字符送进目标输入框 */
  insertChar(text: string): void {
    const client: inputMethodEngine.InputClient | null = this.client;
    if (client === null) {
      probe.note(M3, 'insertChar skipped: 没有连接的输入框（先点 App 里的 TextInput）');
      return;
    }
    try {
      client.insertTextSync(text);
      probe.note(M3, `panel key insertTextSync ok: ${text}`);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      probe.note(M3, `panel key insertTextSync FAILED code=${e.code} msg=${e.message}`);
    }
  }

  deleteBack(): void {
    const client: inputMethodEngine.InputClient | null = this.client;
    if (client === null) {
      return;
    }
    try {
      client.deleteForwardSync(1);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      probe.note(M3, `deleteForwardSync FAILED code=${e.code} msg=${e.message}`);
    }
  }

  async release(): Promise<void> {
    try {
      const panel: inputMethodEngine.Panel | null = this.panel;
      const ability: inputMethodEngine.InputMethodAbility | null = this.ability;
      if (panel !== null) {
        await panel.hide();
        if (ability !== null) {
          await ability.destroyPanel(panel);
        }
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      probe.note(M3, `release panel FAILED code=${e.code} msg=${e.message}`);
    }
    this.panel = null;
    this.client = null;
    this.started = false;
    probe.note(M3, 'ImeController released');
  }

  isReady(): boolean {
    return this.started;
  }

  hasClient(): boolean {
    return this.client !== null;
  }
}

export const imeController: ImeController = ImeController.get();
