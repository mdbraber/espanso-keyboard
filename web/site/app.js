import { init } from "./engine/index.js";
import { haptics } from "./haptics.js";
import { settings, settingsSheet } from "./settings.js";
import { spelling } from "./spelling.js";

const screen = document.getElementById("screen");
const field = document.getElementById("field");
const keyboard = document.getElementById("keyboard");
const bar = document.getElementById("bar");
const keysView = document.getElementById("keys");
const status = document.getElementById("status");
const dark = matchMedia("(prefers-color-scheme: dark)");
const graphemes = new Intl.Segmenter(undefined, { granularity: "grapheme" });

const icon = (body, fill = false) =>
  `<svg viewBox="0 0 24 24" fill="${fill ? "currentColor" : "none"}" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
const arrow = "M12 2.8 2.4 12.4h5.4v7.9h8.4v-7.9h5.4Z";
const symbols = {
  shift: icon(`<path d="${arrow}"/>`),
  "shift.fill": icon(`<path d="${arrow}"/>`, true),
  "capslock.fill": icon(`<path d="M12 2.8 3.4 11h4.9v4.6h7.4V11h4.9Z"/><rect x="8.3" y="18.2" width="7.4" height="2.4" rx=".4"/>`, true),
  capslock: icon(`<path d="M12 2.8 3.4 11h4.9v4.6h7.4V11h4.9Z"/><rect x="8.3" y="18.2" width="7.4" height="2.4" rx=".4"/>`),
  "delete.left": icon(`<path d="M8.2 4.8h11.4a2.4 2.4 0 0 1 2.4 2.4v9.6a2.4 2.4 0 0 1-2.4 2.4H8.2L1.8 12Z"/><path d="m11.2 8.9 6.2 6.2m0-6.2-6.2 6.2"/>`),
  "return.left": icon(`<path d="M21 3.6v8.2a2.6 2.6 0 0 1-2.6 2.6H3.4"/><path d="m8.2 9.6-4.8 4.8 4.8 4.8"/>`),
  "arrow.right": icon(`<path d="M4 12h15.5m-6-6 6 6-6 6"/>`),
  "arrow.up": icon(`<path d="M12 20V4.5m-6 6 6-6 6 6"/>`),
  magnifyingglass: icon(`<circle cx="10.5" cy="10.5" r="6.3"/><path d="m15.2 15.2 5.3 5.3"/>`),
  checkmark: icon(`<path d="m4.5 12.8 4.8 4.8L19.5 6.5"/>`),
  "chevron.right": icon(`<path d="m9 4.5 7.5 7.5L9 19.5"/>`),
  "arrow.right.to.line": icon(`<path d="M3.5 12h13m-5-5 5 5-5 5M20.5 5v14"/>`),
  globe: icon(`<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18M4.6 7h14.8M4.6 17h14.8"/>`),
};
document.querySelector(".system .globe").innerHTML = symbols.globe;
document.querySelector(".system .mic").innerHTML = icon(`<rect x="8.5" y="2.5" width="7" height="12" rx="3.5"/><path d="M5 11.5a7 7 0 0 0 14 0M12 18.5v3M8.5 21.5h7"/>`);

let expected = null;
const mirror = Object.assign(document.createElement("div"), { className: "caret-mirror" });
mirror.setAttribute("aria-hidden", "true");
field.after(mirror);
const reveal = () => {
  mirror.style.width = `${field.clientWidth}px`;
  mirror.textContent = field.value.slice(0, field.selectionEnd);
  const caret = mirror.appendChild(document.createElement("span"));
  caret.textContent = "\u200b";
  const padding = parseFloat(getComputedStyle(field).paddingTop);
  const lowest = caret.offsetTop + caret.offsetHeight + padding - field.clientHeight;
  field.scrollTop = Math.min(caret.offsetTop - padding, Math.max(field.scrollTop, lowest));
};
const remember = () => (expected = { value: field.value, start: field.selectionStart, end: field.selectionEnd });
const graphemeBefore = (index) => {
  let boundary = 0;
  for (const { index: start } of graphemes.segment(field.value.slice(0, index))) boundary = start;
  return boundary;
};
const graphemeAfter = (index) => {
  const next = graphemes.segment(field.value.slice(index))[Symbol.iterator]().next();
  return next.done ? index : index + next.value.segment.length;
};

