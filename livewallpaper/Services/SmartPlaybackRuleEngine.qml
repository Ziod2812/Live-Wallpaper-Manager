pragma Singleton
import QtQuick
QtObject {
    function evaluate(ctx) {
        if (ctx.locked) return {paused:true, reason:"screen locked"}
        if (ctx.sleeping) return {paused:true, reason:"monitor asleep"}
        if (ctx.gaming) return {paused:true, reason:"gaming"}
        if (ctx.fullscreen) return {paused:true, reason:"fullscreen application"}
        if (ctx.battery) return {paused:true, reason:"on battery"}
        return {paused:false, reason:""}
    }
}
