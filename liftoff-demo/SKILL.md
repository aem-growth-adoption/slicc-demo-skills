---
name: liftoff-demo
description: |
  Use when running an automated page migration demo inside SLICC —
  user provides a URL and a target repo, the skill orchestrates the
  full migrate-page pipeline with live progress sprinkles.
  Requires GitHub access and EDS repo pre-configured by the Liftoff Lab.
user-invocable: true
---

# liftoff-demo

One URL in. A migrated EDS page out. Live progress the whole way.

Orchestrates `migrate-page` from `aemcoder/skills` with a pipeline
progress sprinkle and a completion sprinkle — designed for the
Liftoff to AEM Labs demo experience.

## When NOT to Use

- Running a migration manually without the demo UI — use `migrate-page` directly
- Running outside SLICC (no sprinkles available)

## Prerequisites

- Migration skills installed (`upskill aemcoder/skills --path skills/migration --all`)
- The `migrate-page` sprinkle must be closed after install (`sprinkle close migrate-page`)
  because it conflicts with our pipeline sprinkle (enforced by Step 0).
- GitHub access configured by the Liftoff Lab
- EDS repo pre-created by the Liftoff Lab

## Key Rules

- **Cone owns ALL `sprinkle send` calls** — never delegate pipeline updates to scoops.
  This is a deliberate exception to the usual "delegate work to scoops" guidance:
  only the cone sees every phase transition, and scoops busy with block work skip or
  forget updates.
- **Always mint fresh sprinkle names** per migration — never reuse/overwrite
- **Rewrite the pipeline `.shtml` after every `sprinkle send`** — late-joining followers need to see accumulated progress, not a blank initial state
- **All DA content operations go through the mount** (`/mnt/da/`) — never `curl`
  `admin.da.live` to write content. The only admin API use is the authed preview
  trigger (`POST admin.hlx.page/preview/...`).
- **The target content path must be explicit** — take it from the init/handoff
  prompt; default to `index` (site root) and state the assumption in the report.

## Slug Derivation

Derive from URL hostname + path + 4 random hex chars:

- `https://www.adobe.com/products/photoshop` → `adobe-photoshop-a3f1`
- `https://wknd.site/basecamp` → `wknd-basecamp-9c2e`
- `https://wknd-adventures.com/basecamp.html` → `wknd-adventures-basecamp-7b21`
- `https://example.com/` → `example-index-c4d9`

Rules:

1. Strip `www.` and the TLD; keep ALL remaining hostname labels joined with hyphens
   (`wknd-adventures.com` → `wknd-adventures`, `wknd.site` → `wknd`).
2. Take the last path segment, minus any file extension; use `index` when the path is
   `/` or empty.
3. Lowercase everything.
4. **Sanitize:** replace every character outside `[a-z0-9-]` with `-` (this handles
   spaces, punctuation, query strings, and Unicode in the URL — e.g. `foo;bar` →
   `foo-bar`), collapse repeated `-` into one, trim leading/trailing `-`, and cap the
   result at 40 characters.
5. Append `-` + 4 random hex chars. Generate them with node — do NOT assume `openssl`
   exists in the sandbox:

   ```bash
   node -e "console.log(require('crypto').randomBytes(2).toString('hex'))"
   ```

Always double-quote `"$SLUG"` (or the resolved `{{SLUG}}` value) in every shell command
and sprinkle name — never interpolate it unquoted.

## Pipeline Sprinkle Updates

The cone pushes status updates between phases:

- Before starting a phase: push `active` for the current step
- When a phase completes: push `done`, then `active` for the next

Format: `sprinkle send {{SLUG}}-pipeline '{"step":"<id>","status":"active|done","summary":"...","link":"...","startedAt":<epoch_ms>,"completedAt":<epoch_ms>}'`

Timestamp rules:

- When sending `"status":"active"`: include `"startedAt":<now_ms>` (capture BEFORE the
  phase starts)
- When sending `"status":"done"`: include `"completedAt":<now_ms>` (and the phase's
  original `"startedAt"` so late joiners compute the elapsed time)
- Capture timestamps with: `TIMESTAMP=$(date +%s000)` (epoch milliseconds)
- The pipeline template renders live duration timers from these fields — omitting them
  silently disables the timers

Step IDs in order: `setup`, `extraction`, `decomposition`, `blocks`, `assembly`, `deploy`

### State Persistence

Every time you push a pipeline update, you MUST also rewrite the
sprinkle's `.shtml` file with the updated `{{INITIAL_STATE_JSON}}`
reflecting all current step statuses. This ensures followers who join
mid-session see the full accumulated progress.