const textDocument = {
  before: () => field.value.slice(0, field.selectionStart),
  after: () => field.value.slice(field.selectionEnd),
  insert(text) {
    field.setRangeText(text, field.selectionStart, field.selectionEnd, "end");
    spell.editing = true;
    reveal();
    remember();
  },
  deleteBackward(count) {
    for (let i = 0; i < count; i++) {
      const end = field.selectionEnd;
      const start = field.selectionStart === end ? graphemeBefore(end) : field.selectionStart;
      if (start === end) break;
      field.setRangeText("", start, end, "end");
    }
    spell.editing = true;
    reveal();
    remember();
  },
  moveCursor(offset) {
    let position = field.selectionEnd;
    for (let i = 0; i < Math.abs(offset); i++) position = offset < 0 ? graphemeBefore(position) : graphemeAfter(position);
    field.setSelectionRange(position, position);
    spell.editing = false;
    reveal();
    remember();
  },
};

const lexicon = fetch("en.lexicon").then((response) => response.arrayBuffer());
const { exports } = await init();
const kb = new exports.Keyboard(new Uint8Array(await lexicon), textDocument);
status.hidden = true;
const haptic = haptics(keysView);
const spell = spelling(field, (text) => kb.misspellings(text));

function applySettings() {
  kb.configure(settings.autoCapitalization, settings.autoCorrection, settings.capsLock, settings.predictiveText, settings.smartPunctuation, settings.periodShortcut);
  haptic.enabled = settings.haptic;
  spell.enabled = settings.checkSpelling;
}

settingsSheet({
  root: document.getElementById("settings"),
  opener: document.getElementById("open-settings"),
  haptics: haptic,
  onChange() {
    applySettings();
    render();
  },
  onClose: () => field.focus({ preventScroll: true }),
});
applySettings();

let frame;
let look;
let layout;
const caps = [];
const slots = [];

function size() {
  const mock = !matchMedia("(max-width: 500px), (max-height: 500px) and (pointer: coarse)").matches;
  screen.classList.toggle("mock", mock);
  const scale = mock ? Math.min(1, (innerHeight - 100) / 894) : 1;
  screen.style.transform = scale < 1 ? `scale(${scale})` : "";
  screen.style.marginBottom = scale < 1 ? `${(scale - 1) * 874}px` : "";
  kb.resize(keysView.offsetWidth, screen.offsetHeight, dark.matches);
  render();
}

function scale() {
  return keysView.getBoundingClientRect().width / keysView.offsetWidth || 1;
}

function render() {
  frame = kb.frame();
  look = frame.look;
  const vars = {
    "--radius": `${look.cornerRadius}px`,
    "--letter-size": `${look.letterSize}px`,
    "--label-size": `${look.labelSize}px`,
    "--symbol-box": `${look.symbolSize * 1.15}px`,
    "--letter-offset": `${look.letterOffset}px`,
    "--key": look.key,
    "--key-pressed": look.keyPressed,
    "--label": look.label,
    "--prominent": look.prominent,
    "--prominent-label": look.prominentLabel,
    "--selection": look.selection,
    "--selection-label": look.selectionLabel,
    "--shadow": look.shadow,
    "--candidate": look.candidate,
    "--candidate-highlighted": look.candidateHighlighted,
    "--candidate-pill": look.candidatePill,
    "--candidate-divider": look.candidateDivider,
  };
  for (const [name, value] of Object.entries(vars)) keyboard.style.setProperty(name, value);
  keysView.style.height = `${frame.height}px`;
  if (frame.layout !== layout) {
    layout = frame.layout;
    for (const touch of touches.values()) touch.index = -1;
  }
  renderKeys();
  renderBar();
  spell.render();
}

function renderKeys() {
  frame.caps.forEach((cap, index) => {
    let view = caps[index];
    if (!view) {
      view = caps[index] = document.createElement("div");
      view.className = "key";
      keysView.append(view);
    }
    Object.assign(view.style, { left: `${cap.x}px`, top: `${cap.y}px`, width: `${cap.width}px`, height: `${cap.height}px` });
    const content = `${cap.face}:${cap.label}`;
    if (view.dataset.content !== content) {
      view.dataset.content = content;
      view.innerHTML = face(cap);
    }
    view.classList.toggle("prominent", cap.prominent);
    view.setAttribute("aria-label", cap.face === "symbol" || cap.face === "none" ? cap.action : cap.label);
  });
  caps.splice(frame.caps.length).forEach((view) => view.remove());
  paintTouches();
}

