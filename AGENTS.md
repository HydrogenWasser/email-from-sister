# AGENTS.md — Email From Sister

> 本文档供 AI 编码助手阅读。项目内所有注释、设计文档和叙事文本均为中文，因此本文件使用中文撰写。

---

## 项目概览

**《Email From Sister》**（引擎内显示名称为 *Email-From-Sister*）是一款基于 **Godot 4.6** 开发的纯文字心理恐怖冒险游戏。玩家通过阅读邮件、输入指令在不同场景节点间推进剧情，体验以“妹妹死后发来邮件”为核心的悬疑叙事。

- **引擎版本**：Godot 4.6（GLES3 / `gl_compatibility` 渲染器）
- **主场景**：`res://scenes/Main.tscn`
- **目标平台**：Web（已配置 Web Export Preset，默认导出到 `../index.html`）

---

## 项目结构

```
Email-From-Sister/
├── project.godot              # Godot 项目配置
├── export_presets.cfg         # 导出预设（Web）
├── scenes/
│   └── Main.tscn              # 唯一主场景，包含全部 UI 节点树
├── scripts/
│   ├── GameMaster.gd          # UI 渲染、玩家输入、恐怖值/CRT 震动
│   ├── LogicManager.gd        # 剧情状态机、邮件系统、JSON 数据解析
│   └── AudioManager.gd        # 背景音、音效、心跳声控制
├── shaders/
│   ├── CRT.gdshader           # 完整 CRT 复古显示器效果（当前使用）
│   └── CRT_Simple.gdshader    # 简化版 CRT 效果（备用）
├── data/
│   ├── Story.json             # 节点式剧情图（nodes/choices）
│   ├── MailData.json          # 邮件数据（发件人、天数、正文、是否默认已读）
│   ├── GameDesign.md          # UI 设计大纲（ASCII 原型图）
│   └── Email-From-Sister.txt  # 完整故事原文（参考用）
└── .vscode/settings.json      # VS Code Godot 编辑器路径配置
```

---

## 核心架构与模块分工

### 1. GameMaster.gd（场景根节点脚本）
- 负责绑定 `CanvasLayer` 下的所有 UI 控件（`Label`、`RichTextLabel`、`LineEdit`）。
- 设置中文字体回退栈：`JetBrains Mono` → `Consolas` → `SimSun` → `Microsoft YaHei UI`。
- 接收 `LineEdit` 的 `text_submitted` 信号，将指令转交给 `LogicManager`。
- 维护 `terror_value`（恐怖值 0-100）和 `sanity_state`（理智 / 不安 / 恐惧 / 崩溃）。
- 恐怖值变化时触发 `CRT_Overlay` 的屏幕抖动（通过修改 `shake_intensity` shader 参数并用 Tween 恢复）。
- 支持方向键上下导航（在邮件列表页中移动光标）。

### 2. LogicManager.gd（核心逻辑）
- 加载 `data/Story.json` 与 `data/MailData.json`。
- 维护剧情节点状态：`current_scene_id`、`story_nodes`。
- 实现 5 个 UI 页面状态：
  - `PAGE_MAIN`：主场景，显示当前节点正文与选项。
  - `PAGE_MAIL_HOME`：邮件首页。
  - `PAGE_MAIL_UNREAD_LIST`：未读邮件列表。
  - `PAGE_MAIL_READ_DAY_LIST`：已读邮件按天归档列表。
  - `PAGE_MAIL_DAY_MESSAGE_LIST`：某一天的具体邮件列表及正文展开。
- 全局指令：`help/帮助`、`clear/清屏`、`stats/状态`、`quit/退出游戏`。
- 邮件读取后写入 `read_mail_ids`，已读邮件按天数聚合展示。
- 当主场景选项的文本或目标节点标题包含“邮件”时，自动跳转邮件系统而不是普通场景跳转。

### 3. AudioManager.gd（音频）
- 创建三个 `AudioStreamPlayer`：环境音、音效、心跳。
- `update_heartbeat(intensity: float)`：根据恐怖值百分比控制心跳音量与播放/停止。
- 提供 `fade_out_ambient`、`fade_in_ambient` 等工具函数。
- 当前音效函数（`play_sound_effect` 等）多为占位实现，尚未接入实际音频资源。

