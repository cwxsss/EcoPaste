import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { SyncManager } from '../services/SyncManager';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('EcoPaste EntryAbility onCreate');
    this.handleAction(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('EcoPaste EntryAbility onNewWant');
    this.handleAction(want);
  }

  private async handleAction(want: Want): Promise<void> {
    if (!want || !want.parameters) return;
    let action = (want.parameters['action'] || '') as string;
    if (!action && want.parameters['params']) {
      try {
        const rawParams: Object = want.parameters['params'];
        if (typeof rawParams === 'string') {
          const parsed = JSON.parse(rawParams) as Record<string, string>;
          if (parsed && parsed['action']) {
            action = parsed['action'];
          }
        } else {
          const dict = rawParams as Record<string, string>;
          if (dict && dict['action']) {
            action = dict['action'];
          }
        }
      } catch (e) {
        // ignore
      }
    }

    if (!action) return;

    // 关键：若应用冷启动，确保在触发动作前先完成 SyncManager 与 WebDAV 初始化
    if (this.context) {
      await SyncManager.getInstance().init(this.context);
    }

    if (action === 'push_clipboard') {
      await SyncManager.getInstance().pushCurrentClipboardToCloud();
      this.autoReturnToBackgroundAfterDelay(500);
    } else if (action === 'pull_clipboard') {
      await SyncManager.getInstance().pullLatestFromCloud(true);
      this.autoReturnToBackgroundAfterDelay(500);
    }
  }

  /**
   * 桌面胶囊完成轻量动作后，自动退回后台回到桌面
   */
  private autoReturnToBackgroundAfterDelay(delayMs: number): void {
    setTimeout(async () => {
      try {
        if (this.context) {
          await this.context.moveAbilityToBackground();
        }
      } catch (e) {
        console.warn('moveAbilityToBackground failed:', JSON.stringify(e));
      }
    }, delayMs);
  }

  onDestroy(): void {
    console.info('EcoPaste EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    console.info('EcoPaste EntryAbility onWindowStageCreate');

    // 初始化剪贴板与 WebDAV 同步服务
    SyncManager.getInstance().init(this.context);

    windowStage.loadContent('pages/Index', (err, data) => {
      if (err.code) {
        console.error('Failed to load content. Cause:', JSON.stringify(err));
        return;
      }
      console.info('Succeeded in loading content.');
    });
  }

  onWindowStageDestroy(): void {
    console.info('EcoPaste EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    console.info('EcoPaste EntryAbility onForeground');
    // 应用回到前台时：
    // 1. 优先检查并秒传在后台/锁屏期间复制的新内容
    SyncManager.getInstance().checkAndUploadLocalClipboard();
    // 2. 同时主动拉取一次最新云端剪贴板
    SyncManager.getInstance().pullLatestFromCloud(false);
    // 3. 强制重绘/恢复常驻通知栏保活卡片（即便锁屏期间被系统清理，切回前台也会立刻恢复常驻）
    SyncManager.getInstance().updatePermanentNotification(undefined, true);
    // 4. 确保长时后台同步状态处于激活状态
    SyncManager.getInstance().ensureBackgroundRunning();
  }

  onBackground(): void {
    console.info('EcoPaste EntryAbility onBackground');
    // 应用切入后台时，强制刷新一次通知栏常驻卡片确保常驻状态
    SyncManager.getInstance().updatePermanentNotification(undefined, true);
  }
}

