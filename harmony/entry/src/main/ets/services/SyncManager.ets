import pasteboard from '@ohos.pasteboard';
import common from '@ohos.app.ability.common';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import wantAgent from '@ohos.app.ability.wantAgent';
import notificationManager from '@ohos.notificationManager';
import { WebDavService, LivePayload } from './WebDavService';
import { PreferenceManager, WebDavConfig } from './PreferenceManager';
import { cleanToPlainText } from '../utils/TextFormatUtils';

export interface SyncStatus {
  online: boolean;
  syncing: boolean;
  currentText: string;
  sourceDevice: string;
  lastSyncTime: number;
  message: string;
}

export type StatusListener = (status: SyncStatus) => void;

export class SyncManager {
  private static instance: SyncManager | null = null;
  private webDavService: WebDavService | null = null;
  private context: common.UIAbilityContext | null = null;
  private isListening: boolean = false;
  private isPolling: boolean = false;
  private timerId: number = -1;
  private isBackgroundRunning: boolean = false;

  private lastLocalText: string = '';
  private lastSeenRemoteTimestamp: number = 0;
  private statusListeners: StatusListener[] = [];

  private status: SyncStatus = {
    online: false,
    syncing: false,
    currentText: '',
    sourceDevice: '',
    lastSyncTime: 0,
    message: '准备就绪'
  };

  public static getInstance(): SyncManager {
    if (!SyncManager.instance) {
      SyncManager.instance = new SyncManager();
    }
    return SyncManager.instance;
  }

  public addListener(listener: StatusListener): void {
    this.statusListeners.push(listener);
    listener(this.status);
  }

  public removeListener(listener: StatusListener): void {
    const idx = this.statusListeners.indexOf(listener);
    if (idx >= 0) {
      this.statusListeners.splice(idx, 1);
    }
  }

  private notifyStatus(update: Partial<SyncStatus>): void {
    if (update.online !== undefined) {
      this.status.online = update.online;
    }
    if (update.syncing !== undefined) {
      this.status.syncing = update.syncing;
    }
    if (update.currentText !== undefined) {
      this.status.currentText = update.currentText;
    }
    if (update.sourceDevice !== undefined) {
      this.status.sourceDevice = update.sourceDevice;
    }
    if (update.lastSyncTime !== undefined) {
      this.status.lastSyncTime = update.lastSyncTime;
    }
    if (update.message !== undefined) {
      this.status.message = update.message;
    }

    for (let i = 0; i < this.statusListeners.length; i++) {
      this.statusListeners[i](this.status);
    }
    this.updatePermanentNotification();
  }

  public async init(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    const prefMgr = PreferenceManager.getInstance();
    await prefMgr.init(context);
    const config = await prefMgr.loadConfig();

    this.webDavService = new WebDavService(
      config.endpoint,
      config.username,
      config.password,
      config.remoteDir
    );

    // 请求剪贴板与网络权限
    await this.requestPermissions();

    // 启动剪贴板监听与拉取轮询
    this.startClipboardWatcher();
    this.startPolling(config.autoSync);

    // 若配置开启后台任务，启动后台长时运行
    if (config.backgroundSync) {
      await this.startBackgroundRunning();
    }
    await this.updatePermanentNotification();
  }

  public updateConfig(config: WebDavConfig): void {
    if (this.webDavService) {
      this.webDavService.updateConfig(
        config.endpoint,
        config.username,
        config.password,
        config.remoteDir
      );
    }

    if (config.autoSync && !this.isPolling) {
      this.startPolling(true);
    } else if (!config.autoSync && this.isPolling) {
      this.stopPolling();
    }

    if (config.backgroundSync && !this.isBackgroundRunning) {
      this.startBackgroundRunning();
    } else if (!config.backgroundSync && this.isBackgroundRunning) {
      this.stopBackgroundRunning();
    }

    this.updatePermanentNotification();
    this.checkHealth();
  }

  private readonly NOTIFICATION_ID: number = 10001;
  private isNotificationPublished: boolean = false;
  private lastPublishedText: string = '';
  private lastPublishTime: number = 0;
  private isSlotCreated: boolean = false;

