import fs from 'node:fs'
import path from 'node:path'
import {fileURLToPath} from 'node:url'

// Only reviewed packaging adapters may differ. Changed adapters fail closed.
const adapters = JSON.parse(fs.readFileSync(new URL('./lab-packaging.json', import.meta.url)))
export function normalize(text, file, side) {
  if (file === 'manifest.json') {
    const manifest = JSON.parse(text)
    for (const key of ['id', 'name', 'version', 'author', 'license', 'homepage']) delete manifest[key]
    return JSON.stringify(manifest)
  }
  if (file === 'bin/omarchy-lab-vm') {
    for (const [name, body] of Object.entries(adapters[side])) {
      if (!text.includes(body)) throw new Error(`${side}: review changed packaging adapter ${name}`)
      text = text.replace(body, `${name}() { PACKAGING_ADAPTER; }`)
    }
  }
  text = text.replaceAll('acrogenesis.lab', 'omarchy.lab').replaceAll('omarchy-labctl', 'omarchy lab')
  text = text.replace(/^source .*\/omarchy-lab-runtime"\n\n?/m, '')
  text = text.replace(/^source "\$\(dirname .*\/([^"]+)"$/gm, 'source "$OMARCHY_PATH/bin/$1"')
  text = text.replaceAll('$LAB_ROOT', '$OMARCHY_PATH')
  if (file.endsWith('.qml')) {
    const helper = text.match(/  function labCommand\(name\) \{\n([^]*?)\n  }\n/)
    if (helper) {
      const body = helper[1].trim()
      const native = 'if (name.startsWith("/")) return name\n    return Quickshell.env("OMARCHY_PATH") + "/bin/" + name'
      const standalone = 'if (name.startsWith("/")) return name\n    return decodeURIComponent(String(Qt.resolvedUrl("bin/" + name)).replace(/^file:\\/\\//, ""))'
      if (body !== native && body !== standalone) throw new Error(`${side}: review changed QML path adapter`)
      text = text.replace('\n' + helper[0], '')
    }
    text = text.replace(/(?:root\.)?labCommand\(("[^"]+"|command)\)/g, '$1')
  }
  return text.replace(/\n\n+/g, '\n\n').trim()
}

export function check(native, standalone) {
  const files = new Set()
  for (const root of [native, standalone]) {
    for (const name of fs.readdirSync(path.join(root, 'bin'))) {
      if (name.startsWith('omarchy-lab-') && name !== 'omarchy-lab-runtime') files.add('bin/' + name)
    }
    for (const name of fs.readdirSync(path.join(root, 'default/lab-vm'))) files.add('default/lab-vm/' + name)
  }
  for (const name of ['Panel.qml', 'BarWidget.qml', 'Model.js', 'manifest.json', 'test/lab-parity.mjs', 'test/lab-packaging.json']) files.add(name)
  let failures = 0
  for (const file of files) {
    const nativeFile = file === 'manifest.json' || (/\.(qml|js)$/.test(file) && !file.startsWith('test/')) ? 'shell/plugins/panels/lab/' + file : file
    try {
      const left = normalize(fs.readFileSync(path.join(native, nativeFile), 'utf8'), file, 'native')
      const right = normalize(fs.readFileSync(path.join(standalone, file), 'utf8'), file, 'standalone')
      if (left !== right) {
        const a = left.split('\n'), b = right.split('\n')
        const index = a.findIndex((line, i) => line !== b[i])
        throw new Error(`shared code differs at normalized line ${index + 1}\n  native: ${a[index]}\n  plugin: ${b[index]}`)
      }
      console.log(`ok - parity ${file}`)
    } catch (error) {
      console.error(`not ok - parity ${file}: ${error.message}`)
      failures++
    }
  }
  return failures === 0
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 4) {
    console.error('Usage: node test/lab-parity.mjs NATIVE_OMARCHY_CHECKOUT STANDALONE_LAB_CHECKOUT')
    process.exit(2)
  }
  process.exit(check(process.argv[2], process.argv[3]) ? 0 : 1)
}
