#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::ChartEngine;
use Market::ReplayController;
use Market::Panels::Scales;
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel;
use Market::Overlays::Liquidity;
use Market::Indicators::Liquidity;

{
    package ReplayGeometryMD;
    sub new {
        my ($class, $n) = @_;
        my @data;
        for my $i (0 .. $n - 1) {
            my $minute = $i % 60;
            my $hour = int($i / 60) % 24;
            my $day = 1 + int($i / (60 * 24));
            my $base = 100 + $i;
            # El futuro contiene extremos deliberados: no deben llegar a autoescala.
            my $high = $i > 1000 ? 1_000_000 + $i : $base + 2;
            push @data, [
                sprintf('2026-04-%02dT%02d:%02d:00-05:00', $day, $hour, $minute),
                $base, $high, $base - 2, $base + 1, 100,
            ];
        }
        return bless { data => \@data, max_slice_end => -1, max_ts_index => -1 }, $class;
    }
    sub size { scalar @{ shift->{data} } }
    sub last_index { shift->size - 1 }
    sub get_candle { my ($s, $i) = @_; return $s->{data}->[$i] }
    sub get_slice {
        my ($s, $from, $to) = @_;
        $s->{max_slice_end} = $to if $to > $s->{max_slice_end};
        my @out;
        for my $i ($from .. $to) {
            push @out, ($i >= 0 && $i < $s->size) ? $s->{data}->[$i] : undef;
        }
        return \@out;
    }
    sub get_timestamp {
        my ($s, $i) = @_;
        $s->{max_ts_index} = $i if $i > $s->{max_ts_index};
        my $c = $s->get_candle($i);
        return $c ? $c->[0] : undef;
    }
}

{
    package ReplayGeometryIndicators;
    sub new { bless { max_end => -1 }, shift }
    sub slice_array {
        my ($s, $name, $from, $to) = @_;
        $s->{max_end} = $to if $to > $s->{max_end};
        return [ map { defined($_) && $_ >= 0 ? $_ / 100 : undef } ($from .. $to) ];
    }
}

{
    package ReplayGeometryCanvas;
    sub new { my ($class, $w, $h) = @_; bless { w => $w, h => $h, ops => [] }, $class }
    sub geometry { my ($s) = @_; return "$s->{w}x$s->{h}" }
    sub Width { shift->{w} }
    sub Height { shift->{h} }
    sub width { shift->{w} }
    sub height { shift->{h} }
    sub after { return }
    sub configure { return }
    sub delete { my ($s, @a) = @_; push @{ $s->{ops} }, [ delete => @a ]; return }
    sub lower { my ($s, @a) = @_; push @{ $s->{ops} }, [ lower => @a ]; return }
    sub raise { my ($s, @a) = @_; push @{ $s->{ops} }, [ raise => @a ]; return }
    sub createLine { my ($s, @a) = @_; push @{ $s->{ops} }, [ createLine => @a ]; return scalar @{ $s->{ops} } }
    sub createText { my ($s, @a) = @_; push @{ $s->{ops} }, [ createText => @a ]; return scalar @{ $s->{ops} } }
    sub createRectangle { my ($s, @a) = @_; push @{ $s->{ops} }, [ createRectangle => @a ]; return scalar @{ $s->{ops} } }
    sub createOval { my ($s, @a) = @_; push @{ $s->{ops} }, [ createOval => @a ]; return scalar @{ $s->{ops} } }
}

{
    package ReplayGeometryFeedIndicator;
    sub new { bless { reset_count => 0, seen => [] }, shift }
    sub reset { my ($s) = @_; $s->{reset_count}++; $s->{seen} = []; return }
    sub update_last { my ($s, $md, $i) = @_; push @{ $s->{seen} }, $i; return }
}

{
    package ReplayGeometryLiqIndicator;
    sub new { my ($class, $values) = @_; bless { values => $values }, $class }
    sub get_values { shift->{values} }
}

