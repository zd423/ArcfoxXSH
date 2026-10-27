# ArcfoxXSH - 截图改数字 iOS App

在小红书等截图上修改数字（如"小眼睛"观看数），字体、颜色、间距可调，导出后看不出修改痕迹。

## 功能
- 从相册选择截图
- 框选要修改的数字，自动采样原数字颜色与背景色
- 可调：新数字、字号、字距、粗细、文字颜色、遮盖背景色、位置/大小微调
- 针对 1320x2868 的小红书笔记分析截图内置两个预设点（顶部小眼睛数字、流量转化观看数）
- 导出原分辨率图片到相册

## 本地运行
\`\`\`bash
brew install xcodegen
xcodegen generate
open ArcfoxXSH.xcodeproj
\`\`\`

## GitHub Actions 构建 IPA
推送到 main 分支或在 Actions 页手动运行 workflow，产物为未签名 IPA（artifact: ArcfoxXSH-unsigned-ipa）。

未签名 IPA 需要自签后才能安装到 iPhone（AltStore / SideStore / Sideloadly，或使用自己的 Apple ID 证书签名）。