Procedure after every `sprinkle send`:

1. Update your in-memory steps array with the new status AND timestamps (`startedAt`, `completedAt`)
2. Rewrite `/shared/sprinkles/{{SLUG}}-pipeline/{{SLUG}}-pipeline.shtml`
3. The `sprinkle send` pushes the live update; the rewritten file catches up new joiners

## Procedure

### Step 0 — Verify prerequisites

Fail fast before opening any sprinkle:

1. Confirm the migration skills are installed at the expected paths:

   ```bash
   test -f /workspace/skills/migrate-page/SKILL.md
   ```

   If missing, install first: `upskill aemcoder/skills --path skills/migration --all`
   — do NOT continue with a dead path.

2. Close the migrate-page sprinkle (idempotent — safe if already closed):

   ```bash
   sprinkle close migrate-page
   ```

   It conflicts with our pipeline sprinkle. If it re-opens later in the run
   (e.g. after a skill re-install), close it again.

### Step 1 — Setup & open pipeline sprinkle

1. Derive slug from the URL
2. Read `/workspace/skills/liftoff-demo/templates/pipeline.shtml.tpl`
3. Replace `{{URL}}`, `{{SLUG}}`
4. Capture the start timestamp: `START_TS=$(date +%s000)`, then replace
   `{{INITIAL_STATE_JSON}}` with the initial state (setup=active, rest pending):

   ```json
   {"steps":[
     {"id":"setup","status":"active","summary":"Cloning repo & preparing environment...","link":null,"startedAt":<START_TS>,"completedAt":null},
     {"id":"extraction","status":"pending","summary":"Capture page structure & brand","link":null,"startedAt":null,"completedAt":null},
     {"id":"decomposition","status":"pending","summary":"Identify blocks & sections","link":null,"startedAt":null,"completedAt":null},
     {"id":"blocks","status":"pending","summary":"Generate EDS blocks in parallel","link":null,"startedAt":null,"completedAt":null},
     {"id":"assembly","status":"pending","summary":"Assemble page & create preview","link":null,"startedAt":null,"completedAt":null},
     {"id":"deploy","status":"pending","summary":"Publish content & go live","link":null,"startedAt":null,"completedAt":null}
   ]}
   ```

5. Write to `/shared/sprinkles/{{SLUG}}-pipeline/{{SLUG}}-pipeline.shtml`
6. Run: `sprinkle open {{SLUG}}-pipeline`
7. Push initial status:

   ```
   sprinkle send {{SLUG}}-pipeline '{"step":"setup","status":"active","summary":"Cloning repo & preparing environment...","startedAt":'$START_TS'}'
   ```

### Step 2 — Clone repo & verify environment

1. Clone the target repo: `git clone https://github.com/{{OWNER}}/{{REPO}}.git /shared/{{REPO}}`
2. Migration skills were already verified in Step 0
3. Push setup done + extraction active:

   ```
   SETUP_DONE=$(date +%s000)
   sprinkle send {{SLUG}}-pipeline '{"step":"setup","status":"done","summary":"Environment ready","startedAt":'$START_TS',"completedAt":'$SETUP_DONE'}'
   EXTRACT_START=$(date +%s000)
   sprinkle send {{SLUG}}-pipeline '{"step":"extraction","status":"active","summary":"Navigating to page...","startedAt":'$EXTRACT_START'}'
   ```

### Step 3 — Run the migration (follow migrate-page procedure directly)

**DO NOT invoke migrate-page as a named skill** — that would re-open
its sprinkle. Instead, read the migrate-page SKILL.md and follow
its procedure directly:

```
read_file /workspace/skills/migrate-page/SKILL.md
```

Then execute its four phases as the cone, pushing our pipeline sprinkle
updates at each transition:

**Phase 1 — Extraction:**
Follow migrate-page Phase 1 steps (navigate, lazy-load scroll, de-sticky,
visual tree, screenshot, brand extract, metadata, block inventory).

```
sprinkle send {{SLUG}}-pipeline '{"step":"extraction","status":"active","summary":"Capturing page structure...","startedAt":'$EXTRACT_START'}'
```

When complete:

```
EXTRACT_DONE=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"extraction","status":"done","summary":"Page captured","startedAt":'$EXTRACT_START',"completedAt":'$EXTRACT_DONE'}'
```

**Phase 2 — Decomposition:**
Follow migrate-page Phase 2 (classify visual tree into blocks/sections)
and Phase 2.5 (brand/fonts/styles setup).

```
DECOMP_START=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"decomposition","status":"active","summary":"Identifying blocks...","startedAt":'$DECOMP_START'}'
```

