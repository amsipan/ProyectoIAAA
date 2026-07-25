#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::MarketData;
use Market::Indicators::ATR;
use Market::IndicatorManager;
use Market::ChartEngine;

# Canvas minimo: after() ejecuta al tiro (simula background en tests).
{
    package AtrCacheCanvas;
    sub new { bless { after_n => 0 }, shift }
    sub after {
        my ( $self, $ms, $cb ) = @_;
        $self->{after_n}++;
        $cb->() if ref($cb) eq 'CODE';
        return;
    }
    sub delete { return }
    sub configure { return }
    sub Width  { 800 }
    sub Height { 400 }
}

sub build_md {
    my $md = Market::MarketData->new();
    for my $i ( 0 .. 119 ) {
        my $c   = 100 + ( $i % 10 );
        my $min = $i % 60;
        my $hr  = int( $i / 60 );
        $md->add_candle(
            [
                sprintf( '2026-04-06T%02d:%02d:00-05:00', $hr, $min ),
                $c, $c + 2, $c - 2, $c + 1, 10,
            ]
        );
    }
    $md->build_timeframes( eager => 1 );
    return $md;
}

# ---------------------------------------------------------------------------
# 1. ATR update_ohlc == update_last; export/import conserva serie
# ---------------------------------------------------------------------------
{
    my $md = build_md();
    $md->set_timeframe('1m');
    my $a = Market::Indicators::ATR->new(14);
    my $b = Market::Indicators::ATR->new(14);
    for my $i ( 0 .. $md->size - 1 ) {
        $a->update_last( $md, $i );
        my $c = $md->get_candle($i);
        $b->update_ohlc( $c->[2], $c->[3], $c->[4] );
    }
    is_deeply( $b->get_values(), $a->get_values(), 'update_ohlc coincide con update_last' );

    my $st = $a->export_state();
    my $c  = Market::Indicators::ATR->new(14);
    $c->import_state($st);
    is_deeply( $c->get_values(), $a->get_values(), 'import_state restaura ATR' );
}

# ---------------------------------------------------------------------------
# 2. ChartEngine: primer TF construye cache; segundo switch es hit O(1)
# ---------------------------------------------------------------------------
{
    my $md = build_md();
    $md->set_timeframe('1m');
    my $im = Market::IndicatorManager->new();
    my $atr = Market::Indicators::ATR->new(14);
    for my $i ( 0 .. $md->size - 1 ) {
        $atr->update_last( $md, $i );
    }
    $im->register( 'ATR', $atr );

    my $canvas = AtrCacheCanvas->new();
    my $chart  = bless {
        market_data         => $md,
        indicator_manager   => $im,
        price_canvas        => $canvas,
        atr_canvas          => $canvas,
        replay_controller   => undef,
        overlay_manager     => undef,
        _atr_cache          => {},
        _atr_job_id         => 0,
        _atr_chunk          => 40,
        render_pending      => 0,
        visible_bars        => 60,
        offset              => 0,
    }, 'Market::ChartEngine';

    # Evitar render Tk completo
    no warnings 'redefine';
    local *Market::ChartEngine::request_render = sub {
        my ($self) = @_;
        $self->{render_pending} = 0;
        return $self;
    };
    local *Market::ChartEngine::reset_view = sub {
        my ($self) = @_;
        $self->{visible_bars} = 60;
        $self->{offset}       = 0;
        return $self;
    };
    local *Market::ChartEngine::_sync_fibonacci_levels_for_timeframe = sub { };
    local *Market::ChartEngine::_clear_ctrl_zoom_state = sub { };
    local *Market::ChartEngine::clear_replay_select_state = sub { };

    $chart->_atr_seed_cache_from_live();
    ok( $chart->{_atr_cache}{'1m'}, 'seed cachea ATR del TF base' );

    # 5m: miss -> schedule (after sync en canvas fake) -> cache
    my $t0 = time;
    $chart->set_timeframe('5m');
    my $elapsed = time - $t0;
    ok( $chart->{_atr_cache}{'5m'}, 'tras set_timeframe(5m) queda cache ATR' );
    is( scalar @{ $im->get('ATR') || [] },
        scalar @{ $md->{data}{'5m'} },
        'ATR live alineado al size 5m' );

    # Volver a 1m: hit, sin vaciar
    my $vals_1m = [ @{ $chart->{_atr_cache}{'1m'}{values} } ];
    $chart->set_timeframe('1m');
    is_deeply( $im->get('ATR'), $vals_1m, 'vuelta a 1m restaura cache al instante' );
    cmp_ok( $elapsed, '<=', 2, 'set_timeframe no bloquea segundos (smoke)' );
}

done_testing();