  /**
   * 发布或更新常驻通知栏保活卡片（带一键推送与拉取操作按钮）
   */
  public async updatePermanentNotification(customText?: string): Promise<void> {
    const prefMgr = PreferenceManager.getInstance();
    const config = await prefMgr.loadConfig();
    if (!config.notificationSync || !this.context) {
      if (this.isNotificationPublished) {
        try {
          await notificationManager.cancel(this.NOTIFICATION_ID);
          this.isNotificationPublished = false;
          this.lastPublishedText = '';
        } catch (e) {
          // ignore
        }
      }
      return;
    }

    let textToShow = customText;
    if (!textToShow) {
      if (this.status.currentText) {
        const preview = this.status.currentText.length > 25 ? this.status.currentText.slice(0, 25) + '...' : this.status.currentText;
        if (this.status.sourceDevice.includes('电脑')) {
          textToShow = '电脑已同步: ' + preview + ' (长按即可粘贴)';
        } else {
          textToShow = '手机剪贴板: ' + preview;
        }
      } else {
        textToShow = '已连接 WebDAV，前台复制随时同步';
      }
    }

    const now = new Date().getTime();
    // 避免短时间内重复发送相同内容触发系统限流 (Error 1600009: The notification sending frequency reaches the upper limit)
    if (!customText && this.isNotificationPublished && textToShow === this.lastPublishedText) {
      return;
    }
    if (!customText && (now - this.lastPublishTime < 2000)) {
      return;
    }

    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (!enabled) {
        await notificationManager.requestEnableNotification(this.context);
      }
    } catch (e) {
      // ignore
    }

