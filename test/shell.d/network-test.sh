#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const network = requireFromRoot('shell/plugins/panels/network/Model.js')

assertDeepEqual(
  network.parseNetworkStatus('wifi\tCafe WiFi\t78\t5200\n'),
  { kind: 'wifi', label: 'Cafe WiFi', signalStrength: 78, frequency: '5200' },
  'network parses bar status'
)
assertEqual(network.connectionIcon('wifi', 80), network.wifiIconFor(80), 'network maps wifi icon from signal')
assertEqual(network.formatHeaderSpeed('1000'), '1gbit', 'network formats gigabit speed')
assertEqual(network.formatHeaderSpeed('2500'), '2.5gbit', 'network formats fractional gigabit speed')
assertEqual(network.formatHeaderFreq('2462'), '2.4ghz', 'network formats 2.4GHz wifi band')
assertEqual(network.formatHeaderFreq('5200'), '5ghz', 'network formats 5GHz wifi band')
assertEqual(network.formatHeaderFreq('6455.0'), '6ghz', 'network formats 6GHz wifi band')
assertEqual(network.formatHeaderFreq('18300'), '18.3ghz', 'network falls back to exact GHz for unknown bands')
assertEqual(network.headerDetail({ type: 'ethernet', speed: '100' }), '100mbit', 'network header uses ethernet speed')

assertDeepEqual(
  network.parseKeyValue('iface\twlan0\nrx_bytes\t100\ntx_bytes\t50\n'),
  { iface: 'wlan0', rx_bytes: '100', tx_bytes: '50' },
  'network parses detail key values'
)
assertDeepEqual(
  network.throughputState({ prevIface: '', prevSampleTime: 0 }, { iface: 'wlan0', rx_bytes: '100', tx_bytes: '50' }, 10),
  { prevIface: 'wlan0', prevRxBytes: 100, prevTxBytes: 50, prevSampleTime: 10, downloadRate: 0, uploadRate: 0 },
  'network seeds throughput state on first sample'
)
assertDeepEqual(
  network.throughputState({ prevIface: 'wlan0', prevRxBytes: 100, prevTxBytes: 50, prevSampleTime: 10 }, { iface: 'wlan0', rx_bytes: '300', tx_bytes: '90' }, 12),
  { prevIface: 'wlan0', prevRxBytes: 300, prevTxBytes: 90, prevSampleTime: 12, downloadRate: 100, uploadRate: 20 },
  'network computes throughput deltas'
)

let ping = network.pingLatencyState(
  { pingIface: '', routerPingSamples: [], internetPingSamples: [] },
  { iface: 'wlan0', router_ping_ms: '2.0', internet_ping_ms: '20.0' },
  4
)
assertDeepEqual(
  ping,
  { pingIface: 'wlan0', routerPingSamples: [2], internetPingSamples: [20], routerPingLatency: 2, internetPingLatency: 20 },
  'network seeds ping latency samples'
)

ping = network.pingLatencyState(ping, { iface: 'wlan0', router_ping_ms: '4.0', internet_ping_ms: '' }, 4)
assertDeepEqual(
  ping,
  { pingIface: 'wlan0', routerPingSamples: [2, 4], internetPingSamples: [20, null], routerPingLatency: 3, internetPingLatency: 20 },
  'network averages recent successful ping samples'
)

assertDeepEqual(
  network.pingLatencyState(ping, { iface: 'eth0', router_ping_ms: '1.5', internet_ping_ms: '10.0' }, 4),
  { pingIface: 'eth0', routerPingSamples: [1.5], internetPingSamples: [10], routerPingLatency: 1.5, internetPingLatency: 10 },
  'network resets ping samples when interface changes'
)

assertDeepEqual(
  network.pingLatencyState(ping, { iface: 'wlan0', internet_ping_ms: '22.0' }, 4),
  { pingIface: 'wlan0', routerPingSamples: [], internetPingSamples: [20, null, 22], routerPingLatency: -1, internetPingLatency: 21 },
  'network clears ping samples when a target is unavailable'
)

assertEqual(network.formatBytes(1536), '1.5 KB', 'network formats bytes')
assertEqual(network.formatRate(1536), '1.5 KB/s', 'network formats rates')
assertEqual(network.formatPingLatency('2.54'), '2.5 ms', 'network formats low ping with precision')
assertEqual(network.formatPingLatency('25.4'), '25 ms', 'network formats ping')
assertEqual(network.formatPingLatency(''), 'Timeout', 'network formats missing ping as timeout')

const rows = network.sortWifiRows([
  { ssid: 'Open', connected: false, known: false, signal: 95 },
  { ssid: 'Known', connected: false, known: true, signal: 10 },
  { ssid: 'Connected', connected: true, known: true, signal: 20 }
])
assertDeepEqual(rows.map(row => row.ssid), ['Connected', 'Known', 'Open'], 'network sorts wifi rows by connection and known state')
assertEqual(network.wifiSectionTitle(rows, 0), 'KNOWN NETWORKS', 'network labels known wifi section')
assertEqual(network.wifiSectionTitle(rows, 2), 'OTHER NETWORKS', 'network labels other wifi section')

const reasons = { NoSecrets: 1, WifiAuthTimeout: 2, WifiNetworkLost: 3, WifiClientDisconnected: 4, WifiClientFailed: 5 }
assertEqual(network.networkFailureReason(1, reasons), 'Passphrase required', 'network maps missing passphrase failures')
assertEqual(network.networkFailureReason(2, reasons), 'Wrong password', 'network maps auth timeout failures')
assertEqual(network.networkFailureReason(99, reasons), 'Failed to connect', 'network maps unknown failures')
JS
