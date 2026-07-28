#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::MarketData;
use Market::Indicators::PivotPointsHL;
use Market::ML::ExtractFantasmaDataset;

# Test mínimo del extractor Opción A (sin Tk, sin Market/Debug nuevos).

sub build_md_with_moves {
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('1m');
    # Serie larga para length=3: pico, valle, y varias extensiones que mueven el fantasma.
    my @closes = (
        100, 101, 102, 103, 104, 110,           # pico @5
        104, 103, 102, 101, 98, 96, 90,        # valle @12
        95, 100, 105, 108, 110, 112, 114,      # sube
        113, 111, 109, 107, 105, 100, 95,      # baja
        96, 98, 100, 102, 104, 106, 108,       # sube
        107, 105, 103, 101, 99, 97, 95,        # baja
    );
    for my $i ( 0 .. $#closes ) {
        my $c = $closes[$i];
        my $h = $c + 2;
        my $l = $c - 2;
        my $ts = sprintf( '2026-04-01T00:%02d:00-05:00', $i % 60 );
        # Evitar colisión de bucket: usar minutos lineales vía día sintético
        $ts = sprintf(
            '2026-04-01T%02d:%02d:00-05:00',
            int( $i / 60 ),
            $i % 60,
        );
        $md->add_candle( [ $ts, $c, $h, $l, $c, 100 + $i ] );
    }
    $md->build_timeframes();
    $md->set_timeframe('1m');
    return $md;
}

{
    my $md  = build_md_with_moves();
    my $res = Market::ML::ExtractFantasmaDataset->extract(
        market_data  => $md,
        feature_pack => 'core',
        length       => 3,
    );
    ok( $res && $res->{rows}, 'extract core devuelve rows' );
    my $n = scalar @{ $res->{rows} };
    ok( $n >= 1, "al menos 1 muestra Opción A (got $n)" );

    my $r = $res->{rows}[0];
    for my $k (qw(meta_contract meta_event_bar meta_feature_bar meta_time y3 y5 y10 y15 atr_1m vol_1m)) {
        ok( exists $r->{$k}, "columna $k presente" );
    }
    is( $r->{meta_contract}, 'A', 'contrato A' );
    ok( $r->{meta_feature_bar} == $r->{meta_event_bar} + 1, 'feature_bar = event_bar+1' );

    for my $h ( 3, 5, 10, 15 ) {
        my $y = $r->{"y$h"};
        ok( defined $y && $y =~ /^\d+$/, "y$h es conteo no-negativo" );
        ok( $y <= $h, "y$h <= horizonte $h" );
    }

    # Labels causales: yH solo cuenta trails con created_at en (eb, eb+H]
    my $pph = Market::Indicators::PivotPointsHL->new( length => 3 );
    my @created;
    my $prev_n = 0;
    for my $i ( 0 .. $md->size - 1 ) {
        $pph->update_last( $md, $i );
        my $ntr = scalar @{ $pph->get_values->{trails} || [] };
        while ( $prev_n < $ntr ) {
            push @created, $i;
            $prev_n++;
        }
    }
    my $eb = $r->{meta_event_bar};
    my $expect3 = 0;
    for my $t (@created) {
        $expect3++ if $t > $eb && $t <= $eb + 3;
    }
    is( $r->{y3}, $expect3, 'y3 coincide con conteo Opción A de trails futuros' );

    # time no está como feature de train (solo meta_*)
    my @trainish = grep { $_ !~ /^meta_/ && $_ !~ /^y\d+$/ } @{ $res->{columns} };
    ok( !grep { $_ eq 'time' || $_ eq 'meta_time' } @trainish,
        'time crudo no está en columnas de features' );
}

{
    # PIP helper
    is( Market::ML::ExtractFantasmaDataset->pip_size, 0.25, 'PIP NQ = 0.25' );
    is(
        Market::ML::ExtractFantasmaDataset->_pips( 100, 100.5 ),
        2,
        'distancia 0.5 pts = 2 pips'
    );
}

done_testing();
