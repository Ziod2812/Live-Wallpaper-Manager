pragma Singleton
import QtQuick
QtObject {
    property string state: "RUNNING"
    function transition(paused) {
        state = paused ? "PAUSED" : "RUNNING"
        return state
    }
}
