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
- **The cone must NEVER `read_file` a screenshot or other binary** — use
  `open --view --size high <path>` to inspect it. `--fullPage` screenshots here run
  1.4–3 MB; `read_file` on one overflows the cone's context and can cascade into an
  unrecoverable "agent is already processing / context-overflow recovery failed" state
  that needs a human resume. This is the single failure most likely to halt a run.
- **Block scoops must never broadcast previews to followers** — a block scoop verifies
  its work locally with `open` (project-mode preview, no broadcast, no focus grab; the
  mechanism lives in `migrate-block`), never `serve`. Only the cone touches
  follower-visible UI. This restricts *scoops*, not the cone: the orchestration MAY use
  `serve` deliberately when it needs a shareable preview URL for followers — the ban is
  on scoops broadcasting, not on `serve` itself.
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

## Pipeline Updates — use the helpers

Three things MUST happen together on every phase transition: update the
persisted state, rewrite the `.shtml` (so late-joining followers see accumulated
progress, not a blank slate), and issue the `sprinkle send`. Two helpers under
`scripts/` do this so the rule can't be half-done and a dropped timestamp can't
silently disable the live timer. Use them; do NOT hand-roll the send + rewrite.

```bash
# once, at setup — writes state + renders the .shtml (does NOT open the sprinkle):
node /workspace/skills/liftoff-demo/scripts/pipeline.js init "$SLUG" "$URL"

# on every phase transition:
bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" <step> <status> [summary] [link]
```

- `<step>` is one of, in order: `setup`, `extraction`, `decomposition`, `blocks`,
  `assembly`, `deploy`.
- `<status>` is `active`, `done`, or `pending`.
- `active` captures `startedAt` once; `done` captures `completedAt` and keeps the
  original `startedAt`. You never pass timestamps by hand.
- Optional `summary` overrides the step's default line; optional `link` (used on
  `deploy done`) adds a "view ↗" link.
- Between phases: `done` for the finishing step, then `active` for the next.
- State lives at `/shared/sprinkles/{{SLUG}}-pipeline/.state.json`; the helpers
  re-render from the installed template every call, so the `.shtml` and the live
  push never drift.

