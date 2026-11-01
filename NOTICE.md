# 来源说明

原生客户端代码为本次独立工程新增，许可证为 AGPL-3.0-only，全文见 `LICENSE`。

接口适配依据 PUBO 当前 Misskey 2026.9.0 定制后端；App 安装包没有嵌入后端服务或 Miria 源码。

`scripts/isolated/backend-overlay.json` 保存本轮后端变更供公开 CI 联合验收使用，不进入 App 安装包。后端变更保留 syuilo 和 misskey-project 的 AGPL-3.0-only 声明；CI 重新生成的 `packages/misskey-js` 类型沿用该子包 MIT 声明。

`App/Assets.xcassets/Brand.imageset/pubo-logo.png` 原样复用 PUBO 网站品牌资源。构建时仅将其置于纯色背景生成应用图标，不替换网站标志。

Misskey 上游项目：<https://github.com/misskey-dev/misskey>，版权归 syuilo 和 misskey-project。`LICENSE` 使用与当前网站相同的 GNU Affero General Public License v3 全文。
