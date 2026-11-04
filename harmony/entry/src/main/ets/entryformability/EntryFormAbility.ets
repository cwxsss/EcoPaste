import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import formBindingData from '@ohos.app.form.formBindingData';
import formInfo from '@ohos.app.form.formInfo';
import Want from '@ohos.app.ability.Want';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let dimension: number = formInfo.FormDimension.Dimension_1_2;
    if (want.parameters) {
      dimension = (want.parameters[formInfo.FormParam.DIMENSION_KEY] as number) || dimension;
    }

    const formData: Record<string, Object> = {
      'dimension': dimension
    };
    return formBindingData.createFormBindingData(formData);
  }

  onCastToNormalForm(formId: string): void {
  }

  onUpdateForm(formId: string): void {
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
  }

  onFormEvent(formId: string, message: string): void {
  }

  onRemoveForm(formId: string): void {
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
