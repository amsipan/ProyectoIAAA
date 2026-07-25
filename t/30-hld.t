#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::MarketData;
use Market::Indicators::HLD;
use Market::Overlays::HLD;

# Diario: día anterior OK
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('D');
    for my $i ( 0 .. 4 ) {
        my $b = 100 + $i * 5;
        $md->add_candle(
            [ sprintf( '2026-06-0%d', $i + 1 ), $b, $b + 10, $b - 5, $b + 5, 1 ] );
    }
    $md->set_timeframe('D');
    my $ind = Market::Indicators::HLD->new();
    my $r = $ind->compute( $md, tf => 'D', end_index => 4, price => 118 );
    ok( $r->{ok}, 'D ok' );
    is( $r->{anchor_index}, 3, 'D: día anterior' );
    is( $r->{min_age}, 1, 'D min_age=1' );
    is( $md->{active_tf}, 'D', 'compute no cambia active_tf (ya era D)' );
}

# Diario: no ayer si no llega
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('D');
    $md->add_candle( [ 'd0', 180, 200, 170, 190, 1 ] );
    for my $i ( 1 .. 5 ) {
        $md->add_candle( [ "d$i", 100 + $i, 110 + $i, 90 + $i, 105 + $i, 1 ] );
    }
    $md->add_candle( [ 'd6', 150, 160, 140, 195, 1 ] );
    $md->set_timeframe('D');
    my $ind = Market::Indicators::HLD->new();
    my $r = $ind->compute( $md, tf => 'D', end_index => 6, price => 195 );
    ok( $r->{ok}, 'D atrás' );
    is( $r->{anchor_index}, 0, 'D: no ayer' );
}

# 4h: ages 1,2,3 y 5 en rango → debe ser age=5 (idx end-5), no 1–3
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('4h');
    for my $i ( 0 .. 10 ) {
        my ( $h, $l ) =
            ( $i == 9 || $i == 8 || $i == 7 || $i == 5 ) ? ( 110, 90 ) : ( 50, 40 );
        $md->add_candle( [ "b$i", 55, $h, $l, 55, 1 ] );
    }
    $md->set_timeframe('4h');
    my $ind = Market::Indicators::HLD->new();
    my $r = $ind->compute( $md, tf => '4h', end_index => 10, price => 100 );
    ok( $r->{ok}, '4h ok' ) or diag explain $r;
    is( $r->{min_age}, 4, '4h min_age=4' );
    is( $r->{anchor_index}, 5, '4h: age>=4 → idx5 no la anterior' );
    ok( $r->{age_bars} >= 4, '4h age_bars >= 4' );
    ok( $r->{age_bars} != 1, '4h no age=1' );
}

# 4h: solo ages 1–3 en rango → OHLC/fallback
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('4h');
    for my $i ( 0 .. 6 ) {
        my ( $h, $l ) = ( $i >= 4 && $i <= 5 ) ? ( 110, 90 ) : ( 50, 40 );
        $md->add_candle( [ "c$i", 55, $h, $l, 55, 1 ] );
    }
    $md->set_timeframe('4h');
    my $ind = Market::Indicators::HLD->new();
    my $r = $ind->compute( $md, tf => '4h', end_index => 6, price => 100 );
    ok( $r->{ok}, '4h fallback ok' );
    ok( defined $r->{anchor_index}, '4h encuentra algo' );
}

# 4h: age=8 en rango, no 1–3
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('4h');
    for my $i ( 0 .. 10 ) {
        my ( $h, $l ) =
            $i == 9 ? ( 50, 40 )
          : $i == 2 ? ( 110, 90 )
          :           ( 60, 55 );
        $md->add_candle( [ "d$i", 55, $h, $l, 55, 1 ] );
    }
    $md->set_timeframe('4h');
    my $ind = Market::Indicators::HLD->new();
    my $r = $ind->compute( $md, tf => '4h', end_index => 10, price => 100 );
    ok( $r->{ok}, '4h lejana' );
    is( $r->{anchor_index}, 2, '4h idx2 age=8' );
}

