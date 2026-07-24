# liftoff-demo retrospective fixes — design

Date: 2026-07-24
Branch: `fix-skills-liftoff-retrospective-01`
Status: approved design, ready for implementation planning

## 1. Context

The 2026-07-23 migration retrospective (`RETROSPECTIVE (1).md`, wknd-adventures.com/basecamp.html
→ AEM EDS) documented 18 friction points. The ones scoped to **this repo** all concern the
`liftoff-demo` orchestration skill. The headline finding (retrospective §6.2A): liftoff's Deploy
step models deployment as "git push == live page", which is **false for EDS** — code comes from
git, but page CONTENT comes from a content source (DA). Everything that made the page actually
go live (DA mount, content upload, image URL contract, preview API auth, media warming) had to
be inferred by the operator and consumed the majority of debugging time.

Out of scope (handled in a separate session against `aemcoder/skills`): migrate-page viewport
fix (§2.2), node-runnable scripts (§2.3), migrate-header brand-logo pattern (§2.8), playwright
sudo seeding (§2.4). Also out of scope: SLICC runtime lick-duplication bug and the
`/shared/CLAUDE.md` global-memory carve-out (§2.11) — not files in any repo here.

### Reference material (read before implementing)

| Source | Why |
| --- | --- |
| `liftoff-demo/SKILL.md` (this repo) | The file being changed |
| `liftoff-demo/templates/pipeline.shtml.tpl` | Already renders `startedAt`/`completedAt` timers (lines ~107–228) — no template change needed |
| `liftoff-demo/templates/complete.shtml.tpl` | Renders whatever `stats` array it receives — no template change needed |
| `/Users/catalan/repos/ai/aem-growth-adoption/stardust-demo-skills/stardust-demo/SKILL.md` | Field-tested sibling orchestration skill; source of the DA mount contract, timestamp rules, Step-0 verification gate, openssl fallback |
| `/Users/catalan/repos/ai/aemcoder/skills/skills/eds-da-content/SKILL.md` + `references/html-content.md` | `[verified]` DA/EDS content rules: body-fragment constraint, canonical Page Metadata block shape, image sideloading semantics, preview API contract |
| `/Users/catalan/repos/ai/aemcoder/skills/skills/migration/migrate-page/SKILL.md` Phase 4 | Defines the artifacts liftoff's Step 4 consumes: `/shared/{repo-name}/drafts/{page-path}.plain.html` (images as root-relative `/drafts/images/...`), nav/footer fragments, `.migration/metadata.json` |

## 2. Goals

1. Rewrite Step 4 into a self-contained, correct deploy runbook (DA mount → build documents →
   image src rewrite → metadata block → upload → authed preview → media warming → poll).
2. Add a Step 0 verification gate (skills present, migrate-page sprinkle closed).
3. Portable slug derivation with an explicit multi-label hostname rule.
4. Activate the pipeline timers by documenting `startedAt`/`completedAt` in every update.
5. Replace the fabricated "~90% visual match" stat with counted facts.
6. Add a Phase-3 scoop coordination note (mute → batched wait).
7. Key Rules / Known Limitations touch-ups: image guidance in the right place, sprinkle-ownership
   rationale, explicit target content path, DA normalization + lazy ingestion gotchas.

Non-goals: no template changes; no changes to migrate-page or any other skill; no computed
visual-similarity metric (YAGNI for a demo); no restructuring of the parts the retrospective
praised (phase model, state persistence, two-sprinkle split).

## 3. Files changed

- `liftoff-demo/SKILL.md` — only file modified.
- `liftoff-demo/templates/*.tpl` — **unchanged** (verify this stays true).

## 4. Change specification

Each subsection names the SKILL.md anchor (current heading or text), the operation, and the
target content. Where full replacement markdown is given, use it verbatim (adjusting only if
surrounding text drifted).

### 4.1 Slug Derivation — replace section body

Replace the body of the `## Slug Derivation` section with:

````markdown
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
4. Append `-` + 4 random hex chars. Generate them with node — do NOT assume `openssl`
   exists in the sandbox:

   ```bash
   node -e "console.log(require('crypto').randomBytes(2).toString('hex'))"
   ```