**Why `psend.sh` and not `pipeline.js send` directly:** in SLICC, node runs in a
realm where `child_process` cannot spawn `sprinkle`, so `pipeline.js` on its own
can only update state + rewrite the `.shtml` + record the payload to
`.last-send.json` (it will NOT crash — it degrades and prints the send line).
`psend.sh` runs `pipeline.js` for the state work and then issues the
`sprinkle send` itself from `.last-send.json`, keeping all three atomic in one
command. If you ever need to push a transition by hand, run `pipeline.js send …`
and then the `sprinkle send …` line it prints.

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
   bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" setup done "Environment ready"
   bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" extraction active "Navigating to page..."
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
bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" extraction active "Capturing page structure..."
```

When complete:

```bash
bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" extraction done "Page captured"
```

**Phase 2 — Decomposition:**
Follow migrate-page Phase 2 (classify visual tree into blocks/sections)
and Phase 2.5 (brand/fonts/styles setup).

```bash
bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" decomposition active "Identifying blocks..."
```

When complete (replace N with the real block count):

```bash
bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" decomposition done "N blocks identified"
```

**Phase 3 — Block Generation:**
Follow migrate-page Phase 3 (create one scoop per block, monitor completion).

**Model pre-flight (do this before the fan-out).** The block configs may pin a model id
that has since been retired (e.g. `claude-opus-4-6` when the environment is on `-4-8`). A
retired id fails the whole fan-out. Verify the config's model exists (`models
--all-versions`) and, if it doesn't, override every scoop to the cone's own model before
creating them — use the returned configs verbatim for the PROMPTS, but not for a stale
model pin.

**Coordinating the block scoops (mute → batched wait):** create ALL block scoops and feed
each its prompt in a single response, then `scoop_mute` every scoop, then issue ONE batched
`scoop_wait` for all of them. Muting prevents each scoop completion from fragmenting the
cone's flow into separate turns; the single wait delivers all completion summaries at once.

**Pre-authorize playwright at scoop-creation time.** Create each scoop with
`writablePaths` including `/.playwright/` (e.g. `["/shared/", "/.playwright/", "/tmp/"]`)
so the six near-simultaneous browser-state writes don't each fire a sudo prompt mid
fan-out. Doing this up front eliminates the approval stalls entirely — do not rely on
reactively approving sudo requests once they appear.

The batched `scoop_wait` only returns once EVERY scoop completes — it cannot itself report
intermediate progress. **For the demo experience, when `N ≥ 3` you SHOULD show live `M/N`
progress** (this skill's whole promise is "live progress the whole way", and block
generation is the longest phase — a silent 0/N→N/N jump is the least-live moment): between
the spawn and the batched wait, poll each scoop's own completion marker (per migrate-page's
monitoring convention) and send an updated `blocks active "M/N blocks done"` each time a
new marker appears, so followers watch `3/6 → 5/6 → 6/6` tick over. Only skip straight from
`0/N` to `N/N` for tiny runs (`N < 3`) where there's nothing meaningful to watch.

```bash
bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" blocks active "Generating 0/N blocks..."
# optional intermediate updates as markers appear:
bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" blocks active "3/6 blocks done"
```

When all complete:

```bash
bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" blocks done "All N blocks generated"
```

**Phase 4 — Assembly:**
Follow migrate-page Phase 4 (collect results, assemble page, create preview).

```bash
bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" assembly active "Assembling page..."
```

When complete:

```bash
bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" assembly done "Page assembled"
```

### Step 4 — Deploy

**Mental model — this is the step people get wrong:** in EDS, code (blocks, styles,
icons) is served from the git repo, but page CONTENT is served from the content source
(DA). `git push` alone NEVER produces a live page. Deploy = push code + upload content
to DA + trigger preview.

Push deploy active first:

```bash
bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" deploy active "Publishing content to DA..."
```

**Target content path:** the init/handoff prompt MUST state where the page is published
(e.g. "publish as `index` at site root"). If it doesn't, default to `index` (site root) —
demo experiment URLs target the root — and say so in the final report. **Rule:** if the
init/done payload's `experimentUrl` is the bare site root, `CONTENT_PATH=index` regardless
of the source page's filename — do NOT derive it from `basecamp.html` etc. (the source
page name and the deploy target are separate facts).

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
merge it into `main` and push `main` BEFORE triggering preview — otherwise the code never
reaches the ref the experiment serves and the page stays blank. Do NOT use
`git merge --ff-only`: the sandbox git parses it as "no branch specified" and fails, then
a naive run pushes an unchanged `main` and serves a blank site. Use a plain merge and
verify `main` actually contains the migration commit before pushing:

```bash
git checkout main
git merge "migrate/{slug}-{timestamp}"
git log --oneline -1 main   # confirm this is the migration commit, not the initial commit
git push origin main
```

#### 4.2 Mount DA (cone-owned)

```bash
mount --source da://{owner}/{repo} /mnt/da
```

Verify the mount before proceeding (`ls /mnt/da` — existing content or empty is fine).
ALL content reads/writes go through this mount. NEVER use `curl` against `admin.da.live`
to write content. The ONLY valid admin API call is triggering preview (step 4.4).

#### 4.3 Build the DA documents

Build the DA upload documents — `${CONTENT_PATH}.html`, `nav.html`, and `footer.html` —
from the assembled outputs (`/shared/{repo-name}/drafts/{page-path}.plain.html` and the
nav/footer fragments).

**Wrap each DA upload document in a `<body>`/`<main>` envelope.** This is NOT the same
artifact as a bare `.plain.html` (those correctly have no html/body). DA derives the
delivered `.plain.html` from the `<main>` of the uploaded document; with NO `<main>`, DA
silently drops everything and delivers an empty page — and upload + preview still return
200, so the failure is invisible until you check the delivered bytes (see the guard in
Step 4.6). Structure every document like this:

```html
<body>
<header></header>
<main>
  <div>
    <div class="hero"> … </div>
  </div>
  <!-- … one top-level section <div> per block, in decomposition order … -->
  <div>
    <div class="metadata">
      <div><div>title</div><div>{title from .migration/metadata.json}</div></div>
      <div><div>description</div><div>{description from .migration/metadata.json}</div></div>
    </div>
  </div>
