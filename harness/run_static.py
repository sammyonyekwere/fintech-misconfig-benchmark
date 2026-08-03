import json, subprocess, time, csv, pathlib, datetime, shutil

VARIANTS = [
    "hardened",
    "vuln-01-public-storage", "vuln-02-rbac-contributor", "vuln-03-sql-public",
    "vuln-04-open-mgmt-ports", "vuln-05-plaintext-secrets", "vuln-06-no-https",
    "vuln-07-logging-disabled", "vuln-08-no-cmk", "vuln-09-nsg-open-inbound",
    "vuln-10-sp-nonexpiring-owner", "mixed-seed-101", "mixed-seed-202", "mixed-seed-303",
]

# command template per tool ({d} = variant dir, {name} = output stem)
# kics writes a JSON File; checkov and trivy print JSON to stdout.
TOOLS = {
    "kics": "kics scan -p {d} -o results/raw --output-name {name} --report-formats json",
    "checkov": "checkov -d {d} --framework terraform -o json",
    "trivy":   "trivy config {d} -f json",
    # azure policy needs a live scope , it is handled seperately
}

RULE_MAP = {
    "kics": {
        "a5613650-32ec-4975-a305-31af783153ea": "mc01_public_storage",
        "ade36cf4-329f-4830-a83d-9db72c800507": "mc03_sql_public",
        "12944ec4-1fa0-47be-8b17-42a034f937c2": "mc06_no_https",
    },
    "checkov": {
        "CKV2_AZURE_47": "mc01_public_storage",
        "CKV_AZURE_190": "mc01_public_storage",
        "CKV_AZURE_59": "mc01_public_storage",
        "CKV_AZURE_11": "mc03_sql_public",
        "CKV_AZURE_113": "mc03_sql_public",
    },
    "trivy": {
        "AZU-0022": "mc03_sql_public",
        "AZU-0029": "mc03_sql_public",
        "AZU-0048": "mc04_open_mgmt_ports",
        "AZU-0050": "mc04_open_mgmt_ports",
        "AZU-0004": "mc06_no_https",
        "AZU-0008": "mc06_no_https",
        "AZU-0059": "mc06_no_https",
        "AZU-0016": "mc08_no_cmk",
        "AZU-0047": "mc09_nsg_open_inbound",
    },
}

def native_ids (tool, raw):
    if tool == "kics":
        return [q["query_id"] for q in raw.get("queries", [])]
    if tool == "checkov":
        return [c["check_id"] for c in raw.get("results", {}).get("failed_checks", [])]
    if tool == "trivy":
        out = []
        for r in raw.get("Results", []):
            out += [m["ID"] for m in r.get("Misconfigurations", [])]
        return out
    return []

def run(tool, cmd, variant, n, log):
    d = f"variants/{variant}"
    name = f"{tool}_{variant}_run{n}"
    out = pathlib.Path(f"results/raw/{name}.json")
    t0 = time.time()
    if tool == "kics":                              # kics writes the file itself
        # kics won't follow the wrapper's module reference into modules/baseline,
        # so sync this variant's tfvars onto the baseline and scan it directly
        shutil.copyfile(f"variants/{variant}/terraform.tfvars",
                         "modules/baseline/terraform.tfvars")
        args = cmd.format(d="modules/baseline", name=name).split()
        args[0] = shutil.which(args[0]) or args[0]
        subprocess.run(args, capture_output=True, text=True)
        raw_text = out.read_text() if out.exists() else "{}"
    else:                                           # checkov / trivy -> stdout
        args = cmd.format(d=d).split()
        args[0] = shutil.which(args[0]) or args[0]
        raw_text = subprocess.run(args, capture_output=True, text=True).stdout
        out.write_text(raw_text)

    dur = round(time.time() - t0, 2)
    raw = json.loads(raw_text or "{}")
    ids = native_ids(tool, raw)
    mapped = {RULE_MAP[tool][i] for i in ids if i in RULE_MAP[tool]}
    unmapped = [i for i in ids if i not in RULE_MAP[tool]]
    rec = {
        "tool": tool, "variant": variant, "run": n,
        "scanned_at": datetime.datetime.utcnow().isoformat() + "Z",
        "duration_s": dur,
        "findings": [{"mc_id": m, "detected": True} for m in sorted(mapped)],
        "out_of_scope": unmapped,
    }
    pathlib.Path(f"results/normalised/{name}.json").write_text(
        json.dumps(rec, indent=2))
    log.writerow([tool, variant, n, rec["scanned_at"], dur,
                  len(ids), ";".join(sorted(mapped))])

pathlib.Path("results/raw").mkdir(parents=True, exist_ok=True)
pathlib.Path("results/normalised").mkdir(parents=True, exist_ok=True)
with open("results/static_scan_run_log.csv", "w", newline="") as f:
    log = csv.writer(f)
    log.writerow(["tool", "variant", "run", "scanned_at",
                  "duration_s", "n_findings", "mc_detected"])
    for v in VARIANTS:
        for tool, cmd in TOOLS.items():
            for n in (1, 2, 3):
                run(tool, cmd, v, n, log)