{
    package ReplayGeometryRunOrderChart;
    our @ISA = ('Market::ChartEngine');
    sub sync_overlay_indicators {
        my ($s) = @_;
        push @{ $s->{order} }, 'sync';
        $s->{semantic_state} = 'causal';
        return;
    }
    sub compute_run_candle_map {
        my ($s) = @_;
        push @{ $s->{order} }, 'map';
        return { 7 => 1 } if ($s->{semantic_state} // '') eq 'causal';
        return { 99 => 1 };
    }
}

{
    package ReplayGeometryCausalZigZag;
    sub new { bless { last_i => -1, reset_count => 0, compute_external => 0 }, shift }
    sub reset {
        my ($s) = @_;
        $s->{last_i} = -1;
        $s->{reset_count}++;
        return $s;
    }
    sub wants_external { 0 }
    sub set_compute_external { my ($s, $v) = @_; $s->{compute_external} = $v; return $s }
    sub update_last { my ($s, $md, $i) = @_; $s->{last_i} = $i; return $s }
    sub get_values {
        my ($s) = @_;
        my @log;
        # Pivote legítimo: ya estaba confirmado dentro del prefijo causal.
        push @log, { index => 800, side => 'low', open => 0 }
            if $s->{last_i} >= 900;
        # Su índice está antes del head 1000, pero solo se confirma al ver 1100.
        # Debe desaparecer cuando Replay rebobina desde 1499 hasta 1000.
        push @log, { index => 950, side => 'high', open => 0 }
            if $s->{last_i} >= 1100;
        return { external_pivot_log => \@log, external_segments => [] };
    }
}

my $md = ReplayGeometryMD->new(1500);
my $im = ReplayGeometryIndicators->new();
my $rc = Market::ReplayController->new(market_data => $md);
my $chart = bless {
    market_data       => $md,
    indicator_manager => $im,
    replay_controller => $rc,
    price_canvas      => ReplayGeometryCanvas->new(1000, 600),
    visible_bars      => 1000,
    offset            => 0,
    ctrl_zoom_x_shift => 0,
    follow_replay_head => 1,
}, 'Market::ChartEngine';

$rc->start(1000);
my ($start, $end) = $chart->compute_window();
is($end - $start + 1, 1000, 'Replay conserva 1000 slots logicos en zoom extremo');
is($chart->_causal_end(), 1000, 'tope causal es replay_idx');
is($end, 1200, '20% derecho son 200 slots logicos vacios');
is($start, 201, 'inicio logico compensa los slots vacios sin trasladar el canvas');
is($chart->{ctrl_zoom_x_shift}, 0, 'Replay no usa un shift permanente de -20%');

my $scale = Market::Panels::Scales->new(bars => 1000, right_margin => 0);
$scale->{width} = 1000;
$scale->{x_shift} = 0;
my $head_local = 1000 - $start;
my $head_right = $scale->index_to_center_x($head_local) + 0.5;
ok(abs($head_right - 800) < 0.001, 'ultima vela termina exactamente al 80% del plot');

# Este es el camino denso (bar_w=1 < 2): la misma escala que usa grid/overlay
# asigna el ultimo pixel con datos al head y deja vacio el 20% derecho.
my ($head_px_from, $head_px_to) = $scale->local_range_for_pixel(799);
is_deeply([$head_px_from, $head_px_to], [$head_local, $head_local],
          'pixel 799 corresponde al mismo slot del replay head');
my ($blank_from, $blank_to) = $scale->local_range_for_pixel(800);
ok($blank_from > $head_local && $blank_to > $head_local,
   'pixel 800 ya pertenece al hueco derecho, no a una vela futura');

my $ohlc = $chart->_causal_slice('OHLC', $start, $end);
is(scalar(@$ohlc), 1000, 'slice causal mantiene el ancho logico con undef');
ok(defined $ohlc->[$head_local], 'replay head esta presente en su slot exacto');
ok(!defined $ohlc->[$head_local + 1], 'primer slot posterior al head esta vacio');
ok(!defined $ohlc->[-1], 'ultimo slot del viewport esta vacio');
is($md->{max_slice_end}, 1000, 'OHLC nunca solicita indices posteriores a replay_idx');

my $atr = $chart->_causal_slice('ATR', $start, $end);
ok(defined $atr->[$head_local], 'ATR conserva valor del replay head');
ok(!defined $atr->[$head_local + 1], 'ATR deja vacio el futuro');
is($im->{max_end}, 1000, 'ATR nunca solicita indices posteriores a replay_idx');

my $timestamps = $chart->get_all_timestamps();
ok(@$timestamps > 0, 'eje temporal se puede construir en Replay');
is($md->{max_ts_index}, 1000, 'grid temporal no consulta timestamps reales futuros');
my @real_future = grep { !$_->{synthetic} && $_->{index} > 1000 } @$timestamps;
is(scalar(@real_future), 0, 'no hay timestamps reales posteriores al head');
my @synthetic_gap = grep { $_->{synthetic} && $_->{index} > 1000 } @$timestamps;
ok(@synthetic_gap > 0, 'el calendario del hueco se deriva sinteticamente del TF');

# El mismo global index produce la misma X para cualquier overlay que use Scales.
my $overlay_x = $scale->index_to_center_x(1000 - $start);
my $candle_x  = $scale->index_to_center_x($head_local);
is($overlay_x, $candle_x, 'vela, grid y overlay comparten la misma X del head');

# Liquidity no debe arrastrar al borde un label cuyo segmento esta fuera de vista.
is(Market::Overlays::Liquidity->clamp_label_x(-200, -20, 1000), undef,
   'Liquidity oculta label de segmento completamente fuera del viewport');
my $visible_label_x = Market::Overlays::Liquidity->clamp_label_x(-20, 100, 1000);
ok(defined $visible_label_x && $visible_label_x >= 2 && $visible_label_x <= 100,
   'Liquidity etiqueta solo la porcion realmente visible del segmento');

# Autoescala causal: los highs extremos posteriores a replay_idx no entran.
my $price_panel = Market::Panels::PricePanel->new(theme => {});
my ($auto_min, $auto_max) = $price_panel->get_y_range($ohlc);
ok($auto_max < 100_000, 'autoescala Y ignora extremos de velas futuras');

# Render denso real (bar_w=1): PricePanel y ATR deben dejar vacio x>=800.
my $price_canvas = ReplayGeometryCanvas->new(1000, 300);
my $dense_price_scale = Market::Panels::Scales->new(
    min_y => $auto_min, max_y => $auto_max, bars => 1000, right_margin => 0,
);
$dense_price_scale->{width} = 1000;
$dense_price_scale->{height} = 300;
$dense_price_scale->{slice_base_index} = $start;
$dense_price_scale->{visible_count} = 1000;
$dense_price_scale->{replay_max_index} = 1000;
$price_panel->render($price_canvas, $ohlc, $dense_price_scale);
my @candle_lines = grep {
    $_->[0] eq 'createLine' && grep { defined $_ && $_ eq 'candle' } @$_
} @{ $price_canvas->{ops} };
ok(@candle_lines > 0, 'PricePanel ejecuta el camino denso real');
my $max_candle_x = 0;
for my $op (@candle_lines) {
    $max_candle_x = $op->[1] if defined $op->[1] && $op->[1] > $max_candle_x;
}
ok($max_candle_x < 800.1, 'PricePanel denso no pinta velas dentro del hueco derecho');

my $atr_canvas = ReplayGeometryCanvas->new(1000, 120);
my $atr_panel = Market::Panels::ATRPanel->new(theme => {});
my $dense_atr_scale = Market::Panels::Scales->new(
    min_y => 0, max_y => 20, bars => 1000, right_margin => 0,
);
$dense_atr_scale->{width} = 1000;
$dense_atr_scale->{height} = 120;
$dense_atr_scale->{slice_base_index} = $start;
$dense_atr_scale->{visible_count} = 1000;
$dense_atr_scale->{replay_max_index} = 1000;
$atr_panel->render($atr_canvas, $atr, $dense_atr_scale);
my ($atr_line) = grep {
    $_->[0] eq 'createLine' && grep { defined $_ && $_ eq 'atr_line' } @$_
} @{ $atr_canvas->{ops} };
ok($atr_line, 'ATRPanel ejecuta el camino denso real');
if ($atr_line) {
    my @coords;
    for (my $i = 1; $i < @$atr_line; $i++) {
        last if defined $atr_line->[$i] && $atr_line->[$i] eq '-fill';
        push @coords, $atr_line->[$i];
    }
    my @xs = map { $coords[$_] } grep { $_ % 2 == 0 } 0 .. $#coords;
    my $max_atr_x = 0;
    for my $x (@xs) {
        $max_atr_x = $x if defined $x && $x > $max_atr_x;
    }
    ok($max_atr_x < 800.1, 'ATRPanel denso no pinta puntos dentro del hueco derecho');
}

# Rebobinado causal: un indicador alimentado al futuro debe resetearse ANTES del
# early-return y quedar exactamente en replay_idx.
my $feed_ind = ReplayGeometryFeedIndicator->new();
$chart->{_rewind_test_fed_up_to} = 1499;
my $rewind_done = $chart->_feed_indicator_chunk(
    $feed_ind, '_rewind_test_fed_up_to', 1000, 2000,
);
ok($rewind_done, 'rebobinado completa el feed causal en un chunk');
is($feed_ind->{reset_count}, 1, 'rebobinado resetea estado previamente calculado con futuro');
is($chart->{_rewind_test_fed_up_to}, 1000, 'cursor del indicador termina en replay_idx');
is($feed_ind->{seen}->[0], 0, 'rebobinado realimenta desde el inicio');
is($feed_ind->{seen}->[-1], 1000, 'rebobinado no realimenta mas alla de replay_idx');

# Liquidity debe reconstruir también su historial de pivotes. Un pivote cuyo
# índice era <= head pero que solo se confirmó mirando barras futuras no puede
# sobrevivir al rewind.
my $causal_zz = ReplayGeometryCausalZigZag->new();
my $causal_liq = Market::Indicators::Liquidity->new(k => 3);
$chart->{zigzag_indicator} = $causal_zz;
$chart->{liq_indicator} = $causal_liq;
$chart->{_zigzag_fed_up_to} = -1;
$chart->{_liq_fed_up_to} = -1;
$chart->{_smc_fed_up_to} = -1;
$chart->{_smc_pro_fed_up_to} = -1;
$chart->{smc_pro_indicator} = undef;
$chart->_sync_liquidity_feed(1499);
is($causal_liq->pivot_history_count(), 2,
   'Liquidity absorbe ambos pivotes cuando el prefijo futuro los confirma');
ok(exists $causal_liq->{_pivot_history}{'950:high'},
   'precondicion: historial contiene pivote confirmado usando futuro');
$chart->_sync_liquidity_feed(1000);
is($causal_liq->pivot_history_count(), 1,
   'rewind reconstruye historial Liquidity solo con confirmaciones causales');
ok(exists $causal_liq->{_pivot_history}{'800:low'},
   'rewind conserva pivote ya confirmado dentro del prefijo causal');
ok(!exists $causal_liq->{_pivot_history}{'950:high'},
   'rewind elimina pivote cuyo indice ocultaba confirmacion futura');
is($chart->{_liq_fed_up_to}, 1000,
   'Liquidity se realimenta exactamente hasta replay_idx tras reconstruir');

# El estado semántico que recolorea velas RUN se prepara en orden causal antes
# de que PricePanel lo consuma en el primer frame tras un rewind.
my $run_order_chart = bless {
    overlay_manager => 1,
    semantic_state  => 'future',
    order           => [],
}, 'ReplayGeometryRunOrderChart';
my $prepared_run_map = $run_order_chart->_prepare_run_candle_map_for_frame();
is_deeply($run_order_chart->{order}, ['sync', 'map'],
          'frame sincroniza indicadores antes de calcular mapa RUN');
is_deeply($prepared_run_map, { 7 => 1 },
          'mapa RUN del frame proviene del estado causal sincronizado');

# Captura de escala manual en Replay: ignora caches heredados del chart live y
# nunca solicita OHLC/ATR dentro de los slots lógicos posteriores al head.
$chart->{follow_replay_head} = 1;
$chart->{visible_bars} = 1000;
$chart->{offset} = 0;
$chart->{price_panel} = Market::Panels::PricePanel->new(theme => {});
$chart->{atr_panel} = Market::Panels::ATRPanel->new(theme => {});
$chart->{last_auto_min_y} = -9_000_000;
$chart->{last_auto_max_y} = 9_000_000;
$chart->{manual_min_y} = -8_000_000;
$chart->{manual_max_y} = 8_000_000;
$chart->{last_auto_atr_min_y} = -900;
$chart->{last_auto_atr_max_y} = 900;
$chart->{atr_manual_min_y} = -800;
$chart->{atr_manual_max_y} = 800;
$md->{max_slice_end} = -1;
$im->{max_end} = -1;
my ($captured_price_min, $captured_price_max) = $chart->_capture_price_y_range();
my ($captured_atr_min, $captured_atr_max) = $chart->_capture_atr_y_range();
ok($captured_price_max < 100_000 && $captured_price_min > -100_000,
   'escala manual Replay ignora cache live y extremos OHLC futuros');
is($md->{max_slice_end}, 1000,
   'captura manual de precio no consulta OHLC posterior a replay_idx');
ok($captured_atr_max < 100 && $captured_atr_min > -100,
   'escala manual ATR ignora cache live y valores futuros');
is($im->{max_end}, 1000,
   'captura manual ATR no consulta indices posteriores a replay_idx');

# En vista Replay paneada detrás del head, end+1 se conserva como overscan si
# todavía es causal. La misma regla lo clampa al head cerca del límite causal.
$chart->{follow_replay_head} = 0;
$chart->{visible_bars} = 200;
$chart->{offset} = 50;
my ($pan_start, $pan_end) = $chart->compute_window();
is($pan_end, 950, 'vista manual queda detrás del replay head');
my ($draw_start, $draw_end) = $chart->_compute_draw_window($pan_start, $pan_end);
is_deeply([$draw_start, $draw_end], [$pan_start - 1, $pan_end + 1],
          'Replay conserva overscan derecho cuando end+1 sigue siendo causal');
my (undef, $near_head_draw_end) = $chart->_compute_draw_window(802, 1001);
is($near_head_draw_end, 1000, 'overscan Replay nunca sobrepasa replay_idx');

my $pan_draw = $chart->_causal_slice('OHLC', $draw_start, $draw_end);
my $pan_canvas = ReplayGeometryCanvas->new(1000, 300);
my $pan_panel = Market::Panels::PricePanel->new(theme => {});
my $pan_scale = Market::Panels::Scales->new(
    min_y => 800, max_y => 1100, bars => 200, right_margin => 0,
);
$pan_scale->{width} = 1000;
$pan_scale->{height} = 300;
$pan_scale->{x_shift} = -4;
$pan_scale->{draw_start_offset} = $draw_start - $pan_start;
$pan_scale->{visible_count} = 200;
$pan_scale->{slice_base_index} = $draw_start;
$pan_scale->{replay_max_index} = 1000;
$pan_panel->render($pan_canvas, $pan_draw, $pan_scale);
my @pan_wicks = grep {
    $_->[0] eq 'createLine' && grep { defined $_ && $_ eq 'candle' } @$_
} @{ $pan_canvas->{ops} };
my ($overscan_wick) = grep {
    defined $_->[1] && $_->[1] > 995 && $_->[1] < 1000
} @pan_wicks;
ok($overscan_wick,
   'PricePanel pinta la vela causal end+1 parcialmente visible por x_shift');

# Ctrl+zoom manual en el limite nunca deja un x_shift de varias barras.
$chart->{follow_replay_head} = 0;
$chart->{visible_bars} = 200;
$chart->{offset} = -20;
$chart->{ctrl_zoom_x_shift} = 0;
$chart->_ctrl_horizontal_zoom(100, 999);
my $zoom_bar_w = 1000 / $chart->{visible_bars};
ok(abs($chart->{ctrl_zoom_x_shift}) < $zoom_bar_w + 1e-9,
   'Ctrl+zoom normaliza x_shift a residuo menor que una barra');

# MAX_LEVEL_LABELS limita textos, no lineas de niveles.
my @many_levels = map {
    +{ kind => ($_ % 2 ? 'BSL' : 'SSL'), state => 'detected',
       price => 100 + $_ * 2, pivot_index => $_ + 1 }
} 0 .. 29;
my $liq_ind = ReplayGeometryLiqIndicator->new({ levels => \@many_levels, events => [] });
my $liq_overlay = Market::Overlays::Liquidity->new(
    indicator => $liq_ind, visible => 1, elements => { HISTORY => 1 },
);
$liq_overlay->{_feed_end} = 99;
$liq_overlay->compute_visible(undef, $liq_ind, 0, 99);
my $liq_canvas = ReplayGeometryCanvas->new(1000, 400);
my $liq_scale = Market::Panels::Scales->new(min_y => 90, max_y => 170, bars => 100);
$liq_scale->{width} = 1000;
$liq_scale->{height} = 400;
$liq_overlay->draw($liq_canvas, $liq_scale);
my @level_lines = grep {
    my $op = $_;
    $op->[0] eq 'createLine' && grep {
        (ref($_) eq 'ARRAY' && grep { defined $_ && $_ eq 'ov_liq' } @$_)
          || (!ref($_) && defined $_ && $_ eq 'ov_liq')
    } @$op
} @{ $liq_canvas->{ops} };
my @level_texts = grep {
    my $op = $_;
    $op->[0] eq 'createText' && grep {
        (ref($_) eq 'ARRAY' && grep { defined $_ && $_ eq 'liq_lbl' } @$_)
          || (!ref($_) && defined $_ && $_ eq 'liq_lbl')
    } @$op
} @{ $liq_canvas->{ops} };
is(scalar(@level_lines), 30, 'Liquidity conserva todas las lineas visibles');
ok(scalar(@level_texts) <= 24, 'Liquidity limita solo la cantidad de labels');

done_testing;
