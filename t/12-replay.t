use strict;
use warnings;
use Test::More;

use lib '.';
use Market::ChartEngine;
use Market::MarketData;
use Market::ReplayController;
use Market::Debug::IndicatorSnapshot;

# --- TestMarketData: dataset sintético con timestamps 1m ---
{
    package TestMarketData;
    sub new {
        my ($class, $n) = @_;
        my @data;
        for my $i (0 .. $n - 1) {
            my $h = int($i / 60);
            my $m = $i % 60;
            push @data, [sprintf('2026-04-01T%02d:%02d:00-05:00', $h, $m),
                         100 + $i, 101 + $i, 99 + $i, 100 + $i, 100];
        }
        return bless { data => \@data, active_tf => '1m' }, $class;
    }
    sub size { my ($self) = @_; return scalar @{ $self->{data} }; }
    sub last_index { shift->size - 1 }
    sub get_candle { my ($self, $i) = @_; return $self->{data}->[$i]; }
    sub get_timestamp { my ($self, $i) = @_; my $r = $self->get_candle($i); return $r ? $r->[0] : undef; }
    sub get_slice {
        my ($self, $s, $e) = @_;
        my @out;
        for my $i ($s .. $e) {
            push @out, ($i >= 0 && $i < $self->size) ? $self->{data}->[$i] : undef;
        }
        return \@out;
    }
}

# --- TestCanvas mínimo (sin Tk real) ---
{
    package TestCanvas;
    sub new { bless { w => 900, h => 600, ops => [] }, shift }
    sub geometry { '900x600' }
    sub Width { 900 }
    sub Height { 600 }
    sub after { return; }
    sub configure { return; }
    sub delete { return; }
}

# Helper: construir un ChartEngine con dataset de $n velas.
sub build_chart {
    my ($n) = @_;
    $n //= 100;
    my $md = TestMarketData->new($n);
    return bless {
        market_data       => $md,
        price_canvas      => TestCanvas->new(),
        visible_bars      => 20,
        offset            => 0,
        ctrl_zoom_x_shift => 0,
    }, 'Market::ChartEngine';
}

# ===========================================================================
# Test 1: compute_window jamás devuelve end > replay_idx cuando Replay activo.
# ===========================================================================
my $chart = build_chart(100);
my $rc = Market::ReplayController->new(market_data => $chart->{market_data});
$chart->{replay_controller} = $rc;

# Sin replay: end = 99 (última vela)
my ($s, $e) = $chart->compute_window();
is($e, 99, 'sin replay, end = last_index = 99');

# Con replay en idx 50: end no debe pasar de 50
$rc->start(50);
($s, $e) = $chart->compute_window();
ok($e <= 50, 'con replay_idx=50, compute_window end <= 50');

# Con replay en idx 10
$rc->start(10);
($s, $e) = $chart->compute_window();
ok($e <= 10, 'con replay_idx=10, compute_window end <= 10');

# Con replay en idx 0 (primera vela)
$rc->start(0);
($s, $e) = $chart->compute_window();
ok($e <= 0, 'con replay_idx=0, compute_window end <= 0');

# ===========================================================================
# Test 2: step_forward / step_backward mueven exactamente 1; clamp en extremos.
# ===========================================================================
$rc->start(50);
is($rc->current_index(), 50, 'replay inicia en idx 50');

$rc->step_forward();
is($rc->current_index(), 51, 'step_forward avanza exactamente 1');

$rc->step_backward();
is($rc->current_index(), 50, 'step_backward retrocede exactamente 1');

# Clamp al final (idx 99)
$rc->start(99);
$rc->step_forward();
is($rc->current_index(), 99, 'step_forward en último idx clampa a 99');

# En modo playing, llegar al último índice debe pausar el replay para no dejar
# un after-loop re-renderizando el último frame congelado.
$rc->start(98);
$rc->{playing} = 1;
$rc->step_forward();
is($rc->current_index(), 99, 'step_forward llega al último idx');
ok(!$rc->{playing}, 'step_forward pausa automaticamente al llegar al final');

# Clamp al inicio (idx 0)
$rc->start(0);
$rc->step_backward();
is($rc->current_index(), 0, 'step_backward en idx 0 clampa a 0');

# ===========================================================================
# Test 3: exit restaura tope = last_index.
# ===========================================================================
$rc->start(50);
ok($rc->is_active(), 'replay activo tras start');
$rc->exit();
ok(!$rc->is_active(), 'replay inactivo tras exit');
is($rc->current_index(), undef, 'current_index undef tras exit');

# compute_window debe volver a usar el dataset completo
($s, $e) = $chart->compute_window();
is($e, 99, 'tras exit, compute_window end = last_index = 99');

