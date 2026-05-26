// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

window.addEventListener("phx:sync_selected", (e) => {
  const set = new Set((e.detail.ids || []).map(String))
  document.querySelectorAll('input[type=checkbox][phx-click="toggle_select"]').forEach(cb => {
    cb.checked = set.has(cb.getAttribute("phx-value-id"))
  })
})

window.printViaIframe = function(url) {
  const iframe = document.createElement("iframe")
  iframe.style.cssText = "position:fixed;left:-10000px;top:0;width:0;height:0;border:0;"
  iframe.src = url
  iframe.addEventListener("load", () => {
    setTimeout(() => {
      const win = iframe.contentWindow
      win.focus()
      if (typeof win.printElement === "function") {
        win.printElement("print-me")
      } else {
        win.print()
      }
      const cleanup = () => { if (iframe.parentNode) iframe.parentNode.removeChild(iframe) }
      win.addEventListener("afterprint", cleanup)
      setTimeout(cleanup, 60000)
    }, 200)
  })
  document.body.appendChild(iframe)
}

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

