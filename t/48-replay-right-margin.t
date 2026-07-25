#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::ChartEngine;
use Market::ReplayController;
use Market::Panels::Scales;

# Geometría PricePanel: body_w = 0.6*bar_w → inter_gap = 0.4*bar_w
sub assert_last_candle_criterion {
    my ( $width, $bars, $margin, $label ) = @_;
    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => $margin,
        min_y        => 0,
        max_y        => 1,
    );
    $scale->{width}  = $width;
    $scale->{height} = 100;

    my $bar_w  = $scale->plot_width / $bars;
    my $half   = 0.3 * $bar_w;
    my $gap    = 0.4 * $bar_w;
    my $center = $scale->index_to_center_x( $bars - 1 );
    my $body_r = $center + $half;

    cmp_ok( $body_r, '<=', $width + 1e-6, "$label: cuerpo completo dentro del canvas" );
    cmp_ok( $width - $body_r,
        '>=', $gap - 1e-6, "$label: blanco >= inter-vela (0.4*bar_w)" );
}

# ---------------------------------------------------------------------------
# Helper margen: Replay OFF = 0; ON cumple criterio para varios bars (TF/zoom)
# ---------------------------------------------------------------------------
{
    my $eng = bless {
        replay_controller    => undef,
        price_canvas         => undef,
        _last_price_canvas_w => 800,
        visible_bars         => 60,
    }, 'Market::ChartEngine';

    is( $eng->_current_right_margin(60), 0, 'sin Replay zoom normal: margen 0' );

    # Live zoom-out extremo: bar_w aprox < FULL_BW → aire a la derecha
    {
        my $w    = 800;
        my $bars = 400;    # 800/400 = 2px < FULL_BW 3
        my $rm   = $eng->_current_right_margin($bars);
        ok( $rm >= 8, "live zoom-out: margen >= MIN_PX (got $rm)" );
        my $scale = Market::Panels::Scales->new(
            bars => $bars, right_margin => $rm, min_y => 0, max_y => 1
        );
        $scale->{width} = $w;
        my $bar_w  = $scale->plot_width / $bars;
        my $center = $scale->index_to_center_x( $bars - 1 );
        cmp_ok( $center + 0.5, '<', $w, 'live zoom-out: centro última vela antes del borde' );
        cmp_ok( $w - $center, '>=', 4, 'live zoom-out: aire a la derecha del centro' );
    }

    # Rampa continua: sin cliff 0→N al cruzar el antiguo umbral bar_w=4.
    # En w=800, bars=180 → bw≈4.44; bars=220 → bw≈3.64. Ambos en la rampa.
    {
        my $w = 800;
        $eng->{_last_price_canvas_w} = $w;
        my $rm_hi = $eng->_current_right_margin(180);    # bw≈4.44
        my $rm_lo = $eng->_current_right_margin(220);    # bw≈3.64
        ok( $rm_hi > 0, "rampa mid: margen > 0 en bw≈4.4 (got $rm_hi)" );
        ok( $rm_lo >= $rm_hi,
            "rampa: margen no baja al alejar (hi=$rm_hi lo=$rm_lo)" );
        my $rm_mid = $eng->_current_right_margin(100);    # bw=8
        ok( $rm_mid > 0 && $rm_mid <= $rm_hi,
            "rampa suave en bw=8 (got $rm_mid, hi=$rm_hi)" );
        # Paneado (offset>0) + zoom fino: misma necesidad de aire a la derecha
        $eng->{offset} = 10;
        ok( $eng->_current_right_margin(400) >= 8,
            'live paneado + zoom fino: margen >= MIN_PX' );
        is( $eng->_current_right_margin(60), 0,
            'live paneado + zoom normal: margen 0' );
        $eng->{offset} = 0;
    }

    my $rc = bless { active => 1, replay_idx => 100 }, 'Market::ReplayController';
    $eng->{replay_controller} = $rc;

    for my $bars ( 20, 60, 200, 500 ) {
        my $w  = 800;
        my $rm = $eng->_replay_plot_right_margin_px( $w, $bars );
        ok( $rm > 0, "Replay margen > 0 con bars=$bars" );
        assert_last_candle_criterion( $w, $bars, $rm, "bars=$bars" );
        is( $eng->_current_right_margin($bars),
            $rm, "_current_right_margin coincide bars=$bars" );
    }

    $rc->{active} = 0;
    is( $eng->_current_right_margin(60), 0, 'Replay exit + zoom normal: margen 0' );
}

# ---------------------------------------------------------------------------
# Auto-scroll: head al borde no queda con blank=0 (mínimo 1 slot trail)
# ---------------------------------------------------------------------------
{
    package MarginTrailMD;
    sub new {
        my ( $class, $n ) = @_;
        return bless { n => $n }, $class;
    }
    sub size       { $_[0]{n} }
    sub last_index { $_[0]{n} - 1 }
    sub get_candle { return [ 't', 1, 2, 0, 1, 1 ] }
}

{
    my $md = MarginTrailMD->new(500);
    my $rc = Market::ReplayController->new( market_data => $md );
    $rc->start(100);

    my $eng = bless {
        market_data            => $md,
        replay_controller      => $rc,
        visible_bars           => 60,
        replay_view_end        => 100,    # head pegado (blank=0)
        replay_prev_causal_end => 100,
        offset                 => 0,
    }, 'Market::ChartEngine';

    # Simular avance del head con auto-scroll
    $rc->{replay_idx} = 101;
    my ( $start, $end ) = $eng->_replay_window(60);
    my $causal = 101;
    cmp_ok( $end, '>=', $causal + 1,
        'tras avance: view_end >= causal_end + 1 (trail)' );
    cmp_ok( $end - $causal, '>=', 1, 'al menos 1 slot vacío a la derecha' );
}

done_testing();
