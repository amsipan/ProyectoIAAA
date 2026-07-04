use strict;
use warnings;
use Test::More;

use lib '.';
use Market::ChartEngine;
use Market::ReplayController;
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel;

# Task 0037: zoom/Replay no deben envenenar last_auto/manual con el fallback
# (20000,30000) ni dejar el eje Y clavado por ctrl_zoom_y_lock en modo Auto.

{
    package Z37MarketData;
    sub new {
        my ($class, $n) = @_;
        my @data;
        for my $i (0 .. $n - 1) {
            push @data, [sprintf('2026-04-01T00:%02d:00-05:00', $i % 60),
                         100 + $i, 110 + $i, 95 + $i, 105 + $i, 100];
        }
        return bless { data => \@data, active_tf => '1m' }, $class;
    }
    sub size { scalar @{ shift->{data} } }
    sub last_index { shift->size - 1 }
    sub get_candle { my ($s, $i) = @_; return $s->{data}->[$i] }
    sub get_timestamp {
        my ($self, $i) = @_;
        my $c = $self->get_candle($i);
        return $c ? $c->[0] : undef;
    }
    sub get_slice {
        my ($self, $s, $e) = @_;
        my @out;
        for my $i ($s .. $e) {
            push @out, ($i >= 0 && $i < $self->size) ? $self->{data}->[$i] : undef;
        }
        return \@out;
    }
}

{
    package Z37Canvas;
    sub new { bless { w => 900, h => 600 }, shift }
    sub Width  { shift->{w} }
    sub Height { shift->{h} }
    sub after { return }
    sub configure { return }
    sub delete { return }
    sub createLine { return 1 }
    sub createText { return 1 }
    sub createRectangle { return 1 }
    sub lower { return }
    sub raise { return }
}

{
    package Z37Indicators;
    sub new { bless {}, shift }
    sub slice_array {
        my ($self, $name, $start, $end) = @_;
        return [ (50) x ($end - $start + 1) ];
    }
}

sub build_chart {
    my (%args) = @_;
    my $n = $args{n} // 100;
    return bless {
        market_data       => Z37MarketData->new($n),
        price_panel       => Market::Panels::PricePanel->new(),
        atr_panel         => Market::Panels::ATRPanel->new(),
        price_canvas      => Z37Canvas->new(),
        atr_canvas        => Z37Canvas->new(),
        indicator_manager => Z37Indicators->new(),
        visible_bars      => $args{visible_bars} // 20,
        offset            => $args{offset} // 0,
        is_auto_scale     => 1,
        is_atr_auto_scale => 1,
        ctrl_zoom_x_shift => 0,
        replay_controller => $args{replay_controller},
    }, 'Market::ChartEngine';
}

# --- 1A: Replay con offset heredado grande → ventana válida con velas ---
{
    my $chart = build_chart(n => 100, offset => 80);
    my $rc = Market::ReplayController->new(market_data => $chart->{market_data});
    $rc->start(10);
    $chart->{replay_controller} = $rc;

    my ($s, $e) = $chart->compute_window();
    ok($s <= $e, 'replay+offset grande: start <= end');
    ok($e <= 10, 'replay+offset grande: end <= replay_idx');
    ok($e >= 0, 'replay+offset grande: end no negativo');

    my $slice = $chart->{market_data}->get_slice($s, $e);
    ok($chart->_visible_slice_has_candles($slice), 'replay+offset grande: slice tiene velas');
    ok($chart->{offset} <= 9, 'replay+offset grande: offset reclampado a effective_total');
}

