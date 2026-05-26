package Market::ChartEngine;
use strict;
use warnings;

use Time::Moment;
use Market::Panels::Scales;
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel; 

sub new {
    my ($class, %args) = @_;

    my $self = {
        market_data      => $args{market_data},      
        indicator_manager=> $args{indicator_manager},
        price_canvas     => $args{price_canvas},     
        atr_canvas       => $args{atr_canvas},       
        
        visible_bars     => 60,
        offset           => 0,
        is_auto_scale    => 1,
        manual_min_y     => undef,
        manual_max_y     => undef,
        render_pending   => 0,
        drag_start_x     => undef,
        drag_start_y     => undef,
        drag_start_offset=> 0,
        vertical_drag_y  => undef,
        
        %args,
    };
    bless $self, $class;

    $self->{price_panel} = Market::Panels::PricePanel->new(canvas => $self->{price_canvas});
    $self->{atr_panel}   = Market::Panels::ATRPanel->new(canvas => $self->{atr_canvas});

    $self->bind_events();
    
    return $self;
}


sub compute_window {
    my ($self) = @_;
    
    my $total_candles = $self->{market_data}->size();
    my $end_idx = $total_candles - 1 - $self->{offset};
    my $start_idx = $end_idx - $self->{visible_bars} + 1;

    $start_idx = 0 if $start_idx < 0;
    $end_idx = 0 if $end_idx < 0;
    
    return ($start_idx, $end_idx);
}

sub round {
    my ($self, $value) = @_;

    return 0 if !defined $value;
    return int($value + ($value >= 0 ? 0.5 : -0.5));
}

sub request_render {
    my ($self) = @_;

    return if $self->{render_pending};
    $self->{render_pending} = 1;

    my $canvas = $self->{price_canvas} || $self->{atr_canvas};
    if ($canvas) {
        $canvas->afterIdle(sub {
            $self->{render_pending} = 0;
            $self->render();
        });
    } else {
        $self->{render_pending} = 0;
        $self->render();
    }
}

sub render {
    my ($self) = @_;
    
    # 1. Obtener la porción temporal de la ventana visible
    my ($start, $end) = $self->compute_window();
    
    # 2. Extraer subconjuntos de datos reales
    my $visible_candles = $self->{market_data}->get_slice($start, $end);
    my $visible_atr     = $self->{indicator_manager}->slice_array('ATR', $start, $end);
    
    # 3. Calcular rangos de precios e indicadores para construir escalas dinámicas
    my ($min_p, $max_p) = $self->{price_panel}->get_y_range($visible_candles);
    my ($min_a, $max_a) = $self->{atr_panel}->get_y_range($visible_atr);
    
    if (!$self->{is_auto_scale} && defined $self->{manual_min_y} && defined $self->{manual_max_y}) {
        ($min_p, $max_p) = ($self->{manual_min_y}, $self->{manual_max_y});
    } else {
        ($self->{manual_min_y}, $self->{manual_max_y}) = ($min_p, $max_p);
    }

    if (!defined $min_p || !defined $max_p || $min_p == $max_p) {
        $min_p = 20000;
        $max_p = 30000;
    }
    if (!defined $min_a || !defined $max_a || $min_a == $max_a) {
        $min_a = 0;
        $max_a = 100;
    }
    
    # 4. Instanciar los sistemas de coordenadas independientes para píxeles
    my $price_scale = Market::Panels::Scales->new(min_y => $min_p, max_y => $max_p, bars => scalar(@$visible_candles));
    my $atr_scale   = Market::Panels::Scales->new(min_y => $min_a, max_y => $max_a, bars => scalar(@$visible_candles));
    
    $self->{price_panel}->set_scale($price_scale);
    $self->{atr_panel}->set_scale($atr_scale);
    
    # 5. Ejecutar render en cada sub-canvas
    $self->{price_panel}->render($self->{price_canvas}, $visible_candles, $price_scale);
    $self->{atr_panel}->render($self->{atr_canvas}, $visible_atr, $atr_scale);
    $self->{price_panel}->draw_time_axis($self->{price_canvas}, $self->compute_intraday_labels());
}

