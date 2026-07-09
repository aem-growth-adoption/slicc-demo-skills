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
- GitHub access configured by the Liftoff Lab
- EDS repo pre-created by the Liftoff Lab

## Key Rules

- **Cone owns ALL `sprinkle send` calls** — never delegate pipeline updates to scoops
- **Always mint fresh sprinkle names** per migration — never reuse/overwrite
- **Rewrite the pipeline `.shtml` after every `sprinkle send`** — late-joining followers need to see accumulated progress, not a blank initial state

## Slug Derivation

Derive from URL hostname + path + 4 random hex chars:
- `https://www.adobe.com/products/photoshop` → `adobe-photoshop-a3f1`
- `https://wknd.site/basecamp` → `wknd-basecamp-9c2e`

Strip `www.`, take hostname first segment + last path segment, lowercase,
append `-$(openssl rand -hex 2)`.

## Pipeline Sprinkle Updates

The cone pushes status updates between phases:
- Before starting a phase: push `active` for the current step
- When a phase completes: push `done`, then `active` for the next

Format: `sprinkle send {{SLUG}}-pipeline '{"step":"<id>","status":"active|done","summary":"...","link":"..."}'`

Step IDs in order: `setup`, `extraction`, `decomposition`, `blocks`, `assembly`, `deploy`

### State Persistence

Every time you push a pipeline update, you MUST also rewrite the
sprinkle's `.shtml` file with the updated `{{INITIAL_STATE_JSON}}`
reflecting all current step statuses. This ensures followers who join
mid-session see the full accumulated progress.

Procedure after every `sprinkle send`:
1. Update your in-memory steps array with the new status
2. Rewrite `/shared/sprinkles/{{SLUG}}-pipeline/{{SLUG}}-pipeline.shtml`
3. The `sprinkle send` pushes the live update; the rewritten file catches up new joiners

## Procedure

### Step 1 — Setup & open pipeline sprinkle

1. Derive slug from the URL
2. Read `/workspace/skills/liftoff-demo/templates/pipeline.shtml.tpl`
3. Replace `{{URL}}`, `{{SLUG}}`
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
5. Write to `/shared/sprinkles/{{SLUG}}-pipeline/{{SLUG}}-pipeline.shtml`
6. Run: `sprinkle open {{SLUG}}-pipeline`
7. Push initial status:
   ```
   sprinkle send {{SLUG}}-pipeline '{"step":"setup","status":"active","summary":"Cloning repo & preparing environment..."}'
   ```

### Step 2 — Clone repo & verify environment

1. Clone the target repo: `git clone https://github.com/{{OWNER}}/{{REPO}}.git /shared/{{REPO}}`
2. Verify the migration skills are installed (they should be from the init prompt)
3. Push setup done + extraction active:
   ```
   sprinkle send {{SLUG}}-pipeline '{"step":"setup","status":"done","summary":"Environment ready"}'
   sprinkle send {{SLUG}}-pipeline '{"step":"extraction","status":"active","summary":"Navigating to page..."}'
   ```

### Step 3 — Run the migration

Now invoke the `migrate-page` skill with the URL and repo. The skill
handles all four phases internally (extraction → decomposition → blocks → assembly).

**IMPORTANT:** The cone must monitor progress and push pipeline updates
as the migrate-page skill progresses through its phases. Watch for:

- Phase 1 starts (browser opens) → push `extraction` active
- Phase 1 completes (visual tree captured) → push `extraction` done, `decomposition` active
- Phase 2 completes (blocks identified) → push `decomposition` done, `blocks` active
- Phase 3 progress (scoops created) → push `blocks` active with summary like "3/6 blocks done"
- Phase 3 completes (all scoops done) → push `blocks` done, `assembly` active
- Phase 4 completes (page assembled) → push `assembly` done, `deploy` active

The migrate-page skill sends `sprinkle send migrate-page` updates for
its own sprinkle — use those as signals to update our pipeline sprinkle.

### Step 4 — Deploy

After assembly completes:

1. Ensure all changes are committed and pushed to the repo
2. Trigger EDS preview for the migrated page
3. Wait for the preview to be live (poll the URL)
4. Push deploy done:
   ```
   sprinkle send {{SLUG}}-pipeline '{"step":"deploy","status":"done","summary":"Live!","link":"{{PREVIEW_URL}}"}'
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
       { "value": "6", "label": "blocks migrated" },
       { "value": "3", "label": "fragments created" },
       { "value": "~90%", "label": "visual match" }
     ],
     "nextSteps": [
       {
         "icon": "✏️",
         "title": "Edit your content",
         "description": "Open Document Authoring to edit pages and content",
         "url": "https://da.live/canvas#/{{OWNER}}/{{REPO}}/index",
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
4. Write to `/shared/sprinkles/{{SLUG}}-complete/{{SLUG}}-complete.shtml`
5. Run: `sprinkle open {{SLUG}}-complete`

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

- **Sprinkle file size limit** — keep under ~350KB. Use EDS URLs for images.
- **Sprinkle overwrite doesn't push to followers** — always mint fresh names.
- **Scoop outputs go to `/shared/`** — cone and scoops can read each other's outputs.
