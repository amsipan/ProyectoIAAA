use strict;
use warnings;
use Test::More;

use lib '.';
use Market::ChartEngine;
use Market::OverlayManager;
use Market::Indicators::SMC_Structures;
use Market::Indicators::Liquidity;
use Market::Overlays::SMC_Structures;
use Market::Overlays::Liquidity;
use Market::ReplayController;
use Market::UI::Callbacks;

# =============================================================================
# Task 0018: rediseño de UI + corrección de fallos visuales.
# Este test cubre la LÓGICA verificable headless (no la apariencia Tk):
#   F3/F4 — alimentación BAJO DEMANDA: con las capas OFF, sync_overlay_indicators
#           NO alimenta los indicadores pesados (arranque instantáneo).
#   F1   — los toggles restauran las líneas: activar tras desactivar vuelve a
#          dibujar (el indicador queda alimentado; solo cambia visibilidad).
#   Por-capa — activar SMC no alimenta Liquidity y viceversa.
# =============================================================================

# --- MarketData sintético con todos los TF (Liquidity accede a D/W). ---
{
    package TMD;
    sub new {
        my ($class, $arr) = @_;
        return bless {
            data => { '1m'=>$arr, '5m'=>[], '15m'=>[], '1h'=>[], '2h'=>[], '4h'=>[], 'D'=>[], 'W'=>[] },
            _arr => $arr, active_tf => '1m',
        }, $class;
    }
    sub size { scalar @{ shift->{_arr} } }
    sub get_candle { my ($s,$i)=@_; $s->{_arr}[$i] }
    sub get_timestamp { my ($s,$i)=@_; my $r=$s->{_arr}[$i]; $r ? $r->[0] : undef }
    sub get_slice { my ($s,$a,$b)=@_; [ @{$s->{_arr}}[$a..$b] ] }
}

# Dataset con swings + un sweep para que SMC/Liquidity generen items.
sub build_md {
    my @a;
    for my $i (0..120) {
        my $base = 100 + (($i % 10 < 5) ? $i % 10 : 10 - $i % 10);  # zig-zag
        push @a, [ sprintf('2026-04-01T%02d:%02d:00-05:00', int($i/60), $i%60),
                   $base, $base+3, $base-3, $base+1, 100+$i ];
    }
    return TMD->new(\@a);
}

# ChartEngine parcial con overlays REGISTRADOS y OFF (como producción tras 0018).
sub build_engine {
    my ($md) = @_;
    my $smc_ind = Market::Indicators::SMC_Structures->new(k=>3);
    my $liq_ind = Market::Indicators::Liquidity->new(k=>3);
    my $mgr = Market::OverlayManager->new();
    my $smc_ov = Market::Overlays::SMC_Structures->new(indicator=>$smc_ind, visible=>0);
    my $liq_ov = Market::Overlays::Liquidity->new(indicator=>$liq_ind, visible=>0);
    $mgr->register('smc',$smc_ov);
    $mgr->register('liq',$liq_ov);
    return bless {
        market_data=>$md, smc_indicator=>$smc_ind, _smc_fed_up_to=>-1,
        liq_indicator=>$liq_ind, _liq_fed_up_to=>-1,
        smc_overlay=>$smc_ov, liq_overlay=>$liq_ov, overlay_manager=>$mgr,
        replay_controller=>Market::ReplayController->new(market_data=>$md),
        visible_bars=>60, offset=>0, ctrl_zoom_x_shift=>0,
    }, 'Market::ChartEngine';
}

# --- F3/F4: capas OFF => no se alimenta nada pesado ---
{
    my $md = build_md();
    my $eng = build_engine($md);
    $eng->sync_overlay_indicators();
    is($eng->{_smc_fed_up_to}, -1, 'F3/F4: SMC no alimentado con capa OFF (arranque instantáneo)');
    is($eng->{_liq_fed_up_to}, -1, 'F3/F4: Liquidity no alimentado con capa OFF');
}

# --- Por-capa: activar SMC alimenta solo SMC ---
{
    my $md = build_md();
    my $eng = build_engine($md);
    my $last = $md->size - 1;

    my $cb_smc = Market::UI::Callbacks->make_overlay_toggle($eng, 'smc');
    # Activar visibilidad SIN request_render (no hay Tk aquí): set_visible directo
    # replica lo que hace el callback salvo el re-render.
    $eng->{smc_overlay}->set_visible(1);
    $eng->sync_overlay_indicators();
    is($eng->{_smc_fed_up_to}, $last, 'por-capa: activar SMC alimenta SMC hasta el final');
    is($eng->{_liq_fed_up_to}, -1,    'por-capa: Liquidity sigue sin alimentar');

    $eng->{liq_overlay}->set_visible(1);
    $eng->sync_overlay_indicators();
    is($eng->{_liq_fed_up_to}, $last, 'por-capa: activar Liquidity la alimenta hasta el final');
}

# --- F1: desactivar y reactivar restaura los items dibujables ---
{
    my $md = build_md();
    my $eng = build_engine($md);
    my $smc_ov = $eng->{smc_overlay};
    my ($s,$e) = (0, $md->size - 1);

    # Activar
    $smc_ov->set_visible(1);
    $eng->sync_overlay_indicators();
    $eng->{overlay_manager}->compute_all($md, $s, $e);
    my $items_on = scalar @{ $smc_ov->visible_items };
    ok($items_on > 0, "F1: con SMC ON hay items dibujables ($items_on)");

    # Desactivar: visible=0
    $smc_ov->set_visible(0);
    is($smc_ov->is_visible, 0, 'F1: SMC desactivado');

    # Reactivar: deben volver los items (el indicador sigue alimentado)
    $smc_ov->set_visible(1);
    $eng->sync_overlay_indicators();
    $eng->{overlay_manager}->compute_all($md, $s, $e);
    my $items_again = scalar @{ $smc_ov->visible_items };
    is($items_again, $items_on, 'F1: reactivar SMC restaura los mismos items (bug de toggles resuelto)');
}

# --- La factoría de toggle pasa el bool y cambia visibilidad (contrato con market.pl) ---
{
    my $md = build_md();
    my $eng = build_engine($md);
    my $cb = Market::UI::Callbacks->make_overlay_toggle($eng, 'smc');
    # market.pl llama $cb->($var?1:0); aquí simulamos ambos (sin request_render real:
    # el engine parcial no tiene canvas, así que envolvemos en eval para ignorar el render).
    eval { $cb->(1) }; is($eng->{overlay_manager}->get('smc')->is_visible, 1, 'toggle->(1) hace visible SMC');
    eval { $cb->(0) }; is($eng->{overlay_manager}->get('smc')->is_visible, 0, 'toggle->(0) oculta SMC');
    eval { $cb->(1) }; is($eng->{overlay_manager}->get('smc')->is_visible, 1, 'toggle->(1) de nuevo re-muestra SMC (F1)');
}

done_testing();
