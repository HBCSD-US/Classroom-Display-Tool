import { readFileSync, writeFileSync } from "node:fs";

const sourcePath = new URL("./display_utility_flow_elements.json", import.meta.url);
const previewPath = new URL("./previews/display_utility_flow_preview.svg", import.meta.url);

const elements = JSON.parse(readFileSync(sourcePath, "utf8"));
const width = 1600;
const height = 1200;

function esc(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function attrs(values) {
  return Object.entries(values)
    .filter(([, value]) => value !== undefined && value !== null)
    .map(([key, value]) => `${key}="${esc(value)}"`)
    .join(" ");
}

function drawTextLines(text, x, y, options = {}) {
  const lines = String(text).split("\n");
  const size = options.size ?? 18;
  const lineHeight = Math.round(size * 1.22);
  const anchor = options.anchor ?? "start";
  const weight = options.weight ?? 500;
  const fill = options.fill ?? "#1e1e1e";
  return lines
    .map((line, index) => {
      return `<text ${attrs({
        x,
        y: y + index * lineHeight,
        fill,
        "font-family": "Inter, Arial, sans-serif",
        "font-size": size,
        "font-weight": weight,
        "text-anchor": anchor,
      })}>${esc(line)}</text>`;
    })
    .join("");
}

function centerLabel(element) {
  const label = element.label;
  if (!label?.text) return "";
  const lines = String(label.text).split("\n");
  const size = label.fontSize ?? 18;
  const lineHeight = Math.round(size * 1.18);
  const blockHeight = (lines.length - 1) * lineHeight;
  const startY = element.y + element.height / 2 - blockHeight / 2 + size * 0.34;
  return drawTextLines(label.text, element.x + element.width / 2, startY, {
    size,
    anchor: "middle",
    fill: label.strokeColor ?? "#1e1e1e",
  });
}

function fillFor(element) {
  if (!element.backgroundColor || element.backgroundColor === "transparent") {
    return "none";
  }
  return element.backgroundColor;
}

function strokeFor(element) {
  return element.strokeColor ?? "#1e1e1e";
}

function drawShape(element) {
  const common = {
    fill: fillFor(element),
    stroke: strokeFor(element),
    "stroke-width": element.strokeWidth ?? 2,
    opacity: element.opacity ? element.opacity / 100 : 1,
  };
  const fillOpacity = element.fillStyle === "hachure" ? 0.58 : 1;
  let body = "";

  if (element.type === "rectangle") {
    body = `<rect ${attrs({
      x: element.x,
      y: element.y,
      width: element.width,
      height: element.height,
      rx: element.roundness ? 12 : 4,
      ry: element.roundness ? 12 : 4,
      ...common,
      "fill-opacity": fillOpacity,
    })}/>`;
  }

  if (element.type === "ellipse") {
    body = `<ellipse ${attrs({
      cx: element.x + element.width / 2,
      cy: element.y + element.height / 2,
      rx: element.width / 2,
      ry: element.height / 2,
      ...common,
      "fill-opacity": fillOpacity,
    })}/>`;
  }

  if (element.type === "diamond") {
    const cx = element.x + element.width / 2;
    const cy = element.y + element.height / 2;
    const points = [
      [cx, element.y],
      [element.x + element.width, cy],
      [cx, element.y + element.height],
      [element.x, cy],
    ]
      .map((point) => point.join(","))
      .join(" ");
    body = `<polygon ${attrs({
      points,
      ...common,
      "fill-opacity": fillOpacity,
    })}/>`;
  }

  return `${body}${centerLabel(element)}`;
}

function drawArrow(element) {
  const points = element.points ?? [
    [0, 0],
    [element.width ?? 0, element.height ?? 0],
  ];
  const absolute = points.map(([px, py]) => [element.x + px, element.y + py]);
  const pointList = absolute.map((point) => point.join(",")).join(" ");
  const dash = element.strokeStyle === "dashed" ? "8 7" : undefined;
  const marker = element.endArrowhead === null ? undefined : "url(#arrowhead)";
  let label = "";

  if (element.label?.text) {
    const mid = absolute[Math.floor((absolute.length - 1) / 2)];
    const next = absolute[Math.min(Math.floor((absolute.length - 1) / 2) + 1, absolute.length - 1)];
    label = drawTextLines(element.label.text, (mid[0] + next[0]) / 2, (mid[1] + next[1]) / 2 - 8, {
      size: element.label.fontSize ?? 16,
      anchor: "middle",
      fill: "#343a40",
      weight: 600,
    });
  }

  return `<polyline ${attrs({
    points: pointList,
    fill: "none",
    stroke: element.strokeColor ?? "#495057",
    "stroke-width": element.strokeWidth ?? 2,
    "stroke-linecap": "round",
    "stroke-linejoin": "round",
    "stroke-dasharray": dash,
    "marker-end": marker,
  })}/>${label}`;
}

function drawText(element) {
  const weight = element.fontSize >= 30 || element.id?.endsWith("_title") ? 700 : 500;
  return drawTextLines(element.text, element.x, element.y + element.fontSize, {
    size: element.fontSize,
    fill: element.strokeColor ?? "#1e1e1e",
    weight,
  });
}

const parts = [];
for (const element of elements) {
  if (element.type === "cameraUpdate") continue;
  if (["rectangle", "ellipse", "diamond"].includes(element.type)) {
    parts.push(drawShape(element));
  } else if (element.type === "arrow") {
    parts.push(drawArrow(element));
  } else if (element.type === "text") {
    parts.push(drawText(element));
  }
}

const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <defs>
    <marker id="arrowhead" markerWidth="12" markerHeight="8" refX="10" refY="4" orient="auto" markerUnits="strokeWidth">
      <path d="M0,0 L12,4 L0,8 Z" fill="#495057"/>
    </marker>
  </defs>
  <rect x="0" y="0" width="${width}" height="${height}" fill="#ffffff"/>
  ${parts.join("\n  ")}
</svg>
`;

writeFileSync(previewPath, svg);
console.log(`Wrote ${previewPath.pathname}`);
