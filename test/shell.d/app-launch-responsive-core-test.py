#!/usr/bin/python3

from __future__ import annotations

import copy
import importlib.machinery
import json
import tempfile
import types
import unittest
from pathlib import Path
from typing import Mapping
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
CORE_PATH = ROOT / "bin/omarchy-app-launch-responsive-core"
CONFIG_PATH = ROOT / "default/app-launch-responsive/config.json"

loader = importlib.machinery.SourceFileLoader("app_launch_responsive_core", str(CORE_PATH))
core = types.ModuleType(loader.name)
loader.exec_module(core)


def config() -> dict:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def observed(value: dict | None = None) -> dict:
    cfg = config()
    epp_paths = cfg["hardware"]["epp_paths"]
    platform_paths = cfg["hardware"]["platform_profile_realpaths"]
    result = {
        "sys_vendor": "Dell Inc.",
        "product_name": "XPS 16 DA16260",
        "product_sku": "0DBA",
        "cpu_family": 6,
        "cpu_model": 204,
        "on_battery": True,
        "active_profile": "balanced",
        "battery_aware": True,
        "ppd_profiles": [
            {
                "Profile": "balanced",
                "CpuDriver": "intel_pstate",
                "PlatformDriver": "platform_profile",
            }
        ],
        "lpmd_active": True,
        "platform": {
            name: {
                "realpath": path,
                "profile": "balanced",
                "choices": ["low-power", "balanced", "performance"],
            }
            for name, path in platform_paths.items()
        },
        "epp": {path: "balance_power" for path in epp_paths},
        "epp_choices": {
            path: ["performance", "balance_performance", "balance_power", "power"]
            for path in epp_paths
        },
        "epp_drivers": {path: "intel_pstate" for path in epp_paths},
        "slider_balance": "03",
        "slider_offset": "03",
        "preserve": {
            "hwp_dynamic_boost": "0",
            "no_turbo": "0",
            "min_perf_pct": "9",
            "max_perf_pct": "100",
        },
        "external_power": {"AC": {"type": "Mains", "online": "0"}},
        "batteries": {"BAT0": {"present": "1", "status": "Discharging"}},
    }
    if value:
        result.update(value)
    return result


class StaticAuditTest(unittest.TestCase):
    def test_exact_supported_capabilities_pass(self) -> None:
        with patch.object(core, "lpmd_semantic_errors", return_value=[]):
            self.assertEqual(core.static_audit(config(), observed()), [])

    def test_vendor_product_sku_and_cpu_are_all_exact(self) -> None:
        keys = ("sys_vendor", "product_name", "product_sku", "cpu_family", "cpu_model")
        with patch.object(core, "lpmd_semantic_errors", return_value=[]):
            for key in keys:
                sample = observed({key: "wrong"})
                self.assertTrue(
                    any(error.startswith(f"{key}:") for error in core.static_audit(config(), sample)),
                    key,
                )

    def test_epp_inventory_capability_and_driver_are_gated(self) -> None:
        cfg = config()
        path = cfg["hardware"]["epp_paths"][0]
        with patch.object(core, "lpmd_semantic_errors", return_value=[]):
            sample = observed()
            sample["epp"].pop(path)
            self.assertIn("EPP policy path inventory changed", core.static_audit(cfg, sample))

            sample = observed()
            sample["epp_choices"][path].remove("balance_performance")
            self.assertTrue(any("EPP capabilities changed" in error for error in core.static_audit(cfg, sample)))

            sample = observed()
            sample["epp_drivers"][path] = "acpi-cpufreq"
            self.assertTrue(any("not intel_pstate" in error for error in core.static_audit(cfg, sample)))

    def test_platform_provider_and_ppd_semantics_are_gated(self) -> None:
        cfg = config()
        with patch.object(core, "lpmd_semantic_errors", return_value=[]):
            sample = observed()
            sample["platform"]["dell-pc"]["realpath"] = "/wrong"
            self.assertIn("platform profile realpaths changed", core.static_audit(cfg, sample))

            sample = observed({"battery_aware": False})
            self.assertIn("power-profiles-daemon BatteryAware is false", core.static_audit(cfg, sample))

            sample = observed()
            sample["ppd_profiles"][0]["CpuDriver"] = "other"
            self.assertIn("power-profiles-daemon balanced providers changed", core.static_audit(cfg, sample))

    def test_non_target_pstate_baseline_is_exactly_gated(self) -> None:
        cfg = config()
        sample = observed()
        sample["preserve"]["min_perf_pct"] = "8"
        with patch.object(core, "lpmd_semantic_errors", return_value=[]):
            self.assertIn(
                "non-target Intel P-state baseline changed",
                core.static_audit(cfg, sample),
            )

    def test_lpmd_gate_checks_only_relevant_semantics(self) -> None:
        cfg = config()
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "lpmd.xml"
            cfg["providers"]["intel_lpmd_config"] = str(path)
            path.write_text(
                """<Configuration>
                <BalancedSliderDC>3</BalancedSliderDC>
                <SliderOffsetDC>3</SliderOffsetDC>
                <States><CPUFamily>6</CPUFamily><CPUModel>204</CPUModel></States>
                </Configuration>""",
                encoding="utf-8",
            )
            self.assertEqual(core.lpmd_semantic_errors(cfg), [])
            path.write_text(
                path.read_text(encoding="utf-8").replace(
                    "<BalancedSliderDC>3", "<BalancedSliderDC>2"
                ),
                encoding="utf-8",
            )
            self.assertTrue(any("BalancedSliderDC" in error for error in core.lpmd_semantic_errors(cfg)))

    def test_no_volatile_version_or_supply_inventory_pins(self) -> None:
        raw = CONFIG_PATH.read_text(encoding="utf-8")
        for forbidden in (
            "bios_version",
            "kernel_release",
            "microcode",
            "package_version",
            "srcversion",
            "vermagic",
            "sha256",
            "power_supply_inventory",
        ):
            self.assertNotIn(forbidden, raw)