function face(cap) {
  const text = cap.label.replace(/[&<>]/g, (c) => `&#${c.charCodeAt(0)};`);
  switch (cap.face) {
    case "letter": return `<span class="letter">${text}</span>`;
    case "text": return `<span class="text">${text}</span>`;
    case "smallText": return `<span class="small">${text}</span>`;
    case "symbol": return symbols[cap.label] ?? "";
    default: return "";
  }
}

function renderBar() {
  bar.style.visibility = frame.showsSuggestions ? "" : "hidden";
  for (let index = 0; index < 3; index++) {
    let slot = slots[index];
    if (!slot) {
      slot = slots[index] = document.createElement("div");
      slot.className = "slot";
      slot.addEventListener("pointerdown", (event) => {
        event.preventDefault();
        if (slot.textContent) slot.classList.add("pill");
      });
      slot.addEventListener("pointerleave", () => renderBar());
      slot.addEventListener("pointerup", (event) => {
        event.preventDefault();
        if (!slot.textContent) return;
        kb.select(index);
        render();
      });
      bar.append(slot);
    }
    const chip = frame.chips[index];
    slot.textContent = chip?.text ?? "";
    slot.classList.toggle("pill", !!chip?.correction);
  }
}

const touches = new Map();
const callout = Object.assign(document.createElement("div"), { className: "callout", hidden: true });
const accents = Object.assign(document.createElement("div"), { className: "accents", hidden: true });
keyboard.append(callout, accents);
let lastDown = { index: -1, time: 0 };
let deleteRepeat = null;

const capAt = (index) => frame.caps[index];
const point = (event) => {
  const rect = keysView.getBoundingClientRect();
  const s = scale();
  return { x: (event.clientX - rect.left) / s, y: (event.clientY - rect.top) / s };
};

keyboard.addEventListener("pointerdown", (event) => {
  if (event.target.closest(".bar")) return;
  event.preventDefault();
  if (document.activeElement !== field) field.focus({ preventScroll: true });
  keyboard.setPointerCapture(event.pointerId);
  const p = point(event);
  const index = kb.resolve(p.x, p.y);
  if (index < 0) return;
  haptic.keyDown();
  rollOver();
  const now = performance.now();
  const tapCount = lastDown.index === index && now - lastDown.time < 350 ? 2 : 1;
  lastDown = { index, time: tapCount === 2 ? 0 : now };
  const touch = { index, mode: capAt(index).action === "layer" ? "slide" : "typing", start: p, point: p, cursorX: p.x, hold: 0 };
  touches.set(event.pointerId, touch);
  kb.down(index, tapCount);
  if (capAt(index).action === "delete") startDeleteRepeat();
  render();
  scheduleHold(touch);
});

keyboard.addEventListener("pointermove", (event) => {
  const touch = touches.get(event.pointerId);
  if (!touch) return;
  const p = (touch.point = point(event));
  if (touch.mode === "alternates") return trackAccents(p.x);
  if (touch.mode === "trackpad") {
    const step = 9;
    const offset = Math.trunc((p.x - touch.cursorX) / step);
    if (offset) {
      touch.cursorX += offset * step;
      kb.cursor(offset);
    }
    return;
  }
  const index = kb.resolve(p.x, p.y);
  if (index < 0 || index === touch.index) return;
  if (touch.mode !== "slide" && !(capAt(index).isInput && capAt(touch.index)?.isInput)) return;
  clearTimeout(touch.hold);
  touch.index = index;
  paintTouches();
  scheduleHold(touch);
});

keyboard.addEventListener("touchstart", (event) => haptic.needsClicks || event.preventDefault(), { passive: false });
keyboard.addEventListener("mousedown", (event) => event.preventDefault());
keyboard.addEventListener("pointerup", (event) => end(event, true));
keyboard.addEventListener("pointercancel", (event) => end(event, false));

