# liftoff-demo Retrospective Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all liftoff-demo-scoped findings from the 2026-07-23 migration retrospective — chiefly rewriting the Deploy step into a correct, self-contained DA content-publish runbook.

**Architecture:** Documentation-only change to a single skill file, `liftoff-demo/SKILL.md`. The skill's two `.shtml.tpl` templates already support everything the new instructions require (duration timers, arbitrary stats) and MUST NOT change. Every task is a targeted text edit with a mechanical verification step.

**Tech Stack:** Markdown (Slicc SKILL.md format), bash snippets, JSON sprinkle payloads.

**Spec:** `docs/superpowers/specs/2026-07-24-liftoff-demo-retrospective-fixes-design.md` — read it first; it contains the rationale and the traceability matrix (spec §5) that the final task verifies.

## Global Constraints

- Only `liftoff-demo/SKILL.md` may change. `git diff --stat` at the end must show no template (`liftoff-demo/templates/*.tpl`) changes.
- No `openssl` anywhere in the final file.
- No "~90%" / "visual match" stat anywhere in the final file.
- Every `sprinkle send {{SLUG}}-pipeline` example in the final file carries `startedAt` and/or `completedAt` per the timestamp rules (Task 2).
- Preview auth is always `Authorization: Bearer $(oauth-token adobe)` (or a `TOKEN=$(oauth-token adobe)` variable) — never anonymous.
- DA content writes go through the mount (`/mnt/da/`); the only `admin.hlx.page` call is `POST /preview/...`.
- **Environment gotcha:** file writes in this workspace may be auto-fixed by markdownlint on save. If a write/edit reports "File was modified by auto-format", re-read the file before the next edit — never edit from memory.
- Work in the current worktree: `/Users/catalan/repos/ai/aem-growth-adoption/slicc-demo-skills/.worktrees/fix-skills-liftoff-retrospective-01`.

---

### Task 1: Portable slug derivation

**Files:**

- Modify: `liftoff-demo/SKILL.md` (section `## Slug Derivation`, ~lines 40–48)

**Interfaces:**

- Produces: nothing later tasks depend on (self-contained section).

- [ ] **Step 1: Read the current section**

Read `liftoff-demo/SKILL.md` and locate the `## Slug Derivation` section. Its current body is:

````markdown
Derive from URL hostname + path + 4 random hex chars:
- `https://www.adobe.com/products/photoshop` → `adobe-photoshop-a3f1`
- `https://wknd.site/basecamp` → `wknd-basecamp-9c2e`

Strip `www.`, take hostname first segment + last path segment, lowercase,
append `-$(openssl rand -hex 2)`.
````

- [ ] **Step 2: Replace the section body**

Replace the body above (everything between the `## Slug Derivation` heading and the next `##` heading) with exactly:

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

- [ ] **Step 3: Verify**

Run: `grep -c openssl liftoff-demo/SKILL.md`
Expected: `0` (exit code 1 from grep is the pass signal)

Run: `grep -c "wknd-adventures-basecamp" liftoff-demo/SKILL.md`
Expected: `1`

- [ ] **Step 4: Commit**

```bash
git add liftoff-demo/SKILL.md
git commit -m "fix(liftoff-demo): portable slug command + multi-label hostname rule"
```

---

### Task 2: Pipeline timestamps — rules, initial state, Step 1–2 sends

**Files:**

- Modify: `liftoff-demo/SKILL.md` (section `## Pipeline Sprinkle Updates` ~lines 50–75; `### Step 1` ~lines 79–103; `### Step 2` ~lines 105–113)

**Interfaces:**

- Produces: shell variable naming convention used by Tasks 3 and 5 — `START_TS` (setup), `EXTRACT_START`/`EXTRACT_DONE`, `DECOMP_START`/`DECOMP_DONE`, `BLOCKS_START`/`BLOCKS_DONE`, `ASSEMBLY_START`/`ASSEMBLY_DONE`, `DEPLOY_START`/`DEPLOY_DONE`, all captured as `$(date +%s000)` epoch-ms.

