# TikTok Material Cleaner

Codex Skill for batch-cleaning US TikTok e-commerce product-selling materials. It reads a local material folder and `README.txt`, trims invalid pauses and empty/static shots, preserves product and hand/person actions, adds captions, music, CTA stickers, naming rules, and performs basic QA.

## 功能

- 读取 `README.txt` / `README .txt` 里的剪辑要求。
- 自动识别 `素材1`、`素材2` 等素材文件夹。
- 从 `素材N:` / `素材N：` 行解析字幕。
- 支持 `01.MOV`、`1.MOV`、`10.MOV`、`1 (1).MOV` 等素材命名。
- 自动识别真正的音乐文件，例如 `音乐.mp4`、`音乐.mov`、`杰西卡.mp4`。
- 避免把数字素材片段误当成音乐。
- 在 X=0、Y=300 添加白字黑描边字幕。
- 后半段叠加根目录里的 CTA PNG。
- README 包含 `简餐` 时自动添加轻度产品滤镜。
- 对音乐做响度标准化，避免导出后听起来没声音。
- 导出 `1080x1920` MP4，并检查音频、分辨率和解码。

## 安装

在 Codex 环境里安装：

```powershell
python C:\Users\Administrator\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo LemonBuling/CodexAutoSkill --path .
```

如果安装脚本不可用，也可以手动克隆：

```powershell
git clone https://github.com/LemonBuling/CodexAutoSkill.git
```

然后把仓库文件夹复制到：

```text
C:\Users\Administrator\.codex\skills\tiktok-material-cleaner
```

重启 Codex，或开启一个新任务，让 Skill 被重新加载。

## 在 Codex 里使用

示例提示词：

```text
使用 $tiktok-material-cleaner 帮我剪辑这个素材目录：
D:\codex\codex测试\2026.07.27\7.27-群

要求按 README.txt 清洗素材，输出到 output。
命名规则：
素材1-7=7.27-群-毛毯
素材8-13=7.27-群-杯子
```

Codex 会读取 Skill，检查素材目录和 README，然后按命名规则调用脚本批量生成。

## 直接运行脚本

核心脚本：

```text
scripts\render_tiktok_batch.ps1
```

示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\render_tiktok_batch.ps1 `
  -Root "D:\codex\codex测试\2026.07.27\7.27-群" `
  -OutputRoot "C:\Users\Administrator\Documents\Codex\exports\20260727_qun\output" `
  -Ffmpeg "C:\Users\Administrator\AppData\Local\JianyingPro\Apps\10.9.0.14199\ffmpeg.exe" `
  -WorkDir "C:\Users\Administrator\Documents\Codex\work" `
  -NamingRules "1-7=7.27-群-毛毯;8-13=7.27-群-杯子" `
  -StrictIntroTrim
```

输出文件名示例：

```text
7.27-群-毛毯（codex）1.mp4
7.27-群-毛毯（codex）2.mp4
...
7.27-群-杯子（codex）1.mp4
```

## 依赖

机器上需要有 `ffmpeg.exe`。剪映/CapCut 常见路径：

```text
C:\Users\Administrator\AppData\Local\JianyingPro\Apps\<version>\ffmpeg.exe
```

如果不知道路径，可以让 Codex 先搜索 `ffmpeg.exe`。

## 注意事项

- 如果目标输出目录不在 Codex 可写范围内，需要允许文件系统权限，或者输出到 `C:\Users\Administrator\Documents\Codex\...`。
- 如果导出视频听起来没音乐，优先检查是否误选了数字素材片段作为音乐，并保持响度标准化开启。
- 不要为了强行凑 15-20 秒而重复或慢放素材。源素材很短时，应优先保留完整有效的产品展示和人物动作。