{
    is(
        Market::Overlays::HLD->new(
            indicator => Market::Indicators::HLD->new(),
            source_tf => '4h',
            visible   => 1
          )->tag(),
        'ov_hld_4h',
        'tag 4h'
    );
    is(
        Market::Overlays::HLD->new(
            indicator => Market::Indicators::HLD->new(),
            source_tf => 'D',
            visible   => 1
          )->tag(),
        'ov_hld_d',
        'tag D'
    );
}

# --- MTF: chart 15m, cálculo sobre vectores 4h/D sin mutar active_tf ---
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('1m');
    # ~3 días de 1m (session-anchored 4h/D se llenan en add_candle)
    for my $day ( 0 .. 2 ) {
        for my $m ( 0 .. ( 24 * 60 - 1 ) ) {
            my $total = $day * 1440 + $m;
            my $h     = int( $total / 60 ) % 24;
            my $min   = $total % 60;
            my $c     = 100 + ( $total % 17 );
            $md->add_candle(
                [
                    sprintf( '2026-06-%02dT%02d:%02d:00-05:00', $day + 1, $h, $min ),
                    $c, $c + 3, $c - 3, $c + 1, 1,
                ]
            );
        }
    }
    ok( @{ $md->{data}{'4h'} || [] } > 4, '4h precargado vía add_candle' );
    ok( @{ $md->{data}{'D'}  || [] } > 1, 'D precargado vía add_candle' );

    $md->set_timeframe('15m');
    my $chart_end = $md->last_index();
    my $active_before = $md->{active_tf};

    my $ind4 = Market::Indicators::HLD->new();
    my $r4   = $ind4->compute(
        $md,
        source_tf       => '4h',
        chart_tf        => '15m',
        chart_end_index => $chart_end,
    );
    is( $md->{active_tf}, $active_before, 'MTF 4h no muta active_tf' );
    ok( $r4->{ok}, 'HLD 4h ok desde chart 15m' ) or diag explain $r4;
    ok( defined $r4->{resistance} && defined $r4->{support}, '4h R/S definidos' );

    my $indD = Market::Indicators::HLD->new();
    my $rD   = $indD->compute(
        $md,
        source_tf       => 'D',
        chart_tf        => '15m',
        chart_end_index => $chart_end,
    );
    is( $md->{active_tf}, '15m', 'MTF D no muta active_tf' );
    ok( $rD->{ok}, 'HLD D ok desde chart 15m' ) or diag explain $rD;

    # Overlay: chart W → chart_tf_too_high
    my $ovD = Market::Overlays::HLD->new(
        indicator => Market::Indicators::HLD->new(),
        source_tf => 'D',
        visible   => 1,
    );
    $md->set_timeframe('W');
    $ovD->compute_visible( $md, undef, 0, $md->last_index() );
    is( $ovD->{_result}{reason}, 'chart_tf_too_high', 'HLD D oculto en W' );

    # Chart D + HLD 4h → too high; HLD D → ok
    $md->set_timeframe('D');
    my $ov4 = Market::Overlays::HLD->new(
        indicator => Market::Indicators::HLD->new(),
        source_tf => '4h',
        visible   => 1,
    );
    $ov4->compute_visible( $md, undef, 0, $md->last_index() );
    is( $ov4->{_result}{reason}, 'chart_tf_too_high', 'HLD 4h oculto en D' );

    $ovD->compute_visible( $md, undef, 0, $md->last_index() );
    ok( $ovD->{_result}{ok}, 'HLD D ok en chart D' ) or diag explain $ovD->{_result};
}

# chart_tf_allowed helper
{
    my $ind = Market::Indicators::HLD->new();
    ok( $ind->chart_tf_allowed( '15m', '4h' ), '15m <= 4h' );
    ok( $ind->chart_tf_allowed( '4h',  '4h' ), '4h == 4h' );
    ok( !$ind->chart_tf_allowed( 'D', '4h' ),  'D > 4h' );
    ok( $ind->chart_tf_allowed( 'D', 'D' ),    'D == D' );
    ok( !$ind->chart_tf_allowed( 'W', 'D' ),   'W > D' );
}

done_testing();
