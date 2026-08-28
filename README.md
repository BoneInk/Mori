# Mirror

简体中文 | [English](README_EN.md)

Mirror 是一款原生 macOS Markdown 编辑器，专注于安静、清晰的写作体验。它将文件管理、源码编辑、实时预览与沉浸阅读整理在同一个轻量工作区中，并采用暖灰画布、纸张式内容区域和低饱和橙色强调色。

[下载 Mirror 1.0](https://github.com/BoneInk/Mirror/releases/latest) · 支持 macOS 14 及更高版本

## 界面预览

### 编辑与实时预览

文件树与文档大纲可快速切换；Markdown 源码和格式化预览通过语义锚点保持双向滚动同步。

![Mirror 的文件树、Markdown 源码和实时预览](docs/images/editor-preview.png)

### 阅读模式

阅读模式隐藏源码噪音，提供贯穿窗口的纸张画布、章节导航、阅读进度和轻量排版工具。

![Mirror 沉浸式阅读模式](docs/images/reader-mode.png)

### Mermaid 图表

Mermaid 图表在本地离线渲染，可以在分栏模式中一边编辑源码、一边查看结果。

![Mirror 编辑并预览 Mermaid 时序图](docs/images/mermaid-preview.png)

## 核心功能

- 原生 Markdown 编辑器，支持语法高亮、实时预览及双向滚动同步
- 工作区文件树、最近文件、标签页、全文搜索和文档大纲
- 沉浸式阅读模式，可调整阅读宽度、字体、行高与主题
- 内置表格、代码高亮、图片、HTML、Mermaid 图表和 KaTeX 公式渲染
- 简体中文默认界面，可切换 English，并支持浅色、深色与自定义主题
- 自动保存、崩溃恢复、外部修改检测和本地文档历史
- 导出便携 HTML、PDF，或使用原生 macOS 打印流程

Mirror 兼容常用 CommonMark 与 GitHub 风格 Markdown，包括任务列表、脚注、表格、引用式链接、围栏代码块和安全 HTML。文本与源码文件可直接编辑，图片、PDF 和常见二进制文档可在应用内预览。

## 构建

需要 macOS 14 或更高版本，以及 Swift 6 工具链。

```bash
swift build
swift run Mirror
```

生成 Universal 2 应用和可安装 DMG：

```bash
./scripts/build-app.sh release
./scripts/build-dmg.sh --skip-build
```

构建产物位于 `dist/Mirror.app` 和 `dist/Mirror-1.0.dmg`。本地脚本使用临时签名；公开分发仍需 Apple Developer ID 签名和 Apple 公证。
