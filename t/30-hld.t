#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::MarketData;
use Market::Indicators::HLD;
use Market::Overlays::HLD;

sub _md_daily {
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('D');
    # 5 días sintéticos
    my @rows = (
        [ '2026-06-01T00:00:00-05:00', 100, 110, 95,  105, 1 ],  # 0
        [ '2026-06-02T00:00:00-05:00', 105, 115, 100, 112, 1 ],  # 1
        [ '2026-06-03T00:00:00-05:00', 112, 120, 108, 118, 1 ],  # 2
        [ '2026-06-04T00:00:00-05:00', 118, 125, 110, 122, 1 ],  # 3
        [ '2026-06-05T00:00:00-05:00', 122, 130, 120, 128, 1 ],  # 4 current
    );
    $md->add_candle($_) for @rows;
    $md->set_timeframe('D');
    return $md;
}

# Precio dentro del rango de vela más reciente pasada (día 3: 110-125, P=122)
{
    my $md  = _md_daily();
    my $ind = Market::Indicators::HLD->new();
    # end=4 close=128 is ATH-ish vs past max 125 → ath. Use end=3 price inside day2
    my $r = $ind->compute( $md, tf => 'D', end_index => 3, price => 114 );
    ok( $r->{ok}, 'ok con precio en rango' ) or diag explain $r;
    # day 3 is end; candidates 0..2; day2 108-120 contains 114 → anchor 2
    is( $r->{anchor_index}, 2, 'ancla = más reciente en rango (día 2)' );
    is( $r->{resistance}, 120, 'resistencia = high' );
    is( $r->{support},    108, 'soporte = low' );
}

# Sin vela en rango: elige mínima distancia OHLC
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('D');
    # past highs far below P except one open close to P
    $md->add_candle( [ 'd0', 100, 105, 99,  102, 1 ] );
    $md->add_candle( [ 'd1', 200, 205, 199, 202, 1 ] );  # open 200 near 201
    $md->add_candle( [ 'd2', 50,  55,  49,  52,  1 ] );
    $md->add_candle( [ 'd3', 90,  95,  88,  92,  1 ] );  # current P=201 via price opt
    $md->set_timeframe('D');
    my $ind = Market::Indicators::HLD->new();
    # P=201: not in any past range (d1 is 199-205 — wait that is in range)
    # Use P=150: no range contains; d0 max dist to 105=45, d1 to 199=49, d2 to 55=95
    my $r = $ind->compute( $md, tf => 'D', end_index => 3, price => 150 );
    ok( $r->{ok}, 'ok por distancia OHLC' ) or diag explain $r;
    is( $r->{anchor_index}, 0, 'd0 más cercana a 150 (high 105 dist 45)' );
}

# Empate distancia → más reciente
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('D');
    $md->add_candle( [ 'd0', 100, 100, 100, 100, 1 ] );  # dist to 50 = 50
    $md->add_candle( [ 'd1', 0,   0,   0,   0,   1 ] );  # dist 50
    $md->add_candle( [ 'd2', 200, 200, 200, 200, 1 ] );  # current
    $md->set_timeframe('D');
    my $ind = Market::Indicators::HLD->new();
    my $r = $ind->compute( $md, tf => 'D', end_index => 2, price => 50 );
    ok( $r->{ok}, 'ok empate' );
    is( $r->{anchor_index}, 1, 'empate: gana más reciente' );
}

# ATH
{
    my $md  = _md_daily();
    my $ind = Market::Indicators::HLD->new();
    my $r   = $ind->compute( $md, tf => 'D', end_index => 4, price => 130 );
    ok( !$r->{ok}, 'ATH no ok' );
    is( $r->{reason}, 'ath_no_ref', 'reason ath_no_ref' );
}

# wrong TF
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('15m');
    $md->add_candle( [ 't0', 1, 2, 0, 1, 1 ] );
    $md->add_candle( [ 't1', 1, 2, 0, 1, 1 ] );
    $md->set_timeframe('15m');
    my $ind = Market::Indicators::HLD->new();
    my $r   = $ind->compute( $md, tf => '15m', end_index => 1, price => 1 );
    ok( !$r->{ok}, '15m no ok' );
    is( $r->{reason}, 'wrong_tf', 'wrong_tf' );
}

# Overlay tag
{
    my $ind = Market::Indicators::HLD->new();
    my $ov  = Market::Overlays::HLD->new( indicator => $ind, visible => 1 );
    is( $ov->tag(), 'ov_hld', 'tag ov_hld' );
    ok( $ov->is_visible, 'visible' );
}

done_testing();
