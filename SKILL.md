---
name: tiktok-material-cleaner
description: Batch clean TikTok e-commerce video materials from local folders. Use when Codex needs to process README-driven素材 folders for US TikTok product-selling clips: trim invalid pauses/static/empty shots, preserve product and hand/person actions, add English subtitles, CTA stickers, optional JianCan-style filter, music normalization, requested output naming, and QA reports.
---

# TikTok Material Cleaner

## Workflow

Use this skill for local batch editing tasks where the user provides a material root folder, a README.txt with editing requirements, and naming rules such as `素材1-7 -> 7.27-群-毛毯（codex）1-7`.

1. Read the material root folder and README first.
2. Identify material folders by trailing numbers, such as `素材1`, `素材2`, or `item1`.
3. Parse README captions from `素材N:` / `素材N：` lines until the `以上字幕` section.
4. Identify numeric clip files in each material folder:
   - `01.MOV`, `1.MOV`, `10.MOV`
   - `1 (1).MOV`, `1 (2).MOV`
5. Identify music files by excluding numeric clip files and accepting `.mp4`, `.mov`, `.m4a`, `.wav`.
6. Find the CTA image from the root PNG files when README asks for CTA.
7. Generate outputs to a new folder distinct from source files. If requested output is outside writable roots, either request filesystem permission or export to a writable Codex folder.
8. Validate every output with ffmpeg: duration, 1080x1920 video, audio present, decode OK, plus a contact-sheet spot check.

## Rendering Script

Use `scripts/render_tiktok_batch.ps1` for deterministic batch rendering.

Example:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\render_tiktok_batch.ps1 `
  -Root "D:\codex\codex测试\2026.07.27\7.27-群" `
  -OutputRoot "C:\Users\Administrator\Documents\Codex\exports\20260727_qun\output" `
  -Ffmpeg "C:\Users\Administrator\AppData\Local\JianyingPro\Apps\10.9.0.14199\ffmpeg.exe" `
  -WorkDir "C:\Users\Administrator\Documents\Codex\work" `
  -NamingRules "1-7=7.27-群-毛毯;8-13=7.27-群-杯子"
```

`NamingRules` format:

- Use semicolon-separated ranges.
- Each range is `start-end=output-prefix`.
- Output filenames become `output-prefix（codex）index.mp4`, where index resets within each range.

## Editing Defaults

Preserve product and person/hand action. Remove invalid pauses, long still sections, severe blur/shake, and empty shots. Prefer middle/later parts of clips, but keep complete action for very short sources.

Use hard cuts by default. Normalize to 1080x1920, 30 fps. Add subtitles at X=0, Y=300 with white bold text and black outline. Wrap long English text automatically.

Apply a mild JianCan-style filter only when README contains `简餐`; otherwise preserve source color. Add CTA in the latter half when a root PNG exists and README requests CTA.

Always map the actual music file, not a numeric clip. Normalize audio loudness so exported music is audible.

## Validation

After rendering:

1. Confirm output count and names match the user request.
2. Decode each MP4 with ffmpeg using `-v error -i file -map 0:v:0 -map 0:a:0? -f null -`.
3. Confirm `1080x1920`, audio present, and decode OK.
4. Create a contact sheet with one early subtitle frame and one later CTA frame per output.
5. If early frames show empty scenes, rerender with stricter intro trimming.

## Reference

Read `references/readme-contract.md` when README parsing, naming interpretation, or permission/output-location decisions are ambiguous.