- [ ] **Step 1: Update the send format line**

In `## Pipeline Sprinkle Updates`, replace:

```text
Format: `sprinkle send {{SLUG}}-pipeline '{"step":"<id>","status":"active|done","summary":"...","link":"..."}'`
```

with:

```text
Format: `sprinkle send {{SLUG}}-pipeline '{"step":"<id>","status":"active|done","summary":"...","link":"...","startedAt":<epoch_ms>,"completedAt":<epoch_ms>}'`
```

- [ ] **Step 2: Insert the Timestamp rules block**

Immediately after the format line (before `Step IDs in order:`), insert:

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

- [ ] **Step 3: Extend State Persistence item 1**

In `### State Persistence`, replace:

```text
1. Update your in-memory steps array with the new status
```

with:

```text
1. Update your in-memory steps array with the new status AND timestamps (`startedAt`, `completedAt`)
```

- [ ] **Step 4: Update Step 1's initial state and first send**

In `### Step 1 — Setup & open pipeline sprinkle`, replace item 4's JSON block. Current:

````markdown
4. Replace `{{INITIAL_STATE_JSON}}` with the initial state (setup=active, rest pending):
   ```json
   {"steps":[
     {"id":"setup","status":"active","summary":"Cloning repo & preparing environment...","link":null},
     {"id":"extraction","status":"pending","summary":"Capture page structure & brand","link":null},
     {"id":"decomposition","status":"pending","summary":"Identify blocks & sections","link":null},
     {"id":"blocks","status":"pending","summary":"Generate EDS blocks in parallel","link":null},
     {"id":"assembly","status":"pending","summary":"Assemble page & create preview","link":null},
     {"id":"deploy","status":"pending","summary":"Commit & push to EDS","link":null}
   ]}
   ```
````

New:

````markdown
4. Capture the start timestamp: `START_TS=$(date +%s000)`, then replace
   `{{INITIAL_STATE_JSON}}` with the initial state (setup=active, rest pending):
   ```json
   {"steps":[
     {"id":"setup","status":"active","summary":"Cloning repo & preparing environment...","link":null,"startedAt":<START_TS>,"completedAt":null},
     {"id":"extraction","status":"pending","summary":"Capture page structure & brand","link":null,"startedAt":null,"completedAt":null},
     {"id":"decomposition","status":"pending","summary":"Identify blocks & sections","link":null,"startedAt":null,"completedAt":null},
     {"id":"blocks","status":"pending","summary":"Generate EDS blocks in parallel","link":null,"startedAt":null,"completedAt":null},
     {"id":"assembly","status":"pending","summary":"Assemble page & create preview","link":null,"startedAt":null,"completedAt":null},
     {"id":"deploy","status":"pending","summary":"Commit & push to EDS","link":null,"startedAt":null,"completedAt":null}
   ]}
   ```
````

Then in item 7, replace:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"setup","status":"active","summary":"Cloning repo & preparing environment..."}'
```

with:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"setup","status":"active","summary":"Cloning repo & preparing environment...","startedAt":'$START_TS'}'
```

- [ ] **Step 5: Update Step 2's sends**

In `### Step 2 — Clone repo & verify environment` item 3, replace:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"setup","status":"done","summary":"Environment ready"}'
sprinkle send {{SLUG}}-pipeline '{"step":"extraction","status":"active","summary":"Navigating to page..."}'
```

with:

```text
SETUP_DONE=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"setup","status":"done","summary":"Environment ready","startedAt":'$START_TS',"completedAt":'$SETUP_DONE'}'
EXTRACT_START=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"extraction","status":"active","summary":"Navigating to page...","startedAt":'$EXTRACT_START'}'
```

- [ ] **Step 6: Verify**

Run: `grep -c "startedAt" liftoff-demo/SKILL.md`
Expected: ≥ 12 (format line, 4 rule lines mention it once, 6 initial-state entries, Step 1 send, Step 2 sends)

Validate a substituted payload parses:

```bash
node -e 'JSON.parse(`{"step":"setup","status":"done","summary":"Environment ready","startedAt":1753000000000,"completedAt":1753000005000}`); console.log("OK")'
```

Expected: `OK`

- [ ] **Step 7: Commit**

```bash
git add liftoff-demo/SKILL.md
git commit -m "feat(liftoff-demo): send startedAt/completedAt so pipeline timers render"
```

---

### Task 3: Pipeline timestamps — Step 3 phase sends

**Files:**

- Modify: `liftoff-demo/SKILL.md` (`### Step 3` phase blocks, ~lines 115–170)