class PowerSupplySnapshotTest(unittest.TestCase):
    def write_supply(self, root: Path, name: str, values: Mapping[str, str]) -> None:
        directory = root / name
        directory.mkdir()
        for key, value in values.items():
            (directory / key).write_text(f"{value}\n", encoding="utf-8")

    def test_device_scoped_peripherals_are_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            self.write_supply(
                root,
                "BAT0",
                {
                    "scope": "System",
                    "type": "Battery",
                    "present": "1",
                    "status": "Discharging",
                },
            )
            self.write_supply(root, "AC", {"type": "Mains", "online": "0"})
            self.write_supply(root, "mouse", {"scope": "Device"})
            with patch.object(core, "POWER_SUPPLY_ROOT", root):
                external, batteries = core.power_supply_snapshot()
            self.assertEqual(set(external), {"AC"})
            self.assertEqual(set(batteries), {"BAT0"})

    def test_unknown_supply_scope_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            self.write_supply(
                root,
                "mystery",
                {"scope": "SomethingNew", "type": "Mains", "online": "0"},
            )
            with patch.object(core, "POWER_SUPPLY_ROOT", root):
                with self.assertRaisesRegex(RuntimeError, "unknown scope"):
                    core.power_supply_snapshot()


class StateValidationTest(unittest.TestCase):
    def test_ownership_invariants_fail_closed(self) -> None:
        applied_without_restore = core.default_state()
        applied_without_restore["applied"] = True
        with self.assertRaisesRegex(core.StateFileError, "rollback obligation"):
            core.validate_state(applied_without_restore)

        restore_without_baseline = core.default_state()
        restore_without_baseline["needs_restore"] = True
        with self.assertRaisesRegex(core.StateFileError, "requires a baseline"):
            core.validate_state(restore_without_baseline)


class EligibilityTest(unittest.TestCase):
    def test_only_discharging_battery_balanced_is_eligible(self) -> None:
        self.assertEqual(core.is_eligible(observed()), (True, "eligible"))
        cases = (
            ({"external_power": {"AC": {"online": "1"}}}, "ac_power"),
            ({"external_power": {"AC": {"online": None}}}, "physical_source_unknown"),
            ({"on_battery": False}, "source_disagreement"),
            ({"batteries": {"BAT0": {"present": "1", "status": "Charging"}}}, "battery_not_discharging"),
            ({"active_profile": "performance"}, "profile_performance"),
        )
        for update, reason in cases:
            self.assertEqual(core.is_eligible(observed(update)), (False, reason))

        sample = observed()
        sample["platform"]["dell-pc"]["profile"] = "performance"
        self.assertEqual(core.is_eligible(sample), (False, "platform_profile_not_balanced"))


class WriteTuningGateTest(unittest.TestCase):
    def test_static_audit_failure_prevents_every_write(self) -> None:
        writes: list[tuple[Path, str]] = []
        with (
            patch.object(core, "static_audit", return_value=["identity drift"]),
            patch.object(core, "write", side_effect=lambda path, value: writes.append((path, value))),
        ):
            with self.assertRaisesRegex(RuntimeError, "provider drift"):
                core.write_tuning(
                    config(), config()["responsive_battery_balanced"], observed()
                )
        self.assertEqual(writes, [])


