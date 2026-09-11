import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { Presentation, PresentationFile } from "@oai/artifact-tool";

const ROOT = path.dirname(new URL(import.meta.url).pathname);
const BUILD = path.join(ROOT, "build");
const OUTPUT = path.join(ROOT, "output");
const ASSETS = path.join(ROOT, "assets");
const SKILL_DIR = process.env.PRESENTATIONS_SKILL_DIR;
const RUNTIME_PYTHON = process.env.RUNTIME_PYTHON;
const FINAL_PPTX = path.join(OUTPUT, "Inferno 101 Draft Slides.pptx");

if (!SKILL_DIR || !RUNTIME_PYTHON) {
  throw new Error("PRESENTATIONS_SKILL_DIR and RUNTIME_PYTHON are required");
}

await fs.mkdir(BUILD, { recursive: true });
await fs.mkdir(OUTPUT, { recursive: true });

const content = JSON.parse(await fs.readFile(path.join(ROOT, "content.json"), "utf8"));
const { finalizePresentation } = await import(
  pathToFileURL(path.join(SKILL_DIR, "container_tools/artifact_tool_utils.mjs")).href
);

const W = 1280;
const H = 720;
const CREAM = "#FFF9EC";
const ORANGE = "#FF6A21";
const NAVY = "#10283B";
const MUTED = "#53616A";
const LINE = "#D9DDE0";
const FONT = "Arial";

const presentation = Presentation.create({ slideSize: { width: W, height: H } });

function addText(slide, text, position, options = {}) {
  const shape = slide.shapes.add({
    geometry: "textbox",
    position,
    fill: "none",
    line: { fill: "none", width: 0 },
  });
  shape.text = text;
  shape.text.style = {
    typeface: FONT,
    fontSize: options.fontSize ?? 26,
    bold: options.bold ?? false,
    color: options.color ?? NAVY,
    alignment: options.alignment ?? "left",
    verticalAlignment: options.verticalAlignment ?? "middle",
    autoFit: options.autoFit ?? "shrinkText",
  };
  return shape;
}

async function addImage(slide, filename, position, alt, fit = "contain") {
  const blob = await fs.readFile(path.join(ASSETS, filename));
  return slide.images.add({ blob, contentType: "image/png", alt, fit, position });
}

function addBrand(slide, dark = false) {
  slide.shapes.add({
    geometry: "rect",
    position: { left: 0, top: 0, width: W, height: 10 },
    fill: ORANGE,
    line: { fill: "none", width: 0 },
  });
  addText(slide, "SPARKED FHIR AU", { left: 72, top: 670, width: 300, height: 24 }, {
    fontSize: 11,
    bold: true,
    color: dark ? "#FFFFFF" : "#9D3E13",
  });
}

function addNotes(slide, text) {
  slide.speakerNotes.textFrame.setText(text);
}

{
  const slide = presentation.slides.add();
  slide.background.fill = CREAM;
  await addImage(slide, "sparked-logo.png", { left: 430, top: 58, width: 420, height: 147 }, "Sparked HL7 FHIR logo");
  await addImage(slide, "inferno-logo.png", { left: 95, top: 310, width: 170, height: 170 }, "Inferno logo");
  addText(slide, content.title, { left: 300, top: 276, width: 860, height: 100 }, {
    fontSize: 54,
    bold: true,
    color: NAVY,
  });
  addText(slide, content.subtitle, { left: 304, top: 382, width: 780, height: 62 }, {
    fontSize: 27,
    color: "#9D3E13",
  });
  addText(slide, "Draft recording for team review", { left: 304, top: 470, width: 600, height: 35 }, {
    fontSize: 18,
    color: MUTED,
  });
  addBrand(slide);
  addNotes(slide, content.segments[0].say.join("\n\n") + "\n\nSource: https://inferno.hl7.org.au/");
}

{
  const slide = presentation.slides.add();
  slide.background.fill = "#FFFFFF";
  await addImage(slide, "acknowledgement-of-country.png", { left: 0, top: 0, width: W, height: H }, "Acknowledgement of Country", "cover");
  addNotes(slide, content.segments[1].say.join("\n\n"));
}

