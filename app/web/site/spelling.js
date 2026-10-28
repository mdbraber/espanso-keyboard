const canvas = document.createElement("canvas").getContext("2d");

export function spelling(field, misspellings) {
  const layer = Object.assign(document.createElement("div"), { className: "spelling" });
  layer.setAttribute("aria-hidden", "true");
  field.after(layer);
  field.addEventListener("scroll", () => (layer.scrollTop = field.scrollTop));
  let drawn = "";

  const spell = {
    enabled: true,
    editing: false,
    render() {
      layer.hidden = !spell.enabled;
      if (!spell.enabled) return;
      const text = field.value;
      const caret = spell.editing && field.selectionStart === field.selectionEnd ? field.selectionStart : -1;
      const ranges = [];
      const offsets = misspellings(text);
      for (let i = 0; i < offsets.length; i += 2) {
        if (caret < offsets[i] || caret > offsets[i + 1]) ranges.push([offsets[i], offsets[i + 1]]);
      }
      Object.assign(layer.style, {
        left: `${field.offsetLeft + field.clientLeft}px`,
        top: `${field.offsetTop + field.clientTop}px`,
        width: `${field.clientWidth}px`,
        height: `${field.clientHeight}px`,
      });
      const key = `${field.clientWidth}:${field.clientHeight}:${JSON.stringify(ranges)}:${text}`;
      if (key !== drawn) {
        drawn = key;
        draw(text, ranges);
      }
      layer.scrollTop = field.scrollTop;
    },
  };

  function draw(text, ranges) {
    const words = [];
    const content = document.createElement("div");
    let end = 0;
    for (const [start, stop] of ranges) {
      const word = Object.assign(document.createElement("span"), { textContent: text.slice(start, stop) });
      content.append(text.slice(end, start), word);
      words.push(word);
      end = stop;
    }
    content.append(`${text.slice(end)}​`);
    layer.replaceChildren(content);

    const style = getComputedStyle(field);
    const size = parseFloat(style.fontSize);
    canvas.font = `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    const ascent = Math.round(canvas.measureText("x").fontBoundingBoxAscent);
    const dot = 0.13247 * size;
    const gap = 0.09457 * size;
    const origin = layer.getBoundingClientRect();
    const scale = origin.width / layer.offsetWidth || 1;
    for (const word of words) {
      for (const rect of word.getClientRects()) {
        const width = rect.width / scale;
        const count = Math.floor((width + gap) / (dot + gap));
        if (count < 1) continue;
        const span = count * dot + (count - 1) * gap;
        const dots = document.createElementNS("http://www.w3.org/2000/svg", "svg");
        dots.setAttribute("width", span);
        dots.setAttribute("height", dot);
        dots.innerHTML = Array.from({ length: count }, (_, i) => `<circle cx="${dot / 2 + i * (dot + gap)}" cy="${dot / 2}" r="${dot / 2}"/>`).join("");
        Object.assign(dots.style, {
          left: `${(rect.left - origin.left) / scale + layer.scrollLeft + (width - span) / 2}px`,
          top: `${(rect.top - origin.top) / scale + layer.scrollTop + ascent + 0.11035 * size}px`,
        });
        layer.append(dots);
      }
    }
  }

  return spell;
}
