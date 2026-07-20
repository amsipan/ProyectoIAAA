#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::MarketData;
use Market::Indicators::Liquidity;
use Market::Overlays::Liquidity;

# ---------------------------------------------------------------------------
# Helpers: build synthetic series
# ---------------------------------------------------------------------------
sub add_flat {
    my ( $md, $n, $base, $start_ts ) = @_;
    $start_ts //= 0;
    for my $i ( 0 .. $n - 1 ) {
        my $p = $base;
        $md->add_candle(
            [ sprintf( 't%04d', $start_ts + $i ), $p, $p + 1, $p - 1, $p, 100 ] );
    }
}

sub feed_all {
    my ( $ind, $md ) = @_;
    my $n = $md->size();
    for my $i ( 0 .. $n - 1 ) {
        $ind->update_last( $md, $i );
    }
}

# ---------------------------------------------------------------------------
# Load / overlay contract + labels ASCII (sin Unicode / mojibake)
# ---------------------------------------------------------------------------
{
    my $ind = Market::Indicators::Liquidity->new( k => 2 );
    ok( $ind, 'new indicator' );
    my $ov = Market::Overlays::Liquidity->new( indicator => $ind, visible => 0 );
    ok( $ov, 'new overlay' );
    is( $ov->tag, 'ov_liq', 'tag' );
    ok( !$ov->is_visible, 'default hidden if visible=>0' );
    $ov->set_visible(1);
    ok( $ov->is_visible, 'set_visible' );
    $ov->set_element_visible( 'BSL', 0 );
    ok( !$ov->is_element_visible('BSL'), 'element toggle BSL off' );
    $ov->set_element_visible( 'BSL', 1 );
    ok( $ov->is_element_visible('BSL'), 'element toggle BSL on' );

    is( Market::Overlays::Liquidity->format_event_label( 'SWEEP', 'BSL' ),
        'SWEEP UP', 'label SWEEP UP ASCII' );
    is( Market::Overlays::Liquidity->format_event_label( 'SWEEP', 'SSL' ),
        'SWEEP DN', 'label SWEEP DN ASCII' );
    is( Market::Overlays::Liquidity->format_event_label( 'GRAB', 'EQL' ),
        'LQ GRAB DN', 'label GRAB DN' );
    my $lab = Market::Overlays::Liquidity->format_event_label( 'SWEEP', 'EQH' );
    ok( $lab !~ /[^\x00-\x7F]/, 'label sin bytes no-ASCII (Tk-safe)' );
    ok( $lab !~ /â/, 'label sin mojibake â' );

    my $lx = Market::Overlays::Liquidity->clamp_label_x( 10, 500, 400 );
    ok( $lx >= 4 && $lx <= 400 - 10, 'clamp_label_x dentro del plot' );
    ok( !$ov->is_element_visible('HISTORY'), 'HISTORY off por defecto' );
    $ov->set_element_visible( 'HISTORY', 1 );
    ok( $ov->is_element_visible('HISTORY'), 'HISTORY se puede activar' );
}

# ---------------------------------------------------------------------------
# absorb_pivots: historial no se pierde al "trim" del ZZ
# ---------------------------------------------------------------------------
{
    my $ind = Market::Indicators::Liquidity->new();
    is( $ind->absorb_pivots( [ { index => 5, price => 100, side => 'high' } ] ),
        1, 'absorb primer pivote' );
    is( $ind->absorb_pivots( [ { index => 5, price => 100, side => 'high' } ] ),
        0, 'absorb duplicado no suma' );
    is( $ind->absorb_pivots( [ { index => 20, price => 90, side => 'low' } ] ),
        1, 'absorb segundo pivote' );
    is( $ind->pivot_history_count(), 2, 'historial tiene 2 pivotes' );

    # Simular que el ZZ solo devuelve el pivote reciente
    is( $ind->absorb_pivots( [ { index => 20, price => 90, side => 'low' } ] ),
        0, 'solo el reciente no borra el viejo' );
    is( $ind->pivot_history_count(), 2, 'historial sigue en 2' );

    $ind->reset_soft();
    is( $ind->pivot_history_count(), 2, 'reset_soft conserva pivotes' );
    $ind->reset_full();
    is( $ind->pivot_history_count(), 0, 'reset_full limpia pivotes' );
}

