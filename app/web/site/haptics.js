// iOS has no navigator.vibrate. A switch plays the system haptic when a trusted click toggles it,
// and since iOS 26.5 a script's label.click() no longer counts
// (https://github.com/WebKit/WebKit/commit/fc1ef83eae), so a real tap has to land on a label that
// holds the switch. iOS makes that click when the finger lifts, so the tick comes on key up.
export function haptics(surface) {
  const touch = matchMedia("(pointer: coarse)").matches;
  const bySwitch = touch && "switch" in HTMLInputElement.prototype;
  const byVibrate = touch && !bySwitch && "vibrate" in navigator;
  const label = Object.assign(document.createElement("label"), { className: "haptic", hidden: true });
  label.setAttribute("aria-hidden", "true");
  label.innerHTML = `<input type="checkbox" switch>`;
  surface.append(label);
  let on = false;
  return {
    available: bySwitch || byVibrate,
    note: bySwitch
      ? "A web page can only play the haptic as your finger lifts off a key, not as it lands like Apple’s keyboard."
      : byVibrate ? "" : "This browser can’t play haptics.",
    set enabled(value) {
      on = value;
      label.hidden = !(on && bySwitch);
    },
    get needsClicks() {
      return on && bySwitch;
    },
    keyDown() {
      if (on && byVibrate) navigator.vibrate(10);
    },
  };
}