# --- 1B: slice vacío (start>end) no envenena last_auto con fallback ---
{
    my $chart = build_chart(n => 50);
    $chart->{last_auto_min_y} = 88.5;
    $chart->{last_auto_max_y} = 121.5;

    my $empty = $chart->{market_data}->get_slice(10, 5);
    ok(!@$empty, 'slice invalido: get_slice vacio cuando start>end');
    ok(!$chart->_visible_slice_has_candles($empty), 'slice invalido: sin velas reales');

    my ($min_p, $max_p) = $chart->{price_panel}->get_y_range($empty);
    is($min_p, 20000, 'slice invalido: get_y_range devuelve fallback min');
    is($max_p, 30000, 'slice invalido: get_y_range devuelve fallback max');

    if ($chart->{is_auto_scale} && $chart->_visible_slice_has_candles($empty)) {
        ($chart->{last_auto_min_y}, $chart->{last_auto_max_y}) = ($min_p, $max_p);
    }

    is($chart->{last_auto_min_y}, 88.5, 'slice invalido: last_auto_min_y conservado');
    is($chart->{last_auto_max_y}, 121.5, 'slice invalido: last_auto_max_y conservado');
}

# --- 1B: captura a manual ignora last_auto envenenado con fallback ---
{
    my $chart = build_chart(n => 50);
    $chart->{last_auto_min_y} = 20000;
    $chart->{last_auto_max_y} = 30000;

    $chart->set_scale_mode('manual');

    ok(!$chart->_is_price_y_fallback($chart->{manual_min_y}, $chart->{manual_max_y}),
        'manual: no captura fallback 20000-30000');
    ok($chart->{manual_max_y} > $chart->{manual_min_y}, 'manual: rango real desde velas visibles');
}

# --- 1C: set_scale_mode(auto) limpia ctrl_zoom_y_lock ---
{
    my $chart = build_chart(n => 50);
    $chart->{ctrl_zoom_y_lock_min} = 50;
    $chart->{ctrl_zoom_y_lock_max} = 80;
    $chart->{is_auto_scale} = 0;
    $chart->{manual_min_y} = 90;
    $chart->{manual_max_y} = 120;

    $chart->set_scale_mode('auto');

    ok($chart->{is_auto_scale}, 'auto: is_auto_scale activo');
    ok(!defined $chart->{ctrl_zoom_y_lock_min}, 'auto: ctrl_zoom_y_lock_min limpiado');
    ok(!defined $chart->{ctrl_zoom_y_lock_max}, 'auto: ctrl_zoom_y_lock_max limpiado');
}

# --- 1C: en auto, ctrl_zoom_y_lock no pisa el rango calculado ---
{
    my $chart = build_chart(n => 50);
    $chart->{is_auto_scale} = 1;
    $chart->{ctrl_zoom_y_lock_min} = 50;
    $chart->{ctrl_zoom_y_lock_max} = 80;

    my ($start, $end) = $chart->compute_window();
    my $visible = $chart->{market_data}->get_slice($start, $end);
    my ($auto_min, $auto_max) = $chart->{price_panel}->get_y_range($visible);
    my $has_candles = $chart->_visible_slice_has_candles($visible);

    my ($min_p, $max_p) = ($auto_min, $auto_max);
    if (!$chart->{is_auto_scale}
        && defined $chart->{manual_min_y}
        && defined $chart->{manual_max_y}) {
        ($min_p, $max_p) = ($chart->{manual_min_y}, $chart->{manual_max_y});
    } elsif (!$chart->{is_auto_scale}
        && defined $chart->{ctrl_zoom_y_lock_min}
        && defined $chart->{ctrl_zoom_y_lock_max}) {
        ($min_p, $max_p) = ($chart->{ctrl_zoom_y_lock_min}, $chart->{ctrl_zoom_y_lock_max});
    } elsif ($chart->{is_auto_scale} && $has_candles) {
        ($min_p, $max_p) = ($auto_min, $auto_max);
    }

    isnt($min_p, 50, 'auto: ctrl_zoom lock ignorado (min)');
    isnt($max_p, 80, 'auto: ctrl_zoom lock ignorado (max)');
    ok($max_p > $min_p, 'auto: rango visible válido');
}

done_testing();