### 4. CRT Shader
- `CRT.gdshader` 被绑定到 `CanvasLayer/CRT_Overlay`（全屏 `ColorRect`，`mouse_filter = 2`）。
- 效果包括：扫描线、曲率、暗角、色差、噪点、闪烁、屏幕抖动。
- 参数通过 `ShaderMaterial` 在运行时由 `GameMaster` 动态修改（如 `shake_intensity`）。

---

## 数据文件格式

### Story.json
```json
{
  "version": 1,
  "metadata": {
    "title": "Email From Sister",
    "startNodeId": "node_xxx"
  },
  "nodes": [
    {
      "id": "node_xxx",
      "title": "节点标题",
      "body": "节点正文（支持换行）",
      "choices": [
        { "id": "choice_xxx", "text": "选项文本", "targetNodeId": "node_yyy" }
      ]
    }
  ]
}
```

### MailData.json
```json
{
  "version": 1,
  "defaultDayLabel": "第 4 天",
  "defaultWeatherLabel": "晴朗",
  "messages": [
    {
      "id": "mail_day1_1",
      "sender": "妹妹",
      "day": 1,
      "time": "02:52",
      "label": "第 1 封",
      "title": "第一天的邮件",
      "body": "...",
      "is_read_default": true
    }
  ]
}
```

> **注意**：`is_read_default` 为 `true` 的邮件在游戏初始化时即视为已读。未读邮件需要玩家在未读列表中主动选择“查看”后才会标记为已读，并进入当天的邮件详情页。

---

## 构建与导出

项目没有额外的构建脚本，完全依赖 Godot 引擎导出：

1. **直接运行**：在 Godot 编辑器中打开项目，按 F6 运行当前场景，或 F5 运行主场景。
2. **Web 导出**：
   - 已配置 `Web` 导出预设（`export_presets.cfg`）。
   - 默认导出路径：`../index.html`（即项目父目录）。
   - 导出命令（CLI 示例）：
     ```bash
     godot --headless --path <项目路径> --export-release "Web" ../index.html
     ```

---

## 开发规范

### 编码风格
- 使用 **GDScript**，缩进为 **Tab**（Godot 4 默认）。
- 常量使用 `SCREAMING_SNAKE_CASE`（如 `PAGE_MAIN`）。
- 私有方法以 `_` 前缀命名（如 `_load_story_data`）。
- 类型标注：大量使用 `-> void`、`: String`、`: Array[Dictionary]` 等静态类型。
- 中文内容直接硬编码在脚本中（选项文本、提示信息、帮助文本等）。

### 文件与版本控制
- `.editorconfig`：强制 `utf-8` 编码。
- `.gitattributes`：自动将文本文件转为 `LF` 换行。
- `.gitignore`：忽略 `.godot/` 和 `/android/`。
- `.godot/` 目录下的任何文件都不应提交到版本控制。

---

## 测试说明

- **无自动化测试框架**：项目规模较小，当前没有单元测试或集成测试。
- **手动测试路径**：
  1. 启动游戏 → 主场景显示“我的妹妹死了。”及三个选项。
  2. 输入 `1` 或“查看邮件” → 进入邮件首页。
  3. 在未读/已读列表中使用方向键 `↑ ↓` 移动光标，按回车或输入“查看”打开邮件。
  4. 输入非法指令 → 观察 `transient_hint` 提示。
  5. 输入 `quit` 或“退出游戏” → 游戏正常退出。

---

## 安全与注意事项

- `LogicManager` 中的 `_load_json_file` 使用 `FileAccess.open` 读取项目内资源文件，**不处理用户上传的外部文件**，无 JSON 反序列化漏洞风险。
- 当前项目没有网络请求、存档系统或玩家数据持久化，隐私和数据安全方面无特殊要求。
- 若后续添加外部音频资源，请注意版权合规。

---

## 常用开发命令速查

| 操作 | 方式 |
|------|------|
| 运行项目 | Godot 编辑器 F5 / F6 |
| Web 导出 | `godot --headless --export-release "Web" ../index.html` |
| 查看完整故事 | 打开 `data/Email-From-Sister.txt` |
| 调整 UI 布局 | 编辑 `scenes/Main.tscn` 中的 `CanvasLayer/MainLayout` 节点 |
| 修改剧情/邮件 | 编辑 `data/Story.json` 或 `data/MailData.json` |