{
  const slide = presentation.slides.add();
  slide.background.fill = CREAM;
  addBrand(slide);
  addText(slide, "What Inferno tests", { left: 72, top: 52, width: 800, height: 64 }, {
    fontSize: 38,
    bold: true,
  });
  await addImage(slide, "inferno-logo.png", { left: 535, top: 232, width: 210, height: 210 }, "Inferno logo");
  addText(slide, "AU Patient Summary", { left: 82, top: 170, width: 390, height: 46 }, {
    fontSize: 29,
    bold: true,
    color: "#9D3E13",
  });
  addText(slide, "You have a patient summary Bundle, or a server that serves or generates one.", { left: 82, top: 232, width: 380, height: 120 }, {
    fontSize: 23,
    color: NAVY,
  });
  addText(slide, "Validate the document, Composition sections, referenced resources, Must Support elements, and terminology.", { left: 82, top: 382, width: 390, height: 126 }, {
    fontSize: 20,
    color: MUTED,
  });
  addText(slide, "AU Core", { left: 810, top: 170, width: 360, height: 46 }, {
    fontSize: 29,
    bold: true,
    color: "#9D3E13",
  });
  addText(slide, "You operate a FHIR server that other systems query.", { left: 810, top: 232, width: 370, height: 100 }, {
    fontSize: 23,
    color: NAVY,
  });
  addText(slide, "Run required searches, inspect returned data, validate profiles, and check references.", { left: 810, top: 382, width: 370, height: 110 }, {
    fontSize: 20,
    color: MUTED,
  });
  addText(slide, "Reference testing, not certification", { left: 388, top: 565, width: 505, height: 42 }, {
    fontSize: 22,
    bold: true,
    alignment: "center",
    color: NAVY,
  });
  addNotes(slide, content.segments[2].say.join("\n\n") + "\n\nSources: https://inferno.hl7.org.au/about/ and planned guidance copy in hl7au/au-fhir-inferno PR 203.");
}

{
  const slide = presentation.slides.add();
  slide.background.fill = "#FFFFFF";
  addBrand(slide);
  addText(slide, "How Inferno organises a run", { left: 72, top: 52, width: 890, height: 64 }, {
    fontSize: 38,
    bold: true,
  });
  const items = [
    ["1", "Test kit", "One use case or implementation guide"],
    ["2", "Suite", "One published or ballot version"],
    ["3", "Group", "One profile or one way to obtain a document"],
    ["4", "Test", "One assertion with its own result"],
  ];
  for (let i = 0; i < items.length; i += 1) {
    const top = 154 + i * 112;
    slide.shapes.add({
      geometry: "ellipse",
      position: { left: 100, top: top + 5, width: 64, height: 64 },
      fill: i === 3 ? NAVY : ORANGE,
      line: { fill: "none", width: 0 },
    });
    addText(slide, items[i][0], { left: 100, top: top + 5, width: 64, height: 64 }, {
      fontSize: 24,
      bold: true,
      color: "#FFFFFF",
      alignment: "center",
    });
    addText(slide, items[i][1], { left: 198, top, width: 230, height: 48 }, {
      fontSize: 27,
      bold: true,
      color: NAVY,
    });
    addText(slide, items[i][2], { left: 455, top, width: 680, height: 62 }, {
      fontSize: 22,
      color: MUTED,
    });
    if (i < items.length - 1) {
      slide.shapes.add({
        geometry: "line",
        position: { left: 132, top: top + 72, width: 0, height: 36 },
        fill: "none",
        line: { style: "solid", fill: LINE, width: 3 },
      });
    }
  }
  addText(slide, "While fixing a problem, rerun the smallest relevant group.", { left: 198, top: 610, width: 850, height: 35 }, {
    fontSize: 19,
    bold: true,
    color: "#9D3E13",
  });
  addNotes(slide, content.segments[3].say.join("\n\n") + "\n\nSource: planned guidance copy in hl7au/au-fhir-inferno PR 203.");
}