**Interfaces:**

- Consumes: variable convention from Task 2 (`EXTRACT_START`, `DECOMP_*`, `BLOCKS_*`, `ASSEMBLY_*`).

- [ ] **Step 1: Phase 1 sends**

Replace the Phase 1 "active" send:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"extraction","status":"active","summary":"Capturing page structure..."}'
```

with:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"extraction","status":"active","summary":"Capturing page structure...","startedAt":'$EXTRACT_START'}'
```

Replace the Phase 1 "done" send:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"extraction","status":"done","summary":"Page captured"}'
```

with:

```text
EXTRACT_DONE=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"extraction","status":"done","summary":"Page captured","startedAt":'$EXTRACT_START',"completedAt":'$EXTRACT_DONE'}'
```

- [ ] **Step 2: Phase 2 sends**

Replace:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"decomposition","status":"active","summary":"Identifying blocks..."}'
```

with:

```text
DECOMP_START=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"decomposition","status":"active","summary":"Identifying blocks...","startedAt":'$DECOMP_START'}'
```

Replace:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"decomposition","status":"done","summary":"N blocks identified"}'
```

with:

```text
DECOMP_DONE=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"decomposition","status":"done","summary":"N blocks identified","startedAt":'$DECOMP_START',"completedAt":'$DECOMP_DONE'}'
```

- [ ] **Step 3: Phase 3 sends**

Replace:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"blocks","status":"active","summary":"Generating 0/N blocks..."}'
```

with:

```text
BLOCKS_START=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"blocks","status":"active","summary":"Generating 0/N blocks...","startedAt":'$BLOCKS_START'}'
```

Replace:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"blocks","status":"active","summary":"3/6 blocks done"}'
```

with:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"blocks","status":"active","summary":"3/6 blocks done","startedAt":'$BLOCKS_START'}'
```

Replace:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"blocks","status":"done","summary":"All N blocks generated"}'
```

with:

```text
BLOCKS_DONE=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"blocks","status":"done","summary":"All N blocks generated","startedAt":'$BLOCKS_START',"completedAt":'$BLOCKS_DONE'}'
```

- [ ] **Step 4: Phase 4 sends**

Replace:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"assembly","status":"active","summary":"Assembling page..."}'
```

with:

```text
ASSEMBLY_START=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"assembly","status":"active","summary":"Assembling page...","startedAt":'$ASSEMBLY_START'}'
```

Replace:

```text
sprinkle send {{SLUG}}-pipeline '{"step":"assembly","status":"done","summary":"Page assembled"}'
```

with:

```text
ASSEMBLY_DONE=$(date +%s000)
sprinkle send {{SLUG}}-pipeline '{"step":"assembly","status":"done","summary":"Page assembled","startedAt":'$ASSEMBLY_START',"completedAt":'$ASSEMBLY_DONE'}'
```

- [ ] **Step 5: Verify no bare sends remain in Steps 1–3**

Run:

```bash
grep -n 'sprinkle send {{SLUG}}-pipeline' liftoff-demo/SKILL.md | grep -v 'startedAt' | grep -v 'completedAt'
```

Expected: only lines from the not-yet-rewritten Step 4 deploy send (fixed in Task 5). If any other line appears, fix it.

