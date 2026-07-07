use strict;
use warnings;
use Test::More;

use lib '.';
use Market::ChartEngine;
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel;
# Task 0035: modo Manual de escala (Precio/ATR) captura el rango visible al activarse
# y no deja que ctrl_zoom_y_lock pise el rango manual.

{
    package ScaleTestMarketData;
    sub new {
        my ($class, $n) = @_;
        my @data;
        for my $i (0 .. $n - 1) {
            push @data, [sprintf('2026-04-01T00:%02d:00-05:00', $i % 60),
                         100 + $i, 110 + $i, 95 + $i, 105 + $i, 100];
        }
        return bless { data => \@data }, $class;
    }
    sub size { scalar @{ shift->{data} } }
    sub get_candle { my ($s, $i) = @_; return $s->{data}->[$i] }
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
    package ScaleTestCanvas;
    sub new { bless {}, shift }
    sub after { return }
}

sub build_chart {
    my ($n) = @_;
    $n //= 50;

    my $md = ScaleTestMarketData->new($n);

    return bless {
        market_data       => $md,
        price_panel       => Market::Panels::PricePanel->new(),
        atr_panel         => Market::Panels::ATRPanel->new(),
        price_canvas      => ScaleTestCanvas->new(),
        visible_bars      => 20,
        offset            => 0,
        is_auto_scale     => 1,
        is_atr_auto_scale => 1,
        show_grid         => 1,
    }, 'Market::ChartEngine';
}

# --- Precio: captura desde last_auto al pasar a manual ---
{
    my $chart = build_chart(50);
    $chart->{last_auto_min_y} = 88.5;
    $chart->{last_auto_max_y} = 121.5;

    $chart->set_scale_mode('manual');

    ok(!$chart->{is_auto_scale}, 'precio: is_auto_scale=0 tras manual');
    is($chart->{manual_min_y}, 88.5, 'precio: manual_min_y capturado desde last_auto');
    is($chart->{manual_max_y}, 121.5, 'precio: manual_max_y capturado desde last_auto');
    ok(!defined $chart->{ctrl_zoom_y_lock_min}, 'precio: ctrl_zoom_y_lock_min limpiado');
    ok(!defined $chart->{ctrl_zoom_y_lock_max}, 'precio: ctrl_zoom_y_lock_max limpiado');
}

# --- Precio: captura desde velas visibles si no hay last_auto ---
{
    my $chart = build_chart(50);
    $chart->set_scale_mode('manual');

    ok(!$chart->{is_auto_scale}, 'precio sin last_auto: modo manual activo');
    ok(defined $chart->{manual_min_y}, 'precio sin last_auto: manual_min_y definido');
    ok(defined $chart->{manual_max_y}, 'precio sin last_auto: manual_max_y definido');
    ok($chart->{manual_max_y} > $chart->{manual_min_y}, 'precio sin last_auto: rango valido');

    my ($exp_min, $exp_max) = $chart->_compute_visible_price_y_range();
    is($chart->{manual_min_y}, $exp_min, 'precio sin last_auto: coincide con rango visible');
    is($chart->{manual_max_y}, $exp_max, 'precio sin last_auto: max coincide con rango visible');
}

# --- Precio: manual tiene prioridad sobre ctrl_zoom_y_lock en render ---
{
    my $chart = build_chart(50);
    $chart->{is_auto_scale}     = 0;
    $chart->{manual_min_y}      = 90;
    $chart->{manual_max_y}      = 120;
    $chart->{ctrl_zoom_y_lock_min} = 50;
    $chart->{ctrl_zoom_y_lock_max} = 80;

    my $visible = $chart->{market_data}->get_slice(30, 49);
    my ($auto_min, $auto_max) = $chart->{price_panel}->get_y_range($visible);

    my ($min_p, $max_p);
    if (!$chart->{is_auto_scale}
        && defined $chart->{manual_min_y}
        && defined $chart->{manual_max_y}) {
        ($min_p, $max_p) = ($chart->{manual_min_y}, $chart->{manual_max_y});
    } elsif (defined $chart->{ctrl_zoom_y_lock_min}
        && defined $chart->{ctrl_zoom_y_lock_max}) {
        ($min_p, $max_p) = ($chart->{ctrl_zoom_y_lock_min}, $chart->{ctrl_zoom_y_lock_max});
    } else {
        ($min_p, $max_p) = ($auto_min, $auto_max);
    }

    is($min_p, 90,  'render logic: manual min gana sobre ctrl_zoom lock');
    is($max_p, 120, 'render logic: manual max gana sobre ctrl_zoom lock');
}

# --- ATR: captura desde last_auto al pasar a manual ---
{
    my $chart = build_chart(50);
    $chart->{last_auto_atr_min_y} = 1.5;
    $chart->{last_auto_atr_max_y} = 9.5;

    $chart->set_atr_scale_mode('manual');

    ok(!$chart->{is_atr_auto_scale}, 'atr: is_atr_auto_scale=0 tras manual');
    is($chart->{atr_manual_min_y}, 1.5, 'atr: min capturado desde last_auto');
    is($chart->{atr_manual_max_y}, 9.5, 'atr: max capturado desde last_auto');
}

# --- Auto restaura autoescala (limpia manual) ---
{
    my $chart = build_chart(50);
    $chart->{manual_min_y} = 90;
    $chart->{manual_max_y} = 120;
    $chart->{is_auto_scale} = 0;

    $chart->{ctrl_zoom_y_lock_min} = 50;
    $chart->{ctrl_zoom_y_lock_max} = 80;

    $chart->set_scale_mode('auto');

    ok($chart->{is_auto_scale}, 'auto: is_auto_scale=1');
    ok(!defined $chart->{manual_min_y}, 'auto: manual_min_y limpiado');
    ok(!defined $chart->{manual_max_y}, 'auto: manual_max_y limpiado');
    ok(!defined $chart->{ctrl_zoom_y_lock_min}, 'auto: ctrl_zoom_y_lock_min limpiado');
    ok(!defined $chart->{ctrl_zoom_y_lock_max}, 'auto: ctrl_zoom_y_lock_max limpiado');
}

# --- Grid: toggle mostrar/ocultar el grid de fondo ---
{
    my $chart = build_chart(50);
    is($chart->show_grid(), 1, 'grid: visible por defecto');

    my $r = $chart->set_show_grid(0);
    is($r, 0, 'grid: set_show_grid(0) retorna 0');
    is($chart->{show_grid}, 0, 'grid: show_grid=0 tras ocultar');

    my $t = $chart->toggle_grid();
    is($t, 1, 'grid: toggle_grid vuelve a 1');
    is($chart->show_grid(), 1, 'grid: show_grid=1 tras toggle');
}

done_testing();