````

Fixes retrospective §2.1 (openssl absent) and §6.2B (multi-label hostname ambiguity).

### 4.2 Pipeline timestamps — extend `## Pipeline Sprinkle Updates`

The pipeline template already renders per-step duration timers from `startedAt`/`completedAt`
(epoch ms) — but the skill never tells the cone to send them, so timers never appear.

1. Change the documented send format to:

   ```
   sprinkle send {{SLUG}}-pipeline '{"step":"<id>","status":"active|done","summary":"...","link":"...","startedAt":<epoch_ms>,"completedAt":<epoch_ms>}'
   ```

2. Insert, after the format line, a **Timestamp rules** block (adapted from stardust-demo):

   ````markdown
   Timestamp rules:
   - When sending `"status":"active"`: include `"startedAt":<now_ms>` (capture BEFORE the
     phase starts)
   - When sending `"status":"done"`: include `"completedAt":<now_ms>` (and the phase's
     original `"startedAt"` so late joiners compute the elapsed time)
   - Capture timestamps with: `TIMESTAMP=$(date +%s000)` (epoch milliseconds)
   - The pipeline template renders live duration timers from these fields — omitting them
     silently disables the timers
   ````

3. Update **every** `sprinkle send {{SLUG}}-pipeline ...` example throughout the Procedure
   (Steps 1–4) to carry the appropriate timestamp fields, following the stardust-demo pattern
   (e.g. `'{"step":"extraction","status":"active","summary":"...","startedAt":'$TS'}'`).
4. Update the `{{INITIAL_STATE_JSON}}` example in Step 1 so every step object includes
   `"startedAt":null,"completedAt":null` (and `setup` gets a real `startedAt`), and extend the
   State Persistence procedure item 1 to say statuses **and timestamps** must be updated when
   rewriting the `.shtml`.

### 4.3 New `### Step 0 — Verify prerequisites` (before current Step 1)

Insert into the `## Procedure` section, before Step 1:

````markdown
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
````

Also: in current Step 2, replace item 2 ("Verify the migration skills are installed (they
should be from the init prompt)") with "Migration skills were already verified in Step 0."
The Prerequisites section keeps its bullets but the sprinkle-close bullet gains
"(enforced by Step 0)".

Fixes §6.2H (fragile sprinkle-close dependency) and softens §6.2C (fail fast on drift
instead of silently breaking).

### 4.4 Step 3 — add "Coordinating Phase 3" note

Inside Step 3, in the **Phase 3 — Block Generation** block (after the migrate-page reference,
before the `sprinkle send` examples), insert:

````markdown
**Coordinating the block scoops (mute → batched wait):** create ALL block scoops and feed
each its prompt in a single response, then `scoop_mute` every scoop, then issue ONE batched
`scoop_wait` for all of them. Muting prevents each scoop completion from fragmenting the
cone's flow into separate turns; the single wait delivers all completion summaries at once.
Push `M/N blocks done` pipeline updates as completions arrive.
````

Fixes §6.2G.

### 4.5 Step 4 — Deploy: full rewrite (the headline change)

Replace the entire `### Step 4 — Deploy` section (currently 4 numbered lines) with the
runbook below. This is the core fix for §6.2A, and folds in §2.5 (preview auth), §2.6a
(image URL contract), §2.6b/c (media warming, incl. hidden panes), §2.7 (DA-native metadata),
§2.9 (naturalWidth unreliability), §2.10 (target content path), §6.2F (image guidance in
deploy context).

````markdown
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

The preview URL derives as:

```
PREVIEW_URL = https://{ref}--{repo}--{owner}.aem.page/{content-path}
```

where `{ref}` is the branch (usually `main`) and `{content-path}` is empty for the
site root.

**Target content path:** the init/handoff prompt MUST state where the page is published
(e.g. "publish as `index` at site root"). If it doesn't, default to `index` (site root) —
demo experiment URLs target the root — and say so in the final report.

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