{
  const slide = presentation.slides.add();
  slide.background.fill = CREAM;
  addBrand(slide);
  addText(slide, "Reading a result", { left: 72, top: 52, width: 720, height: 64 }, {
    fontSize: 38,
    bold: true,
  });
  const states = [
    ["Pass", "The assertion held", "#277A55"],
    ["Fail", "The assertion did not hold", "#C43D3D"],
    ["Skip", "A precondition was missing", "#B56B00"],
    ["Omit", "The test did not apply", "#626970"],
    ["Error", "Something unexpected happened", "#7A3E91"],
  ];
  for (let i = 0; i < states.length; i += 1) {
    const top = 145 + i * 88;
    addText(slide, states[i][0], { left: 110, top, width: 160, height: 52 }, {
      fontSize: 29,
      bold: true,
      color: states[i][2],
    });
    addText(slide, states[i][1], { left: 300, top, width: 770, height: 52 }, {
      fontSize: 24,
      color: NAVY,
    });
    slide.shapes.add({
      geometry: "line",
      position: { left: 110, top: top + 61, width: 960, height: 0 },
      fill: "none",
      line: { style: "solid", fill: LINE, width: 1 },
    });
  }
  addText(slide, "A passing test can still contain warnings and useful information.", { left: 110, top: 605, width: 960, height: 38 }, {
    fontSize: 21,
    bold: true,
    color: "#9D3E13",
  });
  addNotes(slide, content.segments[6].say.join("\n\n") + "\n\nSource: planned guidance copy in hl7au/au-fhir-inferno PR 203.");
}

{
  const slide = presentation.slides.add();
  await addImage(slide, "dark-background.png", { left: 0, top: 0, width: W, height: H }, "Sparked dark patterned background", "cover");
  addBrand(slide, true);
  addText(slide, "Keep the session URL", { left: 84, top: 88, width: 750, height: 72 }, {
    fontSize: 44,
    bold: true,
    color: "#FFFFFF",
  });
  addText(slide, "It lets someone else inspect the same run and request evidence.", { left: 88, top: 176, width: 680, height: 82 }, {
    fontSize: 26,
    color: "#F7EFD8",
  });
  addText(slide, "Messages explain the finding\nRequests show the HTTP evidence\nReport preserves a printable summary", { left: 88, top: 312, width: 630, height: 170 }, {
    fontSize: 24,
    color: "#FFFFFF",
  });
  addText(slide, "inferno.hl7.org.au/guidance/", { left: 88, top: 530, width: 660, height: 50 }, {
    fontSize: 27,
    bold: true,
    color: "#FF8A4A",
  });
  await addImage(slide, "guidance-qr.png", { left: 875, top: 130, width: 280, height: 280 }, "QR code for Inferno guidance");
  addText(slide, "Use synthetic data only", { left: 865, top: 454, width: 300, height: 46 }, {
    fontSize: 21,
    bold: true,
    alignment: "center",
    color: "#FFFFFF",
  });
  addText(slide, "Reference testing, not certification", { left: 835, top: 512, width: 360, height: 45 }, {
    fontSize: 17,
    alignment: "center",
    color: "#F7EFD8",
  });
  addNotes(slide, content.segments[7].say.join("\n\n") + "\n\n" + content.segments[8].say.join("\n\n") + "\n\nSource: https://inferno.hl7.org.au/guidance/");
}

const stagingDir = path.join(ROOT, ".codex-finalizer");
await fs.mkdir(stagingDir, { recursive: true });
const candidatePath = path.join(stagingDir, "inferno-101-candidate.pptx");
await (await PresentationFile.exportPptx(presentation)).save(candidatePath);

await finalizePresentation({
  explicitTotalSlideCount: 6,
  requiredNativeTableOwnerSlides: [],
  requiredNativeChartOwnerSlides: [],
  workspaceDir: ROOT,
  candidatePath,
  finalPath: FINAL_PPTX,
  pythonExecutable: RUNTIME_PYTHON,
  integrityValidatorPath: path.join(SKILL_DIR, "container_tools/inspect_presentation_package_integrity.py"),
  layoutValidatorPath: path.join(SKILL_DIR, "container_tools/inspect_presentation_layout_geometry.py"),
  layoutArgs: [
    "--expected-slide-size-emu", "12192000,6858000",
    "--validate-heading-fit",
  ],
  requiredNativeTableOwnerSlides: [],
  fontPolicy: { basis: "design", families: [FONT] },
  verifyArtifactToolImport: true,
  receiptPath: path.join(stagingDir, "Inferno-101-Draft-Slides.validation.json"),
});

console.log(FINAL_PPTX);