When complete:

```
DECOMP_DONE=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"decomposition","status":"done","summary":"N blocks identified","startedAt":'$DECOMP_START',"completedAt":'$DECOMP_DONE'}'
```

**Phase 3 — Block Generation:**
Follow migrate-page Phase 3 (create one scoop per block, monitor completion).

**Coordinating the block scoops (mute → batched wait):** create ALL block scoops and feed
each its prompt in a single response, then `scoop_mute` every scoop, then issue ONE batched
`scoop_wait` for all of them. Muting prevents each scoop completion from fragmenting the
cone's flow into separate turns; the single wait delivers all completion summaries at once.

The batched `scoop_wait` itself only returns once EVERY scoop in the batch completes — it
cannot report intermediate progress. If you want `M/N blocks done` updates as they arrive,
poll each scoop's own completion marker (per migrate-page's monitoring convention) between
the spawn and the batched wait, pushing an updated summary each time a new marker appears.
If intermediate progress isn't needed, skip straight from `0/N` to `N/N`.

```
BLOCKS_START=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"blocks","status":"active","summary":"Generating 0/N blocks...","startedAt":'$BLOCKS_START'}'
```

Update as scoops complete:

```
sprinkle send {{SLUG}}-pipeline '{"step":"blocks","status":"active","summary":"3/6 blocks done","startedAt":'$BLOCKS_START'}'
```

When all complete:

```
BLOCKS_DONE=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"blocks","status":"done","summary":"All N blocks generated","startedAt":'$BLOCKS_START',"completedAt":'$BLOCKS_DONE'}'
```

**Phase 4 — Assembly:**
Follow migrate-page Phase 4 (collect results, assemble page, create preview).

```
ASSEMBLY_START=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"assembly","status":"active","summary":"Assembling page...","startedAt":'$ASSEMBLY_START'}'
```

When complete:

```
ASSEMBLY_DONE=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"assembly","status":"done","summary":"Page assembled","startedAt":'$ASSEMBLY_START',"completedAt":'$ASSEMBLY_DONE'}'
```

**Remember:** After every `sprinkle send`, rewrite the pipeline `.shtml`
file with updated state (see State Persistence section above).

### Step 4 — Deploy

**Mental model — this is the step people get wrong:** in EDS, code (blocks, styles,
icons) is served from the git repo, but page CONTENT is served from the content source
(DA). `git push` alone NEVER produces a live page. Deploy = push code + upload content
to DA + trigger preview.

Push deploy active first:

```
DEPLOY_START=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"deploy","status":"active","summary":"Publishing content to DA...","startedAt":'$DEPLOY_START'}'
```

**Target content path:** the init/handoff prompt MUST state where the page is published
(e.g. "publish as `index` at site root"). If it doesn't, default to `index` (site root) —
demo experiment URLs target the root — and say so in the final report.

Set `CONTENT_PATH` from that value (default `index`) and use it for EVERY step below —
never hardcode `index`. Reject a value that starts with `/` or contains `..`; strip any
leading `/` and any `.html` suffix before using it.

The preview URL derives as:

```
PREVIEW_URL = https://{ref}--{repo}--{owner}.aem.page/{content-path}
```

where `{ref}` is the branch (usually `main`) and `{content-path}` is the URL-facing form
of `CONTENT_PATH` — empty when `CONTENT_PATH` is `index` (the site root maps to an empty
URL path, NOT a literal `/index`), otherwise `CONTENT_PATH` itself (e.g.
`CONTENT_PATH=products/foo` → `.../products/foo`, backed by the DA document at
`products/foo.html`).

#### 4.1 Commit & push code

Commit and push all generated code to the repo: `blocks/`, `styles/`, `icons/`,
`head.html`, and `drafts/` (images). Content does NOT go live from this push — keep going.

#### 4.2 Mount DA (cone-owned)

```bash
mount --source da://{owner}/{repo} /mnt/da
```

Verify the mount before proceeding (`ls /mnt/da` — existing content or empty is fine).
ALL content reads/writes go through this mount. NEVER use `curl` against `admin.da.live`
to write content. The ONLY valid admin API call is triggering preview (step 4.4).

#### 4.3 Build the DA documents

Build `${CONTENT_PATH}.html`, `nav.html`, and `footer.html` from the
assembled outputs (`/shared/{repo-name}/drafts/{page-path}.plain.html` and the nav/footer
fragments). DA documents are **body fragments** with strict rules — violations fail
silently (DA normalizes the HTML on write and the page just renders wrong):

