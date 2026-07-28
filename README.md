安装方式
如果对方也在 Codex 环境里，可以让他们安装你的 GitHub Skill：
python C:\Users\Administrator\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo LemonBuling/CodexAutoSkill --path .
如果脚本不方便用，也可以手动：
克隆仓库：
git clone https://github.com/LemonBuling/CodexAutoSkill.git
把整个仓库文件夹复制到 Codex skills 目录，例如：
C:\Users\Administrator\.codex\skills\tiktok-material-cleaner
重启 Codex 或开启新任务，让 Skill 被重新加载。
使用方式
之后在 Codex 里直接说：
使用 $tiktok-material-cleaner 帮我剪辑这个素材目录：D:\xxx\素材批次
要求按 README.txt 清洗素材，输出到 output，命名规则是：素材1-7=7.27-群-毛毯；素材8-13=7.27-群-杯子
这个 Skill 会指导 Codex 做这些事：
读取 README
自动找 素材1/素材2/...
按字幕生成英文贴字
识别音乐文件，避免把素材误当音乐
添加 CTA 贴纸
按命名规则导出
做音频、分辨率、解码复检
对方机器上需要有 ffmpeg，比如剪映自带的：
C:\Users\Administrator\AppData\Local\JianyingPro\Apps\版本号\ffmpeg.exe
如果路径不同，让 Codex 先帮他找 ffmpeg.exe 就行。
