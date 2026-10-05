#!/usr/bin/env node
// The transient branch of the notification companion: what Island does with a
// notification nobody looks back at.
//
// Expected behaviour, from the code in Service.qml:
//   - the preview is not affected: a toast is shown or silenced purely by DND;
//   - with DND off, both normal and transient toasts land in history like any
//     other once they leave the screen;
//   - with DND on, a normal notification is written straight into history (so
//     you can see what you missed) and a transient one is dropped entirely.
//
// So isEphemeral() decides exactly one thing: whether a DND-silenced
// notification is worth recording. This test runs the real function, taken out
// of Service.qml, rather than a copy of it, and checks that the branch around
// it still guards the history write with it.
const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '..')
const servicePath = path.join(root, 'companion/lanta.notifications/Service.qml')
const logicPath = path.join(root, 'companion/lanta.notifications/NotificationLogic.js')

const service = fs.readFileSync(servicePath, 'utf8')
const NotificationLogic = require(logicPath)

// Take the function out of the QML by matching braces, not by indentation, and
// with comments stripped first so a brace inside one cannot throw the count.
function extractFunction(source, name) {
  const code = source.replace(/^\s*\/\/.*$/gm, '')
  const start = code.indexOf('function ' + name + '(')
  if (start < 0) return null
  let depth = 0
  for (let i = code.indexOf('{', start); i < code.length; i++) {
    if (code[i] === '{') depth++
    else if (code[i] === '}') {
      depth--
      if (depth === 0) return code.slice(start, i + 1)
    }
  }
  return null
}

let failed = 0
function check(name, actual, expected) {
  const ok = actual === expected
  if (!ok) failed++
  console.log(`  ${ok ? 'ok   ' : 'FAIL '} ${name}${ok ? '' : ` -- expected ${expected}, got ${actual}`}`)
}

const fn = extractFunction(service, 'isEphemeral')
if (!fn) {
  console.log('  FAIL  isEphemeral() was not found in Service.qml')
  process.exit(1)
}
const isEphemeral = new Function('NotificationLogic', fn + '\n; return isEphemeral;')(NotificationLogic)

console.log('  what isEphemeral() decides')
check('a normal notification is not ephemeral', isEphemeral({ appName: 'Meeting', hints: {} }), false)
check('the transient hint makes one ephemeral', isEphemeral({ appName: 'Meeting', hints: { transient: true } }), true)
check('a false hint does not', isEphemeral({ appName: 'Meeting', hints: { transient: false } }), false)
check('missing hints do not throw or count', isEphemeral({ appName: 'Meeting', hints: null }), false)
check('notify-send is ephemeral by name', isEphemeral({ appName: 'notify-send', hints: {} }), true)
check('omarchy-action is ephemeral by name', isEphemeral({ appName: 'omarchy-action', hints: {} }), true)

// The branch itself. isEphemeral() only matters where the companion decides
// whether a silenced notification is written, so that wiring is worth pinning:
// if the guard ever loses its negation, every silenced notification is recorded
// and the ephemeral ones stop being dropped.
console.log('  how the DND branch uses it')
const silenced = service.slice(service.indexOf('if (service.doNotDisturb && !shouldBypassDnd'))
check('the silenced path is guarded by !isEphemeral(...)',
  /if \(!isEphemeral\(notification\)\)/.test(silenced), true)
check('the silenced path writes history only inside that guard',
  silenced.indexOf('writeSilenced(') > silenced.indexOf('if (!isEphemeral(notification))'), true)

console.log(failed === 0 ? '  all good' : `  ${failed} failed`)
process.exit(failed === 0 ? 0 : 1)
