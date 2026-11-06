#!/usr/bin/env python3
"""Build a checked V2 frontend handoff from the new live report and hook deployment log."""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAST = str(Path.home() / ".foundry/bin/cast")
FORGE = str(Path.home() / ".foundry/bin/forge")
ZERO = "0x" + "0" * 64


def env_value(name: str) -> str:
    for line in (ROOT / ".env").read_text().splitlines():
        if line.startswith(name + "="):
            return line.split("=", 1)[1].strip().strip('"')
    raise ValueError(f"Missing {name} in smartcontracts/.env")


def command(*args: str) -> str:
    return subprocess.run(args, cwd=ROOT, text=True, capture_output=True, check=True).stdout.strip()


def read(address: str, signature: str, rpc: str, *args: str):
    return json.loads(command(CAST, "call", address, signature, *args, "--rpc-url", rpc, "--json"))


def hook_addresses(log: str) -> dict[str, str]:
    names = {"V2Hook": "YieldCurveHookV2", "V2LPShare": "YieldLPShare", "V2SwapRouter": "YieldSwapRouter", "V2AtomicRouter": "StakeAndSellRouterV2"}
    result = {}
    for label, name in names.items():
        matches = re.findall(rf"\b{label}\s+(0x[0-9a-fA-F]{{40}})\b", log)
        if not matches:
            raise ValueError(f"Hook deployment log has no {label} address")
        result[name] = matches[-1]
    return result


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hook-log", required=True, type=Path)
    ap.add_argument("--output", default="handoff/v2-flexible", type=Path)
    args = ap.parse_args()
    eth_rpc, arb_rpc = env_value("ETH_SEPOLIA_RPC_URL"), env_value("ARB_SEPOLIA_RPC_URL")
    prepared = json.loads((ROOT / "deployments/v2-flexible-prepared.json").read_text())
    s = prepared["ethereumSepolia"]
    a = prepared["arbitrumSepolia"]
    addresses = hook_addresses(args.hook_log.read_text())
    base = ROOT / "handoff/v2"
    bundle = json.loads((base / "addresses.json").read_text())
    rid = int(read(s["FlexibleReportRegistry"], "reportCount()(uint256)", eth_rpc)[0])
    if rid != 1 or int(read(s["RiskFiStakeVaultV2"], "reportId()(uint256)", eth_rpc)[0]) != rid:
        raise ValueError("Expected a newly published report #1 in the configured vault")
    report = read(s["FlexibleReportRegistry"], "reports(uint256)(bytes32,bytes32,address,address,address,uint64,uint64,uint64,uint64)", eth_rpc, str(rid))
    maturity = int(read(s["FlexibleReportRegistry"], "maturity(uint256)(uint256)", eth_rpc, str(rid))[0])
    cutoff = int(read(a["CCIPStakeSenderV2"], "reportCutoff(uint256)(uint64)", arb_rpc, str(rid))[0])
    if cutoff != int(report[6]):
        raise ValueError("Arbitrum sender cutoff differs from the signed report cutoff")
    if report[0].lower() != "0x" + hashlib.sha256((ROOT / "demo/accelerated-report.json").read_bytes()).hexdigest():
        raise ValueError("Onchain report hash differs from the demo report bytes")
    yt = read(s["RiskFiStakeVaultV2"], "yt()(address)", eth_rpc)[0]
    rep = read(s["RiskFiStakeVaultV2"], "rep()(address)", eth_rpc)[0]
    lp = read(addresses["YieldCurveHookV2"], "shares()(address)", eth_rpc)[0]
    pool_hash = read(addresses["YieldCurveHookV2"], "poolKeyHash()(bytes32)", eth_rpc)[0]
    if lp.lower() != addresses["YieldLPShare"].lower():
        raise ValueError("Hook LP share differs from deployment log")
    s_bundle = bundle["ethereumSepolia"]
    a_bundle = bundle["arbitrumSepolia"]
    s_bundle["reportId"] = rid
    s_bundle["reportTimes"] = {"crossChainCutoff": int(report[6]), "lockTime": int(report[5]), "maturity": maturity}
    s_bundle["contracts"].update({
        "ReportRegistry": s["FlexibleReportRegistry"], "RiskFiStakeVaultV2": s["RiskFiStakeVaultV2"],
        "StakeReceiptREP": rep, "CCIPStakeReceiverV2": s["CCIPStakeReceiverV2"], "StakerYieldToken": yt,
        **addresses,
    })
    token0, token1 = sorted([s_bundle["contracts"]["DemoUSD"], yt], key=lambda x: int(x, 16))
    s_bundle["ytPoolKey"] = {"currency0": token0, "currency1": token1, "fee": 0, "tickSpacing": 1, "hooks": addresses["YieldCurveHookV2"]}
    s_bundle["poolKeyHash"] = pool_hash
    s_bundle["report"] = {
        "reportId": rid, "reportHash": report[0], "claimHash": report[1], "reviewer": report[2],
        "resolver": report[3], "adjudicator": report[4], "resultDeadline": int(report[7]),
        "challengePeriodSeconds": int(report[8]),
    }
    a_bundle["reportId"] = rid
    a_bundle["contracts"]["CCIPStakeSenderV2"] = a["CCIPStakeSenderV2"]
    bundle["version"] = "riskfi-v2-flexible-demo-1"
    bundle["source"] = "deployments/v2-flexible-prepared.json"
    bundle["exampleCCIP"] = {"messageId": ZERO, "sourceTx": ZERO, "destinationTx": ZERO}

    output = ROOT / args.output
    output.mkdir(parents=True, exist_ok=True)
    shutil.copytree(base / "abis", output / "abis", dirs_exist_ok=True)
    manifest = json.loads((base / "abi-manifest.json").read_text())
    abi = json.loads(command(FORGE, "inspect", "src/v2/FlexibleReportRegistry.sol:FlexibleReportRegistry", "abi", "--json"))
    abi_path = output / "abis/ReportRegistry.json"
    abi_path.write_text(json.dumps(abi, indent=2) + "\n")
    manifest["ReportRegistry"] = {"file": "abis/ReportRegistry.json", "entries": len(abi), "sha256": hashlib.sha256(abi_path.read_bytes()).hexdigest()}
    (output / "abi-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (output / "addresses.json").write_text(json.dumps(bundle, indent=2) + "\n")
    print(f"Prepared {output} for report #{rid}; vote lock {report[5]}, maturity {maturity}, deadline {report[7]}")


if __name__ == "__main__":
    main()