    try {
      // 注册服务通知渠道 Slot，确保常驻通知渠道级别正确
      if (!this.isSlotCreated) {
        try {
          await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
          this.isSlotCreated = true;
        } catch (slotErr) {
          // ignore
        }
      }

      const pushWantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: 'com.ecopaste.harmony',
            abilityName: 'EntryAbility',
            parameters: { action: 'push_clipboard' }
          }
        ],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 101,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const pushAgent = await wantAgent.getWantAgent(pushWantAgentInfo);

      const pullWantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: 'com.ecopaste.harmony',
            abilityName: 'EntryAbility',
            parameters: { action: 'pull_clipboard' }
          }
        ],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 102,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const pullAgent = await wantAgent.getWantAgent(pullWantAgentInfo);

      const openWantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: 'com.ecopaste.harmony',
            abilityName: 'EntryAbility'
          }
        ],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 100,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const openAgent = await wantAgent.getWantAgent(openWantAgentInfo);

      const notificationRequest: notificationManager.NotificationRequest = {
        id: this.NOTIFICATION_ID,
        isOngoing: true,
        isUnremovable: true,
        tapDismissed: false, // 关键：点击通知主体或按钮时不清除通知
        isAlertOnce: true, // 关键：更新时不重复响铃震动打扰
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        wantAgent: openAgent,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: 'EcoPaste 剪贴板协同运行中',
            text: textToShow,
            additionalText: '常驻保活'
          }
        },
        actionButtons: [
          {
            title: '📋 推送复制',
            wantAgent: pushAgent
          },
          {
            title: '⬇️ 拉取粘贴',
            wantAgent: pullAgent
          }
        ]
      };

      await notificationManager.publish(notificationRequest);
      this.isNotificationPublished = true;
      this.lastPublishedText = textToShow;
      this.lastPublishTime = now;
    } catch (err) {
      console.warn('updatePermanentNotification error:', JSON.stringify(err));
    }
  }

  public async checkHealth(): Promise<void> {
    if (!this.webDavService) return;
    const res = await this.webDavService.testConnection();
    this.notifyStatus({
      online: res.success,
      message: res.message
    });
  }

  /**
   * 申请 HarmonyOS 运行时权限
   */
  public async requestPermissions(): Promise<boolean> {
    if (!this.context) return false;
    const atManager = abilityAccessCtrl.createAtManager();
    const permissions: Array<Permissions> = [
      'ohos.permission.INTERNET',
      'ohos.permission.READ_PASTEBOARD'
    ];

    try {
      const grantStatus = await atManager.requestPermissionsFromUser(this.context, permissions);
      return grantStatus.authResults.every((res: number) => res === 0);
    } catch (err) {
      console.warn('requestPermissions err:', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 开启系统剪贴板变动监听
   */
  private startClipboardWatcher(): void {
    if (this.isListening) return;
    try {
      const board = pasteboard.getSystemPasteboard();
      board.on('update', () => {
        this.handleLocalClipboardChange();
      });
      this.isListening = true;
    } catch (err) {
      console.error('startClipboardWatcher error:', JSON.stringify(err));
    }
  }

  /**
   * 主动触发本地剪贴板检查与上传（切回前台时无感瞬间执行）
   */
  public async checkAndUploadLocalClipboard(): Promise<void> {
    await this.handleLocalClipboardChange();
  }

  /**
   * 接收来自系统分享菜单（Share Kit）的文本，并直接推送到 WebDAV
   */
  public async uploadSharedText(rawText: string): Promise<void> {
    const text = cleanToPlainText(rawText);
    if (!text) return;
    this.lastLocalText = text;
    this.notifyStatus({ syncing: true, message: '正在推送分享文本到电脑...' });

    if (this.webDavService) {
      const res = await this.webDavService.uploadLiveText(text);
      if (res.success) {
        this.notifyStatus({
          online: true,
          syncing: false,
          currentText: text,
          sourceDevice: '系统分享',
          lastSyncTime: new Date().getTime(),
          message: '已通过分享推送到电脑！直接 Ctrl+V 即可粘贴'
        });
      } else {
        this.notifyStatus({ syncing: false, message: res.message || '上传失败' });
      }
    }
  }

  /**
   * 当手机复制新文本时，自动清洗格式并上传 WebDAV
   */
  private async handleLocalClipboardChange(): Promise<void> {
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = await board.getData();
      const rawText = data.getPrimaryText();

      const text = cleanToPlainText(rawText);
      if (!text || text === this.lastLocalText) {
        return;
      }

      this.lastLocalText = text;
      this.notifyStatus({ syncing: true, message: '正在同步手机复制到电脑...' });

      if (this.webDavService) {
        const res = await this.webDavService.uploadLiveText(text);
        if (res.success) {
          this.notifyStatus({
            online: true,
            syncing: false,
            currentText: text,
            sourceDevice: '本机复制',
            lastSyncTime: new Date().getTime(),
            message: '已同步至云端，电脑端可直接粘贴'
          });
        } else {
          this.notifyStatus({ syncing: false, message: res.message || '上传云端失败' });
        }
      }
    } catch (err) {
      this.notifyStatus({ syncing: false });
    }
  }

  /**
   * 从 WebDAV 拉取电脑端复制的新文本，自动过滤格式转为纯文本并写入手机剪贴板
   */
  public async pullLatestFromCloud(manual: boolean = false): Promise<void> {
    if (!this.webDavService) return;

    if (manual) {
      this.notifyStatus({ syncing: true, message: '正在获取电脑端剪贴板...' });
    }

    try {
      const payload: LivePayload | null = await this.webDavService.fetchLiveText();
      if (!payload || !payload.text || !payload.text.trim()) {
        if (manual) {
          const code = this.webDavService.getLastFetchCode();
          if (code === 401) {
            this.notifyStatus({ syncing: false, online: false, message: '认证失败 (HTTP 401)，请检查账号密码' });
          } else if (code === 403) {
            this.notifyStatus({ syncing: false, online: false, message: '权限不足 (HTTP 403)，请检查目录读写权限' });
          } else if (code === 404) {
            this.notifyStatus({ syncing: false, online: true, message: '云端暂无同步文本（在电脑复制一次即可）' });
          } else {
            this.notifyStatus({ syncing: false, message: '云端暂无可粘贴文本' });
          }
        }
        return;
      }

      // 自动清洗并规范化为纯文本，剥离 HTML、RTF、不换行空格及不可见字符
      const cleanedText = cleanToPlainText(payload.text);
      if (!cleanedText) {
        return;
      }

      // 如果来源是电脑，且时间戳较新，或者手动拉取且内容不同
      const isFromDesktop = payload.device === 'desktop';
      const isNewer = payload.timestamp > this.lastSeenRemoteTimestamp;

      if ((isFromDesktop && isNewer) || (manual && cleanedText !== this.lastLocalText)) {
        this.lastSeenRemoteTimestamp = payload.timestamp;
        this.lastLocalText = cleanedText;

        // 写入手机剪贴板（写入纯文本 MIMETYPE_TEXT_PLAIN）
        const board = pasteboard.getSystemPasteboard();
        const pData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, cleanedText);
        await board.setData(pData);

        this.notifyStatus({
          online: true,
          syncing: false,
          currentText: cleanedText,
          sourceDevice: isFromDesktop ? '电脑复制 (已转纯文本)' : '手机复制',
          lastSyncTime: payload.timestamp,
          message: '已自动转为纯文本并同步到剪贴板，长按即可粘贴'
        });
      } else {
        if (manual) {
          this.notifyStatus({ syncing: false, message: '当前内容已是最新' });
        }
      }
    } catch (err) {
      if (manual) {
        this.notifyStatus({ syncing: false, message: '拉取失败，请检查网络与配置' });
      }
    }
  }

  /**
   * 手动推送当前手机剪贴板文本到 WebDAV
   */
  public async pushCurrentClipboardToCloud(): Promise<void> {
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = await board.getData();
      const rawText = data.getPrimaryText();

      const text = cleanToPlainText(rawText);
      if (!text) {
        this.notifyStatus({ message: '手机剪贴板为空' });
        return;
      }

      this.lastLocalText = text;
      this.notifyStatus({ syncing: true, message: '正在上传手机剪贴板...' });

      if (this.webDavService) {
        const res = await this.webDavService.uploadLiveText(text);
        if (res.success) {
          this.notifyStatus({
            online: true,
            syncing: false,
            currentText: text,
            sourceDevice: '本机推送',
            lastSyncTime: new Date().getTime(),
            message: '推送成功！电脑端直接 Ctrl+V 即可粘贴'
          });
        } else {
          this.notifyStatus({ syncing: false, message: res.message || '上传失败，请检查设置' });
        }
      }
    } catch (err) {
      this.notifyStatus({ syncing: false, message: '读取手机剪贴板失败' });
    }
  }

  /**
   * 启动自动轮询
   */
  /**
   * 尝试后台探测前台应用复制（若系统因安全策略拦截则静默忽略）
   */
  private async tryBackgroundClipboardProbe(): Promise<void> {
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = await board.getData();
      const raw = data.getPrimaryText();
      const text = cleanToPlainText(raw);
      if (text && text !== this.lastLocalText) {
        this.handleLocalClipboardChange();
      }
    } catch (e) {
      // 静默捕获，防止系统后台拦截报错干扰主流程
    }
  }

  private startPolling(enabled: boolean): void {
    if (this.isPolling) {
      this.stopPolling();
    }
    if (!enabled) return;

    this.isPolling = true;
    this.pullLatestFromCloud(false);

    // 默认每 2.5 秒轻量同步一次，兼顾实时性与省电
    this.timerId = setInterval(() => {
      this.pullLatestFromCloud(false);
      // 前台软件复制探测（在系统允许后台读取的特定场景下自动触发）
      this.tryBackgroundClipboardProbe();
    }, 2500);
  }

  private stopPolling(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    this.isPolling = false;
  }

  /**
   * 申请开启后台长时运行任务（Continuous Task），实现无感后台同步
   */
  public async startBackgroundRunning(): Promise<void> {
    if (this.isBackgroundRunning || !this.context) return;
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: 'com.ecopaste.harmony',
            abilityName: 'EntryAbility'
          }
        ],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };

      const agent = await wantAgent.getWantAgent(wantAgentInfo);
      await backgroundTaskManager.startBackgroundRunning(
        this.context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        agent
      );
      this.isBackgroundRunning = true;
      console.info('startBackgroundRunning success');
    } catch (err) {
      console.warn('startBackgroundRunning error:', JSON.stringify(err));
    }
  }

  public async stopBackgroundRunning(): Promise<void> {
    if (!this.isBackgroundRunning || !this.context) return;
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);
      this.isBackgroundRunning = false;
    } catch (err) {
      console.warn('stopBackgroundRunning error:', JSON.stringify(err));
    }
  }
}