- [ ] **Step 6: Commit**

```bash
git add liftoff-demo/SKILL.md
git commit -m "feat(liftoff-demo): timestamps on all Step 3 phase sends"
```

---

### Task 4: Step 0 verification gate + prerequisite cleanup

**Files:**

- Modify: `liftoff-demo/SKILL.md` (`## Prerequisites` ~lines 21–27; `## Procedure` heading ~line 77; `### Step 2` item 2)

**Interfaces:**

- Produces: `### Step 0 — Verify prerequisites` heading that Step 2 references by name.

- [ ] **Step 1: Insert Step 0**

Immediately after the `## Procedure` line (before `### Step 1 — Setup & open pipeline sprinkle`), insert:

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

- [ ] **Step 2: De-duplicate Step 2 item 2**

In `### Step 2 — Clone repo & verify environment`, replace:

```text
2. Verify the migration skills are installed (they should be from the init prompt)
```

with:

```text
2. Migration skills were already verified in Step 0
```

- [ ] **Step 3: Annotate the Prerequisites bullet**

In `## Prerequisites`, replace:

```text
- The `migrate-page` sprinkle must be closed after install (`sprinkle close migrate-page`)
  because it conflicts with our pipeline sprinkle.
```

with:

```text
- The `migrate-page` sprinkle must be closed after install (`sprinkle close migrate-page`)
  because it conflicts with our pipeline sprinkle (enforced by Step 0).
```

- [ ] **Step 4: Verify**

Run: `grep -c "Step 0" liftoff-demo/SKILL.md`
Expected: `3` (heading, Step 2 reference, Prerequisites reference)

- [ ] **Step 5: Commit**

```bash
git add liftoff-demo/SKILL.md
git commit -m "feat(liftoff-demo): add Step 0 prerequisite verification gate"
```

---

### Task 5: Step 4 deploy runbook rewrite (headline change)

**Files:**

- Modify: `liftoff-demo/SKILL.md` (entire `### Step 4 — Deploy` section, currently ~lines 172–182)

**Interfaces:**

- Consumes: timestamp convention from Task 2 (`DEPLOY_START`/`DEPLOY_DONE`).
- Produces: `{{PREVIEW_URL}}` derivation and step anchors `4.1`–`4.6` referenced by Tasks 6 and 7.

- [ ] **Step 1: Replace the whole Step 4 section**

The current section is:

````markdown
### Step 4 — Deploy

After assembly completes:

1. Ensure all changes are committed and pushed to the repo
2. Trigger EDS preview for the migrated page
3. Wait for the preview to be live (poll the URL)
4. Push deploy done:
   ```
   sprinkle send {{SLUG}}-pipeline '{"step":"deploy","status":"done","summary":"Live!","link":"{{PREVIEW_URL}}"}'
   ```
````

Replace it in full (up to, not including, `### Step 5`) with the runbook below — copy verbatim:

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

- [ ] **Step 2: Verify bash snippets parse**

```bash
bash -n <(cat <<'EOF'
TOKEN=$(oauth-token adobe)
for doc in index nav footer; do
  curl -X POST -H "Authorization: Bearer $TOKEN" \
    "https://admin.hlx.page/preview/owner/repo/ref/$doc"
done
EOF
) && echo SYNTAX_OK
```

Expected: `SYNTAX_OK`

- [ ] **Step 3: Verify section content markers**

```bash
grep -c "admin.hlx.page/preview" liftoff-demo/SKILL.md   # expected ≥ 1
grep -c "oauth-token adobe" liftoff-demo/SKILL.md        # expected ≥ 1
grep -c "/mnt/da" liftoff-demo/SKILL.md                  # expected ≥ 3
grep -c 'class="metadata"' liftoff-demo/SKILL.md         # expected 1
grep -c "about:error" liftoff-demo/SKILL.md              # expected 1
grep -n 'sprinkle send {{SLUG}}-pipeline' liftoff-demo/SKILL.md | grep -v -e startedAt -e completedAt
# expected: no output (every send now carries timestamps)
```

