let storage = LocalStorage.getShared();

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('dimension') dimension: number = 1;

  build() {
    if (this.dimension === 2) {
      // 2*2 卡片
      Column() {
        Row() {
          Text('EcoPaste')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1F2329')
          Blank()
          Text('剪贴板')
            .fontSize(12)
            .fontColor('#8F959E')
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12 })

        Row() {
          // 左半边：推送
          Column() {
            Text('推送')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0A59F7')
              .letterSpacing(1)

            Text('推送到电脑')
              .fontSize(11)
              .fontColor('#8F959E')
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility',
              params: { action: 'push_clipboard' }
            });
          })

          // 中间分割线
          Divider()
            .vertical(true)
            .height(30)
            .strokeWidth(0.8)
            .color('#EBEDF0')

          // 右半边：拉取
          Column() {
            Text('拉取')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1F2329')
              .letterSpacing(1)

            Text('从电脑拉取')
              .fontSize(11)
              .fontColor('#8F959E')
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility',
              params: { action: 'pull_clipboard' }
            });
          })
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF')
      .borderRadius(20)
    } else {
      // 1*2 小胶囊样式 (默认，精美纯净，参考简约卡片)
      Row() {
        // 左半边：推送
        Column() {
          Text('推送')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0A59F7')
            .letterSpacing(1)

          Text('推送到电脑')
            .fontSize(11)
            .fontColor('#8F959E')
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: {
              action: 'push_clipboard'
            }
          });
        })

        // 中间分割线
        Divider()
          .vertical(true)
          .height(26)
          .strokeWidth(0.8)
          .color('#EBEDF0')

        // 右半边：拉取
        Column() {
          Text('拉取')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1F2329')
            .letterSpacing(1)

          Text('从电脑拉取')
            .fontSize(11)
            .fontColor('#8F959E')
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: {
              action: 'pull_clipboard'
            }
          });
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF')
      .borderRadius(20)
      .padding({ left: 4, right: 4 })
    }
  }
}