# ===========================================================================
# Test 4: replay_violations del IndicatorSnapshot detecta items con index > k.
# Esto prueba que el guard está disponible para cuando overlays/indicadores
# se integren en tasks 0008/0012.
# ===========================================================================
my $D = 'Market::Debug::IndicatorSnapshot';
my @items = (
    { index => 5,  type => 'HH', price => 101.50 },
    { index => 10, type => 'HL', price => 100.25 },
    { index => 15, type => 'BOS', dir => 'up', price => 102.00 },
    { index => 20, type => 'LH', price => 101.00 },
    { index => 30, type => 'LL', price => 99.50 },
);

# Con replay_idx=15, los items con index 20 y 30 violan el tope.
my @bad = $D->replay_violations(\@items, 15);
is(scalar(@bad), 2, 'replay_violations detecta 2 items con index > 15');
is_deeply([sort { $a <=> $b} map { $_->{index} } @bad], [20, 30],
          'violaciones en indices 20 y 30');

# Con replay_idx=100, no hay violaciones.
is(scalar($D->replay_violations(\@items, 100)), 0,
   'sin violaciones si replay_idx >= max index');

# ===========================================================================
# Test 5: fast_forward avanza N velas y clamp al final.
# ===========================================================================
$rc->start(10);
$rc->fast_forward(5);
is($rc->current_index(), 15, 'fast_forward(5) desde idx 10 => idx 15');

$rc->start(95);
$rc->fast_forward(10);
is($rc->current_index(), 99, 'fast_forward más allá del final clampa a 99');

# ===========================================================================
# Test 6: start clampa replay_idx a [0, last_index].
# ===========================================================================
$rc->start(-5);
is($rc->current_index(), 0, 'start(-5) clampa a 0');

$rc->start(200);
is($rc->current_index(), 99, 'start(200) clampa a last_index=99');

# ===========================================================================
# Test 7: task 0040 — frame_replay_view_at evita ventana inválida con offset heredado.
# ===========================================================================
$rc->exit();
$chart->{offset} = 80;
$chart->frame_replay_view_at(10);
$rc->start(10);
($s, $e) = $chart->compute_window();
ok($s <= $e, 'frame+start: ventana válida tras offset heredado grande');
is($chart->{offset}, 0, 'frame_replay_view_at: offset=0');
ok($e <= 10, 'frame+start: end <= replay_idx');

# ===========================================================================
# Test 8: task 0040-A — clear_replay_select_state limpia marcador/selección.
# ===========================================================================
$chart->set_selected_bar(50);
$chart->set_replay_select_mode(1);
$chart->clear_replay_select_state();
ok(!defined $chart->selected_bar(), 'clear_replay_select_state: sin selected_bar');
ok(!$chart->is_replay_select_mode(), 'clear_replay_select_state: modo OFF');

# ===========================================================================
# Test 9: task 0041 — speed_options devuelve los 9 multiplicadores con ms correctos.
# ===========================================================================
my @opts = Market::ReplayController::speed_options();
is(scalar(@opts), 9, 'speed_options: 9 entradas');
is_deeply(
    \@opts,
    [
        { label => '10x',  ms => 100 },
        { label => '7x',   ms => 143 },
        { label => '5x',   ms => 200 },
        { label => '3x',   ms => 333 },
        { label => '1x',   ms => 1000 },
        { label => '0.5x', ms => 2000 },
        { label => '0.3x', ms => 3000 },
        { label => '0.2x', ms => 5000 },
        { label => '0.1x', ms => 10000 },
    ],
    'speed_options: tabla TradingView exacta',
);

# ===========================================================================
# Test 10: task 0041 — tick_ms según etiqueta; default 1x = 1000 ms.
# ===========================================================================
my $rc2 = Market::ReplayController->new(market_data => $chart->{market_data});
is($rc2->tick_ms(), 1000, 'tick_ms default 1x = 1000');
$rc2->set_speed_label('5x');
is($rc2->tick_ms(), 200, 'set_speed_label(5x) => tick_ms 200');
$rc2->set_speed_label('0.1x');
is($rc2->tick_ms(), 10000, 'set_speed_label(0.1x) => tick_ms 10000');

# ===========================================================================
# Test 11: task 0041 — set_speed numérico sigue afectando fast_forward (retrocompat).
# ===========================================================================
$rc2->start(10);
$rc2->set_speed(2);
$rc2->fast_forward();    # default 10 * speed = 20
is($rc2->current_index(), 30, 'set_speed(2): fast_forward default avanza 20 velas');

# ===========================================================================
# Test 12: task 0041 — replay_interval + advance_one_tick.
# ===========================================================================
$rc2->start(10);
$rc2->set_replay_interval(3);
$rc2->advance_one_tick();
is($rc2->current_index(), 13, 'advance_one_tick con intervalo 3 avanza 3 velas');

# Al llegar al tope, advance_one_tick pausa (playing=0) igual que step_forward.
$rc2->start(97);
$rc2->{playing} = 1;
$rc2->set_replay_interval(5);
$rc2->advance_one_tick();
is($rc2->current_index(), 99, 'advance_one_tick clampa al último índice');
ok(!$rc2->{playing}, 'advance_one_tick pausa al llegar al final');

done_testing();
