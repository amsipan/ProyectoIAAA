#!/usr/bin/env python3
"""Empaqueta ZIP del modulo predictivo (<5 MB). Solo staging; no altera el repo."""
import re
import shutil
import zipfile
from pathlib import Path

REPO = Path(r"C:\Users\bryan\ia\proyecto_iaaa\Proyecto\ProyectoIAAA")
STAGING = Path(r"C:\Users\bryan\Downloads\_staging_ModuloPredictivo")
ZIP_OUT = Path(r"C:\Users\bryan\Downloads\ModuloPredictivo_Fantasma_LSTM.zip")
ROOT_NAME = "ModuloPredictivo_Fantasma_LSTM"
ROOT = STAGING / ROOT_NAME


def sanitize_text(s: str) -> str:
    reps = [
        (r"train_fantasma_lstm_v2b", "train_fantasma_lstm"),
        (r"train_fantasma_lstm_v2", "train_fantasma_lstm"),
        (r"compute_fantasma_binary_metrics_v2", "compute_fantasma_binary_metrics"),
        (r"lstm_fantasma_v2b", "lstm_fantasma"),
        (r"lstm_fantasma_final", "lstm_fantasma"),
        (r"lstm_fantasma_v2", "lstm_fantasma"),
        (r"fantasma_lstm_v2b", "fantasma_lstm"),
        (r"fantasma_lstm_v2", "fantasma_lstm"),
        (r"metrics_test_v2", "metrics_test"),
        (r"preds_test_v2", "preds_test"),
        (r"train_config_v2", "train_config"),
        (r"FantasmaLSTMV2b", "FantasmaLSTM"),
        (r"FantasmaLSTMV2", "FantasmaLSTM"),
        (r"binary_metrics_test_v2", "binary_metrics_test"),
        (r"LSTM_FANTASMA_V2B", "LSTM_FANTASMA"),
        (r"LSTM_FANTASMA_V2", "LSTM_FANTASMA"),
        (r"METRICAS_BINARIAS_V2", "METRICAS_BINARIAS"),
        (r"MODELO_FINAL_V2", "SELECCION_MODELO"),
        (r"PLAN_REENTRENAMIENTO_MODELO_V2\.md", "plan de entrenamiento"),
        (r"AUDIT_FASE\d+_V2\.md", "auditoria"),
        (r"version\s*=>\s*['\"]v2['\"]", "version => '1'"),
        (r'"version":\s*"v2"', '"version": "1"'),
        (r'"model_version":\s*"v2"', '"model_version": "1"'),
        (r"\bv2b\b", "variante"),
        (r" LSTM v2", " LSTM"),
        (r" modelo v2", " modelo"),
        (r" TEST v2", " TEST"),
        (r" final v2", " final"),
        (r"\(v2\)", ""),
        (r"/v2/", "/"),
        (r"_v2\b", ""),
        (r"\bv2\b", ""),
        (r"\bV2\b", ""),
        (r"baseline v1", "baseline"),
        # No borrar "v1" suelto: rompe identificadores Perl ($v1_mae, etc.).
    ]
    out = s
    for pat, repl in reps:
        out = re.sub(pat, repl, out)
    # No colapsar espacios: rompe indentacion Python.
    out = re.sub(r"\[[^\]]*\]\([^)]*AUDIT_[^)]*\)", "", out)
    out = re.sub(r"(?m)^.*PASS_CON_RIESGOS.*\n?", "", out)
    return out


