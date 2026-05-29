import { writeFileSync } from "node:fs";

const outPath = new URL("./display_utility_flow_elements.json", import.meta.url);

const colors = {
  ink: "#1e1e1e",
  muted: "#5f6368",
  line: "#495057",
  panel: "#f8f9fa",
  panelStroke: "#dee2e6",
  blue: "#a5d8ff",
  green: "#b2f2bb",
  yellow: "#ffec99",
  red: "#ffc9c9",
  purple: "#d0bfff",
  teal: "#c3fae8",
  orange: "#ffd8a8",
  white: "#ffffff",
};

const elements = [
  { type: "cameraUpdate", width: 1600, height: 1200, x: 0, y: 0 },
];

const shapes = new Map();

function add(element) {
  elements.push(element);
  if (element.id && ["rectangle", "ellipse", "diamond"].includes(element.type)) {
    shapes.set(element.id, element);
  }
}

function panel(id, x, y, width, height, title, subtitle) {
  add({
    type: "rectangle",
    id,
    x,
    y,
    width,
    height,
    backgroundColor: colors.panel,
    strokeColor: colors.panelStroke,
    fillStyle: "solid",
    strokeWidth: 2,
    roughness: 1,
    roundness: { type: 3 },
  });
  add({
    type: "text",
    id: `${id}_title`,
    x: x + 24,
    y: y + 18,
    text: title,
    fontSize: 22,
    strokeColor: colors.ink,
  });
  if (subtitle) {
    add({
      type: "text",
      id: `${id}_subtitle`,
      x: x + 24,
      y: y + 52,
      text: subtitle,
      fontSize: 15,
      strokeColor: colors.muted,
    });
  }
  add({
    type: "arrow",
    id: `${id}_divider`,
    x: x + 22,
    y: y + 86,
    width: width - 44,
    height: 0,
    points: [
      [0, 0],
      [width - 44, 0],
    ],
    endArrowhead: null,
    strokeColor: "#ced4da",
    strokeWidth: 2,
    roughness: 1,
  });
}

function text(id, x, y, value, fontSize = 18, color = colors.ink) {
  add({
    type: "text",
    id,
    x,
    y,
    text: value,
    fontSize,
    strokeColor: color,
  });
}

function shape(type, id, x, y, width, height, label, backgroundColor, options = {}) {
  add({
    type,
    id,
    x,
    y,
    width,
    height,
    backgroundColor,
    strokeColor: options.strokeColor ?? colors.ink,
    fillStyle: options.fillStyle ?? "hachure",
    strokeWidth: options.strokeWidth ?? 2,
    roughness: options.roughness ?? 1.5,
    roundness: type === "rectangle" ? { type: 3 } : undefined,
    label: {
      text: label,
      fontSize: options.fontSize ?? 18,
      strokeColor: options.labelColor ?? colors.ink,
    },
  });
}

function pointOf(id, fixedPoint) {
  const s = shapes.get(id);
  if (!s) throw new Error(`Unknown shape ${id}`);
  return [s.x + s.width * fixedPoint[0], s.y + s.height * fixedPoint[1]];
}

function arrow(id, fromId, fromPoint, toId, toPoint, label, options = {}) {
  const [sx, sy] = pointOf(fromId, fromPoint);
  const [tx, ty] = pointOf(toId, toPoint);
  const midpoints = options.midpoints ?? [];
  const absolutePoints = [[sx, sy], ...midpoints, [tx, ty]];
  const points = absolutePoints.map(([x, y]) => [x - sx, y - sy]);

  add({
    type: "arrow",
    id,
    x: sx,
    y: sy,
    width: tx - sx,
    height: ty - sy,
    points,
    endArrowhead: "arrow",
    strokeColor: options.strokeColor ?? colors.line,
    strokeWidth: options.strokeWidth ?? 2,
    roughness: 1,
    strokeStyle: options.strokeStyle,
    startBinding: { elementId: fromId, fixedPoint: fromPoint },
    endBinding: { elementId: toId, fixedPoint: toPoint },
    label: label ? { text: label, fontSize: options.fontSize ?? 16 } : undefined,
  });
}

function callout(id, x, y, width, height, label, backgroundColor, options = {}) {
  shape("rectangle", id, x, y, width, height, label, backgroundColor, {
    fillStyle: "solid",
    fontSize: options.fontSize ?? 16,
    strokeColor: options.strokeColor ?? "#748ffc",
    roughness: 1,
  });
}

