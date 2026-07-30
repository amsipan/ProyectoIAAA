#!/usr/bin/env python3
from pathlib import Path
import re
import shutil
import zipfile

REPO = Path(r"C:\Users\bryan\ia\proyecto_iaaa\Proyecto\ProyectoIAAA")
ROOT = Path(r"C:\Users\bryan\Downloads\_staging_ModuloPredictivo\ModuloPredictivo_Fantasma_LSTM")
ZIP = Path(r"C:\Users\bryan\Downloads\ModuloPredictivo_Fantasma_LSTM.zip")
TEST = Path(r"C:\Users\bryan\Downloads\_test_ModuloPredictivo_run")
p = ROOT / "scripts" / "train_fantasma_lstm.pl"

text = (REPO / "scripts" / "train_fantasma_lstm_v2.pl").read_text(encoding="utf-8")
reps = [
    (r"train_fantasma_lstm_v2", "train_fantasma_lstm"),
    (r"lstm_fantasma_final", "lstm_fantasma"),
    (r"lstm_fantasma_v2", "lstm_fantasma"),
    (r"fantasma_lstm_v2", "fantasma_lstm"),
    (r"metrics_test_v2", "metrics_test"),
    (r"preds_test_v2", "preds_test"),
    (r"train_config_v2", "train_config"),
    (r"FantasmaLSTMV2", "FantasmaLSTM"),
    (r"version\s*=>\s*['\"]v2['\"]", "version => '1'"),
    (r'"version":\s*"v2"', '"version": "1"'),
    (r" LSTM v2", " LSTM"),
    (r" modelo v2", " modelo"),
    (r" TEST v2", " TEST"),
    (r" final v2", " final"),
    (r" anti-overfit", ""),
    (r"\(v2\)", ""),
    (r"\bv2\b", ""),
    (r"\bV2\b", ""),
]
for a, b in reps:
    text = re.sub(a, b, text)

text = text.replace(
    'die "Train no encontrado: $opt{train}\\n" unless -f $opt{train};',
    'die "Train no encontrado: $opt{train}\\n" unless $opt{eval_only} || -f $opt{train};',
)

old_load = (
    "my $t_load = time();\n"
    'print "[*] Cargando train...\\n";\n'
    "my $train_pack = Market::ML::FantasmaLSTMData->load_xy(\n"
    "    csv   => $opt{train},\n"
    "    stats => $opt{stats},\n"
    ");\n"
    'print "[*] Cargando test...\\n";\n'
    "my $test_pack = Market::ML::FantasmaLSTMData->load_xy(\n"
    "    csv   => $opt{test},\n"
    "    stats => $opt{stats},\n"
    ");\n"
    'printf "[*] load OK train_rows=%d test_rows=%d feats=%d targets=%s (%.1fs)\\n",\n'
    "  $train_pack->{n_rows}, $test_pack->{n_rows}, $train_pack->{n_features},\n"
    "  join( ',', @{ $train_pack->{targets} } ), time() - $t_load;"
)
new_load = (
    "my $t_load = time();\n"
    'print "[*] Cargando test...\\n";\n'
    "my $test_pack = Market::ML::FantasmaLSTMData->load_xy(\n"
    "    csv   => $opt{test},\n"
    "    stats => $opt{stats},\n"
    ");\n"
    "my $train_pack;\n"
    "if ( $opt{eval_only} ) {\n"
    '    print "[*] eval-only: se omite train CSV\\n";\n'
    "    $train_pack = $test_pack;\n"
    "}\n"
    "else {\n"
    '    die "Train no encontrado: $opt{train}\\n" unless -f $opt{train};\n'
    '    print "[*] Cargando train...\\n";\n'
    "    $train_pack = Market::ML::FantasmaLSTMData->load_xy(\n"
    "        csv   => $opt{train},\n"
    "        stats => $opt{stats},\n"
    "    );\n"
    "}\n"
    'printf "[*] load OK train_rows=%d test_rows=%d feats=%d targets=%s (%.1fs)\\n",\n'
    "  $train_pack->{n_rows}, $test_pack->{n_rows}, $train_pack->{n_features},\n"
    "  join( ',', @{ $train_pack->{targets} } ), time() - $t_load;"
)
if old_load not in text:
    raise SystemExit("OLD_LOAD_NOT_FOUND")
text = text.replace(old_load, new_load)

text, n = re.subn(
    r"\n# Comparacion corta[\s\S]*?\nif \( -f \$v1_metrics_path \) \{[\s\S]*?\n\}\n",
    "\n",
    text,
    count=1,
)
print("comparison_removed", n)
text = text.replace(
    "train_fantasma_lstm.pl — LSTM  (val causal + early stop + grid)",
    "train_fantasma_lstm.pl — LSTM (val causal + early stop + grid)",
)

p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(text, encoding="utf-8", newline="\n")
print("wrote", p)

demo = ROOT / "scripts" / "demo_fantasma_predict.pl"
if demo.exists():
    dt = demo.read_text(encoding="utf-8")
    dt = dt.replace("Dense=2.* (/final)", "Dense=2.*")
    dt = dt.replace("Dense=2.* (v2/final)", "Dense=2.*")
    demo.write_text(dt, encoding="utf-8", newline="\n")

if ZIP.exists():
    ZIP.unlink()
with zipfile.ZipFile(ZIP, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for f in ROOT.rglob("*"):
        if f.is_file():
            zf.write(
                f,
                arcname=f"ModuloPredictivo_Fantasma_LSTM/{f.relative_to(ROOT).as_posix()}",
            )
print("zip_mb", round(ZIP.stat().st_size / 1024 / 1024, 2))

dest = TEST / "ModuloPredictivo_Fantasma_LSTM"
if dest.exists():
    shutil.rmtree(dest)
TEST.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(ZIP) as zf:
    zf.extractall(TEST)
print("extracted OK")
