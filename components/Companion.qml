import QtQuick
import Quickshell
import Quickshell.Io

// The notification companion's setup state: whether it is installed, enabled and
// current, and installing it when it is not. Kept out of Island.qml, which only
// needs the status and the sentence to show for it.
Item {
  id: companion
  required property var host

  // The companion ships inside the plugin, next to this file's parent.
  readonly property string dir: host.pluginDir + "/companion"

  property string status: ""
  property bool installing: false
  readonly property bool needsSetup: status !== "" && status !== "ok"
  readonly property string warning: installing ? "Installing notifications…"
    : status === "missing" ? "Set up notifications"
    : status === "outdated" ? "Update notifications"
    : status === "not-enabled" ? "Enable notifications"
    : status === "menu" ? "Set up switchers"
    : "Notifications need setup"

  function check() { if (!checkProc.running) checkProc.running = true }

  function install() {
    if (installProc.running) return
    companion.installing = true
    installProc.command = ["bash", companion.dir + "/install.sh"]
    installProc.running = true
  }

  // The check is what tells the island whether the setup pill is needed at all,
  // so it runs once as soon as this exists.
  Component.onCompleted: companion.check()

  Process {
    id: checkProc
    command: ["bash", companion.dir + "/check.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: companion.status = String(text || "").trim()
    }
  }

  Process {
    id: installProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text) console.warn("island: companion install:", text)
    }
    onExited: function(code) {
      companion.installing = false
      companion.check()
    }
  }
}