sub _bind_all_canvas {
    my ($self) = @_;
    
    # Aseguramos capturar las referencias exactas de los objetos de Tk
    my $p_canvas = $self->{price_canvas};
    my $a_canvas = $self->{atr_canvas};
    
    # 1. Binding nativo para el panel de Precios usando la sintaxis clásica 'bind'
    if (defined $p_canvas) {
        $p_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_mouse_move($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $p_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_start_horizontal_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $p_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_horizontal_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $p_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_drag(); });
        $p_canvas->Tk::bind('<MouseWheel>', [sub {
            my ($widget, $delta) = @_;
            $self->_horizontal_zoom($delta > 0 ? -5 : 5);
        }, Tk::Ev('D')]);
        $p_canvas->Tk::bind('<Button-4>', sub { $self->_horizontal_zoom(-5); });
        $p_canvas->Tk::bind('<Button-5>', sub { $self->_horizontal_zoom(5); });
        $p_canvas->Tk::bind('<Double-Button-1>', sub { $self->reset_view(); });
        $p_canvas->Tk::bind('<Key-a>', sub { $self->{is_auto_scale} = 1; $self->request_render(); });
        $p_canvas->Tk::bind('<Key-m>', sub { $self->{is_auto_scale} = 0; $self->request_render(); });
        $p_canvas->Tk::bind('<Key-plus>', sub { $self->{is_auto_scale} = 0; $self->_vertical_zoom(0.9); });
        $p_canvas->Tk::bind('<Key-minus>', sub { $self->{is_auto_scale} = 0; $self->_vertical_zoom(1.1); });
        $p_canvas->Tk::bind('<Up>', sub { $self->{is_auto_scale} = 0; $self->_vertical_drag(-10); });
        $p_canvas->Tk::bind('<Down>', sub { $self->{is_auto_scale} = 0; $self->_vertical_drag(10); });
        $p_canvas->Tk::bind('<Enter>', sub { $p_canvas->focus; });
        $p_canvas->Tk::bind('<Leave>', sub {
            $self->{last_mouse_x} = undef;
            $self->{last_mouse_y} = undef;
            $self->{active_canvas} = undef;
            $self->_draw_crosshair_all();
        });
    }
    
    # 2. Binding nativo idéntico para el panel del ATR
    if (defined $a_canvas) {
        $a_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_mouse_move($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $a_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_start_horizontal_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $a_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_horizontal_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $a_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_drag(); });
        $a_canvas->Tk::bind('<MouseWheel>', [sub {
            my ($widget, $delta) = @_;
            $self->_horizontal_zoom($delta > 0 ? -5 : 5);
        }, Tk::Ev('D')]);
        $a_canvas->Tk::bind('<Button-4>', sub { $self->_horizontal_zoom(-5); });
        $a_canvas->Tk::bind('<Button-5>', sub { $self->_horizontal_zoom(5); });
        $a_canvas->Tk::bind('<Leave>', sub {
            $self->{last_mouse_x} = undef;
            $self->{last_mouse_y} = undef;
            $self->{active_canvas} = undef;
            $self->_draw_crosshair_all();
        });
    }
}

sub bind_events {
    my ($self) = @_;
    $self->_bind_all_canvas();
}

sub _horizontal_zoom {
    my ($self, $delta) = @_;

    my $total = $self->{market_data}->size();
    $self->{visible_bars} += $delta;
    $self->{visible_bars} = 10 if $self->{visible_bars} < 10;
    $self->{visible_bars} = $total if $total && $self->{visible_bars} > $total;
    $self->request_render();
}

sub _start_horizontal_drag {
    my ($self, $widget, $x, $y) = @_;

    my $root_x = $widget->pointerx();
    $self->{drag_start_x} = defined $root_x ? $root_x : $x;
    $self->{drag_start_y} = $y;
    $self->{drag_start_offset} = $self->{offset};
}

sub _on_horizontal_drag {
    my ($self, $widget, $x, $y) = @_;

    $self->_on_mouse_move($widget, $x, $y);
    return unless defined $self->{drag_start_x};
    my $canvas = $self->{price_canvas};
    return unless $canvas;

    my $root_x = $widget->pointerx();
    my $current_x = defined $root_x ? $root_x : $x;
    my $width = $canvas->width() || 1;
    my $bar_w = $width / ($self->{visible_bars} || 1);
    return if $bar_w <= 0;

    my $delta_bars = int(($current_x - $self->{drag_start_x}) / $bar_w);
    my $max_offset = $self->{market_data}->size() - $self->{visible_bars};
    $max_offset = 0 if $max_offset < 0;

    $self->{offset} = $self->{drag_start_offset} + $delta_bars;
    $self->{offset} = 0 if $self->{offset} < 0;
    $self->{offset} = $max_offset if $self->{offset} > $max_offset;
    $self->request_render();
}

sub _end_drag {
    my ($self) = @_;

    $self->{drag_start_x} = undef;
    $self->{drag_start_y} = undef;
}