function end(event, commit) {
  const touch = touches.get(event.pointerId);
  if (!touch) return;
  touches.delete(event.pointerId);
  touch.point = point(event);
  finish(touch, commit);
  render();
}

function rollOver() {
  for (const [id, other] of touches) {
    if (other.mode !== "typing" || !capAt(other.index).isInput) continue;
    touches.delete(id);
    finish(other, true);
  }
}

function finish(touch, commit) {
  clearTimeout(touch.hold);
  callout.hidden = true;
  accents.hidden = true;
  if (touch.mode === "trackpad") {
    caps.forEach((view) => view.classList.remove("hidden-label"));
    kb.documentChanged();
  }
  const cap = capAt(touch.index);
  if (!cap) return;
  const { x, y } = touch.point;
  switch (touch.mode) {
    case "alternates":
      if (commit && accents.selected) kb.type(touch.index, accents.selected, x, y);
      break;
    case "trackpad":
      break;
    case "slide":
      if (commit && cap.isInput && cap.typed) kb.slideTyped(cap.typed);
      break;
    default:
      if (!commit) break;
      if (cap.typed) kb.type(touch.index, cap.typed, x, y);
      else if (cap.action === "space") kb.type(touch.index, " ", x, y);
      else kb.trigger(touch.index);
  }
  if (cap.action === "delete") stopDeleteRepeat();
  kb.up(touch.index);
}

function paintTouches() {
  caps.forEach((view) => view.classList.remove("pressed"));
  let preview = null;
  for (const touch of touches.values()) {
    const cap = capAt(touch.index);
    const view = caps[touch.index];
    if (!cap || !view || touch.mode === "trackpad") continue;
    if (touch.mode === "alternates") view.classList.toggle("pressed", look.dimsKeyUnderAccents);
    else if (cap.typed != null && settings.characterPreview) preview = cap;
    else view.classList.add("pressed");
  }
  if (preview) showCallout(preview);
  else callout.hidden = true;
}

function area() {
  return { minX: 0, maxX: frame.width, minY: -(keysView.offsetTop + keyboard.offsetTop) };
}

function showCallout(cap) {
  const r = look.cornerRadius;
  const spread = cap.width * 0.32;
  const height = cap.height * 1.22;
  const neck = cap.height * 0.3;
  const a = area();
  const bubble = { x: cap.x - spread, y: cap.y - neck - height, w: cap.width + spread * 2, h: height };
  bubble.x = Math.min(Math.max(bubble.x, a.minX + 1), a.maxX - bubble.w - 1);
  bubble.y = Math.max(bubble.y, a.minY + 1);
  const left = Math.min(bubble.x, cap.x);
  const top = bubble.y;
  const right = Math.max(bubble.x + bubble.w, cap.x + cap.width);
  const bottom = cap.y + cap.height;
  const b = { minX: bubble.x - left, minY: bubble.y - top, maxX: bubble.x + bubble.w - left, maxY: bubble.y + bubble.h - top };
  const k = { minX: cap.x - left, minY: cap.y - top, maxX: cap.x + cap.width - left, maxY: cap.y + cap.height - top };
  const br = r * 1.4;
  const shoulder = b.maxY;
  const neckTop = Math.max(k.minY, shoulder + r);
  const path = [
    `M${k.minX + r} ${k.maxY}`,
    `A${r} ${r} 0 0 1 ${k.minX} ${k.maxY - r}`,
    `L${k.minX} ${neckTop}`,
    `C${k.minX} ${neckTop - (neckTop - shoulder) * 0.6} ${b.minX} ${shoulder + (neckTop - shoulder) * 0.2} ${b.minX} ${shoulder - br}`,
    `L${b.minX} ${b.minY + br}`,
    `A${br} ${br} 0 0 1 ${b.minX + br} ${b.minY}`,
    `L${b.maxX - br} ${b.minY}`,
    `A${br} ${br} 0 0 1 ${b.maxX} ${b.minY + br}`,
    `L${b.maxX} ${shoulder - br}`,
    `C${b.maxX} ${shoulder + (neckTop - shoulder) * 0.2} ${k.maxX} ${neckTop - (neckTop - shoulder) * 0.6} ${k.maxX} ${neckTop}`,
    `L${k.maxX} ${k.maxY - r}`,
    `A${r} ${r} 0 0 1 ${k.maxX - r} ${k.maxY}`,
    "Z",
  ].join(" ");
  Object.assign(callout.style, { left: `${left + keysView.offsetLeft}px`, top: `${top + keysView.offsetTop}px`, width: `${right - left}px`, height: `${bottom - top}px` });
  callout.innerHTML = `<svg width="${right - left}" height="${bottom - top}"><path d="${path}" fill="var(--key)"/></svg><span></span>`;
  const label = callout.querySelector("span");
  label.textContent = cap.shown;
  Object.assign(label.style, { left: `${b.minX}px`, top: `${b.minY - look.keyHeight * 0.06}px`, width: `${bubble.w}px`, height: `${bubble.h}px` });
  callout.hidden = false;
}

