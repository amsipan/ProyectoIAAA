# t/51-replay-cross-tf.t — Replay cross-TF: al cambiar de temporalidad con
# Replay activo, el instante causal se preserva vía base_index (paridad TV).
use strict;
use warnings;
use Test::More;
use Time::Moment;

use lib '.';
use Market::ChartEngine;
use Market::MarketData;
use Market::ReplayController;
use Market::UI::Callbacks;

# Dataset 1m continuo de 3 días (2026-07-13 08:00 + 4320 min, UTC-5).
sub build_md {
    my ($n) = @_;
    my $md = Market::MarketData->new();
    my $tm = Time::Moment->from_string('2026-07-13T08:00:00-05:00');
    for my $i (0 .. $n - 1) {
        my $p = 100 + $i;
        $md->add_candle([$tm->to_string, $p, $p + 1, $p - 1, $p, 10]);
        $tm = $tm->plus_minutes(1);
    }
    return $md;
}

{
    package TestCanvas;
    sub new { bless {}, shift }
    sub geometry { '900x600' }
    sub Width { 900 }
    sub Height { 600 }
    sub after { return; }   # no ejecuta: request_render no dispara render real
    sub configure { return; }
    sub delete { return; }
}

sub build_chart {
    my ($md) = @_;
    my $chart = bless {
        market_data       => $md,
        price_canvas      => TestCanvas->new(),
        visible_bars      => 20,
        offset            => 0,
        ctrl_zoom_x_shift => 0,
    }, 'Market::ChartEngine';
    $chart->{replay_controller} = Market::ReplayController->new(market_data => $md);
    return $chart;
}

my $md = build_md(3 * 1440);

# Helpers de MarketData sobre el índice compartido.
is($md->base_index_at('1m', 7), 7, 'base_index_at en serie base = propio índice');
is($md->base_index_at('15m', 0), 14, 'bucket 15m[0] cierra en base 14');
is($md->index_for_base_index('15m', 14), 0, 'bi 14 -> 15m idx 0');
is($md->index_for_base_index('15m', 28), 0, 'bi 28 -> 15m idx 0 (bucket 1 aún abierto)');
is($md->index_for_base_index('15m', 29), 1, 'bi 29 -> 15m idx 1');
ok($md->index_for_base_index('D', 30) < 0, 'sin vela D cerrada al inicio -> -1');
is($md->index_for_base_index('D', 539), 0, 'bi 539 -> D idx 0 (primer día de trading)');

# 1m -> 15m con Play activo: preserva instante y sigue.
{
    $md->set_timeframe('1m');
    my $chart = build_chart($md);
    my $rc = $chart->{replay_controller};
    my $I = 1500;   # 2026-07-14 09:00
    $rc->start($I);
    $rc->{playing} = 1;
    $chart->frame_replay_view_at($I);
    is($rc->current_base_index(), $I, 'head base_index en serie base');

    $chart->set_timeframe('15m');
    ok($rc->is_active(), '1m->15m: Replay sobrevive al cambio de TF');
    ok($rc->{playing}, '1m->15m: Play no se detiene');
    # 15m: bucket k cubre base [15k..15k+14]; último cerrado con [6] <= 1500 es 99.
    is($rc->current_index(), 99, '1m->15m: idx = última vela 15m cerrada (bi 1499)');
    is($md->{data}{'15m'}[99][6], 1499, '15m[99] cierra en base 1499');
    is($chart->{replay_view_end}, 99, 'ancla de vista remapeada (sin trail)');
    is($chart->{visible_bars}, 20, 'zoom conservado (visible_bars intacto)');
    is($md->{active_tf}, '15m', 'active_tf cambiado a 15m');

    my ($ws, $we) = $chart->compute_window();   # render inicial tras el cambio
    is($we, 99, 'vista anclada al head remapeado');
    $rc->advance_one_tick();
    is($rc->current_index(), 100, 'Play avanza en el TF nuevo');
    is($md->{data}{'15m'}[100][6], 1514, 'siguiente vela 15m cierra en base 1514');
    ($ws, $we) = $chart->compute_window();
    ok($we >= 100, 'auto-scroll deja el head visible tras avanzar');

    my $slice = $chart->_causal_slice('OHLC', $ws, $we);
    my $beyond = 0;
    for my $k (0 .. $#$slice) {
        $beyond++ if $slice->[$k] && ($ws + $k) > $rc->current_index();
    }
    is($beyond, 0, 'sin velas futuras: nada dibujado por encima del head');

    $chart->set_timeframe('1m');
    ok($rc->is_active(), '15m->1m: Replay sobrevive la vuelta');
    # Semántica vela-atómica: el instante se conserva con granularidad de vela
    # cerrada (1500 -> 1499 al pasar a 15m; el avance lo llevó a 1514).
    is($rc->current_index(), 1514, '15m->1m: head en el mismo instante base (1514)');
}