def copy_one(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if not src.exists():
        raise FileNotFoundError(src)
    if src.suffix.lower() in {".pl", ".pm", ".py", ".md", ".txt", ".json", ".sh"}:
        raw = src.read_text(encoding="utf-8", errors="replace")
        dst.write_text(sanitize_text(raw), encoding="utf-8", newline="\n")
    else:
        shutil.copy2(src, dst)
    print(f"OK {dst.relative_to(ROOT)} ({dst.stat().st_size} B)")


def patch_train_eval_without_train(path: Path) -> None:
    """En eval-only, no exige fantasma_train_norm.csv (ahorra ~12 MB)."""
    text = path.read_text(encoding="utf-8")
    old = """my $t_load = time();
print "[*] Cargando train...\\n";
my $train_pack = Market::ML::FantasmaLSTMData->load_xy(
 csv => $opt{train},
 stats => $opt{stats},
);
print "[*] Cargando test...\\n";
my $test_pack = Market::ML::FantasmaLSTMData->load_xy(
 csv => $opt{test},
 stats => $opt{stats},
);
printf "[*] load OK train_rows=%d test_rows=%d feats=%d targets=%s (%.1fs)\\n",
 $train_pack->{n_rows}, $test_pack->{n_rows}, $train_pack->{n_features},
 join( ',', @{ $train_pack->{targets} } ), time() - $t_load;"""

    # Tolerate whitespace variants from sanitize
    pattern = re.compile(
        r"my \$t_load = time\(\);\s*"
        r'print "\[\*\] Cargando train\.\.\.\\n";\s*'
        r"my \$train_pack = Market::ML::FantasmaLSTMData->load_xy\(\s*"
        r"csv\s*=>\s*\$opt\{train\},\s*"
        r"stats\s*=>\s*\$opt\{stats\},\s*"
        r"\);\s*"
        r'print "\[\*\] Cargando test\.\.\.\\n";\s*'
        r"my \$test_pack = Market::ML::FantasmaLSTMData->load_xy\(\s*"
        r"csv\s*=>\s*\$opt\{test\},\s*"
        r"stats\s*=>\s*\$opt\{stats\},\s*"
        r"\);\s*"
        r'printf "\[\*\] load OK train_rows=%d test_rows=%d feats=%d targets=%s \(%.1fs\)\\n",\s*'
        r"\$train_pack->\{n_rows\}, \$test_pack->\{n_rows\}, \$train_pack->\{n_features\},\s*"
        r"join\( ',', @\{ \$train_pack->\{targets\} \} \), time\(\) - \$t_load;",
        re.S,
    )
    new = """my $t_load = time();
print "[*] Cargando test...\\n";
my $test_pack = Market::ML::FantasmaLSTMData->load_xy(
 csv => $opt{test},
 stats => $opt{stats},
);
my $train_pack;
if ( $opt{eval_only} ) {
 print "[*] eval-only: se omite train CSV\\n";
 $train_pack = $test_pack;
}
else {
 die "Train no encontrado: $opt{train}\\n" unless -f $opt{train};
 print "[*] Cargando train...\\n";
 $train_pack = Market::ML::FantasmaLSTMData->load_xy(
 csv => $opt{train},
 stats => $opt{stats},
 );
}
printf "[*] load OK train_rows=%d test_rows=%d feats=%d targets=%s (%.1fs)\\n",
 $train_pack->{n_rows}, $test_pack->{n_rows}, $train_pack->{n_features},
 join( ',', @{ $train_pack->{targets} } ), time() - $t_load;"""

    text2, n = pattern.subn(new, text, count=1)
    if n != 1:
        # fallback: insert flag after make_path
        raise RuntimeError(f"No se pudo parchear train load (matches={n})")
    path.write_text(text2, encoding="utf-8", newline="\n")
    print("patched train eval-only without train CSV")


def patch_binary_defaults(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = text.replace(
        r'Data\ml_out\lstm_fantasma\preds_test.csv',
        "Data/ml_out/lstm_fantasma/preds_test.csv",
    )
    text = text.replace(
        r'Data\ml_out\lstm_fantasma\binary_metrics_test.json',
        "Data/ml_out/lstm_fantasma/binary_metrics_test.json",
    )
    # after sanitize defaults may still be windows-ish
    text = re.sub(
        r'default=r?"[^"]*preds_test[^"]*"',
        'default="Data/ml_out/lstm_fantasma/preds_test.csv"',
        text,
    )
    text = re.sub(
        r'default=r?"[^"]*binary_metrics_test[^"]*"',
        'default="Data/ml_out/lstm_fantasma/binary_metrics_test.json"',
        text,
    )
    text = re.sub(r'"model_version":\s*"[^"]*"', '"model_version": "1"', text)
    path.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    if STAGING.exists():
        shutil.rmtree(STAGING)
    ROOT.mkdir(parents=True)

    # guia (repo) ya recortada
    copy_one(REPO / "docs/material_profesor/guia.md", ROOT / "guia.md")
    copy_one(
        REPO / "docs/material_profesor/ENTREGA_JUAN_86_FEATURES.txt",
        ROOT / "features_86.txt",
    )
    docx = Path(r"C:\Users\bryan\Downloads\ModuloPredictivo_GR2.docx")
    shutil.copy2(docx, ROOT / "ModuloPredictivo_GR2.docx")
    print("OK ModuloPredictivo_GR2.docx")

    # Solo pptx (pdf omitido por peso)
    copy_one(
        REPO / "docs/material_profesor/PRESENTACION_FINAL_ML.pptx",
        ROOT / "presentacion/PRESENTACION_FINAL_ML.pptx",
    )

    for src_rel, dst_rel in [
        ("scripts/extract_fantasma_dataset.pl", "scripts/extract_fantasma_dataset.pl"),
        ("scripts/normalize_fantasma_dataset.pl", "scripts/normalize_fantasma_dataset.pl"),
        ("scripts/train_fantasma_lstm_v2.pl", "scripts/train_fantasma_lstm.pl"),
        ("scripts/demo_fantasma_predict.pl", "scripts/demo_fantasma_predict.pl"),
        (
            "scripts/compute_fantasma_binary_metrics_v2.py",
            "scripts/compute_fantasma_binary_metrics.py",
        ),
    ]:
        copy_one(REPO / src_rel, ROOT / dst_rel)

    patch_train_eval_without_train(ROOT / "scripts/train_fantasma_lstm.pl")
    # Quitar bloque de comparacion contra baseline (en el zip el unico modelo es este)
    tp = ROOT / "scripts/train_fantasma_lstm.pl"
    tt = tp.read_text(encoding="utf-8")
    tt2, ncmp = re.subn(
        r"\n# Comparacion corta[\s\S]*?\nif \( -f \$v1_metrics_path \) \{[\s\S]*?\n\}\n",
        "\n",
        tt,
        count=1,
    )
    if ncmp != 1:
        # fallback name after sanitize may vary
        tt2, ncmp = re.subn(
            r"\nif \( -f \$v1_metrics_path \) \{[\s\S]*?\n\}\n",
            "\n",
            tt,
            count=1,
        )
    print(f"removed comparison block matches={ncmp}")
    tp.write_text(tt2, encoding="utf-8", newline="\n")
    patch_binary_defaults(ROOT / "scripts/compute_fantasma_binary_metrics.py")

    market = [
        "Market/MarketData.pm",
        "Market/ML/ExtractFantasmaDataset.pm",
        "Market/ML/FantasmaLSTMData.pm",
        "Market/ML/NormalizeFantasmaDataset.pm",
        "Market/Drawing/FibRetracement.pm",
    ]
    for ind in (
        "PivotPointsHL",
        "ATR",
        "SMC_Pro",
        "SMC_Structures_FVG",
        "ZigZag",
        "DIY",
        "AnchoredVWAP",
        "VolumeProfile2",
        "HLD",
        "AutoTrendChannel",
        "Liquidity",
    ):
        market.append(f"Market/Indicators/{ind}.pm")
    for m in market:
        copy_one(REPO / m, ROOT / m)

    # Datos minimos para demo/eval (SIN train_norm ni CSV crudos)
    for src_rel, dst_rel in [
        ("Data/ml_out/fantasma_test_norm.csv", "Data/ml_out/fantasma_test_norm.csv"),
        ("Data/ml_out/fantasma_norm_stats.json", "Data/ml_out/fantasma_norm_stats.json"),
    ]:
        copy_one(REPO / src_rel, ROOT / dst_rel)

    final_dir = REPO / "Data/ml_out/lstm_fantasma_final"
    out_dir = ROOT / "Data/ml_out/lstm_fantasma"
    for name in (
        "fantasma_lstm.params",
        "metrics_test.json",
        "binary_metrics_test.json",
        "preds_test.csv",
        "train_config.json",
    ):
        copy_one(final_dir / name, out_dir / name)

    for src_rel, dst_rel in [
        ("docs/material_profesor/EXTRACTOR_FANTASMA.md", "docs/EXTRACTOR_FANTASMA.md"),
        ("docs/material_profesor/NORMALIZACION_FANTASMA.md", "docs/NORMALIZACION_FANTASMA.md"),
        ("docs/material_profesor/LSTM_FANTASMA_V2.md", "docs/LSTM_FANTASMA.md"),
        ("docs/material_profesor/METRICAS_BINARIAS_V2.md", "docs/METRICAS_BINARIAS.md"),
    ]:
        copy_one(REPO / src_rel, ROOT / dst_rel)

    # demo: limpiar restos " /final"
    demo_path = ROOT / "scripts/demo_fantasma_predict.pl"
    demo = demo_path.read_text(encoding="utf-8")
    demo = re.sub(
        r"\(2\.weight →.*?1\.weight →.*?\)",
        "(2.weight = Dropout+Dense; 1.weight = Dense directo)",
        demo,
    )
    demo = demo.replace("arch detectada: Dense=2.* (/final)", "arch detectada: Dense=2.*")
    demo = demo.replace("Dense=2.* (v2/final)", "Dense=2.*")
    demo = demo.replace("Dense=2.* (/final)", "Dense=2.*")
    demo_path.write_text(demo, encoding="utf-8", newline="\n")

    # guia: eval sin flags que pisan herencia + sin pdf
    guia = (ROOT / "guia.md").read_text(encoding="utf-8")
    guia = guia.replace(
        """perl -I. scripts/train_fantasma_lstm.pl --eval-only \\
  --model Data/ml_out/lstm_fantasma/fantasma_lstm.params \\
  --out-dir /tmp/fantasma_eval \\
  --hidden 48 --dropout 0.2 --batch-size 32 --seq-len 5""",
        """perl -I. scripts/train_fantasma_lstm.pl --eval-only \\
  --model Data/ml_out/lstm_fantasma/fantasma_lstm.params \\
  --out-dir Data/ml_out/lstm_fantasma""",
    )
    guia = guia.replace("| `presentacion/`                  | Diapositivas (pptx, pdf)   |",
                        "| `presentacion/`                  | Diapositivas (pptx)        |")
    (ROOT / "guia.md").write_text(guia, encoding="utf-8", newline="\n")
    # sync repo guia with eval command fix
    (REPO / "docs/material_profesor/guia.md").write_text(guia, encoding="utf-8", newline="\n")

    bad = []
    for p in ROOT.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".md", ".pl", ".pm", ".py", ".txt", ".json"}:
            text = p.read_text(encoding="utf-8", errors="replace")
            if re.search(r"v2", text, re.I):
                for i, line in enumerate(text.splitlines(), 1):
                    if re.search(r"v2", line, re.I):
                        bad.append(f"{p.relative_to(ROOT)}:{i}:{line.strip()[:140]}")
    print("V2_HITS", len(bad))
    for b in bad[:30]:
        print(b)

    if ZIP_OUT.exists():
        ZIP_OUT.unlink()
    with zipfile.ZipFile(
        ZIP_OUT, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as zf:
        for p in ROOT.rglob("*"):
            if p.is_file():
                zf.write(p, arcname=f"{ROOT_NAME}/{p.relative_to(ROOT).as_posix()}")

    size_mb = ZIP_OUT.stat().st_size / 1024 / 1024
    nfiles = sum(1 for p in ROOT.rglob("*") if p.is_file())
    print("ZIP", ZIP_OUT)
    print(f"size_mb={size_mb:.2f} files={nfiles}")
    if size_mb >= 5.0:
        print("WARNING: zip >= 5 MB")
        for p in sorted(ROOT.rglob("*"), key=lambda x: -x.stat().st_size if x.is_file() else 0):
            if p.is_file():
                print(f"  {p.stat().st_size/1024/1024:.2f} MB  {p.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
