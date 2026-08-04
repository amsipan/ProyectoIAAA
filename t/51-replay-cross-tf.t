# t/51-replay-cross-tf.t — Replay cross-TF con paridad TradingView: al cambiar
# de temporalidad con Replay activo se preserva el instante EXACTO vía
# base_index y el head puede quedar como vela en formación (agregada solo
# hasta ese instante, sin fuga de futuro).
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

{
    package FakeIM;
    sub new { bless {}, shift }
    sub slice_array { my ($s, $name, $a, $b) = @_; return [ map { $_ } ($a .. $b) ]; }
}

sub build_chart {
    my ($md) = @_;
    my $chart = bless {
        market_data       => $md,
        indicator_manager => FakeIM->new(),
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
is($md->index_for_base_index('15m', 14), 0, 'bi 14 -> última cerrada 15m idx 0');
is($md->index_for_base_index('15m', 28), 0, 'bi 28 -> última cerrada 15m idx 0');
is($md->index_of_bucket_containing('15m', 14), 0, 'bi 14 -> contenedor 15m idx 0 (cerrado)');
is($md->index_of_bucket_containing('15m', 15), 1, 'bi 15 -> contenedor 15m idx 1 (abierto)');
is($md->index_of_bucket_containing('D', 30), 0, 'bi 30 -> contenedor D idx 0 (abierto)');
is($md->base_last_index(), 4319, 'base_last_index = última vela 1m');

# partial_candle: agrega la base solo hasta el instante.
{
    my $pc = $md->partial_candle('15m', 100, 1500);
    is_deeply([@$pc[1 .. 6]], [1600, 1601, 1599, 1600, 10, 1500],
              'partial_candle 15m[100]@1500 = solo la vela base 1500');
    my $full = $md->{data}{'15m'}[100];
    is($full->[2], 1615, 'la vela 15m[100] almacenada sí tiene el high completo (1615)');
    my $closed = $md->partial_candle('15m', 99, 1500);
    is($closed->[6], 1499, 'partial_candle de bucket ya cerrado devuelve la vela completa');
}

# 1m -> 15m con Play activo: instante exacto + vela en formación.
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
    is($rc->current_base_index(), $I, '1m->15m: instante EXACTO preservado (1500)');
    is($rc->current_index(), 100, '1m->15m: idx = bucket contenedor 15m (cierra 1514)');
    ok($rc->head_is_partial(), '1m->15m: head parcial (bucket abierto)');
    is($rc->closed_index(), 99, '1m->15m: feeds de indicadores hasta la última cerrada (99)');
    is($chart->{replay_view_end}, 100, 'ancla de vista remapeada al bucket contenedor');
    is($chart->{visible_bars}, 20, 'zoom conservado (visible_bars intacto)');

    my ($ws, $we) = $chart->compute_window();
    is($we, 100, 'vista anclada al bucket en formación');

    # El slice OHLC dibuja la vela 100 como parcial (no el high completo del bucket).
    my $slice = $chart->_causal_slice('OHLC', 90, 105);
    is($slice->[10][2], 1601, 'slice OHLC: high del head = 1601 (parcial), no 1615');
    is($slice->[10][6], 1500, 'slice OHLC: head [6] = instante exacto');
    my $beyond = 0;
    for my $k (0 .. $#$slice) {
        $beyond++ if $slice->[$k] && (90 + $k) > $rc->current_index();
    }
    is($beyond, 0, 'sin velas futuras: nada dibujado por encima del bucket contenedor');

    # ATR se trunca en la última vela cerrada (la vela en formación no tiene ATR).
    my $atr = $chart->_causal_slice('ATR', 95, 105);
    is($atr->[4], 99, 'ATR: último valor definido en la cerrada 99');
    ok(!defined $atr->[5], 'ATR: bucket en formación sin ATR (undef)');

    # Play: el primer paso COMPLETA el bucket en formación (no salta al siguiente).
    $rc->step_forward();
    is($rc->current_base_index(), 1514, 'step completa el bucket: instante = cierre 1514');
    is($rc->current_index(), 100, 'step completa el bucket: mismo idx 100');
    ok(!$rc->head_is_partial(), 'bucket completado: head ya no es parcial');
    is($rc->closed_index(), 100, 'bucket completado: feeds llegan a 100');

    $rc->step_forward();
    is($rc->current_base_index(), 1529, 'step siguiente abre el bucket siguiente (1529)');
    is($rc->current_index(), 101, 'idx avanza a 101');

    ($ws, $we) = $chart->compute_window();
    ok($we >= 101, 'auto-scroll deja el head visible tras avanzar');

    $rc->step_backward();
    is($rc->current_base_index(), 1514, 'step back vuelve al cierre anterior (1514)');
    is($rc->current_index(), 100, 'step back: idx 100');

    # Vuelta a 1m: el instante exacto se conserva (sin redondeo de bucket).
    $chart->set_timeframe('1m');
    ok($rc->is_active(), '15m->1m: Replay sobrevive la vuelta');
    is($rc->current_index(), 1514, '15m->1m: head en el instante base exacto (1514)');
    ok(!$rc->head_is_partial(), '15m->1m: sin parcial en la serie base');
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
    my $exp = $md->index_of_bucket_containing('1h', 1500);
    is($rc->current_index(), $exp, '1m->1h: idx = bucket contenedor');
    is($chart->{replay_view_end}, $exp + $trail, 'trail conservado en el TF nuevo');
    is($rc->current_base_index(), 1500, '1m->1h: instante exacto preservado');
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
    is($rc->current_index(), $md->index_of_bucket_containing('5m', 1500),
       'callback TF: idx = bucket contenedor vía base_index');
}

# Borde: instante dentro del primer bucket del TF destino (sin vela cerrada).
{
    $md->set_timeframe('1m');
    my $chart = build_chart($md);
    my $rc = $chart->{replay_controller};
    $rc->start(30);   # 08:30 del día 1: el primer bucket D aún no cierra
    $chart->set_timeframe('D');
    ok($rc->is_active(), 'borde: Replay activo aunque no haya vela D cerrada');
    is($rc->current_index(), 0, 'borde: head en el bucket D[0] en formación');
    ok($rc->head_is_partial(), 'borde: head parcial en D[0]');
    is($rc->closed_index(), -1, 'borde: sin cerrada para feeds (closed_index -1)');
    $rc->step_forward();
    is($rc->current_base_index(), $md->{data}{'D'}[0][6],
       'borde: step completa el primer bucket D');
    ok(!$rc->head_is_partial(), 'borde: D[0] completado');
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

# ReplayController con market_data sin los helpers nuevos: modo legacy intacto.
{
    my $dumb = bless {}, 'DumbMD';
    my $rcd = Market::ReplayController->new(market_data => $dumb);
    $rcd->{active} = 1;
    $rcd->{replay_idx} = 3;
    ok(!defined $rcd->current_base_index(), 'md sin base_index_at -> current_base_index undef');
    ok(!defined $rcd->seek_base_index(10), 'md sin helpers -> seek_base_index undef');
    ok(!$rcd->head_is_partial(), 'modo legacy: nunca parcial');
    is($rcd->closed_index(), 3, 'modo legacy: closed_index = replay_idx');
}

done_testing();