class ReconcileHarness(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.state_path = root / "state.json"
        self.lock_path = root / "control.lock"
        self.config = config()
        self.current = observed()
        self.writes: list[dict] = []
        self.fail_writes = 0
        self.drift_after_failed_write = None
        self.real_static_audit = core.static_audit

        self.patches = (
            patch.object(core.os, "geteuid", return_value=0),
            patch.object(core, "config_path", return_value=root / "config.json"),
            patch.object(core, "state_path", return_value=self.state_path),
            patch.object(core, "lock_path", return_value=self.lock_path),
            patch.object(core, "load_json", return_value=self.config),
            patch.object(core, "observe", side_effect=self.observe),
            patch.object(core, "static_audit", return_value=[]),
            patch.object(core, "service_active", return_value=True),
            patch.object(core, "write_tuning", side_effect=self.write_tuning),
        )
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    def observe(self) -> dict:
        return copy.deepcopy(self.current)

    def write_tuning(self, _config: dict, target: Mapping, _observed: Mapping) -> dict:
        self.writes.append(copy.deepcopy(dict(target)))
        if self.fail_writes:
            self.fail_writes -= 1
            if self.drift_after_failed_write is not None:
                self.drift_after_failed_write(self.current)
            raise RuntimeError("simulated write failure")
        self.current["slider_balance"] = target["slider_balance"]
        self.current["slider_offset"] = target["slider_offset"]
        wanted_epp = target["epp"]
        if isinstance(wanted_epp, Mapping):
            self.current["epp"] = dict(wanted_epp)
        else:
            self.current["epp"] = {
                path: wanted_epp for path in self.config["hardware"]["epp_paths"]
            }
        if isinstance(target.get("platform"), Mapping):
            for name, value in target["platform"].items():
                self.current["platform"][name]["profile"] = value
        return self.observe()

    def state(self) -> dict:
        return json.loads(self.state_path.read_text(encoding="utf-8"))

    def initialize(self) -> None:
        ok, detail = core.reconcile("test_initialize")
        self.assertTrue(ok, detail)
        self.assertTrue(self.state()["initialized"])

    def enable(self) -> None:
        self.initialize()
        ok, detail = core.set_requested(True)
        self.assertTrue(ok, detail)

    def test_enable_captures_stock_then_applies_exact_target(self) -> None:
        self.enable()
        state = self.state()
        self.assertTrue(state["requested"])
        self.assertTrue(state["applied"])
        self.assertTrue(state["needs_restore"])
        self.assertEqual(state["baseline"]["slider_balance"], "03")
        self.assertEqual(self.current["slider_balance"], "01")
        self.assertEqual(self.current["slider_offset"], "00")
        self.assertEqual(set(self.current["epp"].values()), {"balance_performance"})

    def test_disable_restores_captured_stock_and_clears_ownership(self) -> None:
        self.enable()
        ok, detail = core.set_requested(False)
        self.assertTrue(ok, detail)
        state = self.state()
        self.assertFalse(state["requested"])
        self.assertFalse(state["applied"])
        self.assertFalse(state["needs_restore"])
        self.assertIsNone(state["baseline"])
        self.assertEqual(self.current["slider_balance"], "03")
        self.assertEqual(self.current["slider_offset"], "03")
        self.assertEqual(set(self.current["epp"].values()), {"balance_power"})

    def test_ac_never_writes_and_defers_owned_restore(self) -> None:
        self.enable()
        writes_before = len(self.writes)
        self.current["external_power"]["AC"]["online"] = "1"
        self.current["on_battery"] = False
        ok, detail = core.set_requested(False)
        self.assertFalse(ok)
        self.assertIn("restore deferred", detail)
        self.assertEqual(len(self.writes), writes_before)
        self.assertTrue(self.state()["needs_restore"])
        self.current["external_power"]["AC"]["online"] = "0"
        self.current["on_battery"] = True
        ok, detail = core.reconcile("back_on_dc")
        self.assertTrue(ok, detail)
        self.assertFalse(self.state()["needs_restore"])
        self.assertEqual(self.current["slider_balance"], "03")

    def test_non_balanced_profile_never_writes(self) -> None:
        self.enable()
        writes_before = len(self.writes)
        self.current["active_profile"] = "performance"
        for item in self.current["platform"].values():
            item["profile"] = "performance"
        ok, detail = core.set_requested(False)
        self.assertFalse(ok)
        self.assertIn("restore deferred", detail)
        self.assertEqual(len(self.writes), writes_before)

    def test_failed_apply_rolls_back_and_latches(self) -> None:
        self.initialize()
        self.fail_writes = 1
        ok, detail = core.set_requested(True)
        self.assertFalse(ok)
        self.assertIn("simulated write failure", detail)
        state = self.state()
        self.assertFalse(state["requested"])
        self.assertFalse(state["needs_restore"])
        self.assertTrue(state["failure_latched"])
        self.assertEqual(len(self.writes), 2)

    def test_failed_apply_and_rollback_preserve_ownership_obligation(self) -> None:
        self.initialize()
        self.fail_writes = 2
        ok, detail = core.set_requested(True)
        self.assertFalse(ok)
        self.assertIn("rollback also failed", detail)
        state = self.state()
        self.assertTrue(state["needs_restore"])
        self.assertIsNotNone(state["baseline"])
        self.assertTrue(state["failure_latched"])

    def test_apply_failure_race_drift_blocks_rollback_write(self) -> None:
        self.initialize()
        self.fail_writes = 1
        self.drift_after_failed_write = lambda sample: sample.__setitem__(
            "product_sku", "wrong"
        )
        core.static_audit.side_effect = self.real_static_audit
        with patch.object(core, "lpmd_semantic_errors", return_value=[]):
            ok, detail = core.set_requested(True)
        self.assertFalse(ok)
        self.assertIn("simulated write failure", detail)
        self.assertEqual(len(self.writes), 1)
        state = self.state()
        self.assertTrue(state["needs_restore"])
        self.assertIsNotNone(state["baseline"])
        self.assertTrue(state["failure_latched"])

    def test_off_discards_prewrite_crash_baseline_even_under_drift(self) -> None:
        self.initialize()
        state = self.state()
        state.update(
            {
                "requested": True,
                "applied": False,
                "needs_restore": False,
                "baseline": core.capture_baseline(self.current),
            }
        )
        core.save_state(state)
        core.static_audit.return_value = ["simulated provider drift"]
        ok, detail = core.set_requested(False)
        self.assertTrue(ok, detail)
        self.assertEqual(self.writes, [])
        state = self.state()
        self.assertFalse(state["requested"])
        self.assertFalse(state["needs_restore"])
        self.assertIsNone(state["baseline"])

    def test_quiesce_discards_prewrite_crash_baseline(self) -> None:
        self.initialize()
        state = self.state()
        state.update(
            {
                "requested": True,
                "applied": False,
                "needs_restore": False,
                "baseline": core.capture_baseline(self.current),
            }
        )
        core.save_state(state)
        ok, detail = core.quiesce_service()
        self.assertTrue(ok, detail)
        self.assertEqual(self.writes, [])
        state = self.state()
        self.assertTrue(state["quiesced"])
        self.assertIsNone(state["baseline"])

    def test_drift_never_writes_and_retains_owned_baseline(self) -> None:
        self.enable()
        writes_before = len(self.writes)
        core.static_audit.return_value = ["simulated provider drift"]
        ok, detail = core.reconcile("drift")
        self.assertFalse(ok)
        self.assertIn("simulated provider drift", detail)
        state = self.state()
        self.assertTrue(state["needs_restore"])
        self.assertIsNotNone(state["baseline"])
        self.assertTrue(state["failure_latched"])
        self.assertEqual(len(self.writes), writes_before)
        self.assertEqual(self.current["slider_balance"], "01")

    def assert_owned_drift_never_writes(self, mutate) -> None:
        self.enable()
        writes_before = len(self.writes)
        mutate(self.current)
        core.static_audit.side_effect = self.real_static_audit
        with patch.object(core, "lpmd_semantic_errors", return_value=[]):
            ok, _detail = core.reconcile("audited_drift")
        self.assertFalse(ok)
        self.assertEqual(len(self.writes), writes_before)
        self.assertTrue(self.state()["needs_restore"])
        self.assertIsNotNone(self.state()["baseline"])

    def test_identity_drift_never_writes(self) -> None:
        self.assert_owned_drift_never_writes(
            lambda sample: sample.__setitem__("product_sku", "wrong")
        )

    def test_epp_driver_drift_never_writes(self) -> None:
        path = self.config["hardware"]["epp_paths"][0]
        self.assert_owned_drift_never_writes(
            lambda sample: sample["epp_drivers"].__setitem__(path, "acpi-cpufreq")
        )

    def test_epp_capability_drift_never_writes(self) -> None:
        path = self.config["hardware"]["epp_paths"][0]
        self.assert_owned_drift_never_writes(
            lambda sample: sample["epp_choices"][path].remove("balance_performance")
        )

    def test_non_target_pstate_drift_never_writes(self) -> None:
        self.assert_owned_drift_never_writes(
            lambda sample: sample["preserve"].__setitem__("min_perf_pct", "8")
        )

    def test_matching_target_without_ownership_is_not_claimed_or_restored(self) -> None:
        self.initialize()
        self.current["slider_balance"] = "01"
        self.current["slider_offset"] = "00"
        self.current["epp"] = {
            path: "balance_performance" for path in self.config["hardware"]["epp_paths"]
        }
        ok, detail = core.reconcile("unowned_target")
        self.assertFalse(ok)
        self.assertIn("exact stock", detail)
        self.assertEqual(self.writes, [])
        self.assertFalse(self.state()["needs_restore"])

    def test_quiesce_restores_before_service_stop(self) -> None:
        self.enable()
        ok, detail = core.quiesce_service()
        self.assertTrue(ok, detail)
        state = self.state()
        self.assertTrue(state["quiesced"])
        self.assertFalse(state["needs_restore"])
        self.assertTrue(state["requested"])
        self.assertEqual(self.current["slider_balance"], "03")

    def test_installed_availability_requires_eligible_policy(self) -> None:
        self.initialize()
        status = core.status_document()
        self.assertTrue(status["supported"])
        self.assertTrue(status["available"])
        self.assertFalse(status["enabled"])

        self.current["external_power"]["AC"]["online"] = "1"
        self.current["on_battery"] = False
        status = core.status_document()
        self.assertTrue(status["supported"])
        self.assertFalse(status["available"])
        self.assertFalse(status["enabled"])

    def test_enabled_remains_off_actionable_under_provider_drift(self) -> None:
        self.enable()
        core.static_audit.return_value = ["simulated drift"]
        ok, _detail = core.set_requested(False)
        self.assertFalse(ok)
        status = core.status_document()
        self.assertTrue(status["enabled"])
        self.assertFalse(status["requested"])
        self.assertTrue(status["ownership_pending"])
        self.assertFalse(status["available"])
        self.assertFalse(status["supported"])
        self.assertEqual(status["reason"], "provider_drift")

    def test_unowned_non_stock_policy_is_blocked_not_disabled(self) -> None:
        self.initialize()
        self.current["slider_balance"] = "02"
        status = core.status_document()
        self.assertTrue(status["supported"])
        self.assertFalse(status["available"])
        self.assertFalse(status["enabled"])
        self.assertEqual(status["health"], "blocked")
        self.assertEqual(status["reason"], "unexpected_unowned_policy")


class ProbeTest(unittest.TestCase):
    def test_preinstall_status_is_available_only_on_supported_hardware(self) -> None:
        cfg = config()
        with (
            patch.object(core, "load_json", return_value=cfg),
            patch.object(core, "observe", return_value=observed()),
            patch.object(core, "static_audit", return_value=[]),
        ):
            status = core.probe_document(CONFIG_PATH)
            self.assertFalse(status["installed"])
            self.assertTrue(status["supported"])
            self.assertTrue(status["available"])
            self.assertTrue(status["can_enable_now"])
            self.assertFalse(status["enabled"])

        ac = observed()
        ac["external_power"]["AC"]["online"] = "1"
        ac["on_battery"] = False
        with (
            patch.object(core, "load_json", return_value=cfg),
            patch.object(core, "observe", return_value=ac),
            patch.object(core, "static_audit", return_value=[]),
        ):
            status = core.probe_document(CONFIG_PATH)
            self.assertTrue(status["supported"])
            self.assertFalse(status["available"])
            self.assertFalse(status["can_enable_now"])
            self.assertEqual(status["reason"], "ac_power")

        performance = observed({"active_profile": "performance"})
        with (
            patch.object(core, "load_json", return_value=cfg),
            patch.object(core, "observe", return_value=performance),
            patch.object(core, "static_audit", return_value=[]),
        ):
            status = core.probe_document(CONFIG_PATH)
            self.assertTrue(status["supported"])
            self.assertFalse(status["available"])
            self.assertEqual(status["reason"], "profile_performance")

        with (
            patch.object(core, "load_json", return_value=cfg),
            patch.object(core, "observe", return_value=observed()),
            patch.object(core, "static_audit", return_value=["wrong SKU"]),
        ):
            status = core.probe_document(CONFIG_PATH)
            self.assertFalse(status["supported"])
            self.assertFalse(status["available"])


if __name__ == "__main__":
    unittest.main()
