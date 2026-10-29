const { Plugin, Panel, Command } = require("@opencode/plugin/gui")

let frame = null

function getFrame() {
  if (frame && frame.isConnected) return frame
  frame = document.createElement("iframe")
  frame.src = "http://127.0.0.1:8770/"
  frame.title = "剧情编辑器"
  frame.style.cssText = "display:block;width:100%;height:100%;border:0;background:#171310"
  return frame
}

module.exports = Plugin.define({
  setup(ctx) {
    ctx.add(Panel, {
      id: "web",
      region: "side",
      list: () => [{ id: "web", title: "剧情编辑器", closable: "compact", fallback: true }],
      render: () => getFrame(),
    })
    ctx.add(Command, () => ({
      id: "open",
      title: "打开剧情编辑器",
      run: () => {
        const s = ctx.sessions.current()
        if (s) ctx.layout.open(ctx.id + ":web", s)
      },
    }))
  },
})
