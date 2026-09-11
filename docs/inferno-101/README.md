# Inferno Test Kit 101 draft recording pack

This pack supports a full draft recording for team review. The recording is designed around the live Inferno interface, with slides used only to establish the purpose, vocabulary, result meanings, and next steps.

## Files

- `output/Inferno 101 Draft Slides.pptx`: presentation used before and after the live browser demonstration
- `output/Inferno 101 Draft Script.docx`: full spoken script with screen directions and fallbacks
- `output/Inferno 101 Run Sheet.html`: self-contained rehearsal and recording run sheet
- `content.json`: canonical timing, directions, and narration
- `build_documents.py`: generates the HTML and Word outputs
- `build_deck.mjs`: generates the PowerPoint output

## Recording path

1. Slides 1 to 4 establish the purpose and vocabulary.
2. The AU Patient Summary demo validates a clean Bundle, inspects messages, then reruns with one mandatory section removed.
3. The AU Core demo tests the Patient group against the public synthetic server and inspects the HTTP request evidence.
4. Slides 5 and 6 explain result states and direct viewers to guidance and support.

For the internal draft recording, the run sheet opens the PR 203 preview for the new guidance copy. The closing slide and QR code retain the stable production URL so the final recording does not preserve a temporary address.

The target duration is 14 minutes. Use the HTML run sheet during rehearsal because it includes a timer, checkboxes, exact URLs, and fallback sessions.

## Rebuild

Use the bundled document and presentation runtimes. Run `build_documents.py`, then set `PRESENTATIONS_SKILL_DIR`, `RUNTIME_PYTHON`, `RUNTIME_NODE`, and `RUNTIME_NODE_MODULES` for the installed artifact runtime before running `build_deck.mjs`. The generated DOCX and PPTX must be rendered and visually checked before delivery.

## Recording-day checks

Test counts, timings, suite versions, server behaviour, validator versions, and saved session availability can change. The run sheet keeps these items in its preflight section instead of baking them into reusable narration.
