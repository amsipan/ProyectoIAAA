#!/usr/bin/env python3
"""One-shot: strip Liquidity/VP/VWAP/Strategy dead code from ChartEngine.pm"""
from pathlib import Path
import re

p = Path(__file__).resolve().parents[1] / "Market" / "ChartEngine.pm"
t = p.read_text(encoding="utf-8")

for line in [
    "use Market::Indicators::Liquidity;\n",
    "use Market::Overlays::Liquidity;\n",
    "use Market::Indicators::Strategy_Builder;\n",
    "use Market::Overlays::Strategy_Builder;\n",
    "use Market::Indicators::VolumeProfile;\n",
    "use Market::Overlays::VolumeProfile;\n",
    "use Market::Indicators::AnchoredVWAP;\n",
    "use Market::Overlays::AnchoredVWAP;\n",
]:
    t = t.replace(line, "")

t = t.replace(
    """    # --- FASE ACTUAL ---
    # Activo: SMC Pro, Structures+FVG, HLD, Parallel Channel,
    #         ZigZag externo (ChartPrime) + ZigZag interno (ZZMTF).
    # Desactivado (no registrar): Liquidity, Strategy, VP, VWAP, Mxwll.
    # ZZ CHANNEL / Fibonacci: OFF (captura profe).
""",
    """    # --- PRODUCTO OFICIAL (docs/PRODUCTO_OFICIAL.md) ---
    # smc_pro, smc_fvg, hld, pchan, zigzag, fib.
    # NO registrar: Liquidity/Mxwll/Strategy/VP/VWAP (ver legacy/).
""",
)

old_sync = r"""    my \$liq_wants_feed = \$self->_overlay_wants_feed\('liq'\) \? 1 : 0;
    # task 0055: Liquidity puede depender de pivotes SMC aunque el overlay SMC esté apagado\.
    # Si Liq quiere alimentación, SMC también debe alimentarse hasta feed_to para no dejar
    # Liquidity en modo externo sin pivotes\.
    # smc_pro y alias 'smc' \(tests legacy\): solo si alguno está visible \(o ninguno registrado\)\.
    my \$smc_wants_feed = \$self->_any_named_overlay_wants\(qw\(smc_pro smc\)\) \? 1 : 0;
    my \$smc_fvg_wants_feed = \$self->_overlay_wants_feed\('smc_fvg'\) \? 1 : 0;
    if \(\$liq_wants_feed && \$self->\{liq_indicator\}\) \{
.*?    \$self->_feed_indicator_to\(\$self->\{vwap_indicator\}, '_vwap_fed_up_to', \$feed_to\)
        if \$self->_overlay_wants_feed\('vwap'\);
    \$self->_feed_indicator_to\(\$self->\{zigzag_indicator\}, '_zigzag_fed_up_to', \$feed_to\)
        if \$self->_overlay_wants_feed\('zigzag'\);
    return \$feed_to;
"""

new_sync = """    # Solo producto oficial (sin Liquidity/Strategy/VP/VWAP legacy).
    my $smc_wants_feed = $self->_any_named_overlay_wants(qw(smc_pro smc)) ? 1 : 0;
    my $smc_fvg_wants_feed = $self->_overlay_wants_feed('smc_fvg') ? 1 : 0;
    if ($smc_wants_feed) {
        my $done = $self->_feed_smc_chunk($feed_to, $self->{_smc_feed_chunk_size} // 1200);
        $self->_schedule_smc_background_feed($feed_to) unless $done;
    }
    if ($smc_fvg_wants_feed) {
        my $fvg_done = $self->_feed_indicator_chunk(
            $self->{smc_fvg_indicator}, '_smc_fvg_fed_up_to', $feed_to,
            $self->{_smc_feed_chunk_size} // 1200
        );
        $self->_schedule_smc_background_feed($feed_to) unless $fvg_done;
    }
    $self->_feed_indicator_to($self->{zigzag_indicator}, '_zigzag_fed_up_to', $feed_to)
        if $self->_overlay_wants_feed('zigzag');
    return $feed_to;
"""

t2, n = re.subn(old_sync, new_sync, t, count=1, flags=re.S)
print("sync replacements:", n)
t = t2 if n else t

t2, n = re.subn(
    r"sub compute_run_candle_map \{.*?\n\}\n\nsub set_zigzag_internal_resolution",
    """sub compute_run_candle_map {
    my ($self) = @_;
    # Liquidity RUN recolor es legacy; producto oficial no lo usa.
    return {};
}

sub set_zigzag_internal_resolution""",
    t,
    count=1,
    flags=re.S,
)
print("run_candle replacements:", n)
t = t2 if n else t

t2, n = re.subn(
    r"\n# task 0063: alimentación coordinada SMC → Liquidity\..*?^sub _feed_indicator_chunk \{",
    "\n# --- SMC Pro / FVG: feed no bloqueante ---\nsub _feed_indicator_chunk {",
    t,
    count=1,
    flags=re.S | re.M,
)
print("liq stack replacements:", n)
t = t2 if n else t

t2, n = re.subn(
    r"\nsub is_vwap_select_mode \{.*?\nsub set_selected_bar \{",
    """
# VWAP/VP placement = legacy (docs/LEGACY.md). Stubs.
sub is_vwap_select_mode { 0 }
sub set_vwap_select_mode { $_[0] }
sub begin_vwap_placement { $_[0] }
sub end_vwap_overlay { $_[0] }
sub confirm_vwap_anchor { $_[0] }
sub reanchor_vwap { $_[0] }
sub cancel_vwap_select_mode { $_[0] }
sub is_vp_select_mode { 0 }
sub set_vp_select_mode { $_[0] }
sub begin_vp_placement { $_[0] }
sub end_vp_overlay { $_[0] }
sub confirm_vp_anchor { $_[0] }
sub reanchor_vp { $_[0] }
sub cancel_vp_select_mode { $_[0] }

sub set_selected_bar {""",
    t,
    count=1,
    flags=re.S,
)
print("vwap/vp replacements:", n)
t = t2 if n else t

# set_timeframe legacy resets
t2, n = re.subn(
    r"\n    # spec 0005 / task 0012: reset del indicador de liquidez.*?"
    r"\$self->set_vp_select_mode\(0\) if \$self->can\('set_vp_select_mode'\);\n    \}\n",
    "\n",
    t,
    count=1,
    flags=re.S,
)
print("tf reset replacements:", n)
t = t2 if n else t

if "sub enable_liquidity_background_feed" not in t:
    t = t.replace(
        "\n1;\n",
        "\n# Legacy no-op (market.pl puede llamar al arranque)\n"
        "sub enable_liquidity_background_feed { return $_[0]; }\n\n1;\n",
        1,
    )
    print("added enable_liquidity no-op")

t = t.replace(
    "    # Alias legacy: Liquidity y feed coordinado usan pivotes swing de SMC Pro.\n",
    "    # Alias smc → smc_pro (nombres antiguos / tests).\n",
)

# Neutralize render branches that call removed private helpers
# Keep is_vwap/vp as 0 so branches never run; remove calls to _clear_vwap if any left in stubs area

p.write_text(t, encoding="utf-8")
print("OK lines", t.count("\n") + 1)
