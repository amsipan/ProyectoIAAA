#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::MarketData;
use Market::Indicators::HLD;
use Market::Overlays::HLD;

# Contrato del cache/mapeos binarios de HLD bajo Play: resultados idénticos a
# compute fresco por tick (sin cache), sin fuga de futuro tras rewind.

sub build_md {
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('1m');
    for my $day ( 0 .. 3 ) {
        for my $m ( 0 .. 1439 ) {
            my $total = $day * 1440 + $m;
            my $h     = int( $total / 60 ) % 24;
            my $min   = $total % 60;
            my $c     = 100 + ( $total % 29 );
            $md->add_candle(
                [
                    sprintf( '2026-06-%02dT%02d:%02d:00-05:00', $day + 1, $h, $min ),
                    $c, $c + 4, $c - 4, $c + 1, 1,
                ]
            );
        }
    }
    $md->build_timeframes();
    $md->set_timeframe('1m');
    return $md;
}

my $md = build_md();
my $n  = $md->size();
ok( @{ $md->{data}{'4h'} } > 10, '4h precargado' );
ok( @{ $md->{data}{'D'} } >= 3,  'D precargado' );
my $from = int( $n * 0.5 );

# Play simulado: indicador reusado (cache) vs fresco por tick, 4h y D
{
    my $ind4 = Market::Indicators::HLD->new();
    my $indD = Market::Indicators::HLD->new();
    my ( $bad, $first_bad ) = ( 0, undef );
    for my $e ( $from .. $from + 239 ) {
        for my $stf ( '4h', 'D' ) {
            my $ind = $stf eq '4h' ? $ind4 : $indD;
            my $rc  = $ind->compute( $md, source_tf => $stf, chart_tf => '1m', chart_end_index => $e );
            my $rf  = Market::Indicators::HLD->new()->compute( $md, source_tf => $stf, chart_tf => '1m', chart_end_index => $e );
            if ( !is_deeply( $rc, $rf ) ) { $bad++; $first_bad //= "$stf\@$e"; }
        }
    }
    is( $bad, 0, 'Play 240 ticks x2 capas: cache == fresco' )
      or diag "primer mismatch: $first_bad";
    ok( defined $ind4->{_ath_max}{'4h'}{max}, 'cache ATH 4h poblado tras Play' );
    ok( defined $indD->{_ath_max}{'D'}{max}, 'cache ATH D poblado tras Play' );
}

# Rewind: retroceder el tope recomputa ATH y no arrastra futuro
{
    my $ind = Market::Indicators::HLD->new();
    $ind->compute( $md, source_tf => '4h', chart_tf => '1m', chart_end_index => $from + 200 );
    my $upto_hi = $ind->{_ath_max}{'4h'}{upto};
    my $e0 = $from - 500;
    my $rc = $ind->compute( $md, source_tf => '4h', chart_tf => '1m', chart_end_index => $e0 );
    my $rf = Market::Indicators::HLD->new()->compute( $md, source_tf => '4h', chart_tf => '1m', chart_end_index => $e0 );
    is_deeply( $rc, $rf, 'rewind: resultado == fresco (sin fuga)' );
    ok( $ind->{_ath_max}{'4h'}{upto} < $upto_hi, 'rewind: cache ATH recomputado hacia atrás' );
}

# Mapeo chart→fuente: mismo resultado que el helper binario de MarketData
{
    my $ind = Market::Indicators::HLD->new();
    for my $e ( 1000, 2345, $from, $n - 1 ) {
        my $bi = $md->base_index_at( '1m', $e );
        for my $stf ( '4h', 'D' ) {
            my $expect = $md->index_for_base_index( $stf, $bi );
            # Sin vela fuente cerrada aún: fallback por ts → bucket en formación
            $expect = 0 if $expect < 0;
            is( $ind->map_chart_index_to_source( $md, '1m', $e, $stf ),
                $expect, "c2s $stf \@$e" );
        }
    }
}

# Mapeo fuente→chart: invariante lower_bound sobre ts del bucket
{
    my $ind = Market::Indicators::HLD->new();
    my $s4  = $md->{data}{'4h'};
    my $c1  = $md->{data}{'1m'};
    for my $si ( 1, int( @$s4 / 2 ), $#$s4 ) {
        my $ci = $ind->map_source_index_to_chart( $md, '4h', $si, '1m' );
        my $ts = $s4->[$si][0];
        ok( $c1->[$ci][0] ge $ts, "s2c \@$si: chart ts >= bucket ts" );
        ok( $ci == 0 || $c1->[ $ci - 1 ][0] lt $ts, "s2c \@$si: vela anterior < bucket ts" );
    }
}

# ATH: dispara con precio sobre max_high; reset limpia el cache
{
    my $ind = Market::Indicators::HLD->new();
    my $r   = $ind->compute( $md, source_tf => '4h', chart_tf => '1m', chart_end_index => $n - 1, price => 1e9 );
    is( $r->{reason}, 'ath_no_ref', 'ATH: P sobre max_high → ath_no_ref' );
    ok( defined $ind->{_ath_max}{'4h'}{max}, 'ATH cache poblado' );
    $ind->reset();
    is_deeply( $ind->{_ath_max}, {}, 'reset limpia cache ATH' );
}

# Ruta real del overlay en Play: compute_visible con _feed_end == fresco
{
    my $ov = Market::Overlays::HLD->new(
        indicator => Market::Indicators::HLD->new(),
        source_tf => '4h', visible => 1,
    );
    my $bad = 0;
    for my $e ( $from .. $from + 59 ) {
        $ov->{_feed_end} = $e;
        $ov->compute_visible( $md, undef, 0, $e );
        my $rf = Market::Indicators::HLD->new()->compute( $md, source_tf => '4h', chart_tf => '1m', chart_end_index => $e );
        $bad++ if !is_deeply( $ov->{_result}, $rf );
    }
    is( $bad, 0, 'overlay compute_visible (cache) == fresco en 60 ticks' );
}

# Desborde (P bajo de todo el historial, caso 16-jul del profesor): consistente
{
    my $ind = Market::Indicators::HLD->new();
    my $bad = 0;
    for my $e ( $from .. $from + 59 ) {
        my $rc = $ind->compute( $md, source_tf => '4h', chart_tf => '1m', chart_end_index => $e, price => 1 );
        my $rf = Market::Indicators::HLD->new()->compute( $md, source_tf => '4h', chart_tf => '1m', chart_end_index => $e, price => 1 );
        $bad++ if !is_deeply( $rc, $rf );
    }
    is( $bad, 0, 'desborde (P bajo de todo): cache == fresco' );
}

done_testing();
