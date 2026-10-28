const storageKey = "hex.settings";

const defaults = {
  autoCapitalization: true,
  autoCorrection: true,
  capsLock: true,
  predictiveText: true,
  checkSpelling: true,
  smartPunctuation: true,
  characterPreview: true,
  periodShortcut: true,
  haptic: false,
};

export const settings = (() => {
  try {
    return { ...defaults, ...JSON.parse(localStorage.getItem(storageKey)) };
  } catch {
    return { ...defaults };
  }
})();

function save() {
  try {
    localStorage.setItem(storageKey, JSON.stringify(settings));
  } catch {}
}

export function settingsSheet({ root, opener, haptics, onChange, onClose }) {
  const sections = [
    {
      footer: haptics.note,
      rows: [
        ["characterPreview", "Character Preview"],
        ["haptic", "Haptic Feedback"],
      ],
    },
    {
      title: "All Keyboards",
      footer: "Double tapping the space bar will insert a period followed by a space.",
      rows: [
        ["autoCapitalization", "Auto-Capitalization"],
        ["autoCorrection", "Auto-Correction"],
        ["predictiveText", "Predictive Text"],
        ["checkSpelling", "Check Spelling and Grammar"],
        ["capsLock", "Enable Caps Lock"],
        ["smartPunctuation", "Smart Punctuation"],
        ["periodShortcut", "“.” Shortcut"],
      ],
    },
  ];
  const native = "switch" in HTMLInputElement.prototype;
  const sheet = root.querySelector(".sheet");
  sheet.querySelector(".sections").innerHTML = sections
    .map(({ title, footer, rows }) => `
      ${title ? `<h3>${title}</h3>` : ""}
      <div class="group">${rows.map(([key, name]) => `
        <label class="row"><span>${name}</span><input type="checkbox" ${native ? "switch" : 'class="switch"'} data-key="${key}"></label>`).join("")}
      </div>
      ${footer ? `<p class="footer">${footer}</p>` : ""}`)
    .join("");

  for (const toggle of sheet.querySelectorAll("input[data-key]")) {
    toggle.checked = settings[toggle.dataset.key];
    toggle.addEventListener("change", () => {
      settings[toggle.dataset.key] = toggle.checked;
      save();
      onChange();
    });
  }
  const haptic = sheet.querySelector('[data-key="haptic"]');
  haptic.disabled = !haptics.available;
  haptic.checked &&= haptics.available;

  const setOpen = (open) => {
    root.classList.toggle("open", open);
    sheet.inert = !open;
    if (!open) onClose();
  };
  sheet.inert = true;
  opener.addEventListener("click", () => setOpen(true));
  root.querySelector(".scrim").addEventListener("click", () => setOpen(false));
  sheet.querySelector(".done").addEventListener("click", () => setOpen(false));
  addEventListener("keydown", (event) => event.key === "Escape" && root.classList.contains("open") && setOpen(false));
}
