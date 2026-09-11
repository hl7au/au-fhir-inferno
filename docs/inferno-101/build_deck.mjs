import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { Presentation, PresentationFile } from "@oai/artifact-tool";

const ROOT = path.dirname(new URL(import.meta.url).pathname);
const OUTPUT = path.join(ROOT, "output");
const ASSETS = path.join(ROOT, "assets");
const SKILL_DIR = process.env.PRESENTATIONS_SKILL_DIR;
const RUNTIME_PYTHON = process.env.RUNTIME_PYTHON;
const FINAL_PPTX = path.join(OUTPUT, "Inferno 101 General Slides.pptx");

if (!SKILL_DIR || !RUNTIME_PYTHON) {
  throw new Error("PRESENTATIONS_SKILL_DIR and RUNTIME_PYTHON are required");
}

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

function addText(slide, value, position, options = {}) {
  const shape = slide.shapes.add({
    geometry: "textbox",
    position,
    fill: "none",
    line: { fill: "none", width: 0 },
  });
  shape.text = value;
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

function addNotes(slide, value) {
  slide.speakerNotes.textFrame.setText(value);
}

{
  const slide = presentation.slides.add();
  slide.background.fill = CREAM;
  await addImage(slide, "sparked-logo.png", { left: 430, top: 64, width: 420, height: 147 }, "Sparked HL7 FHIR logo");
  addText(slide, content.title, { left: 130, top: 270, width: 1020, height: 105 }, {
    fontSize: 62,
    bold: true,
    alignment: "center",
  });
  addText(slide, content.subtitle, { left: 220, top: 385, width: 840, height: 65 }, {
    fontSize: 29,
    color: "#9D3E13",
    alignment: "center",
  });
  addText(slide, "Four minute introduction", { left: 420, top: 488, width: 440, height: 36 }, {
    fontSize: 18,
    color: MUTED,
    alignment: "center",
  });
  addBrand(slide);
  addNotes(slide, content.segments[0].say.join("\n\n") + "\n\nSource: https://inferno.hl7.org.au/");
}

{
  const slide = presentation.slides.add();
  slide.background.fill = "#FFFFFF";
  addBrand(slide);
  addText(slide, "What Inferno does", { left: 72, top: 52, width: 760, height: 64 }, {
    fontSize: 38,
    bold: true,
  });
  await addImage(slide, "inferno-logo.png", { left: 535, top: 154, width: 210, height: 210 }, "Inferno logo");
  const steps = [
    ["1", "Guide requirements", "A FHIR implementation guide defines the rules"],
    ["2", "Automated tests", "Inferno applies selected requirements consistently"],
    ["3", "Results and evidence", "Messages and HTTP details explain what happened"],
  ];
  const lefts = [70, 430, 850];
  for (let index = 0; index < steps.length; index += 1) {
    const left = lefts[index];
    slide.shapes.add({
      geometry: "ellipse",
      position: { left, top: 420, width: 58, height: 58 },
      fill: index === 1 ? NAVY : ORANGE,
      line: { fill: "none", width: 0 },
    });
    addText(slide, steps[index][0], { left, top: 420, width: 58, height: 58 }, {
      fontSize: 22,
      bold: true,
      color: "#FFFFFF",
      alignment: "center",
    });
    addText(slide, steps[index][1], { left: left + 76, top: 406, width: 285, height: 50 }, {
      fontSize: 25,
      bold: true,
    });
    addText(slide, steps[index][2], { left: left + 76, top: 462, width: 285, height: 90 }, {
      fontSize: 20,
      color: MUTED,
    });
  }
  addText(slide, "Community reference testing", { left: 410, top: 585, width: 460, height: 38 }, {
    fontSize: 21,
    bold: true,
    alignment: "center",
    color: "#9D3E13",
  });
  addNotes(slide, content.segments[1].say.join("\n\n") + "\n\nSources: https://inferno.hl7.org.au/about/ and planned guidance copy in hl7au/au-fhir-inferno PR 203.");
}

{
  const slide = presentation.slides.add();
  slide.background.fill = CREAM;
  addBrand(slide);
  addText(slide, "Choosing a test kit", { left: 72, top: 52, width: 800, height: 64 }, {
    fontSize: 38,
    bold: true,
  });
  slide.shapes.add({
    geometry: "line",
    position: { left: 640, top: 165, width: 0, height: 390 },
    fill: "none",
    line: { style: "solid", fill: LINE, width: 2 },
  });
  addText(slide, "AU Patient Summary", { left: 90, top: 170, width: 460, height: 52 }, {
    fontSize: 31,
    bold: true,
    color: "#9D3E13",
  });
  addText(slide, "You have a patient summary Bundle", { left: 90, top: 245, width: 460, height: 82 }, {
    fontSize: 26,
    bold: true,
  });
  addText(slide, "The kit can test a Bundle directly, retrieve one from a server, or ask a server to generate one.", { left: 90, top: 350, width: 460, height: 145 }, {
    fontSize: 23,
    color: MUTED,
  });
  addText(slide, "AU Core", { left: 730, top: 170, width: 430, height: 52 }, {
    fontSize: 31,
    bold: true,
    color: "#9D3E13",
  });
  addText(slide, "You operate a FHIR server", { left: 730, top: 245, width: 440, height: 82 }, {
    fontSize: 26,
    bold: true,
  });
  addText(slide, "The kit sends the required searches, validates returned resources, and records the HTTP evidence.", { left: 730, top: 350, width: 440, height: 145 }, {
    fontSize: 23,
    color: MUTED,
  });
  addText(slide, "Choose the version that matches your implementation", { left: 300, top: 585, width: 680, height: 40 }, {
    fontSize: 21,
    bold: true,
    alignment: "center",
  });
  addNotes(slide, content.segments[2].say.join("\n\n") + "\n\nSource: https://inferno.hl7.org.au/test-kits");
}

{
  const slide = presentation.slides.add();
  slide.background.fill = "#FFFFFF";
  addBrand(slide);
  addText(slide, "A useful first run", { left: 72, top: 52, width: 800, height: 64 }, {
    fontSize: 38,
    bold: true,
  });
  const steps = [
    ["1", "Small scope", "Choose one relevant group"],
    ["2", "Synthetic data", "Keep personal and health information off the public service"],
    ["3", "First failure", "Read Messages or Requests before downstream results"],
    ["4", "Rerun", "Confirm the result changes after the fix"],
  ];
  for (let index = 0; index < steps.length; index += 1) {
    const top = 150 + index * 115;
    slide.shapes.add({
      geometry: "ellipse",
      position: { left: 96, top: top + 4, width: 62, height: 62 },
      fill: index === 3 ? NAVY : ORANGE,
      line: { fill: "none", width: 0 },
    });
    addText(slide, steps[index][0], { left: 96, top: top + 4, width: 62, height: 62 }, {
      fontSize: 23,
      bold: true,
      color: "#FFFFFF",
      alignment: "center",
    });
    addText(slide, steps[index][1], { left: 196, top, width: 250, height: 48 }, {
      fontSize: 27,
      bold: true,
    });
    addText(slide, steps[index][2], { left: 480, top, width: 680, height: 68 }, {
      fontSize: 23,
      color: MUTED,
    });
    if (index < steps.length - 1) {
      slide.shapes.add({
        geometry: "line",
        position: { left: 127, top: top + 72, width: 0, height: 38 },
        fill: "none",
        line: { style: "solid", fill: LINE, width: 3 },
      });
    }
  }
  addNotes(slide, content.segments[4].say.join("\n\n") + "\n\nSource: planned guidance copy in hl7au/au-fhir-inferno PR 203.");
}

{
  const slide = presentation.slides.add();
  await addImage(slide, "dark-background.png", { left: 0, top: 0, width: W, height: H }, "Sparked dark patterned background", "cover");
  addBrand(slide, true);
  addText(slide, "Your first Inferno run", { left: 84, top: 78, width: 720, height: 72 }, {
    fontSize: 44,
    bold: true,
    color: "#FFFFFF",
  });
  addText(slide, "Choose the right kit and version", { left: 88, top: 180, width: 650, height: 46 }, {
    fontSize: 25,
    color: "#FFFFFF",
  });
  addText(slide, "Use synthetic data", { left: 88, top: 244, width: 650, height: 46 }, {
    fontSize: 25,
    color: "#FFFFFF",
  });
  addText(slide, "Start with one group", { left: 88, top: 308, width: 650, height: 46 }, {
    fontSize: 25,
    color: "#FFFFFF",
  });
  addText(slide, "Keep the session URL", { left: 88, top: 372, width: 650, height: 46 }, {
    fontSize: 25,
    color: "#FFFFFF",
  });
  addText(slide, "inferno.hl7.org.au/guidance/", { left: 88, top: 520, width: 660, height: 50 }, {
    fontSize: 27,
    bold: true,
    color: "#FF8A4A",
  });
  await addImage(slide, "guidance-qr.png", { left: 875, top: 135, width: 280, height: 280 }, "QR code for Inferno guidance");
  addText(slide, "Next: AU Patient Summary and AU Core walkthroughs", { left: 815, top: 458, width: 400, height: 80 }, {
    fontSize: 19,
    bold: true,
    alignment: "center",
    color: "#F7EFD8",
  });
  addNotes(slide, content.segments[5].say.join("\n\n") + "\n\nSource: https://inferno.hl7.org.au/guidance/");
}

const stagingDir = path.join(ROOT, ".codex-finalizer");
await fs.mkdir(stagingDir, { recursive: true });
const candidatePath = path.join(stagingDir, "inferno-101-general-candidate.pptx");
await (await PresentationFile.exportPptx(presentation)).save(candidatePath);

await finalizePresentation({
  explicitTotalSlideCount: 5,
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
  fontPolicy: { basis: "design", families: [FONT] },
  verifyArtifactToolImport: true,
  receiptPath: path.join(stagingDir, "Inferno-101-General-Slides.validation.json"),
});

console.log(FINAL_PPTX);