- [ ] **Step 4: Commit**

```bash
git add liftoff-demo/SKILL.md
git commit -m "feat(liftoff-demo): rewrite Step 4 into a concrete DA deploy runbook"
```

---

### Task 6: Honest completion stats (Step 5)

**Files:**

- Modify: `liftoff-demo/SKILL.md` (`### Step 5 — Open completion sprinkle` data-island example, ~lines 190–200)

**Interfaces:**

- Consumes: "media URLs from Step 4" refers to the warm list produced in runbook step 4.5 (Task 5).

- [ ] **Step 1: Replace the stats array**

In the Step 5 `{{COMPLETE_JSON}}` example, replace:

```json
     "stats": [
       { "value": "6", "label": "blocks migrated" },
       { "value": "3", "label": "fragments created" },
       { "value": "~90%", "label": "visual match" }
     ],
```

with:

```json
     "stats": [
       { "value": "6", "label": "blocks migrated" },
       { "value": "3", "label": "fragments created" },
       { "value": "24", "label": "media assets published" }
     ],
```

- [ ] **Step 2: Add the real-counts rule**

Immediately after the closing of the data-island JSON example (after its closing code fence, before item 4 "Write to ..."), insert:

````markdown
**Stats must be real counts** (blocks from the decomposition, fragments and media URLs
from Step 4). Never report a metric the pipeline didn't compute — there is no visual-match
measurement, so do not present one; describe fidelity qualitatively in chat if asked.
````

- [ ] **Step 3: Verify**

Run: `grep -c "visual match" liftoff-demo/SKILL.md`
Expected: `0` (grep exit code 1)

Run: `grep -c "media assets published" liftoff-demo/SKILL.md`
Expected: `1` (the stats example)

Run: `grep -c "Stats must be real counts" liftoff-demo/SKILL.md`
Expected: `1` (the rule paragraph)

- [ ] **Step 4: Commit**

```bash
git add liftoff-demo/SKILL.md
git commit -m "fix(liftoff-demo): replace fabricated visual-match stat with real counts"
```

---

### Task 7: Phase-3 coordination note + Key Rules + Known Limitations

**Files:**

- Modify: `liftoff-demo/SKILL.md` (`### Step 3` Phase 3 block; `## Key Rules` ~lines 29–33; `## Known Limitations` last section)

**Interfaces:**

- Consumes: "Step 4.3" / "Step 4.5" anchors from Task 5.

- [ ] **Step 1: Insert the Phase-3 coordination note**

In Step 3's **Phase 3 — Block Generation** block, immediately after the line
`Follow migrate-page Phase 3 (create one scoop per block, monitor completion).`, insert:

````markdown
**Coordinating the block scoops (mute → batched wait):** create ALL block scoops and feed
each its prompt in a single response, then `scoop_mute` every scoop, then issue ONE batched
`scoop_wait` for all of them. Muting prevents each scoop completion from fragmenting the
cone's flow into separate turns; the single wait delivers all completion summaries at once.
Push `M/N blocks done` pipeline updates as completions arrive.
````

- [ ] **Step 2: Extend the sprinkle-ownership rule**

In `## Key Rules`, replace:

```text
- **Cone owns ALL `sprinkle send` calls** — never delegate pipeline updates to scoops
```

with:

```text
- **Cone owns ALL `sprinkle send` calls** — never delegate pipeline updates to scoops.
  This is a deliberate exception to the usual "delegate work to scoops" guidance:
  only the cone sees every phase transition, and scoops busy with block work skip or
  forget updates.
```

- [ ] **Step 3: Add two Key Rules**

Append to the `## Key Rules` bullet list:

```text
- **All DA content operations go through the mount** (`/mnt/da/`) — never `curl`
  `admin.da.live` to write content. The only admin API use is the authed preview
  trigger (`POST admin.hlx.page/preview/...`).
- **The target content path must be explicit** — take it from the init/handoff
  prompt; default to `index` (site root) and state the assumption in the report.
```

