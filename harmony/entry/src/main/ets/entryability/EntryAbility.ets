import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { SyncManager } from '../services/SyncManager';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('EcoPaste EntryAbility onCreate');
    this.handleShareData(want);
    this.handleAction(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('EcoPaste EntryAbility onNewWant');
    this.handleShareData(want);
    this.handleAction(want);
  }

  private handleAction(want: Want): void {
    if (!want || !want.parameters) return;
    const action = want.parameters['action'] as string;
    if (action === 'push_clipboard') {
      SyncManager.getInstance().pushCurrentClipboardToCloud();
    } else if (action === 'pull_clipboard') {
      SyncManager.getInstance().pullLatestFromCloud(true);
    }
  }

  private handleShareData(want: Want): void {
    if (want && want.action === 'ohos.want.action.sendData') {
      let sharedText = '';
      if (want.parameters) {
        sharedText = (want.parameters['ohos.extra.param.key.text'] ||
          want.parameters['ohos.extra.param.key.TEXT'] ||
          want.parameters['text'] || '') as string;
      }
      if (sharedText && sharedText.trim()) {
        SyncManager.getInstance().uploadSharedText(sharedText);
      }
    }
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
    SyncManager.getInstance().updatePermanentNotification();
  }

  onBackground(): void {
    console.info('EcoPaste EntryAbility onBackground');
    SyncManager.getInstance().updatePermanentNotification();
  }
}