</main>
<footer></footer>
</body>
```

Still NO `<!DOCTYPE>`, `<html>`, `<head>`, `<script>`, `<style>`, or inline `style=`
attributes — the pipeline injects head/scripts/styles from the code bus. Also:

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

**Page Metadata block** — the LAST section inside `<main>` (shown in the skeleton above):
its own top-level `<div>` wrapping `<div class="metadata">`, with key/value CELL DIVS, not
`<p>` tags (DA's normalization flattens anything else and strips the class). The class
must be exactly `metadata` (single lowercase token). A bare `<div class="metadata">` that
is NOT its own section is consumed but NOT converted — the class disappears, zero
`<title>`/`<meta>`/OG tags are emitted, and the title falls back to the H1. Placed
correctly it becomes `<title>`/`<meta name="description">`/OG tags at delivery — without
it the page has no SEO metadata.

**Symbol characters:** some symbols don't round-trip through DA's markdown conversion — a
literal `©` arrives as the replacement character `�` on the live page even though it's
stored correctly in `/mnt/da/`. Don't rely on remembering to hand-encode; run a fixed
transform on each assembled upload document BEFORE the `cp` to `/mnt/da` (Step 4.4). Use
`|` as the `sed` delimiter — `#` collides with the `&#NNN;` entities and silently fails
with `sed: command expected`:

```bash
for doc in "${CONTENT_PATH}.html" nav.html footer.html; do
  sed -i 's|©|\&#169;|g; s|™|\&#8482;|g; s|®|\&#174;|g' "$doc"
done
```

(Em-dash `—` and middot `·` do survive, so this is per-symbol, not a blanket failure —
still verify the delivered page after preview.)

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

DA ingests external image URLs lazily — on first load, `media_*` derivatives may 404 or
render broken (`naturalWidth == 0`) even though nothing is wrong. Blocks with hidden
containers (tabs/accordion/carousel) are worse: their images aren't in a loadable state
until the pane is activated, so a passive DOM scan under-counts them and a passive
`naturalWidth` read on the visible pane still misleads. Warm everything deterministically:

1. **Reveal hidden panes first.** If any assembled block has hidden panes (a block scoop
   reports `hasHiddenPanes` — see migrate-block; or infer from the decomposition, e.g.
   `tabs`/`accordion`/`carousel`), make every pane visible before enumerating so ALL
   image URLs are discovered and actually load:

   ```bash
   playwright-cli eval --tab={previewTabId} "Array.from(document.querySelectorAll('[hidden],[aria-hidden=\"true\"],[style*=\"display:none\"],[style*=\"display: none\"]')).forEach(function(el){ el.hidden=false; el.removeAttribute('aria-hidden'); el.style.display=''; }); 'revealed'"
   ```

   Then reload/scroll and give the newly-visible images a moment to load.

2. **Enumerate media URLs to a file.** Do NOT pipe into `node` (the sandbox has no
   `process.stdin`/streaming node — see Known Limitations); redirect the eval output and
   parse with `jq`:

   ```bash
   playwright-cli eval --tab={previewTabId} "JSON.stringify((function(){ var urls = Array.from(document.querySelectorAll('img[src], source[srcset]')).flatMap(function(el){ return el.srcset ? el.srcset.split(',').map(function(s){ return s.trim().split(' ')[0]; }) : [el.getAttribute('src')]; }).filter(Boolean); var broken = urls.filter(function(u){ return u === 'about:error' || u === ''; }); var mediaUrls = Array.from(new Set(urls.filter(function(u){ return u.indexOf('media_') !== -1; }).map(function(u){ return new URL(u, location.href).href; }))); return { broken: broken, mediaUrls: mediaUrls }; })())" > /tmp/media.json
   jq -r '.mediaUrls[]' /tmp/media.json > /tmp/media-urls.txt
   ```

3. **Fail loudly, don't just warm and hope:** if `.broken` is non-empty, or `.mediaUrls`
   is empty despite the document containing images, there's a real broken image (exactly
   the hidden-pane failure mode) — report it and do NOT mark deploy done:

   ```bash
   jq -e '.broken | length == 0' /tmp/media.json >/dev/null \
     || { echo "broken images on the page — do NOT mark deploy done" >&2; exit 1; }
   ```