function scheduleHold(touch) {
  const cap = capAt(touch.index);
  if (touch.mode !== "typing") return;
  const isSpace = cap.action === "space";
  if (!isSpace && cap.alternates.length <= 1) return;
  touch.hold = setTimeout(() => {
    if (touch.mode !== "typing" || ![...touches.values()].includes(touch)) return;
    if (isSpace) {
      touch.mode = "trackpad";
      caps.forEach((view) => view.classList.add("hidden-label"));
    } else {
      touch.mode = "alternates";
      callout.hidden = true;
      showAccents(cap);
    }
    paintTouches();
  }, isSpace ? 400 : 450);
}

function showAccents(cap) {
  const options = cap.alternates;
  const padding = 10;
  const cell = cap.width + 4;
  const height = cap.height * 1.57;
  const width = cell * options.length + padding * 2;
  const base = Math.max(options.indexOf(cap.shown), 0);
  const a = area();
  const x = Math.min(Math.max(cap.x + cap.width / 2 - padding - cell * (base + 0.5), a.minX + 7), a.maxX - width - 7);
  const y = Math.max(cap.y - height - 3, a.minY + 1);
  Object.assign(accents.style, {
    left: `${x + keysView.offsetLeft}px`, top: `${y + keysView.offsetTop}px`, width: `${width}px`, height: `${height}px`, borderRadius: `${look.cornerRadius * 2}px`,
  });
  accents.innerHTML = `<div class="highlight"></div>` + options.map((option, index) => `<div class="cell" style="left:${padding + index * cell}px;width:${cell}px;height:${height}px"></div>`).join("");
  accents.querySelectorAll(".cell").forEach((view, index) => (view.textContent = options[index]));
  Object.assign(accents, { options, cell, padding, originX: x, highlightHeight: cap.height + 4 });
  accents.hidden = false;
  selectAccent(base);
}

function trackAccents(x) {
  selectAccent(Math.min(Math.max(Math.floor((x - accents.originX - accents.padding) / accents.cell), 0), accents.options.length - 1));
}

function selectAccent(index) {
  accents.selected = accents.options[index];
  accents.querySelectorAll(".cell").forEach((view, offset) => view.classList.toggle("selected", offset === index));
  Object.assign(accents.querySelector(".highlight").style, {
    left: `${accents.padding + index * accents.cell}px`,
    top: `${(accents.offsetHeight - accents.highlightHeight) / 2}px`,
    width: `${accents.cell}px`,
    height: `${accents.highlightHeight}px`,
    borderRadius: `${look.cornerRadius * 1.25}px`,
  });
}

function startDeleteRepeat() {
  let count = 0;
  const fire = () => {
    count += 1;
    const words = count > 20;
    kb.repeatDelete(words);
    render();
    deleteRepeat = setTimeout(fire, words ? 250 : 100);
  };
  deleteRepeat = setTimeout(fire, 500);
}

function stopDeleteRepeat() {
  clearTimeout(deleteRepeat);
  deleteRepeat = null;
}

const external = () => {
  if (expected && expected.value === field.value && expected.start === field.selectionStart && expected.end === field.selectionEnd) return;
  remember();
  spell.editing = false;
  kb.documentChanged();
  render();
};
field.addEventListener("input", external);
document.addEventListener("selectionchange", () => document.activeElement === field && external());
field.addEventListener("select", external);
document.addEventListener("visibilitychange", () => document.hidden && kb.endSession());

dark.addEventListener("change", size);
addEventListener("resize", size);
size();
remember();
field.focus({ preventScroll: true });
