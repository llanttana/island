import QtQuick
import Quickshell
import Quickshell.Io

// Live CPU / memory / temperature for the system-monitor live activity and its
// page. One sampler runs every couple of seconds and both consumers read the
// same numbers, so opening the page does not start a second poll.
Item {
  id: stats

  property real cpu: 0          // percent, 0-100
  property bool ready: false     // true once a sample has landed
  property real memUsed: 0      // bytes
  property real memTotal: 0     // bytes
  property int temp: 0          // degrees Celsius, 0 when unreadable
  property var cpuHistory: []   // newest last, up to 60 samples (~2 min)
  property var memHistory: []
  property var tempHistory: []
  readonly property real memFraction: stats.memTotal > 0 ? stats.memUsed / stats.memTotal : 0
  readonly property real memPercent: Math.round(stats.memFraction * 100)

  readonly property string script:
    'c1=$(awk \'/^cpu /{print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}\' /proc/stat)\n' +
    'sleep 0.35\n' +
    'c2=$(awk \'/^cpu /{print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}\' /proc/stat)\n' +
    't1=${c1%% *}; i1=${c1##* }\n' +
    't2=${c2%% *}; i2=${c2##* }\n' +
    'dt=$((t2-t1)); di=$((i2-i1))\n' +
    'cpu=$(awk -v dt=$dt -v di=$di \'BEGIN{if(dt<=0){print 0}else{printf "%.0f", (1-di/dt)*100}}\')\n' +
    'total=$(awk \'/MemTotal/{print $2}\' /proc/meminfo)\n' +
    'avail=$(awk \'/MemAvailable/{print $2}\' /proc/meminfo)\n' +
    'used=$((total-avail))\n' +
    'temp=0\n' +
    'for f in /sys/class/hwmon/hwmon*/temp*_input; do\n' +
    '  [ -e "$f" ] || continue\n' +
    '  name=$(cat "${f%/*}/name" 2>/dev/null)\n' +
    '  case "$name" in k10temp|coretemp|zenpower|cpu_thermal|acpitz) ;; *) continue;; esac\n' +
    '  v=$(cat "$f" 2>/dev/null) || continue\n' +
    '  [ -n "$v" ] || continue\n' +
    '  t=$((v/1000))\n' +
    '  [ "$t" -gt "$temp" ] && temp=$t\n' +
    'done\n' +
    'printf \'{"cpu":%s,"memUsed":%s,"memTotal":%s,"temp":%s}\\n\' "$cpu" "$used" "$total" "$temp"\n'

  Process {
    id: sampler
    command: ["bash", "-c", stats.script]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: stats.apply(String(text || ""))
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!sampler.running) sampler.running = true
  }

  function push(history, value) {
    var next = history.concat([value])
    return next.length > 60 ? next.slice(next.length - 60) : next
  }

  function apply(raw) {
    var line = String(raw || "").trim().split("\n").pop()
    if (line === "") return
    try {
      var d = JSON.parse(line)
      stats.cpu = Math.max(0, Math.min(100, Number(d.cpu) || 0))
      stats.memTotal = (Number(d.memTotal) || 0) * 1024
      stats.memUsed = (Number(d.memUsed) || 0) * 1024
      stats.temp = Number(d.temp) || 0
      stats.cpuHistory = stats.push(stats.cpuHistory, stats.cpu)
      stats.memHistory = stats.push(stats.memHistory, stats.memPercent)
      stats.tempHistory = stats.push(stats.tempHistory, stats.temp)
      stats.ready = true
    } catch (e) {
      // A malformed sample is not worth breaking the pill over.
    }
  }
}