- No `<!DOCTYPE>`, `<html>`, `<head>`, `<script>`, `<style>`, or inline `style=`
  attributes. The pipeline injects head/scripts/styles from the code bus.
- Blocks keep their canonical shape: `<div class="blockname">` with row/cell `<div>`s.
  Malformed blocks are flattened to plain divs and lose their class — and there is no
  error when this happens.

**Rewrite every `<img src>` to an absolute, publicly reachable URL.** The assembled
`.plain.html` uses root-relative `/drafts/images/...` paths — these are code-bus paths
that DA cannot resolve; they render as `about:error` on the live page. EDS preview
fetches each image URL and ingests it into its media pipeline (serving it back as
`./media_<hash>.<ext>?...`), so any URL that returns image bytes works:

- Preferred: the original absolute source-site URLs captured during extraction.
- Alternative: absolute code-bus URLs (`https://{ref}--{repo}--{owner}.aem.page/drafts/images/...`)
  AFTER the 4.1 push — verify one with `curl -sI` returns an image content-type before
  relying on this.

**Brand logo caution:** SVGs containing `<text>` do not survive DA's media optimization
(rasterized to webp, text dropped — renders blank). Brand logos must be an icon-shape
SVG served from the code bus via the EDS icon system
(`<span class="icon icon-{name}">`) plus real HTML text — never a text-bearing
`<img src="logo.svg">`.

**Append a Page Metadata block** as the LAST element of the document, in the canonical
div form — key/value CELL DIVS, not `<p>` tags (DA's normalization flattens anything
else and strips the class, leaving visible junk text and no meta tags):

```html
<div class="metadata">
  <div><div>title</div><div>{title from .migration/metadata.json}</div></div>
  <div><div>description</div><div>{description from .migration/metadata.json}</div></div>
</div>
```

The class must be exactly `metadata` (single lowercase token). This is what becomes
`<title>`/`<meta name="description">`/OG tags at delivery — without it the page has no
SEO metadata and the browser falls back to the H1.

#### 4.4 Upload via the mount + trigger preview

```bash
mkdir -p "/mnt/da/$(dirname "$CONTENT_PATH")"
cp "${CONTENT_PATH}.html" "/mnt/da/${CONTENT_PATH}.html"
cp nav.html    /mnt/da/nav.html
cp footer.html /mnt/da/footer.html
```

Then trigger preview for EACH document. The endpoint requires auth (anonymous POSTs
return 401) and the path has NO `.html` extension. Use `--fail-with-body` so an
expired/invalid token or a 4xx/5xx response actually stops the run instead of being
silently ignored, and bound each call with a timeout:

```bash
TOKEN=$(oauth-token adobe)
for doc in "$CONTENT_PATH" nav footer; do
  if ! curl --fail-with-body --show-error --connect-timeout 10 --max-time 30 \
    -X POST -H "Authorization: Bearer $TOKEN" \
    "https://admin.hlx.page/preview/{owner}/{repo}/{ref}/$doc"; then
    echo "preview trigger failed for $doc — stopping, do not mark deploy done" >&2
    exit 1
  fi
done
```

#### 4.5 Warm the media pipeline

DA ingests external image URLs lazily — on the first page loads, `media_*` derivatives
may 404 or render broken (`naturalWidth == 0`) even though nothing is wrong. Images in
hidden containers (e.g. inactive tab panes) never trigger a load at all and stay
un-ingested until a user clicks. Warm everything deterministically:

1. Open `{{PREVIEW_URL}}` in playwright and collect image state from the DOM in one pass —
   including hidden elements — separating already-broken URLs from warmable media
   derivatives:

   ```bash
   playwright-cli eval --tab={previewTabId} "JSON.stringify((function(){ var urls = Array.from(document.querySelectorAll('img[src], source[srcset]')).flatMap(function(el){ return el.srcset ? el.srcset.split(',').map(function(s){ return s.trim().split(' ')[0]; }) : [el.getAttribute('src')]; }).filter(Boolean); var broken = urls.filter(function(u){ return u === 'about:error' || u === ''; }); var mediaUrls = Array.from(new Set(urls.filter(function(u){ return u.indexOf('media_') !== -1; }).map(function(u){ return new URL(u, location.href).href; }))); return { broken: broken, mediaUrls: mediaUrls }; })())"
   ```

2. **Fail loudly, don't just warm and hope:** if `broken` is non-empty, or `mediaUrls` is
   empty despite the authored document containing images, the page has a real broken
   image (this is exactly how the hidden-tab-pane failure from the retrospective would
   show up) — report it and do NOT mark deploy done.
