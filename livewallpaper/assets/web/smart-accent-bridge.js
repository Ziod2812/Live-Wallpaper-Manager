/**
 * smart-accent-bridge.js
 * ==========================================================================
 * Cầu nối (bridge) cho Web Wallpaper (Canvas/HTML) đọc màu "Smart Accent
 * Color" runtime, được apply_smart_color.py ghi liên tục vào
 * /tmp/livewallpaper_color.current mỗi khi người dùng đổi wallpaper.
 *
 * CÁCH DÙNG
 * --------------------------------------------------------------------------
 * Thêm một dòng vào tệp HTML wallpaper của bạn (trước script vẽ hiệu ứng
 * hạt/đồ hoạ của bạn):
 *
 *     <script src="/duong/dan/toi/smart-accent-bridge.js"></script>
 *
 * Sau đó, hiệu ứng của bạn có 2 cách để lấy màu mới nhất:
 *
 *   1) THUẦN CSS (không cần sửa JS): dùng biến CSS `--lw-accent` mà bridge
 *      này tự set trên <html> mỗi khi màu đổi:
 *
 *          .particle { background: var(--lw-accent, #353446); }
 *
 *   2) JAVASCRIPT: lắng nghe sự kiện tuỳ biến "lw:accentchange" trên
 *      `document`, hoặc đọc trực tiếp `window.LWSmartAccent.current`:
 *
 *          document.addEventListener("lw:accentchange", (e) => {
 *              // e.detail = { hex: "#RRGGBB", r, g, b }
 *              particleSystem.setColor(e.detail.hex);
 *          });
 *
 *          // Hoặc đọc giá trị hiện có bất cứ lúc nào (không cần đợi event):
 *          const hex = window.LWSmartAccent.current; // "#RRGGBB"
 *
 * VÌ SAO LÀ POLLING (không phải WebSocket/EventSource)
 * --------------------------------------------------------------------------
 * Web Wallpaper ở đây được mpvpaper/mpv phát trực tiếp (định dạng "url")
 * hoặc chạy trong một trình duyệt kiosk cục bộ (định dạng "local" -- xem
 * scripts/_web_worker.sh). Không có tiến trình server nào chạy nền để đẩy
 * (push) sự kiện xuống — cách đơn giản, không phụ thuộc thêm hạ tầng nào,
 * là định kỳ đọc lại tệp `/tmp/livewallpaper_color.current` bằng fetch().
 * Khoảng polling mặc định 1000ms là đủ nhanh để cảm giác "runtime" trong
 * khi gần như không tốn CPU.
 *
 * THIẾT KẾ PHÒNG VỆ (Defensive Coding)
 * --------------------------------------------------------------------------
 * - Không bao giờ throw ra ngoài: mọi lỗi fetch (tệp chưa tồn tại, trình
 *   duyệt chặn truy cập file://, mạng tạm thời gián đoạn với mpv's CEF nếu
 *   có) đều bị nuốt (catch) và bridge tự thử lại ở vòng poll kế tiếp.
 * - Không polling dồn dập: dùng setTimeout đệ quy (không phải setInterval)
 *   nên một lần fetch bị treo/chậm không bao giờ chồng lấn với lần kế tiếp.
 * - Bỏ qua giá trị không đổi: chỉ dispatch "lw:accentchange" và set biến
 *   CSS khi màu THỰC SỰ khác lần trước, để không spam listener/reflow CSS
 *   mỗi giây ngay cả khi màu không đổi qua nhiều phút.
 * - Dừng poll sạch khi trang bị unload (không để lại timer treo).
 */
(function () {
    "use strict";

    // Đường dẫn mặc định khớp với apply_smart_color.py's TMP_COLOR_FILE.
    // Có thể override trước khi script này chạy bằng:
    //   window.LW_SMART_ACCENT_FILE = "file:///duong/dan/khac";
    var COLOR_FILE_URL =
        window.LW_SMART_ACCENT_FILE || "file:///tmp/livewallpaper_color.current";

    // Có thể override tốc độ polling (ms) trước khi script chạy bằng:
    //   window.LW_SMART_ACCENT_POLL_MS = 500;
    var POLL_INTERVAL_MS = Number(window.LW_SMART_ACCENT_POLL_MS) || 1000;

    var FALLBACK_HEX = "#353446";
    var HEX_RE = /^#[0-9a-fA-F]{6}$/;

    var lastHex = null;
    var pollTimer = null;
    var stopped = false;

    function hexToRgb(hex) {
        var n = parseInt(hex.slice(1), 16);
        return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
    }

    function applyColor(hex) {
        if (hex === lastHex) return; // không đổi -- không làm gì cả
        lastHex = hex;

        // 1) Biến CSS -- mọi phần tử trong trang có thể dùng var(--lw-accent)
        //    mà không cần JS riêng.
        try {
            document.documentElement.style.setProperty("--lw-accent", hex);
        } catch (e) {
            /* documentElement chưa sẵn sàng (rất hiếm) -- bỏ qua, lần poll
               sau sẽ tự thử lại vì lastHex đã được set nên chỉ mất 1 nhịp. */
        }

        // 2) Sự kiện tuỳ biến cho code JS của wallpaper.
        var rgb = hexToRgb(hex);
        try {
            document.dispatchEvent(
                new CustomEvent("lw:accentchange", {
                    detail: { hex: hex, r: rgb.r, g: rgb.g, b: rgb.b },
                })
            );
        } catch (e) {
            /* CustomEvent không khả dụng trên môi trường siêu cũ -- bỏ qua,
               window.LWSmartAccent.current vẫn được cập nhật bên dưới. */
        }
    }

    function poll() {
        if (stopped) return;

        fetch(COLOR_FILE_URL, { cache: "no-store" })
            .then(function (res) {
                if (!res.ok) throw new Error("bad status");
                return res.text();
            })
            .then(function (text) {
                var hex = String(text || "").trim().toUpperCase();
                applyColor(HEX_RE.test(hex) ? hex : FALLBACK_HEX);
            })
            .catch(function () {
                // Tệp chưa tồn tại / trình duyệt chặn file:// fetch (cần cờ
                // --allow-file-access-from-files khi chạy Chromium kiosk,
                // xem _web_worker.sh) / lỗi mạng tạm thời -- không throw,
                // chỉ giữ nguyên màu hiện tại và thử lại ở vòng sau.
                if (lastHex === null) applyColor(FALLBACK_HEX);
            })
            .finally(function () {
                if (!stopped) {
                    pollTimer = setTimeout(poll, POLL_INTERVAL_MS);
                }
            });
    }

    function stop() {
        stopped = true;
        if (pollTimer !== null) {
            clearTimeout(pollTimer);
            pollTimer = null;
        }
    }

    window.addEventListener("beforeunload", stop);

    // API công khai tối giản cho code wallpaper không muốn lắng nghe event.
    window.LWSmartAccent = {
        get current() {
            return lastHex || FALLBACK_HEX;
        },
        stop: stop,
    };

    poll();
})();