// Canvas shell.
add({
  type: "rectangle",
  id: "canvas_background",
  x: 38,
  y: 38,
  width: 1524,
  height: 1128,
  backgroundColor: "#ffffff",
  strokeColor: "#adb5bd",
  fillStyle: "solid",
  strokeWidth: 2,
  roughness: 1,
  roundness: { type: 3 },
});
text("title", 80, 68, "Classroom Display Utility Flow", 34);
text(
  "subtitle",
  82,
  112,
  "From display discovery to safe classroom presets, then verification and fallback.",
  18,
  colors.muted,
);

panel(
  "discovery_panel",
  78,
  155,
  365,
  640,
  "1. Discover",
  "Build enough context before changing displays.",
);
panel(
  "topology_panel",
  475,
  155,
  370,
  735,
  "2. Classify",
  "Branch by active display count.",
);
panel(
  "preset_panel",
  875,
  155,
  645,
  735,
  "3. Preset Logic",
  "Each preset has a constrained behavior.",
);
panel(
  "verify_panel",
  475,
  920,
  1045,
  205,
  "4. Apply and Verify",
  "Change state, re-scan, and explain the outcome plainly.",
);

// Discovery.
shape("ellipse", "open_utility", 128, 230, 265, 74, "User opens\ndisplay utility", colors.blue, {
  fillStyle: "solid",
});
shape("rectangle", "scan_displays", 128, 334, 265, 74, "Scan current\ndisplays", colors.blue);
shape("rectangle", "build_inventory", 128, 438, 265, 84, "Build display\ninventory", colors.teal);
callout(
  "inventory_details",
  105,
  562,
  312,
  175,
  "Inventory captures:\nDisplay name\nDisplay ID / UUID if available\nCurrent + available modes\nAspect ratio\nBuilt-in vs external\nClassroom display ranking",
  colors.teal,
  { strokeColor: "#0ca678", fontSize: 15 },
);

arrow("a_open_scan", "open_utility", [0.5, 1], "scan_displays", [0.5, 0]);
arrow("a_scan_inventory", "scan_displays", [0.5, 1], "build_inventory", [0.5, 0]);
arrow("a_inventory_details", "build_inventory", [0.5, 1], "inventory_details", [0.5, 0]);

// Topology.
shape("diamond", "display_count", 520, 330, 280, 195, "How many active\ndisplays?", colors.red, {
  fillStyle: "solid",
  fontSize: 18,
});
callout(
  "one_display",
  522,
  215,
  278,
  86,
  "1 display\nShow safe message\nNo display changes applied",
  colors.red,
  { strokeColor: "#e03131", fontSize: 16 },
);
shape(
  "rectangle",
  "two_displays",
  498,
  585,
  326,
  125,
  "2 displays\nBuilt-in Mac display\nOne external display\nEnable 2-display presets",
  colors.yellow,
  { fontSize: 16 },
);
shape(
  "rectangle",
  "three_plus_displays",
  498,
  744,
  326,
  122,
  "3+ displays\nBuilt-in Mac display\nExternal candidates\nBest external source selected\nEnable classroom presets",
  colors.purple,
  { fontSize: 15 },
);

arrow("a_inventory_to_count", "build_inventory", [1, 0.5], "display_count", [0, 0.5], "", {
  midpoints: [[462, 480]],
});
arrow("a_count_one", "display_count", [0.5, 0], "one_display", [0.5, 1], "", {
  strokeColor: "#c92a2a",
});
arrow("a_count_two", "display_count", [0.5, 1], "two_displays", [0.5, 0]);
arrow("a_count_three", "display_count", [0.8, 0.85], "three_plus_displays", [0.5, 0], "", {
  midpoints: [[835, 560], [835, 730], [661, 730]],
});

// Preset selection.
shape("rectangle", "choose_preset", 940, 238, 235, 70, "User chooses\npreset", colors.blue, {
  fillStyle: "solid",
});
shape("diamond", "preset_selected", 1102, 350, 250, 160, "Preset\nselected", colors.yellow, {
  fillStyle: "solid",
});

shape(
  "rectangle",
  "mirror_everything",
  908,
  564,
  290,
  160,
  "Mirror Everything\nExternal as mirror source\nSet external as Main Display\nUse external-friendly 16:9\nAvoid built-in aspect source",
  colors.orange,
  { fontSize: 15 },
);
shape(
  "rectangle",
  "teacher_private",
  1218,
  564,
  270,
  152,
  "Teacher Private Mode\nBuilt-in stays private/main\nExternal display(s) show content\nMirror externals together if possible",
  colors.green,
  { fontSize: 15 },
);
shape(
  "rectangle",
  "extend_all",
  1030,
  748,
  300,
  108,
  "Extend All\nKeep displays separate\nBuilt-in remains main/private\nArrange externals logically",
  colors.blue,
  { fontSize: 15 },
);
callout(
  "extend_visibility",
  1364,
  748,
  124,
  108,
  "Only shown\nfor 3+\ndisplays",
  colors.purple,
  { strokeColor: "#7048e8", fontSize: 15 },
);

