function assetsForBackground(path) {
  var background = String(path || "").trim()
  var slash = background.lastIndexOf("/")
  var fileName = slash >= 0 ? background.slice(slash + 1) : ""
  var extension = fileName.lastIndexOf(".")

  if (!background.startsWith("/") || slash < 0 || extension <= 0) {
    return { videoPath: "", firstFramePath: "" }
  }

  var directory = background.slice(0, slash)
  var name = fileName.slice(0, extension)
  var startupDirectory = directory + "/startup/" + name

  return {
    videoPath: startupDirectory + "/video.mp4",
    firstFramePath: startupDirectory + "/first-frame.webp"
  }
}

function sessionClaimPath(runtimeDirectory, hyprlandSignature) {
  var runtime = String(runtimeDirectory || "").trim().replace(/\/+$/, "")
  var signature = String(hyprlandSignature || "").trim()

  if (!runtime.startsWith("/") || !/^[A-Za-z0-9_.-]+$/.test(signature)) return ""
  return runtime + "/omarchy-startup-background-video-" + signature
}

if (typeof module !== "undefined") {
  module.exports = {
    assetsForBackground: assetsForBackground,
    sessionClaimPath: sessionClaimPath
  }
}
