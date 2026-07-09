# Slicc Demo Skills

Demo orchestration skills for [Slicc](https://www.sliccy.ai/) — each
skill wraps existing migration/creation skills with a polished demo
experience including pipeline progress sprinkles, completion views,
and automated flow orchestration.

## Skills

| Skill | What it does |
|---|---|
| `liftoff-demo` | Single-page migration to AEM EDS with live pipeline progress |

## Installation

```bash
upskill aem-growth-adoption/slicc-demo-skills --all
```

Or install a specific skill:

```bash
upskill aem-growth-adoption/slicc-demo-skills --skill liftoff-demo
```

## Architecture

Each demo skill follows the same pattern:

1. **SKILL.md** — orchestration procedure (what to run, when to update sprinkles)
2. **templates/** — `.shtml.tpl` sprinkle templates (HTML/CSS/JS apps that render inside Slicc's sidebar)

The skill does NOT implement the migration/creation logic — it wraps
existing skills (e.g. `aemcoder/skills` for migration) and adds the
demo UX layer on top.
