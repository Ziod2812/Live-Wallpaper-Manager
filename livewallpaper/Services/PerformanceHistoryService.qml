pragma Singleton
import Quickshell
import QtQuick

QtObject {
    property var samples: []
    property int maxSamples: 300

    function addSample(gpu, cpu, ram) {
        // PERFORMANCE FIX: mutate the existing array in place instead of
        // copying it every tick. PerformanceHistoryCard samples at 1Hz and
        // this array can hold up to maxSamples entries (default 300, up to
        // 7200 for a 2-hour window) -- the old `(samples || []).slice()` +
        // repeated `.shift()` pattern cloned the entire array AND shifted
        // its head on every single tick: O(n) garbage per second that grew
        // linearly with the window size (~57 KB/s of discarded array slots
        // at 1Hz with 7200 samples). In-place push + one bounded `splice`
        // is O(1) amortized no matter how long the history gets.
        //
        // The card calls canvas.requestPaint() itself after every
        // addSample(), so repaint never depends on the array identity
        // changing; assigning `samples = arr` below is kept so
        // resetHistory()'s fresh [] (a genuine identity change) still
        // notifies onSamplesChanged listeners exactly as before.
        const arr = Array.isArray(samples) ? samples : [];
        arr.push({
            "gpu": Number(gpu) || 0,
            "cpu": Number(cpu) || 0,
            "ram": Number(ram) || 0
        });

        const limit = Math.max(2, Number(maxSamples) || 300);
        const excess = arr.length - limit;
        if (excess > 0)
            arr.splice(0, excess);

        samples = arr;
    }
}
