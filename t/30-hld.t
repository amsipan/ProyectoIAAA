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
    # end=10; bar 9,8,7 (age 1,2,3) y bar 5 (age 5) contienen 100
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

# 4h: solo ages 1–3 en rango → OHLC/fallback (puede ser más atrás o relajar)
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('4h');
    for my $i ( 0 .. 6 ) {
        my ( $h, $l ) = ( $i >= 4 && $i <= 5 ) ? ( 110, 90 ) : ( 50, 40 );
        # end=6; age1=5, age2=4 contienen; age>=4 max_i=2 no tiene en rango
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
            visible   => 1
          )->tag(),
        'ov_hld',
        'tag'
    );
}

done_testing();