Build `index.html` (or `{content-path}.html`), `nav.html`, and `footer.html` from the
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
cp index.html /mnt/da/index.html
cp nav.html   /mnt/da/nav.html
cp footer.html /mnt/da/footer.html
```

Then trigger preview for EACH document. The endpoint requires auth (anonymous POSTs
return 401) and the path has NO `.html` extension:

```bash
TOKEN=$(oauth-token adobe)
for doc in index nav footer; do
  curl -X POST -H "Authorization: Bearer $TOKEN" \
    "https://admin.hlx.page/preview/{owner}/{repo}/{ref}/$doc"
done
```

#### 4.5 Warm the media pipeline

DA ingests external image URLs lazily — on the first page loads, `media_*` derivatives
may 404 or render broken (`naturalWidth == 0`) even though nothing is wrong. Images in
hidden containers (e.g. inactive tab panes) never trigger a load at all and stay
un-ingested until a user clicks. Warm everything deterministically:

1. Open `{{PREVIEW_URL}}` in playwright and extract ALL media URLs from the DOM —
   including hidden elements:

   ```bash
   playwright-cli eval --tab={previewTabId} "JSON.stringify(Array.from(new Set(Array.from(document.querySelectorAll('img[src], source[srcset]')).flatMap(function(el){ return el.srcset ? el.srcset.split(',').map(function(s){ return s.trim().split(' ')[0]; }) : [el.getAttribute('src')]; }).filter(function(u){ return u && u.indexOf('media_') !== -1; }).map(function(u){ return new URL(u, location.href).href; }))))"
   ```

2. `curl -s -o /dev/null -w '%{http_code}'` each URL; retry with backoff (e.g. 3 attempts,
   5s apart) until every one returns 200. The fetch itself warms the ingestion.

**Verification rule:** `naturalWidth == 0` is ambiguous — it is a false negative for
SVGs sized by the icon decorator, and a transient state for still-ingesting media. Judge
images by HTTP status of the media URL + a screenshot, never by `naturalWidth` alone.

#### 4.6 Poll and confirm

Poll `{{PREVIEW_URL}}` until it returns 200, then reload once more and screenshot to
confirm the page renders (fonts, images, header, footer). Then push deploy done:

```
DEPLOY_DONE=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"deploy","status":"done","summary":"Live!","link":"{{PREVIEW_URL}}","startedAt":'$DEPLOY_START',"completedAt":'$DEPLOY_DONE'}'
```
````

Implementation note: the inner numbering `4.1`–`4.6` uses `####` headings so the outer
`### Step 4` anchor keeps its position in the Procedure flow.

### 4.6 Step 5 — honest completion stats

In the Step 5 data-island example, replace the `stats` array:

```json
"stats": [
  { "value": "6", "label": "blocks migrated" },
  { "value": "3", "label": "fragments created" },
  { "value": "24", "label": "media assets published" }
]
```

and add immediately after the JSON example:

````markdown
**Stats must be real counts** (blocks from the decomposition, fragments and media URLs
from Step 4). Never report a metric the pipeline didn't compute — there is no visual-match
measurement, so do not present one; describe fidelity qualitatively in chat if asked.
````

Fixes §6.2E.

### 4.7 Key Rules — amendments

In `## Key Rules`:

1. Extend the first rule to carry its rationale:

   ````markdown
   - **Cone owns ALL `sprinkle send` calls** — never delegate pipeline updates to scoops.
     This is a deliberate exception to the usual "delegate work to scoops" guidance:
     only the cone sees every phase transition, and scoops busy with block work skip or
     forget updates.
   ````

2. Add two rules:

   ````markdown
   - **All DA content operations go through the mount** (`/mnt/da/`) — never `curl`
     `admin.da.live` to write content. The only admin API use is the authed preview
     trigger (`POST admin.hlx.page/preview/...`).
   - **The target content path must be explicit** — take it from the init/handoff
     prompt; default to `index` (site root) and state the assumption in the report.
   ````

