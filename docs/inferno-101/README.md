# Inferno 101 short video series

This pack supports a four minute general introduction to Inferno and defines two separate follow-up walkthroughs. The first video explains what Inferno checks, when to use it, and how to approach a first run. It does not teach either test kit in detail.

## Files

- `output/Inferno 101 General Slides.pptx`: five-slide presentation for the general introduction
- `output/Inferno 101 General Script.docx`: spoken script, browser cues, preflight checks, and series plan
- `output/Inferno 101 Run Sheet.html`: standalone rehearsal run sheet with timer and checkboxes
- `content.json`: canonical timing, directions, narration, and follow-up video briefs
- `build_documents.py`: generates the HTML and Word outputs
- `build_deck.mjs`: generates the PowerPoint output

## Series structure

1. `Inferno 101`, four minutes. Explain what Inferno does, how to select a kit, how sessions and results are organised, and how to use the evidence.
2. `AU Patient Summary Test Kit 101`, four to five minutes. Run a clean Bundle, inspect Messages, then rerun with one required section removed.
3. `AU Core Test Kit 101`, four to five minutes. Run one Patient group against the public synthetic server and inspect Requests and dependent skips.

The split keeps the general introduction useful for every viewer. Each follow-up video can then move quickly because it only needs to explain one testing workflow.

For the internal review recording, the run sheet uses the PR 203 preview for the new guidance copy. The closing slide and QR code retain the stable production URL.

## Rebuild

Use the bundled document and presentation runtimes. Run `build_documents.py`, then set `PRESENTATIONS_SKILL_DIR`, `RUNTIME_PYTHON`, `RUNTIME_NODE`, and `RUNTIME_NODE_MODULES` for the installed artifact runtime before running `build_deck.mjs`. Render and visually inspect the generated DOCX and PPTX before delivery.

## Recording day checks

Test counts, versions, server behaviour, and saved session availability can change. The run sheet keeps these items in its preflight section instead of baking them into reusable narration.