sub _vertical_drag {
    my ($self, $dy) = @_;

    return if $self->{is_auto_scale};
    return if !$dy || $dy == 0;

    my $price_scale = $self->{price_panel}->{scale};
    return if !defined $price_scale;

    my $val_at_zero = $price_scale->y_to_value(0);
    my $val_at_one  = $price_scale->y_to_value(1);
    my $units_per_pixel = $val_at_zero - $val_at_one;

    my $value_delta = $dy * $units_per_pixel;

    $self->{manual_min_y} += $value_delta;
    $self->{manual_max_y} += $value_delta;

    $self->request_render();
}

sub _vertical_zoom {
    my ($self, $factor) = @_;

    return if $self->{is_auto_scale};
    return if !$factor || $factor <= 0;

    my $min = $self->{manual_min_y};
    my $max = $self->{manual_max_y};
    return if !defined $min || !defined $max;

    my $center = ($min + $max) / 2;
    my $half_range = ($max - $min) / 2;

    $half_range *= $factor;

    $self->{manual_min_y} = $center - $half_range;
    $self->{manual_max_y} = $center + $half_range;

    $self->request_render();
}

sub _on_mouse_move {
    my ($self, $widget, $raw_x, $raw_y) = @_;
    
    return if !defined $raw_x || !defined $raw_y;
    
    my $pixel_x = $self->round($raw_x);
    my $pixel_y = $self->round($raw_y);
    
    $self->{last_mouse_x} = $pixel_x;
    $self->{last_mouse_y} = $pixel_y;
    $self->{active_canvas} = $widget;
    
    $self->_draw_crosshair_all();
}

sub _draw_crosshair_all {
    my ($self) = @_;

    my $last_x = $self->{last_mouse_x};
    my $last_y = $self->{last_mouse_y};

    if (!defined $last_x) {
        $self->{price_panel}->draw_crosshair(undef, undef);
        $self->{atr_panel}->draw_crosshair(undef, undef);
        return;
    }

    my $price_y = undef;
    my $atr_y = undef;

    if (defined $self->{active_canvas} && $self->{active_canvas} == $self->{atr_canvas}) {
        $atr_y = $last_y;
    } else {
        $price_y = $last_y;
    }

    $self->{price_panel}->draw_crosshair($last_x, $price_y);
    $self->{atr_panel}->draw_crosshair($last_x, $atr_y);
}

sub set_timeframe {
    my ($self, $tf) = @_;

    if ($tf ne '1m' && $tf ne '5m' && $tf ne '15m') {
            warn "Temporalidad '$tf' no soportada por el sistema.";
            return;
    }

    $self->{market_data}->build_tf_candles($tf) if $tf ne '1m';
    $self->{market_data}->set_timeframe($tf);
    $self->{indicator_manager}->reset_all();
    for (my $i = 0; $i < $self->{market_data}->size(); $i++) {
        $self->{indicator_manager}->update_last($self->{market_data}, $i);
    }
    $self->{is_auto_scale} = 1;
    $self->{manual_min_y} = undef;
    $self->{manual_max_y} = undef;
    $self->reset_view();
}

sub reset_view {
    my ($self) = @_;

    $self->{visible_bars} = 60;
    $self->{offset} = 0;
    $self->{is_auto_scale} = 1;
    $self->{manual_min_y} = undef;
    $self->{manual_max_y} = undef;
    $self->request_render();
}

sub compute_intraday_labels {
    my ($self) = @_;

    my $visible_elements = $self->get_all_timestamps();
    my @labels;
    
    my $total_visibles = scalar(@$visible_elements);
    return \@labels if $total_visibles == 0;

    my $step = 5;
    if ($total_visibles > 150) { $step = 20; }
    elsif ($total_visibles > 80) { $step = 10; }
    else { $step = 5; }

    for (my $i = 0; $i < $total_visibles; $i++) {
        if ($i % $step == 0) {
            my $item = $visible_elements->[$i];
            my $ts   = $item->{ts};
            my $idx  = $i;
            
            my $time_str = sprintf("%02d:%02d", $ts->hour, $ts->minute);
            push @labels, { index => $idx, text => $time_str };
        }
    }

    return \@labels;
}

sub get_all_timestamps {
    my ($self) = @_;

    my ($start, $end) = $self->compute_window();
    my @timestamps;

    for (my $i = $start; $i <= $end; $i++) {
        my $ts = $self->{market_data}->get_timestamp($i);
        if (defined $ts) {
            my $parsed = eval { Time::Moment->from_string($ts) };
            push @timestamps, { index => $i, ts => $parsed } if $parsed;
        }
    }
    
    return \@timestamps;
}
1;