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

- **Never reference `/workspace/` or `file://` in anything a follower sees** —
  pipeline `link` fields, confirmation screenshots, and sprinkle data must use
  EDS/`aem.page` URLs, never local paths.
- **Cone owns ALL `sprinkle send` calls** — never delegate pipeline updates to scoops.
  This is a deliberate exception to the usual "delegate work to scoops" guidance:
  only the cone sees every phase transition, and scoops busy with block work skip or
  forget updates.
- **Always mint fresh sprinkle names** per migration — never reuse/overwrite
- **Rewrite the pipeline `.shtml` after every `sprinkle send`** — late-joining followers need to see accumulated progress, not a blank initial state
- **All DA content operations go through the mount** (`/mnt/da/`) — never `curl`
  `admin.da.live` to write content. The only admin API use is the authed preview
  trigger (`POST admin.hlx.page/preview/...`).
- **Never delete block-generation scoops after completion** — leave them alive for
  debugging and retrospective; they cost nothing idle and their logs/state are
  invaluable if something goes wrong downstream.
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

## Pipeline Updates — use `pipeline.js`

Three things MUST happen together on every phase transition: update the
persisted state, rewrite the `.shtml` (so late-joining followers see accumulated
progress, not a blank slate), and issue the `sprinkle send`. The
`scripts/pipeline.js` helper does all three in one call — including capturing
`startedAt`/`completedAt` automatically — so the rule can't be half-done and a
dropped timestamp can't silently disable the live timer. Use it; do NOT
hand-roll the send + rewrite.

```bash
# once, at setup — writes state + renders the .shtml (does NOT open the sprinkle):
node /workspace/skills/liftoff-demo/scripts/pipeline.js init "$SLUG" "$URL"

# on every phase transition:
node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" <step> <status> [summary] [link]
```

- `<step>` is one of, in order: `setup`, `extraction`, `decomposition`, `blocks`,
  `assembly`, `deploy`.
- `<status>` is `active`, `done`, or `pending`.
- `active` captures `startedAt` once; `done` captures `completedAt` and keeps the
  original `startedAt`. You never pass timestamps by hand.
- Optional `summary` overrides the step's default line; optional `link` (used on
  `deploy done`) adds a "view ↗" link.
- Between phases: `send` `done` for the finishing step, then `active` for the next.
- State lives at `/shared/sprinkles/{{SLUG}}-pipeline/.state.json`; the helper
  re-renders from the installed template every call, so the `.shtml` and the live
  push never drift.
- If `sprinkle` isn't directly spawnable, the helper still writes state + `.shtml`
  and prints the exact `sprinkle send …` line for you to run — the rewrite is
  never skipped.

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

   It conflicts with our pipeline sprinkle. Note: `sprinkle close` succeeds even though
   `sprinkle list` will still show `migrate-page` — the list includes ALL available
   `.shtml` files, not just open ones. Confirm closure by the ABSENCE of the `[open]`
   marker next to it in `sprinkle list`, not by its absence from the list. Only re-close
   if it actually shows `[open]` again (e.g. after a skill re-install).

### Step 1 — Setup & open pipeline sprinkle

1. Derive the slug from the URL (see Slug Derivation); keep the source URL too.
   Set `SLUG` and `URL` for the helper calls below.
2. Initialize state + render the pipeline `.shtml` (setup active, rest pending):

   ```bash
   node /workspace/skills/liftoff-demo/scripts/pipeline.js init "$SLUG" "$URL"
   ```

3. Open the sprinkle:

   ```bash
   sprinkle open {{SLUG}}-pipeline
   ```

   `init` already baked setup=active (with its `startedAt`) into the rendered
   `.shtml`, so the first follower sees setup running immediately — no separate
   initial `send` is needed until the first transition.

### Step 2 — Clone repo & verify environment

1. Clone the target repo: `git clone https://github.com/{{OWNER}}/{{REPO}}.git /shared/{{REPO}}`
2. Migration skills were already verified in Step 0
3. Push setup done + extraction active:

   ```bash
   node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" setup done "Environment ready"
   node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" extraction active "Navigating to page..."
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

```bash
node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" extraction active "Capturing page structure..."
```

When complete:

```bash
node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" extraction done "Page captured"
```

**Phase 2 — Decomposition:**
Follow migrate-page Phase 2 (classify visual tree into blocks/sections)
and Phase 2.5 (brand/fonts/styles setup).

```bash
node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" decomposition active "Identifying blocks..."
```

When complete (replace N with the real block count):

```bash
node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" decomposition done "N blocks identified"
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
the spawn and the batched wait, sending an updated summary each time a new marker appears.
If intermediate progress isn't needed, skip straight from `0/N` to `N/N`.

```bash
node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" blocks active "Generating 0/N blocks..."
# optional intermediate updates as markers appear:
node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" blocks active "3/6 blocks done"
```

When all complete:

```bash
node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" blocks done "All N blocks generated"
```

