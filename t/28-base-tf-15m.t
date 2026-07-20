#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';
use Market::MarketData;

# --- base 15m: carga nativa y agregación a 1h+ ---
{
    my $md = Market::MarketData->new();
    $md->set_base_timeframe('15m');
    is($md->base_timeframe(), '15m', 'base_tf = 15m');
    is($md->{active_tf}, '15m', 'active_tf arranca en base');

    # 8 velas 15m (2 horas exactas de sesión ficticia)
    my @rows = (
        ['2026-06-01T10:00:00-05:00', 100, 101, 99,  100.5, 1],
        ['2026-06-01T10:15:00-05:00', 100.5, 102, 100, 101, 1],
        ['2026-06-01T10:30:00-05:00', 101, 103, 100.5, 102, 1],
        ['2026-06-01T10:45:00-05:00', 102, 104, 101, 103, 1],
        ['2026-06-01T11:00:00-05:00', 103, 105, 102, 104, 1],
        ['2026-06-01T11:15:00-05:00', 104, 106, 103, 105, 1],
        ['2026-06-01T11:30:00-05:00', 105, 107, 104, 106, 1],
        ['2026-06-01T11:45:00-05:00', 106, 108, 105, 107, 1],
    );
    $md->add_candle($_) for @rows;

    $md->set_timeframe('15m');
    is($md->size(), 8, '15m nativo: 8 velas');
    is($md->get_candle(0)->[0], '2026-06-01T10:00:00-05:00', 'primera vela 15m');

    # TF más fino que la base → vacío, sin crash
    $md->set_timeframe('1m');
    is($md->size(), 0, '1m vacío con base 15m');
    $md->set_timeframe('5m');
    is($md->size(), 0, '5m vacío con base 15m');

    # Volver a 15m
    $md->set_timeframe('15m');
    is($md->size(), 8, 'vuelve a 15m');

    # 1h agregado desde 15m
    $md->set_timeframe('1h');
    ok($md->size() >= 1, '1h tiene al menos 1 barra desde base 15m');
    my $c0 = $md->get_candle(0);
    ok(defined $c0 && $c0->[2] >= $c0->[3], '1h OHLC coherente');

    $md->set_timeframe('2h');
    ok($md->size() >= 1, '2h tiene barras');
}

# --- base 1m: retrocompat (comportamiento histórico) ---
{
    my $md = Market::MarketData->new();
    is($md->base_timeframe(), '1m', 'default base 1m');
    for my $i (0 .. 29) {
        my $m = sprintf('%02d', $i);
        $md->add_candle(["2026-06-01T10:$m:00-05:00", 100+$i, 101+$i, 99+$i, 100.5+$i, 1]);
    }
    $md->set_timeframe('1m');
    is($md->size(), 30, '1m: 30 velas');
    $md->set_timeframe('15m');
    is($md->size(), 2, '15m agregado desde 1m: 2 barras (0-14 y 15-29)');
}

done_testing();
