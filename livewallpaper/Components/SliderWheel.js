.pragma library

/*
 * SliderWheel.js
 * ----------------
 * The one wheel-to-value mapping used by every slider in this app.
 * SettingSlider.qml (Components/) is the single restyled QQCB.Slider
 * component -- used for the MusicDockPanel.qml param sliders and for
 * the seek/progress sliders in StreamingPanel.qml and MusicDock.qml --
 * and it's the only file that imports this module, so the wheel math
 * lives in exactly one place for every slider instance in the app.
 *
 * apply(slider, wheelEvent) reads the slider's own from/to/stepSize,
 * computes the new value for the wheel event's modifiers, writes
 * slider.value, and emits slider.moved() -- the same signal a real
 * drag/keypress emits -- so every call site's existing `onMoved`
 * handler (SettingsService.set(...), PlaybackService.seek(...),
 * MprisService.seek(...)) fires exactly as it already does today.
 * Nothing about those handlers changes.
 *
 * Step sizing, per the product spec:
 *   - plain wheel:   +/- 1 step
 *   - Shift + wheel: +/- 10 steps
 *   - Ctrl + wheel:  +/- 0.1 step (fine adjustment)
 * "1 step" is slider.stepSize when the slider declares one (Width,
 * Height, Corner radius, Album art size, Bar width/spacing,
 * Sensitivity, Animation speed all do). For continuous sliders with no
 * stepSize (Opacity, and the playback/seek position sliders), "1 step"
 * falls back to 1% of the slider's range, which makes Shift's "10
 * steps" land exactly on the "10% of range" the spec calls out for
 * floating-point sliders, and Ctrl's "0.1 step" land on 0.1% -- a
 * genuinely fine nudge -- without needing a separate code path.
 */

function apply(slider, wheel) {
    var range = slider.to - slider.from;
    if (!(range > 0)) return;

    var baseStep = slider.stepSize > 0 ? slider.stepSize : range * 0.01;

    var magnitude = baseStep;
    if (wheel.modifiers & Qt.ControlModifier) {
        magnitude = baseStep * 0.1;
    } else if (wheel.modifiers & Qt.ShiftModifier) {
        magnitude = baseStep * 10;
    }

    // angleDelta is in eighths of a degree; +/-120 is one physical
    // notch. Dividing by 120 also gives fractional "notches" for
    // smooth/high-res trackpad wheels, so those scrub continuously
    // instead of jumping.
    var notches = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y / 120
                                            : wheel.angleDelta.x / 120;
    if (notches === 0) return;

    var newValue = slider.value + notches * magnitude;

    // Keep discrete sliders on their declared grid.
    if (slider.stepSize > 0) {
        newValue = slider.from + Math.round((newValue - slider.from) / slider.stepSize) * slider.stepSize;
    }

    newValue = Math.max(slider.from, Math.min(slider.to, newValue));

    if (newValue !== slider.value) {
        slider.value = newValue;
        slider.moved();
    }

    wheel.accepted = true;
}