3. Otherwise, `curl -s -o /dev/null -w '%{http_code}'` every URL in `mediaUrls`; retry with
   backoff (e.g. 3 attempts, 5s apart) until each returns 200. The fetch itself warms the
   ingestion.

**Verification rule:** `naturalWidth == 0` is ambiguous — it is a false negative for
SVGs sized by the icon decorator, and a transient state for still-ingesting media. Judge
images by HTTP status of the media URL + a screenshot, never by `naturalWidth` alone.

#### 4.6 Poll and confirm

Poll `{{PREVIEW_URL}}` with a bounded deadline (e.g. every 5s, up to 2 minutes) until it
returns 200 — do NOT poll unbounded; if the deadline is reached without a 200, stop and
report the failure instead of hanging or silently marking deploy done. Once it's live,
reload once more and screenshot to confirm the page renders (fonts, images, header,
footer). Then push deploy done:

```
DEPLOY_DONE=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"deploy","status":"done","summary":"Live!","link":"{{PREVIEW_URL}}","startedAt":'$DEPLOY_START',"completedAt":'$DEPLOY_DONE'}'
```

### Step 5 — Open completion sprinkle

1. Read `/workspace/skills/liftoff-demo/templates/complete.shtml.tpl`
2. Replace `{{SLUG}}` and `{{COMPLETE_JSON}}`
3. The data island shape:

   ```json
   {
     "url": "{{URL}}",
     "previewUrl": "{{PREVIEW_URL}}",
     "stats": [
       { "value": "{{BLOCK_COUNT}}", "label": "blocks migrated" },
       { "value": "{{FRAGMENT_COUNT}}", "label": "fragments created" },
       { "value": "{{MEDIA_ASSET_COUNT}}", "label": "media assets published" }
     ],
     "nextSteps": [
       {
         "icon": "✏️",
         "title": "Edit your content",
         "description": "Open Document Authoring to edit pages and content",
         "url": "https://da.live/canvas#/{{OWNER}}/{{REPO}}/{{CONTENT_PATH}}",
         "linkLabel": "open"
       },
       {
         "icon": "🔍",
         "title": "Review the code",
         "description": "See the generated blocks, CSS, and JS on GitHub",
         "url": "https://github.com/{{OWNER}}/{{REPO}}",
         "linkLabel": "open"
       },
       {
         "icon": "🚀",
         "title": "Migrate more pages",
         "description": "Use Liftoff to AEM to migrate additional pages",
         "url": "https://l2a-service-dev.franklin-prod.workers.dev/",
         "linkLabel": "open"
       }
     ]
   }
   ```

**Stats must be real counts, never sample literals.** Compute each placeholder before
writing the completion sprinkle:

- `{{BLOCK_COUNT}}` — number of blocks in `decomposition.json`.
- `{{FRAGMENT_COUNT}}` — nav + footer + any additional fragments uploaded in Step 4.
- `{{MEDIA_ASSET_COUNT}}` — count of UNIQUE media assets by source image or content
  hash, NOT raw warmed-URL count (Step 4.5's URL list includes multiple responsive
  variants per image, which would inflate the count).

Never report a metric the pipeline didn't compute — there is no visual-match
measurement, so do not present one; describe fidelity qualitatively in chat if asked.

1. Write to `/shared/sprinkles/{{SLUG}}-complete/{{SLUG}}-complete.shtml`
2. Run: `sprinkle open {{SLUG}}-complete`

### Step 6 — Report

```
🚀 Migration complete — {{URL}}

Sprinkles open:
  {{SLUG}}-pipeline  — migration progress
  {{SLUG}}-complete  — result + next steps

Preview: {{PREVIEW_URL}}
```

## Lick Events

None — this is a fully automated flow. The user watches, the cone drives.

## Known Limitations

- **Sprinkle file size limit** — keep each `.shtml` under ~350KB. Reference images
  by URL in sprinkle payloads rather than base64-embedding. (Image handling for PAGE
  CONTENT is covered in Step 4.3.)
- **Sprinkle overwrite doesn't push to followers** — always mint fresh names.
- **Scoop outputs go to `/shared/`** — cone and scoops can read each other's outputs.
- **DA normalizes HTML on write** — malformed blocks (wrong cell structure, stray
  `<p>` children) are silently flattened and lose their class. If a block "disappears"
  on the live page, re-read the stored HTML from `/mnt/da/` and compare against the
  canonical shape; your original markup is gone, so match on visible text.
- **DA media ingestion is lazy** — first preview after upload may show broken images
  for a while. Warm derivatives per Step 4.5 before judging anything broken.
