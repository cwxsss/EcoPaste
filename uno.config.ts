// VS Code / Cursor / 集成终端环境下 VSCODE_CWD 会被 @unocss/preset-icons 误识别为编辑器插件沙箱，
// 导致跳过本地 nodeLoader，从而导致构建时所有图标缺失变白。在此显式清除该环境变量。
delete process.env.VSCODE_CWD;

import {
  defineConfig,
  presetIcons,
  presetWind4,
  transformerDirectives,
  transformerVariantGroup,
} from "unocss";
import { presetAntdColors } from "./src/unocss/presetAntdColors";

export default defineConfig({
  presets: [presetWind4(), presetAntdColors(), presetIcons()],
  transformers: [
    transformerVariantGroup(),
    transformerDirectives({
      applyVariable: ["--uno"],
    }),
  ],
});
