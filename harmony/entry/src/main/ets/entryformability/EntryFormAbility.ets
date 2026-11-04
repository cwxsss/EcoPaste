import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import formBindingData from '@ohos.app.form.formBindingData';
import formProvider from '@ohos.app.form.formProvider';
import formInfo from '@ohos.app.form.formInfo';
import Want from '@ohos.app.ability.Want';
import pasteboard from '@ohos.pasteboard';
import { WebDavService, LivePayload } from '../services/WebDavService';
import { PreferenceManager } from '../services/PreferenceManager';
import { cleanToPlainText } from '../utils/TextFormatUtils';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let dimension: number = formInfo.FormDimension.Dimension_1_2;
    if (want.parameters) {
      dimension = (want.parameters[formInfo.FormParam.DIMENSION_KEY] as number) || dimension;
    }

    const formData: Record<string, Object> = {
      'dimension': dimension,
      'pushStatus': '推送',
      'pushSub': '推送到电脑',
      'pushColor': '#0A59F7',
      'pullStatus': '拉取',
      'pullSub': '从电脑拉取',
      'pullColor': '#1F2329'
    };
    return formBindingData.createFormBindingData(formData);
  }

  async onFormEvent(formId: string, message: string): Promise<void> {
    try {
      const params = JSON.parse(message) as Record<string, string>;
      const action = params.action;

      const prefMgr = PreferenceManager.getInstance();
      await prefMgr.init(this.context);
      const config = await prefMgr.loadConfig();
      const webDav = new WebDavService(
        config.endpoint,
        config.username,
        config.password,
        config.remoteDir
      );

      if (action === 'push_clipboard') {
        // 胶囊卡片即时轻量交互反馈（正在推送）
        const loadingData: Record<string, Object> = {
          'pushStatus': '推送中...',
          'pushSub': '正在上传',
          'pushColor': '#0A59F7'
        };
        await formProvider.updateForm(formId, formBindingData.createFormBindingData(loadingData));

        try {
          const board = pasteboard.getSystemPasteboard();
          const pData = await board.getData();
          const rawText = pData.getPrimaryText();
          const text = cleanToPlainText(rawText);

          if (!text) {
            const emptyData: Record<string, Object> = {
              'pushStatus': '剪贴板为空',
              'pushSub': '暂无可推内容',
              'pushColor': '#FA8C16'
            };
            await formProvider.updateForm(formId, formBindingData.createFormBindingData(emptyData));
            this.resetFormState(formId, 2500);
            return;
          }

          const res = await webDav.uploadLiveText(text);
          if (res.success) {
            const successData: Record<string, Object> = {
              'pushStatus': '已推送 ✓',
              'pushSub': '已同步至电脑',
              'pushColor': '#00B578',
              'pullStatus': '拉取',
              'pullSub': '从电脑拉取',
              'pullColor': '#1F2329'
            };
            await formProvider.updateForm(formId, formBindingData.createFormBindingData(successData));
          } else {
            const failData: Record<string, Object> = {
              'pushStatus': '上传失败',
              'pushSub': res.message || '网络异常',
              'pushColor': '#E02020'
            };
            await formProvider.updateForm(formId, formBindingData.createFormBindingData(failData));
          }
        } catch (clipErr) {
          const errData: Record<string, Object> = {
            'pushStatus': '已响应',
            'pushSub': '推送到电脑',
            'pushColor': '#0A59F7'
          };
          await formProvider.updateForm(formId, formBindingData.createFormBindingData(errData));
        }

        this.resetFormState(formId, 3000);

      } else if (action === 'pull_clipboard') {
        // 胶囊卡片即时轻量交互反馈（正在拉取）
        const loadingData: Record<string, Object> = {
          'pullStatus': '拉取中...',
          'pullSub': '正在获取',
          'pullColor': '#0A59F7'
        };
        await formProvider.updateForm(formId, formBindingData.createFormBindingData(loadingData));

        try {
          const payload: LivePayload | null = await webDav.fetchLiveText();
          if (payload && payload.text && payload.text.trim()) {
            const cleaned = cleanToPlainText(payload.text);
            const board = pasteboard.getSystemPasteboard();
            const pData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, cleaned);
            await board.setData(pData);

            const successData: Record<string, Object> = {
              'pullStatus': '已拉取 ✓',
              'pullSub': '已写入剪贴板',
              'pullColor': '#00B578',
              'pushStatus': '推送',
              'pushSub': '推送到电脑',
              'pushColor': '#0A59F7'
            };
            await formProvider.updateForm(formId, formBindingData.createFormBindingData(successData));
          } else {
            const emptyData: Record<string, Object> = {
              'pullStatus': '云端无新词',
              'pullSub': '电脑尚未复制',
              'pullColor': '#8F959E'
            };
            await formProvider.updateForm(formId, formBindingData.createFormBindingData(emptyData));
          }
        } catch (pullErr) {
          const failData: Record<string, Object> = {
            'pullStatus': '拉取失败',
            'pullSub': '网络或配置错误',
            'pullColor': '#E02020'
          };
          await formProvider.updateForm(formId, formBindingData.createFormBindingData(failData));
        }

        this.resetFormState(formId, 3000);
      }
    } catch (e) {
      console.error('onFormEvent error:', JSON.stringify(e));
    }
  }

  private resetFormState(formId: string, delayMs: number): void {
    setTimeout(async () => {
      try {
        const normalData: Record<string, Object> = {
          'pushStatus': '推送',
          'pushSub': '推送到电脑',
          'pushColor': '#0A59F7',
          'pullStatus': '拉取',
          'pullSub': '从电脑拉取',
          'pullColor': '#1F2329'
        };
        await formProvider.updateForm(formId, formBindingData.createFormBindingData(normalData));
      } catch (e) {
        // ignore
      }
    }, delayMs);
  }

  onCastToNormalForm(formId: string): void {}
  onUpdateForm(formId: string): void {}
  onChangeFormVisibility(newStatus: Record<string, number>): void {}
  onRemoveForm(formId: string): void {}
  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
