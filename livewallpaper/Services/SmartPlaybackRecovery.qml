pragma Singleton
import QtQuick
QtObject {
    property int retries: 0
    function reset(){ retries = 0 }
}