- [ ] **Step 4: Rescope the Known Limitations image bullet**

In `## Known Limitations`, replace:

```text
- **Sprinkle file size limit** — keep under ~350KB. Use EDS URLs for images.
```

with:

```text
- **Sprinkle file size limit** — keep each `.shtml` under ~350KB. Reference images
  by URL in sprinkle payloads rather than base64-embedding. (Image handling for PAGE
  CONTENT is covered in Step 4.3.)
```

- [ ] **Step 5: Add two Known Limitations bullets**

Append to the `## Known Limitations` bullet list:

```text
- **DA normalizes HTML on write** — malformed blocks (wrong cell structure, stray
  `<p>` children) are silently flattened and lose their class. If a block "disappears"
  on the live page, re-read the stored HTML from `/mnt/da/` and compare against the
  canonical shape; your original markup is gone, so match on visible text.
- **DA media ingestion is lazy** — first preview after upload may show broken images
  for a while. Warm derivatives per Step 4.5 before judging anything broken.
```

- [ ] **Step 6: Verify**

```bash
grep -c "scoop_mute" liftoff-demo/SKILL.md        # expected 1
grep -c "deliberate exception" liftoff-demo/SKILL.md  # expected 1
grep -c "DA normalizes HTML" liftoff-demo/SKILL.md    # expected 1
```

- [ ] **Step 7: Commit**

```bash
git add liftoff-demo/SKILL.md
git commit -m "docs(liftoff-demo): phase-3 coordination note, key rules, known limitations"
```

---

### Task 8: Final verification sweep

**Files:**

- Read: `liftoff-demo/SKILL.md` (full)
- Read: `docs/superpowers/specs/2026-07-24-liftoff-demo-retrospective-fixes-design.md` (§5 matrix, §6 checks)

**Interfaces:**

- Consumes: everything above.

- [ ] **Step 1: Global constraint greps**

```bash
grep -n "openssl" liftoff-demo/SKILL.md                       # expected: no output
grep -n "visual match\|~90%" liftoff-demo/SKILL.md            # expected: no output
grep -n 'sprinkle send {{SLUG}}-pipeline' liftoff-demo/SKILL.md | grep -v -e startedAt -e completedAt
                                                              # expected: no output
git diff main --stat -- liftoff-demo/templates/               # expected: no output
```

- [ ] **Step 2: Traceability pass**

Open spec §5 and confirm each of the 17 rows maps to a hunk in `git diff main -- liftoff-demo/SKILL.md`. Every row must be traceable; if one isn't, go back to the task that owns it.

- [ ] **Step 3: Full consistency read**

Read the entire updated `liftoff-demo/SKILL.md` top to bottom and check:

- (a) every `sprinkle send` example carries timestamps
- (b) step numbering is coherent: Step 0, 1, 2, 3, 4 (with 4.1–4.6), 5, 6
- (c) Step 2 references Step 0 instead of duplicating verification
- (d) no section contradicts another (e.g. Known Limitations vs Step 4.3 image guidance)
- (e) the frontmatter and "When NOT to Use" sections are untouched

- [ ] **Step 4: Update repo AGENTS.md check (no-op confirmation)**

The repo `AGENTS.md` conventions (fresh sprinkle names, cone-owned sends, `.shtml` rewrite after send, EDS URLs for images) all remain satisfied by the new text. No AGENTS.md change needed — confirm and move on.

- [ ] **Step 5: Final commit (if any fixups) and report**

```bash
git status --short   # should be clean or only fixups from Step 2/3
git log --oneline main..HEAD
```

Report the commit list and the traceability confirmation.

**Optional live test** (requires a Slicc cone; skip if unavailable):
`upskill aem-growth-adoption/slicc-demo-skills --skill liftoff-demo`, then invoke the skill by name and confirm Step 0 runs before any sprinkle opens.