# Trail del encuadre Select Bar se conserva en el TF nuevo.
{
    $md->set_timeframe('1m');
    my $chart = build_chart($md);
    my $rc = $chart->{replay_controller};
    $rc->start(1500);
    $chart->frame_replay_view_at(1500, { anchor => 1 });
    my $trail = $chart->{replay_view_end} - 1500;
    ok($trail > 0, 'trail de anclaje Select Bar > 0');

    $chart->set_timeframe('1h');
    my $exp = $md->index_for_base_index('1h', 1500);
    is($rc->current_index(), $exp, '1m->1h: idx = último bucket cerrado');
    is($chart->{replay_view_end}, $exp + $trail, 'trail conservado en el TF nuevo');
}

# Callback de TF (wiring real): con Replay activo no hay limpieza de sesión.
{
    $md->set_timeframe('1m');
    my $chart = build_chart($md);
    my $rc = $chart->{replay_controller};
    my $replay_on = 1;
    my $active = '1m';
    my %vars = ( replay_on => \$replay_on, active_tf => \$active );

    $rc->start(1500);
    $rc->{playing} = 1;
    $chart->frame_replay_view_at(1500);
    Market::UI::Callbacks->make_tf_callback($chart, '5m', \%vars)->();

    ok($rc->is_active(), 'callback TF: Replay sigue activo');
    ok($rc->{playing}, 'callback TF: Play no se detiene');
    is($replay_on, 1, 'callback TF: replay_on se mantiene en 1');
    is($active, '5m', 'callback TF: active_tf sincronizado');
    is($rc->current_index(), $md->index_for_base_index('5m', 1500),
       'callback TF: idx remapeado vía base_index');
}

# Borde: instante dentro del primer bucket del TF destino (sin vela cerrada).
{
    $md->set_timeframe('1m');
    my $chart = build_chart($md);
    my $rc = $chart->{replay_controller};
    $rc->start(30);   # 08:30 del día 1: el primer bucket D aún no cierra
    $chart->set_timeframe('D');
    ok($rc->is_active(), 'borde: Replay activo aunque no haya vela D cerrada');
    is($rc->current_index(), 0, 'borde: sin bucket cerrado -> idx 0 (regla v1)');
}

# Sin Replay activo: comportamiento clásico intacto (reset de vista).
{
    $md->set_timeframe('1m');
    my $chart = build_chart($md);
    my $rc = $chart->{replay_controller};
    $chart->set_timeframe('5m');
    ok(!$rc->is_active(), 'sin Replay: set_timeframe no activa sesión');
    is($chart->{visible_bars}, 60, 'sin Replay: reset_view clásico (visible_bars=60)');
}

# ReplayController con market_data sin los helpers nuevos: undef sin morir.
{
    my $dumb = bless {}, 'DumbMD';
    my $rcd = Market::ReplayController->new(market_data => $dumb);
    $rcd->{active} = 1;
    $rcd->{replay_idx} = 3;
    ok(!defined $rcd->current_base_index(), 'md sin base_index_at -> undef');
    ok(!defined $rcd->seek_base_index(10), 'md sin index_for_base_index -> undef');
}

done_testing();
