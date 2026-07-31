import random, pathlib, textwrap

SWITCHES = [
    "mc01_public_storage", "mc02_rbac_contributor", 
    "mc03_sql_public", "mc04_open_mgmt_ports",  
    "mc05_plaintext_secrets",
    "mc06_no_https",          
    "mc07_logging_disabled", 
    "mc08_no_cmk",           
    "mc09_nsg_open_inbound", 
    "mc10_sp_nonexpiring",
]
SEEDS = [101, 202, 303]

for seed in SEEDS:
    rng = random.Random(seed)
    chosen = sorted(rng.sample(SWITCHES, 3))
    folder = pathlib.Path(f"../variants/mixed-seed-{seed}")
    folder.mkdir(parents=True, exist_ok=True)
    lines = [f'variant_name = "mixed{seed}"',
             f"# seed {seed} selected: " + ", ".join(c[:4] for c in chosen)]
    width = max(len(c) for c in chosen)
    lines += [f"{c.ljust(width)} = true" for c in chosen]
    (folder / "terraform.tfvars").write_text("\n".join(lines) + "\n")
    print(seed, chosen)