arrow("a_two_to_choose", "two_displays", [1, 0.5], "choose_preset", [0, 0.5], "", {
  midpoints: [[875, 648], [875, 273]],
});
arrow("a_three_to_choose", "three_plus_displays", [1, 0.5], "choose_preset", [0, 0.5], "", {
  midpoints: [[892, 805], [892, 273]],
});
arrow("a_choose_selected", "choose_preset", [1, 0.5], "preset_selected", [0, 0.5]);
arrow("a_selected_mirror", "preset_selected", [0.28, 1], "mirror_everything", [0.5, 0]);
arrow("a_selected_teacher", "preset_selected", [0.77, 1], "teacher_private", [0.5, 0]);
arrow("a_selected_extend", "preset_selected", [0.18, 1], "extend_all", [0.5, 0], "", {
  midpoints: [[1180, 530], [1180, 748]],
});
arrow("a_extend_visibility", "extend_all", [1, 0.5], "extend_visibility", [0, 0.5], "", {
  strokeColor: "#7048e8",
  strokeStyle: "dashed",
});

// Apply and verify.
shape("rectangle", "apply_command", 540, 990, 225, 72, "Apply display\ncommand", colors.yellow);
shape("rectangle", "rescan_after", 812, 990, 225, 72, "Re-scan displays\nafter change", colors.teal);
shape("diamond", "result_matches", 1090, 950, 220, 132, "Did result match\nexpected state?", colors.red, {
  fillStyle: "solid",
  fontSize: 17,
});
shape("rectangle", "success_message", 1360, 936, 130, 70, "Show success\nmessage", colors.green, {
  fillStyle: "solid",
  fontSize: 16,
});
shape(
  "rectangle",
  "warning_message",
  1338,
  1042,
  174,
  70,
  "Plain-language warning\nLog actual state\nSuggest fallback preset",
  colors.red,
  { fillStyle: "solid", fontSize: 14 },
);

arrow("a_mirror_apply", "mirror_everything", [0.5, 1], "apply_command", [0.5, 0], "", {
  strokeColor: "#868e96",
  strokeStyle: "dashed",
  midpoints: [[1053, 912], [652, 912]],
});
arrow("a_teacher_apply", "teacher_private", [0.5, 1], "apply_command", [0.5, 0], "", {
  strokeColor: "#868e96",
  strokeStyle: "dashed",
  midpoints: [[1353, 912], [652, 912]],
});
arrow("a_extend_apply", "extend_all", [0.5, 1], "apply_command", [0.5, 0], "", {
  strokeColor: "#868e96",
  strokeStyle: "dashed",
  midpoints: [[1180, 912], [652, 912]],
});
arrow("a_apply_rescan", "apply_command", [1, 0.5], "rescan_after", [0, 0.5]);
arrow("a_rescan_match", "rescan_after", [1, 0.5], "result_matches", [0, 0.5]);
arrow("a_match_success", "result_matches", [1, 0.38], "success_message", [0, 0.5], "Yes", {
  strokeColor: "#2b8a3e",
});
arrow("a_match_warning", "result_matches", [1, 0.76], "warning_message", [0, 0.5], "No", {
  strokeColor: "#c92a2a",
});

// A small legend helps decode the condensed view without distracting from the flow.
shape("rectangle", "legend_decision", 96, 842, 120, 42, "Decision", colors.red, {
  fillStyle: "solid",
  fontSize: 15,
});
shape("rectangle", "legend_action", 236, 842, 120, 42, "Action", colors.blue, {
  fontSize: 15,
});
shape("rectangle", "legend_safe", 96, 900, 120, 42, "Safe stop", colors.red, {
  fillStyle: "solid",
  fontSize: 15,
});
shape("rectangle", "legend_success", 236, 900, 120, 42, "Success", colors.green, {
  fillStyle: "solid",
  fontSize: 15,
});
text("legend_note", 96, 965, "Dashed arrows converge\nall preset paths into apply.", 15, colors.muted);

writeFileSync(outPath, `${JSON.stringify(elements, null, 2)}\n`);
console.log(`Wrote ${outPath.pathname}`);