**Phase 4 — Assembly:**
Follow migrate-page Phase 4 (collect results, assemble page, create preview).

```bash
node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" assembly active "Assembling page..."
```

When complete:

```bash
node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" assembly done "Page assembled"
```

### Step 4 — Deploy

**Mental model — this is the step people get wrong:** in EDS, code (blocks, styles,
icons) is served from the git repo, but page CONTENT is served from the content source
(DA). `git push` alone NEVER produces a live page. Deploy = push code + upload content
to DA + trigger preview.

Push deploy active first:

```bash
node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" deploy active "Publishing content to DA..."
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

**Push to `main`.** The preview/experiment URL serves from `main`
(`https://main--{repo}--{owner}.aem.page/`), so `{ref}` is `main`. If `migrate-page`
created a working branch (its Phase 1 runs `git checkout -b migrate/{slug}-{timestamp}`),
fast-forward-merge it into `main` and push `main` BEFORE triggering preview — otherwise
the code never reaches the ref the experiment serves and the page stays blank:

```bash
git checkout main && git merge --ff-only "migrate/{slug}-{timestamp}" && git push origin main
```

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

**Append a Page Metadata block** as the LAST element of the document, wrapped in its
OWN top-level section `<div>` — in the canonical div form with key/value CELL DIVS, not
`<p>` tags (DA's normalization flattens anything else and strips the class, leaving
visible junk text and no meta tags):

```html
<div>
  <div class="metadata">
    <div><div>title</div><div>{title from .migration/metadata.json}</div></div>
    <div><div>description</div><div>{description from .migration/metadata.json}</div></div>
  </div>
</div>
```

The class must be exactly `metadata` (single lowercase token), and the block MUST be its
own top-level section — a bare `<div class="metadata">` placed directly under `<main>`
is consumed but NOT converted to meta tags (the class disappears, zero
`<title>`/`<meta>`/OG tags emitted, and the title falls back to the H1). Wrapped
correctly, this becomes `<title>`/`<meta name="description">`/OG tags at delivery.

**Symbol characters:** use HTML entities for symbols that may not round-trip through
DA's markdown conversion — `&#169;` (©), `&#8482;` (™), `&#174;` (®). A literal `©` can
arrive as the replacement character `�` on the live page even though it's stored
correctly in `/mnt/da/`. (Em-dash `—` and middot `·` do survive, so this is per-symbol,
not a blanket failure — verify the delivered page after preview.)

#### 4.4 Upload via the mount + trigger preview

```bash
mkdir -p "/mnt/da/$(dirname "$CONTENT_PATH")"
cp "${CONTENT_PATH}.html" "/mnt/da/${CONTENT_PATH}.html"
cp nav.html    /mnt/da/nav.html
cp footer.html /mnt/da/footer.html
```

Then trigger preview for EACH document. The endpoint requires auth (anonymous POSTs
return 401) and the path has NO `.html` extension. SLICC's `curl` does NOT support
`--fail-with-body` (it errors `unrecognized option` and exits non-zero BEFORE making any
request), so capture the status code explicitly and check it — this fails loudly on any
non-2xx and bounds each call with a timeout:

```bash
TOKEN=$(oauth-token adobe)
for doc in "$CONTENT_PATH" nav footer; do
  CODE=$(curl -s -o /tmp/preview-resp -w '%{http_code}' --connect-timeout 10 --max-time 30 \
    -X POST -H "Authorization: Bearer $TOKEN" \
    "https://admin.hlx.page/preview/{owner}/{repo}/{ref}/$doc")
  if [ "$CODE" -lt 200 ] || [ "$CODE" -ge 300 ]; then
    echo "preview trigger failed for $doc (HTTP $CODE) — stopping, do not mark deploy done" >&2
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
footer). Then push deploy done, passing the live URL as the `link`:

```bash
node /workspace/skills/liftoff-demo/scripts/pipeline.js send "$SLUG" deploy done "Live!" "$PREVIEW_URL"
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

## Re-run Behavior

If `/shared/{{REPO}}` already exists (a prior run of this skill for the same target
repo):

- Ask: "I have an existing clone at `/shared/{{REPO}}`. Re-run from scratch, or resume
  from where it left off?"
- If resume: skip Step 2's `git clone`. Check `/shared/{{REPO}}/.migration/` for
  completed-phase markers (`decomposition.json` present = Phases 1-2 already done;
  the Phase 3 completion messages collected last time indicate which blocks are
  done) and resume at the first incomplete phase instead of re-running everything.
- If re-run: `rm -rf /shared/{{REPO}}` and start fresh from Step 1. Always mint a NEW
  sprinkle slug even though the target repo is unchanged (see Key Rules — never reuse
  sprinkle names).

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
- **Sandbox `curl` quirks** — SLICC's `curl` does NOT support `--fail-with-body`; it
  errors `unrecognized option` and exits before making the request. Check HTTP status
  with `-w '%{http_code}'` and an explicit range test instead (see Step 4.4).