4. **Warm** each URL: `curl -s -o /dev/null -w '%{http_code}'` every line of
   `/tmp/media-urls.txt`; retry with backoff (e.g. 3 attempts, 5s apart) until each
   returns 200. The fetch itself warms the ingestion.

5. **Verify by activation + screenshot, never `naturalWidth` alone.** `naturalWidth == 0`
   is ambiguous — a false negative for icon-decorator SVGs and a transient state for
   still-ingesting media. After warming, navigate again, activate each pane, scroll, and
   confirm real `naturalWidth` values plus a clean screenshot before marking deploy done.

#### 4.6 Poll and confirm

**First, assert the content actually converted — an empty `.plain.html` is the canonical
symptom of a missing `<main>` envelope (Step 4.3) and every other signal (200s) will lie.**
Fetch the delivered `.plain.html` for each document and fail loudly if any is empty or
near-empty BEFORE polling the page or marking deploy done:

```bash
for doc in "$CONTENT_PATH" nav footer; do
  BYTES=$(curl -s "https://{ref}--{repo}--{owner}.aem.page/${doc}.plain.html" | wc -c)
  if [ "$BYTES" -lt 100 ]; then
    echo "$doc.plain.html is empty ($BYTES bytes) — DA dropped the content (missing <main>?). Re-check Step 4.3, re-upload, re-preview. Do NOT mark deploy done." >&2
    exit 1
  fi
done
```

Then poll `{{PREVIEW_URL}}` with a bounded deadline (e.g. every 5s, up to 2 minutes) until
it returns 200 — do NOT poll unbounded; if the deadline is reached without a 200, stop and
report the failure instead of hanging or silently marking deploy done. Once it's live,
reload once more and screenshot to confirm the page renders (fonts, images, header,
footer). Then push deploy done, passing the live URL as the `link`:

```bash
bash /workspace/skills/liftoff-demo/scripts/psend.sh "$SLUG" deploy done "Live!" "$PREVIEW_URL"
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

- `{{BLOCK_COUNT}}` — count the block directories under `blocks/` that this run created
  or modified, INCLUDING auxiliary blocks a scoop spawned (e.g. a `footer-columns`
  sub-block). Prefer the on-disk directories over `decomposition.json` so the number
  reflects what actually shipped (auxiliary sub-blocks make the disk count ≥ the
  decomposition count). If you instead use the decomposition count, keep the label
  "blocks migrated" and note auxiliary sub-blocks are excluded — just be consistent and
  defensible.
- `{{FRAGMENT_COUNT}}` — count the fragment documents uploaded to DA (nav + footer + any
  additional). The page document itself is NOT a fragment and is not counted here.
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

The target repo may also be pre-seeded at `/workspace/{{REPO}}` (the lab may stage it
there). That copy is NOT authoritative for this run — `/shared/{{REPO}}` is the working
clone and the only path the resume check below consults. Ignore `/workspace/{{REPO}}`
unless you deliberately copy from it.

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
- **Sandbox `git` quirks** — `git merge --ff-only <branch>` is misparsed as "no branch
  specified" and fails. Use a plain `git merge <branch>` and verify `main` contains the
  migration commit before pushing (see Step 4.1).
- **`node` cannot spawn `sprinkle`** — in SLICC's realm `child_process.spawnSync` is
  unavailable, so `pipeline.js` can only write state + `.shtml` + `.last-send.json`; use
  `psend.sh` to actually push the update (see Pipeline Updates).
- **Sandbox `node` stdin/streaming unavailable** — `process.stdin`, `readFileSync(0)`,
  and `child_process` all fail in the realm (`process.stdin.on is not a function`,
  `startsWith is not a function`/EBADF). Do NOT pipe data into `node -e`. Pipe JSON to
  `jq`, or write to a temp file and read it with a `*Sync` call. (Applies to the Step 4.5
  media enumeration.)
- **`mount --list` / `mount refresh` are approval-gated** — the initial
  `mount --source … /mnt/da` runs unprompted, but `list`/`refresh` block on interactive
  approval and can stall a run. Avoid them on the hot path; if you need `refresh` to
  confirm a write persisted, expect an approval prompt.
- **`admin.da.live` / `content.da.live` reads are egress-gated** — direct GETs of the DA
  source return empty from the sandbox. Debug via the `/mnt/da/` mount, not direct HTTP;
  an "empty" response there is an egress block, not empty content.
