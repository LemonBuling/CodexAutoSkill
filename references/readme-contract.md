# README Contract

Use this reference when handling TikTok e-commerce material batches.

## Expected Root Layout

The root folder usually contains:

- `README.txt` or `README .txt`
- One CTA image such as `CTA标识.png`, `cta贴纸.png`, `贴纸标志.png`
- Material folders such as `素材1`, `素材2`, ...

Each material folder usually contains numeric video clips and one music file.

## README Sections

Common README instructions:

- `导入方式`: import numeric clips in filename order; add folder music to audio track.
- `建议转场`: hard cuts or dissolve; keep TikTok product-selling rhythm.
- `字幕贴字`: one caption per material folder.
- `以上字幕`: stop parsing captions after this line.
- `整条视频添加 简餐 滤镜`: apply mild warm/clean product filter.
- `视频后半段左下方添加 CTA`: overlay root CTA PNG from the middle of the output onward.

## Naming Interpretation

When the user writes a typo like `7.24` inside a `7.27` task, prefer the batch date/path context and use the current batch date unless the user explicitly insists otherwise.

When output path is outside writable roots, do not modify the source folder. Ask for permission if available, or export to a writable `C:\Users\Administrator\Documents\Codex\...` folder and clearly report the substituted output path.

## Quality Rules

Keep the product visible as early as possible. If the first extracted QA frame shows an empty room, door, table, or floor instead of the product/action, trim more aggressively from the first clip and rerender.

Do not duplicate or slow footage just to hit 15-20 seconds. For short source batches, preserve complete effective action and accept shorter outputs.
