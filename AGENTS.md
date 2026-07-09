# Slicc Demo Skills

## Repository Structure

```
{skill-name}/
  SKILL.md              Slicc skill definition (YAML frontmatter + procedure)
  templates/            Sprinkle templates (.shtml.tpl)
```

Each top-level directory is a self-contained demo skill. Skills are
installed via Slicc's `upskill` command.

## Conventions

### Skills

- Skills are SKILL.md files with YAML frontmatter (`name`, `description`)
- Slicc discovers skills at `/workspace/skills/{name}/SKILL.md`
- Templates use `{{PLACEHOLDER}}` syntax, replaced by the cone at runtime
- Sprinkle templates are `.shtml.tpl` files — self-contained HTML apps
  that use `slicc.on('update')` for live updates and `slicc.getState()`
  / `slicc.setState()` for persistence

### Sprinkle Rules

- The **cone** owns ALL `sprinkle send` calls — never delegate to scoops
- Mint **fresh sprinkle names** per session — never reuse/overwrite
- After every `sprinkle send`, **rewrite the `.shtml` file** with
  updated `{{INITIAL_STATE_JSON}}` so late-joining followers see
  accumulated progress
- Keep sprinkle files under ~350KB — use EDS URLs for images
- Never reference `/workspace/` or `file://` in anything a follower
  sees — use EDS URLs

### Design

- Dark theme matching the Liftoff to AEM palette
- Stagger animations on load for polish
- Live duration timers on active steps
- Progress bars with smooth transitions

## Adding a New Demo Skill

1. Create `{skill-name}/SKILL.md` with the orchestration procedure
2. Create `{skill-name}/templates/` with sprinkle templates
3. The skill should wrap existing skills (not reimplement logic)
4. Follow the pattern in `liftoff-demo/` for sprinkle state management

## Testing

Install locally in a Slicc cone:

```bash
upskill aem-growth-adoption/slicc-demo-skills --skill {skill-name}
```

Then invoke the skill by name in the cone chat.