Fixes §6.2D (from this repo's side) and §2.10.

### 4.8 Known Limitations — amendments

1. Rescope the image bullet so it's clearly about sprinkle payloads only:

   ````markdown
   - **Sprinkle file size limit** — keep each `.shtml` under ~350KB. Reference images
     by URL in sprinkle payloads rather than base64-embedding. (Image handling for PAGE
     CONTENT is covered in Step 4.3.)
   ````

2. Add two bullets:

   ````markdown
   - **DA normalizes HTML on write** — malformed blocks (wrong cell structure, stray
     `<p>` children) are silently flattened and lose their class. If a block "disappears"
     on the live page, re-read the stored HTML from `/mnt/da/` and compare against the
     canonical shape; your original markup is gone, so match on visible text.
   - **DA media ingestion is lazy** — first preview after upload may show broken images
     for a while. Warm derivatives per Step 4.5 before judging anything broken.
   ````

Fixes §6.2F placement and documents the §2.6/§2.7 failure modes.

## 5. Traceability matrix

| Retrospective item | Fix location (this design) |
| --- | --- |
| §2.1 openssl missing | 4.1 slug rules |
| §2.5 preview 401 | 4.5 runbook step 4.4 |
| §2.6a root-relative img → about:error | 4.5 runbook step 4.3 |
| §2.6b lazy media ingestion | 4.5 runbook step 4.5; 4.8 known limitation |
| §2.6c hidden-pane images never warm | 4.5 runbook step 4.5 (querySelectorAll incl. hidden) |
| §2.7 metadata flattened / SEO lost | 4.5 runbook step 4.3 (canonical metadata block); 4.8 |
| §2.9 naturalWidth false negatives | 4.5 runbook step 4.5 verification rule |
| §2.10 content path inference | 4.5 runbook preamble; 4.7 key rule |
| §2.11 / §6.2D sprinkle ownership conflict | 4.7 rationale (repo-side half; global memory carve-out is external) |
| §6.2A deploy step false mental model | 4.5 entire runbook |
| §6.2B slug hostname ambiguity | 4.1 |
| §6.2C coupling to migrate-page | 4.3 fail-fast gate (mitigation, not elimination) |
| §6.2E fabricated visual-match stat | 4.6 |
| §6.2F image hint mis-scoped | 4.5 step 4.3 + 4.8 rescoped bullet |
| §6.2G Phase-3 coordination | 4.4 |
| §6.2H migrate-page sprinkle re-opening | 4.3 Step 0 (idempotent close + re-close note) |
| Timer fields never sent (found during design) | 4.2 |

## 6. Verification

1. **Traceability pass:** every row in §5 maps to a hunk in the final diff of
   `liftoff-demo/SKILL.md`. No row unaddressed.
2. **Syntax checks:** extract each bash snippet from the new Step 4 and run `bash -n`
   on it; parse each JSON example with `node -e 'JSON.parse(...)'` (the sprinkle send
   payloads after shell-var substitution with a dummy value).
3. **Template invariance:** `git diff --stat` shows only `liftoff-demo/SKILL.md` changed
   (plus this spec and the plan doc).
4. **Consistency read:** one full read of the updated SKILL.md checking (a) every
   `sprinkle send` example carries timestamps, (b) step numbering is coherent after
   inserting Step 0, (c) no remaining reference to `openssl`, (d) no remaining
   "~90%"/"visual match" stat, (e) Step 2 no longer duplicates Step 0's verification.
5. **Optional live test** (per repo AGENTS.md): `upskill aem-growth-adoption/slicc-demo-skills
   --skill liftoff-demo` in a Slicc cone and invoke the skill by name.

## 7. Risks / notes

- The DA mount + preview contract is copied from stardust-demo, which runs in the same
  SLICC environment and was field-tested; eds-da-content marks the underlying platform
  facts `[verified]`.
- The code-bus image URL alternative in step 4.3 is intentionally labeled "verify with
  curl first" — the retrospective only verified source-site absolute URLs.
- Step numbering: the runbook's `#### 4.1`–`#### 4.6` sub-headings coexist with the
  design's own §4.x numbering only in this document; in SKILL.md there is no collision.