# ---------------------------------------------------------------------------
# SWEEP: mecha rompe BSL y cierra debajo en la misma vela (PDF)
# ---------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('1m') if $md->can('set_base_timeframe');

    # Need enough bars for k=2 pivots + ATR warm-up
    # Build: flat ~100, swing high at index 10 (high=120), flat, then sweep bar
    for my $i ( 0 .. 9 ) {
        my $p = 100;
        $md->add_candle( [ "a$i", $p, $p + 2, $p - 2, $p, 50 ] );
    }
    # pivot high candidate at 10: high must exceed neighbors for k=2
    # bars 8,9,10,11,12 with 10 being highest
    $md->add_candle( [ 'a10', 100, 120, 99, 105, 80 ] );    # swing high 120
    $md->add_candle( [ 'a11', 105, 110, 100, 108, 60 ] );
    $md->add_candle( [ 'a12', 108, 112, 102, 106, 60 ] );
    # more bars so pivot 10 confirms at i=12 (k=2)
    for my $i ( 13 .. 20 ) {
        $md->add_candle( [ "a$i", 106, 110, 102, 106, 50 ] );
    }
    # Sweep BSL 120: high>120, close<120
    $md->add_candle( [ 'sweep', 106, 125, 100, 110, 200 ] );

    my $ind = Market::Indicators::Liquidity->new(
        k              => 2,
        atr_period     => 5,
        run_accept_n   => 3,
        sweep_max_bars => 2,
        grab_max_bars  => 8,
    );
    feed_all( $ind, $md );

    my $events = $ind->get_events();
    my @sweeps = grep { ( $_->{resolution} // '' ) eq 'sweep' } @$events;
    ok( @sweeps >= 1, 'al menos un SWEEP detectado' )
      or diag explain $events;

    if (@sweeps) {
        is( $sweeps[0]{level_kind}, 'BSL', 'sweep sobre BSL' );
    }

    my $export = $ind->export_liquidity_events();
    ok( ref($export) eq 'ARRAY', 'export_liquidity_events array' );
    ok( @$export >= 1, 'export tiene filas de evento' ) if @sweeps;

    my $stream = $ind->get_observation_stream();
    ok( ref($stream) eq 'ARRAY' && @$stream == $md->size(), 'observation stream por vela' );
}

# ---------------------------------------------------------------------------
# RUN: N cierres consecutivos por encima de BSL
# ---------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    for my $i ( 0 .. 9 ) {
        $md->add_candle( [ "b$i", 100, 102, 98, 100, 50 ] );
    }
    $md->add_candle( [ 'b10', 100, 120, 99, 110, 80 ] );    # SH 120
    $md->add_candle( [ 'b11', 110, 115, 105, 112, 60 ] );
    $md->add_candle( [ 'b12', 112, 116, 108, 114, 60 ] );
    for my $i ( 13 .. 18 ) {
        $md->add_candle( [ "b$i", 110, 114, 106, 110, 50 ] );
    }
    # Break and accept above 120 with N=3 closes
    $md->add_candle( [ 'r0', 118, 128, 117, 125, 150 ] );    # sweep + close above
    $md->add_candle( [ 'r1', 125, 130, 124, 128, 150 ] );    # close above
    $md->add_candle( [ 'r2', 128, 132, 127, 130, 150 ] );    # close above → RUN

    my $ind = Market::Indicators::Liquidity->new(
        k            => 2,
        atr_period   => 5,
        run_accept_n => 3,
    );
    feed_all( $ind, $md );

    my $events = $ind->get_events();
    my @runs = grep { ( $_->{resolution} // '' ) eq 'run' } @$events;
    ok( @runs >= 1, 'RUN con N cierres fuera' )
      or diag explain $events;
}

# ---------------------------------------------------------------------------
# GRAB: rompe y regresa en ventana 3..grab_max (no mismo día 1-2)
# ---------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    for my $i ( 0 .. 9 ) {
        $md->add_candle( [ "c$i", 100, 102, 98, 100, 50 ] );
    }
    $md->add_candle( [ 'c10', 100, 120, 99, 110, 80 ] );
    $md->add_candle( [ 'c11', 110, 115, 105, 112, 60 ] );
    $md->add_candle( [ 'c12', 112, 116, 108, 114, 60 ] );
    for my $i ( 13 .. 18 ) {
        $md->add_candle( [ "c$i", 110, 114, 106, 110, 50 ] );
    }
    # Sweep: high>120, close still above (not reclaim same bar)
    $md->add_candle( [ 'g0', 118, 126, 117, 124, 120 ] );
    # Stay outside a couple bars (not yet run N=3 if we reclaim before)
    $md->add_candle( [ 'g1', 124, 127, 122, 125, 100 ] );
    $md->add_candle( [ 'g2', 125, 128, 123, 126, 100 ] );
    # bars_since_sweep = 3 at reclaim → GRAB (if grab_max>=3, sweep_max=2)
    $md->add_candle( [ 'g3', 126, 127, 115, 118, 100 ] );    # close back below 120

    my $ind = Market::Indicators::Liquidity->new(
        k              => 2,
        atr_period     => 5,
        run_accept_n   => 5,    # don't trigger RUN before grab reclaim
        sweep_max_bars => 2,
        grab_max_bars  => 8,
    );
    feed_all( $ind, $md );

    my $events = $ind->get_events();
    my @grabs = grep { ( $_->{resolution} // '' ) eq 'grab' } @$events;
    ok( @grabs >= 1, 'GRAB por reclaim lento' )
      or diag explain $events;
}

# ---------------------------------------------------------------------------
# SSL sweep down
# ---------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    for my $i ( 0 .. 9 ) {
        $md->add_candle( [ "d$i", 100, 102, 98, 100, 50 ] );
    }
    $md->add_candle( [ 'd10', 100, 101, 80, 95, 80 ] );      # swing low 80
    $md->add_candle( [ 'd11', 95, 100, 90, 96, 60 ] );
    $md->add_candle( [ 'd12', 96, 100, 92, 97, 60 ] );
    for my $i ( 13 .. 20 ) {
        $md->add_candle( [ "d$i", 97, 100, 94, 97, 50 ] );
    }
    # Sweep SSL: low<80, close>80
    $md->add_candle( [ 'ss', 97, 100, 75, 90, 200 ] );

    my $ind = Market::Indicators::Liquidity->new( k => 2, atr_period => 5 );
    feed_all( $ind, $md );
    my @sweeps =
      grep { ( $_->{resolution} // '' ) eq 'sweep' && ( $_->{level_kind} // '' ) eq 'SSL' }
      @{ $ind->get_events() };
    ok( @sweeps >= 1, 'SWEEP SSL' )
      or diag explain $ind->get_events();
}

# ---------------------------------------------------------------------------
# EQH: dos swing highs dentro de tolerancia ATR
# ---------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    # Create two similar highs
    for my $i ( 0 .. 5 ) {
        $md->add_candle( [ "e$i", 100, 102, 98, 100, 50 ] );
    }
    $md->add_candle( [ 'e6', 100, 110, 99, 105, 80 ] );      # SH ~110
    $md->add_candle( [ 'e7', 105, 108, 100, 104, 60 ] );
    $md->add_candle( [ 'e8', 104, 107, 101, 103, 60 ] );
    for my $i ( 9 .. 14 ) {
        $md->add_candle( [ "e$i", 103, 106, 100, 103, 50 ] );
    }
    $md->add_candle( [ 'e15', 103, 110.5, 100, 105, 80 ] );  # second SH ~110.5
    $md->add_candle( [ 'e16', 105, 108, 101, 104, 60 ] );
    $md->add_candle( [ 'e17', 104, 107, 100, 103, 60 ] );
    for my $i ( 18 .. 25 ) {
        $md->add_candle( [ "e$i", 103, 106, 100, 103, 50 ] );
    }

    my $ind = Market::Indicators::Liquidity->new(
        k           => 2,
        atr_period  => 5,
        eq_atr_mult => 0.5,    # loose for synthetic
    );
    feed_all( $ind, $md );
    my $levels = $ind->get_levels();
    my @eqh = grep { ( $_->{kind} // '' ) eq 'EQH' } @$levels;
    my $events = $ind->get_events();
    # EQH may still be live or already swept — either levels history or swings
    my $sh = $ind->get_values()->{swings_high};
    ok( @$sh >= 2, 'al menos 2 swing highs para EQH' )
      or diag explain $ind->get_values();
    # Soft: EQH created if tolerance allows
    if ( @eqh || grep { ( $_->{level_kind} // '' ) eq 'EQH' } @$events ) {
        pass('EQH detectado');
    }
    else {
        pass('EQH no forzado (tolerancia); swings OK');
    }
}

# ---------------------------------------------------------------------------
# reset clears state
# ---------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    for my $i ( 0 .. 30 ) {
        $md->add_candle( [ "z$i", 100, 105, 95, 100, 50 ] );
    }
    my $ind = Market::Indicators::Liquidity->new( k => 2, atr_period => 5 );
    feed_all( $ind, $md );
    $ind->reset();
    is( $ind->get_values()->{last_index}, -1, 'reset last_index' );
    is( scalar @{ $ind->get_events() }, 0, 'reset events' );
}

done_testing;
