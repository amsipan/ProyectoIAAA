package Market::ChartEngine;
use strict;
use warnings;

use Time::Moment;
use Market::Panels::Scales;
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel; 

# Constantes del módulo (valores fijos del paquete, no estado global mutable).
#   RIGHT_MARGIN     => margen interno derecho del área de ploteo. Los ejes ahora
#                       son canvases separados, así que debe ser 0.
#   MIN_VISIBLE_BARS => mínimo de velas visibles en la ventana (Req. 8, 10)
#   ZOOM_STEP        => barras por paso de rueda en el zoom horizontal
#   TIME_AXIS_DRAG_PX_PER_BAR => sensibilidad del drag horizontal del eje temporal
use constant {
    RIGHT_MARGIN     => 0,
    MIN_VISIBLE_BARS => 2,
    MAX_VISIBLE_BARS => 40000,
    ZOOM_STEP        => 5,
    CTRL_MASK        => 0x0004,
    TIME_AXIS_DRAG_PX_PER_BAR => 8,
};

# Paleta de tema claro por defecto (local al módulo). Se usa solo si el llamador
# no inyecta un hash `theme`. Mantiene EXACTAMENTE las mismas claves del contrato
# de tema definido en el diseño, de modo que los paneles puedan consumirla sin
# recurrir a variables globales.
sub _default_theme {
    return {
        bg             => '#ffffff',
        grid           => '#e6e6e6',
        date_grid      => '#c4c9d1',
        axis_text      => '#363a45',
        bull           => '#26a69a',
        bear           => '#ef5350',
        atr_line       => '#2962ff',
        crosshair_line => '#9598a1',
        label_bg       => '#363a45',
        label_fg       => '#ffffff',
        last_price_bg  => '#363a45',
        last_price_fg  => '#ffffff',
    };
}

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
        scale_mode_callback => $args{scale_mode_callback},
        ctrl_zoom_x_shift => 0,
        ctrl_zoom_y_lock_min => undef,
        ctrl_zoom_y_lock_max => undef,
        is_atr_auto_scale => 1,
        atr_manual_min_y => undef,
        atr_manual_max_y => undef,
        atr_axis_drag_start_y => undef,
        atr_axis_drag_min_y => undef,
        atr_axis_drag_max_y => undef,
        atr_drag_start_min_y => undef,
        atr_drag_start_max_y => undef,
        render_pending   => 0,
        drag_start_x     => undef,
        drag_start_y     => undef,
        drag_start_panel => undef,
        drag_start_offset=> 0,
        axis_drag_start_y=> undef,
        axis_drag_min_y  => undef,
        axis_drag_max_y  => undef,
        vertical_drag_y  => undef,
        
        %args,
    };
    bless $self, $class;

    # Tema claro: se usa el inyectado por el llamador (market.pl) o un default
    # local con las mismas claves. El tema viaja por la instancia, nunca como global.
    $self->{theme} = $args{theme} || _default_theme();

    $self->{price_panel} = Market::Panels::PricePanel->new(
        canvas => $self->{price_canvas},
        theme  => $self->{theme},
    );
    $self->{atr_panel}   = Market::Panels::ATRPanel->new(
        canvas => $self->{atr_canvas},
        theme  => $self->{theme},
    );

    $self->bind_events();
    
    return $self;
}


sub compute_window {
    my ($self) = @_;
    
    my $total_candles = $self->{market_data}->size();
    return (0, -1) if !$total_candles || $total_candles <= 0;

    if ($total_candles >= MIN_VISIBLE_BARS) {
        $self->{visible_bars} = MIN_VISIBLE_BARS if $self->{visible_bars} < MIN_VISIBLE_BARS;
    } else {
        $self->{visible_bars} = $total_candles;
    }

    $self->{visible_bars} = $total_candles if $self->{visible_bars} > $total_candles;
    $self->{visible_bars} = MAX_VISIBLE_BARS if $self->{visible_bars} > MAX_VISIBLE_BARS;

    $self->{offset} = $self->_clamp_offset($self->{offset});

    my $end_idx = $total_candles - 1 - $self->{offset};
    my $start_idx = $end_idx - $self->{visible_bars} + 1;

    return ($start_idx, $end_idx);
}

sub round {
    my ($self, $value) = @_;

    return 0 if !defined $value;

    return int($value + ($value >= 0 ? 0.5 : -0.5));
}

sub _max_offset_for_visible {
    my ($self) = @_;

    my $total = $self->{market_data}->size() || 0;
    return 0 if $total < MIN_VISIBLE_BARS;

    return ($total - MIN_VISIBLE_BARS) > 0 ? ($total - MIN_VISIBLE_BARS) : 0;
}

sub _min_offset_for_visible {
    my ($self) = @_;

    my $total = $self->{market_data}->size() || 0;
    return 0 if $total < MIN_VISIBLE_BARS;


    my $visible = $self->{visible_bars} || MIN_VISIBLE_BARS;
    $visible = $total if $visible > $total;

    return -(($visible > MIN_VISIBLE_BARS) ? ($visible - MIN_VISIBLE_BARS) : 0);
}

sub _clamp_offset {
    my ($self, $offset) = @_;

    $offset = 0 if !defined $offset;
    my $min_offset = $self->_min_offset_for_visible();
    my $max_offset = $self->_max_offset_for_visible();
    $offset = $min_offset if $offset < $min_offset;
    $offset = $max_offset if $offset > $max_offset;
    return $offset;
}

sub _pad_visible_slice {
    my ($self, $slice, $start, $end) = @_;

    return unless $slice;
    my $target = defined $start && defined $end && $end >= $start ? $end - $start + 1 : 0;
    push @$slice, (undef) x ($target - @$slice) if $target > @$slice;
}

sub _canvas_width {
    my ($self, $canvas) = @_;
    return 1 unless $canvas;

    my $w = 0;
    my $geom = eval { $canvas->geometry() };
    if (defined $geom && $geom =~ /^(\d+)x\d+/) {
        $w = $1;
    }
    $w ||= eval { $canvas->Width() } || eval { $canvas->width() } || 1;
    return $w > 1 ? $w : 1;
}

sub _canvas_size {
    my ($self, $canvas) = @_;
    return (1, 1) unless $canvas;
    my ($w, $h) = (0, 0);
    my $geom = eval { $canvas->geometry() };
    if (defined $geom && $geom =~ /^(\d+)x(\d+)/) {
        ($w, $h) = ($1, $2);
    }
    $w ||= eval { $canvas->Width() }  || eval { $canvas->width() }  || 1;
    $h ||= eval { $canvas->Height() } || eval { $canvas->height() } || 1;
    $w = 1 if $w < 1;
    $h = 1 if $h < 1;
    return ($w, $h);
}

sub _reset_canvas_view {
    my ($self, $canvas) = @_;
    return unless $canvas;

    my ($w, $h) = $self->_canvas_size($canvas);
    eval { $canvas->xviewMoveto(0) };
    eval { $canvas->yviewMoveto(0) };
    eval { $canvas->configure(-scrollregion => [0, 0, $w, $h]) };
}

sub request_render {
    my ($self) = @_;

    return if $self->{render_pending};
    $self->{render_pending} = 1;

    my $canvas = $self->{price_canvas} || $self->{atr_canvas};
    if ($canvas) {
        $canvas->after(20, sub {
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
    $self->_pad_visible_slice($visible_candles, $start, $end);
    $self->_pad_visible_slice($visible_atr, $start, $end);
    
    # 3. Calcular rangos de precios e indicadores para construir escalas dinámicas
    my ($min_p, $max_p) = $self->{price_panel}->get_y_range($visible_candles);
    my ($min_a, $max_a) = $self->{atr_panel}->get_y_range($visible_atr);
    
    if (defined $self->{ctrl_zoom_y_lock_min} && defined $self->{ctrl_zoom_y_lock_max}) {
        ($min_p, $max_p) = ($self->{ctrl_zoom_y_lock_min}, $self->{ctrl_zoom_y_lock_max});
    } elsif (!$self->{is_auto_scale} && defined $self->{manual_min_y} && defined $self->{manual_max_y}) {
        ($min_p, $max_p) = ($self->{manual_min_y}, $self->{manual_max_y});
    } else {
        ($self->{manual_min_y}, $self->{manual_max_y}) = ($min_p, $max_p);
    }

    if (!defined $min_p || !defined $max_p || $min_p == $max_p) {
        $min_p = 20000;
        $max_p = 30000;
    }
    if (!$self->{is_atr_auto_scale} && defined $self->{atr_manual_min_y} && defined $self->{atr_manual_max_y}) {
        ($min_a, $max_a) = ($self->{atr_manual_min_y}, $self->{atr_manual_max_y});
    } else {
        ($self->{atr_manual_min_y}, $self->{atr_manual_max_y}) = ($min_a, $max_a);
    }
    if (!defined $min_a || !defined $max_a || $min_a == $max_a) {
        $min_a = 0;
        $max_a = 100;
    }
    
    # 4. Instanciar los sistemas de coordenadas. La escala X usa un ancho compartido
    # para que PricePanel y ATRPanel queden sincronizados barra por barra.
    my ($price_w, $price_h) = $self->_canvas_size($self->{price_canvas});
    my ($atr_w, $atr_h)     = $self->_canvas_size($self->{atr_canvas});
    my $shared_w = $price_w;

    $self->_reset_canvas_view($self->{price_canvas});
    $self->_reset_canvas_view($self->{atr_canvas});
    $self->_reset_canvas_view($self->{price_axis_canvas});
    $self->_reset_canvas_view($self->{atr_axis_canvas});
    $self->_reset_canvas_view($self->{time_axis_canvas});

    if (!$self->{_printed_render_diag}) {
        print "[*] Render geometry: price=${price_w}x${price_h} atr=${atr_w}x${atr_h} window=$start-$end bars=" . scalar(@$visible_candles) . "\n";
        $self->{_printed_render_diag} = 1;
    }

    my $x_bars = $end - $start + 1;
    $x_bars = scalar(@$visible_candles) if $x_bars < 1;
    $x_bars = 1 if $x_bars < 1;

    my $price_scale = Market::Panels::Scales->new(min_y => $min_p, max_y => $max_p, bars => $x_bars, right_margin => RIGHT_MARGIN);
    my $atr_scale   = Market::Panels::Scales->new(min_y => $min_a, max_y => $max_a, bars => $x_bars, right_margin => RIGHT_MARGIN);
    $price_scale->{width}  = $shared_w;
    $price_scale->{height} = $price_h;
    $price_scale->{draw_labels} = $self->{price_axis_canvas} ? 0 : 1;
    $price_scale->{draw_last_label} = $self->{price_axis_canvas} ? 0 : 1;
    $price_scale->{draw_crosshair_label} = $self->{price_axis_canvas} ? 0 : 1;
    $price_scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    $price_scale->{tick_size} = 0.25;
    $atr_scale->{width}    = $shared_w;
    $atr_scale->{height}   = $atr_h;
    $atr_scale->{draw_labels} = $self->{atr_axis_canvas} ? 0 : 1;
    $atr_scale->{draw_last_label} = $self->{atr_axis_canvas} ? 0 : 1;
    $atr_scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;

    
    $self->{price_panel}->set_scale($price_scale);

    $self->{atr_panel}->set_scale($atr_scale);
    
    # 5. Ejecutar render en cada sub-canvas
    $self->{price_panel}->render($self->{price_canvas}, $visible_candles, $price_scale);
    $self->{atr_panel}->render($self->{atr_canvas}, $visible_atr, $atr_scale);
    my $time_labels = $self->compute_intraday_labels();
    $self->{price_panel}->draw_time_axis($self->{price_canvas}, $time_labels, { draw_grid => 1, draw_labels => 0 });
    $self->_render_price_axis($price_scale, $visible_candles);
    $self->_render_atr_axis($atr_scale, $visible_atr);
    $self->_render_time_axis($price_scale, $time_labels);
    $self->_draw_crosshair_all() if defined $self->{last_mouse_x};
    $self->_redraw_pointer_symbol();
}

sub _render_price_axis {
    my ($self, $source_scale, $visible_candles) = @_;

    my $canvas = $self->{price_axis_canvas};
    return unless $canvas && $source_scale;

    my ($w, $h) = $self->_canvas_size($canvas);
    $canvas->delete('y_scale');
    $canvas->delete('axis_last_price');

    my $axis_scale = Market::Panels::Scales->new(
        min_y        => $source_scale->{min_y},
        max_y        => $source_scale->{max_y},
        bars         => 1,
        right_margin => 0,
    );
    $axis_scale->{width}           = $w;
    $axis_scale->{height}          = $source_scale->{height} || $h;
    $axis_scale->{draw_grid}       = 0;
    $axis_scale->{draw_labels}     = 1;
    $axis_scale->{label_x}         = 4;
    $axis_scale->{label_anchor}    = 'w';
    $axis_scale->{grid_color}      = $self->{theme}{grid}      // '#e6e6e6';
    $axis_scale->{axis_text_color} = $self->{theme}{axis_text} // '#363a45';
    $axis_scale->{tick_size}       = $source_scale->{tick_size};
    $axis_scale->_draw_y_scale($canvas);

    return unless $visible_candles && @$visible_candles;
    my $last_candle;
    for my $candle (@$visible_candles) {
        $last_candle = $candle if defined $candle;
    }
    return unless defined $last_candle;
    my ($open, $close) = @{$last_candle}[1, 4];
    return unless defined $close;

    my $y = $axis_scale->value_to_y($close);

    my $label = sprintf('%.2f', $close);
    my $bg = (defined $open && $close >= $open)
        ? ($self->{theme}{bull} // '#26a69a')
        : ($self->{theme}{bear} // '#ef5350');
    my $fg = $self->{theme}{last_price_fg} // '#ffffff';

    $canvas->createRectangle(0, $y - 8, $w, $y + 8, -fill => $bg, -outline => $bg, -tags => 'axis_last_price');
    $canvas->createText(4, $y, -text => $label, -anchor => 'w', -font => 'Helvetica 9 bold', -fill => $fg, -tags => 'axis_last_price');
}

sub _draw_price_axis_crosshair {
    my ($self, $y) = @_;

    my $canvas = $self->{price_axis_canvas};
    return unless $canvas;

    $canvas->delete('axis_crosshair');
    return unless defined $y;

    my $scale = $self->{price_panel} ? $self->{price_panel}->{scale} : undef;
    return unless $scale;

    my ($w, undef) = $self->_canvas_size($canvas);
    my $value = $scale->y_to_value($y);
    my $tick = $scale->{tick_size} || 0.25;
    $value = int($value / $tick + ($value >= 0 ? 0.5 : -0.5)) * $tick;
    my $label = sprintf('%.2f', $value);
    my $bg = $self->{theme}{label_bg} // '#363a45';
    my $fg = $self->{theme}{label_fg} // '#ffffff';

    $canvas->createRectangle(0, $y - 8, $w, $y + 8, -fill => $bg, -outline => $bg, -tags => 'axis_crosshair');
    $canvas->createText(4, $y, -text => $label, -anchor => 'w', -font => 'Helvetica 9 bold', -fill => $fg, -tags => 'axis_crosshair');
}

sub _draw_atr_axis_crosshair {
    my ($self, $y) = @_;

    my $canvas = $self->{atr_axis_canvas};
    return unless $canvas;

    $canvas->delete('atr_axis_crosshair');
    return unless defined $y;

    my $scale = $self->{atr_panel} ? $self->{atr_panel}->{scale} : undef;
    return unless $scale;

    my ($w, undef) = $self->_canvas_size($canvas);
    my $value = $scale->y_to_value($y);
    my $label = sprintf('%.4f', $value);
    my $bg = $self->{theme}{label_bg} // '#363a45';
    my $fg = $self->{theme}{label_fg} // '#ffffff';

    $canvas->createRectangle(0, $y - 8, $w, $y + 8, -fill => $bg, -outline => $bg, -tags => 'atr_axis_crosshair');
    $canvas->createText(4, $y, -text => $label, -anchor => 'w', -font => 'Helvetica 9 bold', -fill => $fg, -tags => 'atr_axis_crosshair');
}

sub _render_time_axis {
    my ($self, $source_scale, $labels) = @_;

    my $canvas = $self->{time_axis_canvas};
    return unless $canvas && $source_scale;

    my ($w, $h) = $self->_canvas_size($canvas);
    my $old_scale = $self->{price_panel}->{scale};
    my $axis_scale = Market::Panels::Scales->new(
        bars         => $source_scale->{bars},
        right_margin => RIGHT_MARGIN,
    );
    $axis_scale->{width}  = $source_scale->{width} || $w;
    $axis_scale->{height} = $h;
    $axis_scale->{x_shift} = $source_scale->{x_shift} || 0;

    $self->{price_panel}->{scale} = $axis_scale;
    $self->{price_panel}->draw_time_axis($canvas, $labels, { draw_grid => 0, draw_labels => 1 });
    $self->{price_panel}->{scale} = $old_scale;
}

sub _render_atr_axis {
    my ($self, $source_scale, $visible_atr) = @_;

    my $canvas = $self->{atr_axis_canvas};
    return unless $canvas && $source_scale;

    my ($w, $h) = $self->_canvas_size($canvas);
    $canvas->delete('y_scale');
    $canvas->delete('atr_axis_last');

    my $axis_scale = Market::Panels::Scales->new(
        min_y        => $source_scale->{min_y},
        max_y        => $source_scale->{max_y},
        bars         => 1,
        right_margin => 0,
    );
    $axis_scale->{width}           = $w;
    $axis_scale->{height}          = $source_scale->{height} || $h;
    $axis_scale->{draw_grid}       = 0;
    $axis_scale->{draw_labels}     = 1;
    $axis_scale->{label_x}         = 4;
    $axis_scale->{label_anchor}    = 'w';
    $axis_scale->{grid_color}      = $self->{theme}{grid}      // '#e6e6e6';
    $axis_scale->{axis_text_color} = $self->{theme}{axis_text} // '#363a45';
    $axis_scale->_draw_y_scale($canvas);

    my $last;
    for my $v (@$visible_atr) {
        $last = $v if defined $v;
    }
    return unless defined $last;

    my $y = $axis_scale->value_to_y($last);
    my $label = sprintf('%.4f', $last);
    my $fg = $self->{theme}{last_price_fg} // '#ffffff';
    my $line = $self->{theme}{atr_line} // '#2962ff';

    $canvas->createRectangle(0, $y - 8, $w, $y + 8, -fill => $line, -outline => $line, -tags => 'atr_axis_last');
    $canvas->createText(4, $y, -text => $label, -anchor => 'w', -font => 'Helvetica 9 bold', -fill => $fg, -tags => 'atr_axis_last');
}


sub _set_cursor {
    my ($self, $widget, $cursor) = @_;

    return unless defined $widget && defined $cursor;
    eval { $widget->configure(-cursor => $cursor) };
}

sub _draw_pointer_symbol {
    my ($self, $widget, $x, $y, $kind) = @_;

    return unless defined $widget;
    eval { $widget->delete('pointer_symbol') };
}

sub _clear_pointer_symbol {
    my ($self, $widget) = @_;

    eval { $widget->delete('pointer_symbol') } if defined $widget;
    $self->{pointer_widget} = undef;
}

sub _redraw_pointer_symbol {
    my ($self) = @_;

    return;
}

sub _bind_all_canvas {
    my ($self) = @_;
    
    # Aseguramos capturar las referencias exactas de los objetos de Tk
    my $p_canvas = $self->{price_canvas};
    my $a_canvas = $self->{atr_canvas};
    my $axis_canvas = $self->{price_axis_canvas};
    my $atr_axis_canvas = $self->{atr_axis_canvas};
    my $time_canvas = $self->{time_axis_canvas};
    
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
            my ($widget, $delta, $x, $y, $state) = @_;
            my $step = $delta > 0 ? -ZOOM_STEP : ZOOM_STEP;
            $self->_wheel_zoom($widget, $step, $x, $y, $state);
            return 'break';
        }, Tk::Ev('D'), Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $p_canvas->Tk::bind('<Button-4>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, -ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $p_canvas->Tk::bind('<Button-5>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $p_canvas->Tk::bind('<Double-Button-1>', sub { $self->reset_view(); });
        $p_canvas->Tk::bind('<Configure>', sub { $self->_on_resize($p_canvas); });
        $p_canvas->Tk::bind('<Key-a>', sub { $self->set_scale_mode('auto'); });
        $p_canvas->Tk::bind('<Key-m>', sub { $self->set_scale_mode('manual'); });
        $p_canvas->Tk::bind('<Key-plus>', sub { $self->set_scale_mode('manual'); $self->_vertical_zoom(0.9); });
        $p_canvas->Tk::bind('<Key-minus>', sub { $self->set_scale_mode('manual'); $self->_vertical_zoom(1.1); });
        $p_canvas->Tk::bind('<Up>', sub { $self->set_scale_mode('manual'); $self->_vertical_drag(-10); });
        $p_canvas->Tk::bind('<Down>', sub { $self->set_scale_mode('manual'); $self->_vertical_drag(10); });
        $p_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($p_canvas, 'crosshair'); $p_canvas->focus; });
        $p_canvas->Tk::bind('<Leave>', sub {
            $self->_set_cursor($p_canvas, 'crosshair');
            $self->{last_mouse_x} = undef;
            $self->{last_mouse_y} = undef;
            $self->{active_canvas} = undef;
            $self->_draw_crosshair_all();
            $self->_clear_pointer_symbol($p_canvas);
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
            my ($widget, $delta, $x, $y, $state) = @_;
            my $step = $delta > 0 ? -ZOOM_STEP : ZOOM_STEP;
            $self->_wheel_zoom($widget, $step, $x, $y, $state);
            return 'break';
        }, Tk::Ev('D'), Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $a_canvas->Tk::bind('<Button-4>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, -ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $a_canvas->Tk::bind('<Button-5>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $a_canvas->Tk::bind('<Configure>', sub { $self->_on_resize($a_canvas); });
        $a_canvas->Tk::bind('<Key-a>', sub { $self->set_atr_scale_mode('auto'); });
        $a_canvas->Tk::bind('<Key-m>', sub { $self->set_atr_scale_mode('manual'); });
        $a_canvas->Tk::bind('<Key-plus>', sub { $self->set_atr_scale_mode('manual'); $self->_atr_vertical_zoom(0.9); });
        $a_canvas->Tk::bind('<Key-minus>', sub { $self->set_atr_scale_mode('manual'); $self->_atr_vertical_zoom(1.1); });
        $a_canvas->Tk::bind('<Up>', sub { $self->set_atr_scale_mode('manual'); $self->_atr_vertical_drag(-10); });
        $a_canvas->Tk::bind('<Down>', sub { $self->set_atr_scale_mode('manual'); $self->_atr_vertical_drag(10); });
        $a_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($a_canvas, 'crosshair'); $a_canvas->focus; });
        $a_canvas->Tk::bind('<Leave>', sub {
            $self->_set_cursor($a_canvas, 'crosshair');
            $self->{last_mouse_x} = undef;
            $self->{last_mouse_y} = undef;
            $self->{active_canvas} = undef;
            $self->_draw_crosshair_all();
            $self->_clear_pointer_symbol($a_canvas);
        });
    }

    if (defined $axis_canvas) {
        $axis_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_draw_pointer_symbol($widget, $x, $y, 'v');
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $axis_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $y) = @_;
            $self->_start_price_axis_drag($widget, $y);
        }, Tk::Ev('y')]);
        $axis_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $y) = @_;
            $self->_on_price_axis_drag($widget, $y);
        }, Tk::Ev('y')]);
        $axis_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_price_axis_drag(); });
        $axis_canvas->Tk::bind('<Double-Button-1>', sub { $self->set_scale_mode('auto'); });
        $axis_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($axis_canvas, 'sb_v_double_arrow') });
        $axis_canvas->Tk::bind('<Leave>', sub { $self->_set_cursor($axis_canvas, 'sb_v_double_arrow'); $self->_clear_pointer_symbol($axis_canvas); });
    }

    if (defined $atr_axis_canvas) {
        $atr_axis_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_draw_pointer_symbol($widget, $x, $y, 'v');
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $atr_axis_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $y) = @_;
            $self->_start_atr_axis_drag($widget, $y);
        }, Tk::Ev('y')]);
        $atr_axis_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $y) = @_;
            $self->_on_atr_axis_drag($widget, $y);
        }, Tk::Ev('y')]);
        $atr_axis_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_atr_axis_drag(); });
        $atr_axis_canvas->Tk::bind('<Double-Button-1>', sub { $self->_reset_atr_scale(); });
        $atr_axis_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($atr_axis_canvas, 'sb_v_double_arrow') });
        $atr_axis_canvas->Tk::bind('<Leave>', sub { $self->_set_cursor($atr_axis_canvas, 'sb_v_double_arrow'); $self->_clear_pointer_symbol($atr_axis_canvas); });
    }

    if (defined $time_canvas) {
        $time_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_time_axis_motion($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $time_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_start_time_axis_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $time_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_time_axis_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $time_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_time_axis_drag(); });
        $time_canvas->Tk::bind('<MouseWheel>', [sub {
            my ($widget, $delta, $x, $y, $state) = @_;
            my $step = $delta > 0 ? -ZOOM_STEP : ZOOM_STEP;
            $self->_wheel_zoom($widget, $step, $x, $y, $state);
            return 'break';
        }, Tk::Ev('D'), Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $time_canvas->Tk::bind('<Button-4>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, -ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $time_canvas->Tk::bind('<Button-5>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $time_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($time_canvas, 'sb_h_double_arrow') });
        $time_canvas->Tk::bind('<Leave>', sub {
            $self->_set_cursor($time_canvas, 'sb_h_double_arrow');
            $self->{last_mouse_x} = undef;
            $self->{last_mouse_y} = undef;
            $self->{active_canvas} = undef;
            $self->_draw_crosshair_all();
            $self->_clear_pointer_symbol($time_canvas);
        });
    }
}

sub bind_events {
    my ($self) = @_;
    $self->_bind_all_canvas();
}

# _anchor_index_and_x($anchor_x) — calcula el punto de anclaje del zoom (Req. 9.1, 9.2,
# 9.4) ANTES de cambiar el nivel de zoom.
#
# Dado un X de pantalla (o undef), devuelve la pareja:
#       ($anchor_index, $anchor_screen_x)
# donde $anchor_index es el índice GLOBAL del dato que debe quedar fijo y
# $anchor_screen_x es la coordenada X de pantalla en la que debe permanecer.
#
# Toda conversión X<->índice vive EXCLUSIVAMENTE en Scales (regla de oro de
# coordenadas): se instancia un Market::Panels::Scales con los mismos parámetros que
# usa render() —bars = nº de velas visibles (end - start + 1 de compute_window),
# right_margin => RIGHT_MARGIN y el ancho real del canvas de precios—.
#
#   * $anchor_x DEFINIDO (cursor sobre una barra del área de ploteo):
#       local  = Scales->x_to_index($anchor_x)   # índice LOCAL acotado a [0, bars-1]
#       global = start + local                    # índice GLOBAL del dato
#       => devuelve (global, $anchor_x)
#
#   * $anchor_x UNDEF (sin cursor): el ancla es la última vela visible, cuyo índice
#     GLOBAL es 'end' (de compute_window). Su X de pantalla es el centro de su barra:
#       local_de_end = end - start
#       screen_x     = Scales->index_to_center_x(local_de_end)
#       => devuelve (end, screen_x)
sub _anchor_index_and_x {
    my ($self, $anchor_x) = @_;

    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    $bars = 1 if $bars < 1;

    # Escala SOLO para convertir X <-> índice; mismos parámetros que render().
    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});

    if (defined $anchor_x) {
        # Cursor sobre una barra: índice LOCAL -> GLOBAL; la X se conserva tal cual.
        my $local  = $scale->x_to_index($anchor_x);
        my $global = $start + $local;
        return ($global, $anchor_x);
    }

    # Sin cursor: ancla = última vela real visible. Si la ventana incluye espacio
    # vacío a cualquier lado, el ancla se acota al rango real de datos.
    my $last_real = ($self->{market_data}->size() || 1) - 1;
    my $anchor_index = $end > $last_real ? $last_real : $end;
    $anchor_index = 0 if $anchor_index < 0;
    my $local_of_anchor = $anchor_index - $start;

    my $screen_x = $scale->index_to_center_x($local_of_anchor);
    return ($anchor_index, $screen_x);
}

# _zoom_anchor_x — decide el X de anclaje para los eventos de rueda/Button-4/5.
#
# Devuelve $self->{last_mouse_x} (ya actualizado por <Motion>) SOLO si el cursor está
# sobre una barra del área de ploteo, es decir, dentro de [0, plot_width]. En cualquier
# otro caso (sin cursor, o el cursor cae sobre el margen derecho de precios) devuelve
# undef, de modo que el ancla pase a ser la última vela visible (Req. 9.1).
#
# plot_width vive en Scales (regla de oro): se obtiene de una instancia con el ancho
# real del canvas y RIGHT_MARGIN, sin calcular el margen por nuestra cuenta.
sub _zoom_anchor_x {
    my ($self) = @_;

    my $x = $self->{last_mouse_x};
    return undef unless defined $x;                  # sin cursor => última vela

    my $canvas = $self->{price_canvas};
    return undef unless $canvas;
    my $w = $self->_canvas_width($canvas);
    return undef unless defined $w && $w > 0;

    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    $bars = 1 if $bars < 1;

    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $w;
    my $plot_w = $scale->plot_width();

    return ($x >= 0 && $x <= $plot_w) ? $x : undef;
}

sub _clear_ctrl_zoom_state {
    my ($self) = @_;

    $self->{ctrl_zoom_x_shift} = 0;
    $self->{ctrl_zoom_y_lock_min} = undef;
    $self->{ctrl_zoom_y_lock_max} = undef;
}

sub _wheel_zoom_delta {
    my ($self, $step) = @_;

    my $total = $self->{market_data}->size() || 0;
    return 0 unless $total > 0;

    my $old_visible = $self->{visible_bars} || MIN_VISIBLE_BARS;
    my $max_visible = $total < MAX_VISIBLE_BARS ? $total : MAX_VISIBLE_BARS;
    $max_visible = MIN_VISIBLE_BARS if $max_visible < MIN_VISIBLE_BARS;

    my $zoom_scale = -$step / ZOOM_STEP;
    my $factor = 1 + ($zoom_scale / 10);
    $factor = 0.1 if $factor < 0.1;

    my $new_visible = $self->round($old_visible / $factor);
    $new_visible = MIN_VISIBLE_BARS if $new_visible < MIN_VISIBLE_BARS;
    $new_visible = $max_visible if $new_visible > $max_visible;

    if ($new_visible == $old_visible) {
        if ($zoom_scale < 0 && $old_visible < $max_visible) {
            $new_visible = $old_visible + 1;
        } elsif ($zoom_scale > 0 && $old_visible > MIN_VISIBLE_BARS) {
            $new_visible = $old_visible - 1;
        }
    }

    return $new_visible - $old_visible;
}

sub _wheel_zoom {
    my ($self, $widget, $step, $x, $y, $state) = @_;

    if (defined $x) {
        $self->{last_mouse_x} = $self->_snap_crosshair_x($x);
        $self->{last_mouse_y} = $self->round($y) if defined $y;
        $self->{active_canvas} = $widget if defined $widget;
    }

    my $delta = $self->_wheel_zoom_delta($step);
    return if $delta == 0;

    my $ctrl_pressed = defined $state && ($state & CTRL_MASK);
    if ($ctrl_pressed) {
        my $anchor_x = $self->_zoom_anchor_x();
        if (defined $anchor_x) {
            $self->_ctrl_horizontal_zoom($delta, $anchor_x);
            return;
        }
    }

    $self->_clear_ctrl_zoom_state();
    $self->_horizontal_zoom($delta, undef);
}

sub _ctrl_horizontal_zoom {
    my ($self, $delta, $anchor_x) = @_;

    my $total = $self->{market_data}->size();
    return if !$total;

    my ($start, $end) = $self->compute_window();
    my $old_visible = $self->{visible_bars} || ($end - $start + 1) || 1;
    my $max_visible = $total < MAX_VISIBLE_BARS ? $total : MAX_VISIBLE_BARS;
    $max_visible = MIN_VISIBLE_BARS if $max_visible < MIN_VISIBLE_BARS;
    my $new_visible = $old_visible + $delta;
    $new_visible = MIN_VISIBLE_BARS if $new_visible < MIN_VISIBLE_BARS;
    $new_visible = $max_visible     if $new_visible > $max_visible;
    return if $new_visible == $old_visible;

    my $canvas_w = $self->_canvas_width($self->{price_canvas});
    return if !$canvas_w || $canvas_w <= 0;

    my $old_scale = Market::Panels::Scales->new(bars => $old_visible, right_margin => RIGHT_MARGIN);
    $old_scale->{width} = $canvas_w;
    $old_scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    my $anchor_global = $start + $old_scale->x_to_index_float($anchor_x) - 0.5;

    my $new_scale = Market::Panels::Scales->new(bars => $new_visible, right_margin => RIGHT_MARGIN);
    $new_scale->{width} = $canvas_w;
    my $new_bar_w = $new_scale->plot_width() / $new_visible;
    return if $new_bar_w <= 0;

    my $target_start = $anchor_global - (($anchor_x - ($new_bar_w / 2)) / $new_bar_w);
    my $new_start = $self->round($target_start);
    my $new_end = $new_start + $new_visible - 1;
    my $new_offset = ($total - 1) - $new_end;

    $self->{visible_bars} = $new_visible;
    $self->{offset} = $self->_clamp_offset($new_offset);
    ($new_start, $new_end) = $self->compute_window();

    $self->{ctrl_zoom_x_shift} = $anchor_x - (($anchor_global - $new_start + 0.5) * $new_bar_w);
    $self->{last_mouse_x} = $self->round($anchor_x);

    if ($self->{is_auto_scale}) {
        $self->{ctrl_zoom_y_lock_min} = undef;
        $self->{ctrl_zoom_y_lock_max} = undef;
    } elsif (!defined $self->{ctrl_zoom_y_lock_min} || !defined $self->{ctrl_zoom_y_lock_max}) {
        if (defined $self->{manual_min_y} && defined $self->{manual_max_y}) {
            $self->{ctrl_zoom_y_lock_min} = $self->{manual_min_y};
            $self->{ctrl_zoom_y_lock_max} = $self->{manual_max_y};
        }
    }

    $self->request_render();
}

# _horizontal_zoom($delta, $anchor_x) — zoom horizontal con ANCLAJE (Req. 8.1, 8.2,
# 9.1, 9.2, 9.3, 9.4).
#
# $delta      cambio en visible_bars (negativo = zoom-in, positivo = zoom-out).
# $anchor_x   X de pantalla del ancla, o undef. Si se llama con un solo argumento
#             ($anchor_x undef), el ancla es la última vela visible (compatibilidad
#             con los llamadores antiguos de un argumento).
#
# Algoritmo (design.md, "Algoritmo de zoom con anclaje"):
#   1. (anchor_index, anchor_screen_x) = _anchor_index_and_x($anchor_x)  [ANTES del zoom]
#   2. new_visible = clamp(visible_bars + delta, MIN_VISIBLE_BARS, total)
#   3. visible_bars = new_visible
#   4. bar_w' = plot_width / new_visible  (derivado dentro de Scales)
#   5. reposicionar el ancla en anchor_screen_x:
#        local'   = anchor_screen_x / bar_w' - 0.5   (vía Scales->x_to_index_float)
#        end_idx' = anchor_index + (new_visible - 1 - local')
#        offset   = (total - 1) - end_idx'
#   6. offset entero y acotado para conservar como mínimo dos velas reales en cada extremo.

#   7. request_render()
#
# Toda conversión X<->índice se hace SOLO con Scales (Req. 9.4). El ancla se conserva
# dentro de la tolerancia de una barra (Req. 9.3) porque offset es entero (el redondeo
# introduce a lo sumo ±0.5 barra de desviación).
sub _horizontal_zoom {
    my ($self, $delta, $anchor_x) = @_;

    my $total = $self->{market_data}->size();
    return unless $total && $total > 0;
    my $old_offset = $self->{offset};
    my $use_cursor_anchor = defined $anchor_x;

    # 1. Punto de anclaje (índice GLOBAL + X de pantalla) ANTES de cambiar el zoom.
    #    Solo Ctrl+rueda usa ancla de cursor; rueda normal conserva el borde derecho.
    my ($anchor_index, $anchor_screen_x) = $use_cursor_anchor ? $self->_anchor_index_and_x($anchor_x) : $self->_anchor_index_and_x(undef);

    # 2. Nuevo nº de velas visibles, acotado a [MIN_VISIBLE_BARS, total].
    #    (Esto sustituye el antiguo mínimo de 10 por MIN_VISIBLE_BARS = 2.)
    my $new_visible = $self->{visible_bars} + $delta;

    my $max_visible = $total < MAX_VISIBLE_BARS ? $total : MAX_VISIBLE_BARS;
    $new_visible = MIN_VISIBLE_BARS if $new_visible < MIN_VISIBLE_BARS;
    $new_visible = $max_visible     if $new_visible > $max_visible;

    # 3. Aplicar el nuevo zoom.
    $self->{visible_bars} = $new_visible;

    if (!$use_cursor_anchor) {
        if ($old_offset <= 0) {
            $self->{offset} = $self->_clamp_offset($old_offset);
            $self->request_render();
            return;
        }
    }

    # 4. Nueva escala con el nuevo nº de barras. bar_w' = plot_width / new_visible se
    #    deriva dentro de Scales; la inversión X->índice continuo vive en x_to_index_float.
    my $scale = Market::Panels::Scales->new(
        bars         => $new_visible,

        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});

    # 5. Reposicionar el ancla en su X de pantalla previa.
    #    index_to_center_x(local) = (local + 0.5) * bar_w  =>  local = X/bar_w - 0.5.
    #    X/bar_w lo da Scales->x_to_index_float (la división vive en Scales).
    my $local_target = $scale->x_to_index_float($anchor_screen_x) - 0.5;
    my $end_idx      = $anchor_index + ($new_visible - 1 - $local_target);
    my $offset       = ($total - 1) - $end_idx;

    # 6. Offset entero y acotado. compute_window define:
    #      end = total - 1 - offset ; start = end - visible_bars + 1.
    #    El clamp conserva como mínimo MIN_VISIBLE_BARS velas reales en ambos extremos.

    $offset = $self->round($offset);
    $self->{offset} = $self->_clamp_offset($offset);

    if ($use_cursor_anchor) {
        my ($new_start, undef) = $self->compute_window();
        my $new_local = $anchor_index - $new_start;
        $new_local = 0 if $new_local < 0;
        $new_local = $new_visible - 1 if $new_local >= $new_visible;
        $scale->{x_shift} = 0;
        $self->{last_mouse_x} = $self->round($scale->index_to_center_x($new_local));
    }

    # 7. Render diferido (coalescing).
    $self->request_render();
}

sub _start_horizontal_drag {
    my ($self, $widget, $x, $y) = @_;

    $self->_clear_ctrl_zoom_state();
    my $root_x = eval { $widget->pointerx() };
    my $root_y = eval { $widget->pointery() };
    $self->{drag_start_x} = defined $root_x ? $root_x : $x;
    $self->{drag_start_y} = defined $root_y ? $root_y : $y;
    $self->{drag_start_panel} = defined $widget && defined $self->{atr_canvas} && $widget == $self->{atr_canvas} ? 'atr' : 'price';
    $self->{drag_start_offset} = $self->{offset};

    if (defined $widget) {
        $self->_set_cursor($widget, 'fleur');
        $self->{drag_cursor_canvas} = $widget;
    }

    my $price_scale = $self->{price_panel} ? $self->{price_panel}->{scale} : undef;
    $self->{drag_start_min_y} = defined $self->{manual_min_y} ? $self->{manual_min_y} : (defined $price_scale ? $price_scale->{min_y} : undef);
    $self->{drag_start_max_y} = defined $self->{manual_max_y} ? $self->{manual_max_y} : (defined $price_scale ? $price_scale->{max_y} : undef);

    my $atr_scale = $self->{atr_panel} ? $self->{atr_panel}->{scale} : undef;
    $self->{atr_drag_start_min_y} = defined $self->{atr_manual_min_y} ? $self->{atr_manual_min_y} : (defined $atr_scale ? $atr_scale->{min_y} : undef);
    $self->{atr_drag_start_max_y} = defined $self->{atr_manual_max_y} ? $self->{atr_manual_max_y} : (defined $atr_scale ? $atr_scale->{max_y} : undef);
}

sub _on_horizontal_drag {
    my ($self, $widget, $x, $y) = @_;

    $self->_on_mouse_move($widget, $x, $y);
    return unless defined $self->{drag_start_x};
    my $canvas = $self->{price_canvas};
    return unless $canvas;

    my $root_x = eval { $widget->pointerx() };
    my $root_y = eval { $widget->pointery() };
    my $current_x = defined $root_x ? $root_x : $x;
    my $current_y = defined $root_y ? $root_y : $y;
    my $width = $self->_canvas_width($canvas);
    my $scale = Market::Panels::Scales->new(
        bars         => $self->{visible_bars} || 1,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $width;
    my $bar_w = $scale->plot_width() / ($self->{visible_bars} || 1);
    return if $bar_w <= 0;

    my $delta_bars = int(($current_x - $self->{drag_start_x}) / $bar_w);
    $self->{offset} = $self->_clamp_offset($self->{drag_start_offset} + $delta_bars);
    if (($self->{drag_start_panel} || 'price') eq 'atr') {
        $self->_apply_atr_vertical_drag_from_start($current_y);
    } else {
        $self->_apply_vertical_drag_from_start($current_y);
    }
    $self->request_render();
}

sub _on_time_axis_motion {
    my ($self, $widget, $x, $y) = @_;

    return unless defined $x;
    $self->{last_mouse_x} = $self->_snap_crosshair_x($x);
    $self->{last_mouse_y} = undef;
    $self->{active_canvas} = $widget if defined $widget;
    $self->_draw_crosshair_all();
    $self->_draw_pointer_symbol($widget, $x, $y, 'h') if defined $widget && defined $y;
}

sub _start_time_axis_drag {
    my ($self, $widget, $x, $y) = @_;

    $self->_clear_ctrl_zoom_state();
    $self->_set_cursor($widget, 'sb_h_double_arrow');
    my $root_x = eval { $widget->pointerx() };
    $self->{time_axis_drag_start_x} = defined $root_x ? $root_x : $x;
    $self->{time_axis_drag_visible} = $self->{visible_bars};
}

sub _on_time_axis_drag {
    my ($self, $widget, $x, $y) = @_;

    $self->_on_time_axis_motion($widget, $x, $y);
    return unless defined $self->{time_axis_drag_start_x};

    my $root_x = eval { $widget->pointerx() };
    my $current_x = defined $root_x ? $root_x : $x;
    return unless defined $current_x;

    my $total = $self->{market_data}->size();
    return unless $total && $total > 0;

    my $max_visible = $total < MAX_VISIBLE_BARS ? $total : MAX_VISIBLE_BARS;
    my $delta = int(($current_x - $self->{time_axis_drag_start_x}) / TIME_AXIS_DRAG_PX_PER_BAR);
    my $new_visible = ($self->{time_axis_drag_visible} || $self->{visible_bars}) + $delta;
    $new_visible = MIN_VISIBLE_BARS if $new_visible < MIN_VISIBLE_BARS;
    $new_visible = $max_visible     if $new_visible > $max_visible;
    return if $new_visible == $self->{visible_bars};

    $self->_horizontal_zoom($new_visible - $self->{visible_bars}, undef);
}

sub _end_time_axis_drag {
    my ($self) = @_;
    $self->_set_cursor($self->{time_axis_canvas}, 'sb_h_double_arrow');
    $self->{time_axis_drag_start_x} = undef;
    $self->{time_axis_drag_visible} = undef;
}

sub _apply_vertical_drag_from_start {
    my ($self, $current_y) = @_;

    return if $self->{is_auto_scale};
    return unless defined $current_y;
    return unless defined $self->{drag_start_y};
    return unless defined $self->{drag_start_min_y} && defined $self->{drag_start_max_y};

    my $range = $self->{drag_start_max_y} - $self->{drag_start_min_y};
    return if $range <= 0;

    my (undef, $height) = $self->_canvas_size($self->{price_canvas});
    return if $height <= 0;

    my $dy = $current_y - $self->{drag_start_y};
    return if $dy == 0;

    my $delta_value = $dy * ($range / $height);
    $self->{manual_min_y} = $self->{drag_start_min_y} + $delta_value;
    $self->{manual_max_y} = $self->{drag_start_max_y} + $delta_value;
}

sub _apply_atr_vertical_drag_from_start {
    my ($self, $current_y) = @_;

    return if $self->{is_atr_auto_scale};
    return unless defined $current_y;
    return unless defined $self->{drag_start_y};
    return unless defined $self->{atr_drag_start_min_y} && defined $self->{atr_drag_start_max_y};

    my $range = $self->{atr_drag_start_max_y} - $self->{atr_drag_start_min_y};
    return if $range <= 0;

    my (undef, $height) = $self->_canvas_size($self->{atr_canvas});
    return if $height <= 0;

    my $dy = $current_y - $self->{drag_start_y};
    return if $dy == 0;

    my $delta_value = $dy * ($range / $height);
    $self->{atr_manual_min_y} = $self->{atr_drag_start_min_y} + $delta_value;
    $self->{atr_manual_max_y} = $self->{atr_drag_start_max_y} + $delta_value;
}

sub _start_price_axis_drag {
    my ($self, $widget, $y) = @_;

    $self->_clear_ctrl_zoom_state();
    $self->_set_cursor($widget, 'sb_v_double_arrow');
    my $root_y = eval { $widget->pointery() };
    $self->{axis_drag_start_y} = defined $root_y ? $root_y : $y;

    my $scale = $self->{price_panel} ? $self->{price_panel}->{scale} : undef;
    my $min = defined $self->{manual_min_y} ? $self->{manual_min_y} : (defined $scale ? $scale->{min_y} : undef);
    my $max = defined $self->{manual_max_y} ? $self->{manual_max_y} : (defined $scale ? $scale->{max_y} : undef);
    return unless defined $min && defined $max && $max > $min;

    $self->{axis_drag_min_y} = $min;
    $self->{axis_drag_max_y} = $max;
}

sub _on_price_axis_drag {
    my ($self, $widget, $y) = @_;

    return unless defined $self->{axis_drag_start_y};
    return unless defined $self->{axis_drag_min_y} && defined $self->{axis_drag_max_y};

    my $root_y = eval { $widget->pointery() };
    my $current_y = defined $root_y ? $root_y : $y;
    return unless defined $current_y;

    my $dy = $current_y - $self->{axis_drag_start_y};
    my $min = $self->{axis_drag_min_y};
    my $max = $self->{axis_drag_max_y};
    my $center = ($min + $max) / 2;
    my $half = ($max - $min) / 2;

    my $factor = exp($dy / 220);
    $factor = 0.000001 if $factor < 0.000001;
    $half *= $factor;

    $self->{manual_min_y} = $center - $half;
    $self->{manual_max_y} = $center + $half;
    if ($self->{is_auto_scale}) {
        $self->set_scale_mode('manual');
    } else {
        $self->request_render();
    }
}

sub _end_price_axis_drag {
    my ($self) = @_;

    $self->_set_cursor($self->{price_axis_canvas}, 'sb_v_double_arrow');
    $self->{axis_drag_start_y} = undef;
    $self->{axis_drag_min_y} = undef;
    $self->{axis_drag_max_y} = undef;
}

sub _start_atr_axis_drag {
    my ($self, $widget, $y) = @_;

    $self->_clear_ctrl_zoom_state();
    $self->_set_cursor($widget, 'sb_v_double_arrow');
    my $root_y = eval { $widget->pointery() };
    $self->{atr_axis_drag_start_y} = defined $root_y ? $root_y : $y;

    my $scale = $self->{atr_panel} ? $self->{atr_panel}->{scale} : undef;
    my $min = defined $self->{atr_manual_min_y} ? $self->{atr_manual_min_y} : (defined $scale ? $scale->{min_y} : undef);
    my $max = defined $self->{atr_manual_max_y} ? $self->{atr_manual_max_y} : (defined $scale ? $scale->{max_y} : undef);
    return unless defined $min && defined $max && $max > $min;

    $self->{atr_axis_drag_min_y} = $min;
    $self->{atr_axis_drag_max_y} = $max;
}

sub _on_atr_axis_drag {
    my ($self, $widget, $y) = @_;

    return unless defined $self->{atr_axis_drag_start_y};
    return unless defined $self->{atr_axis_drag_min_y} && defined $self->{atr_axis_drag_max_y};

    my $root_y = eval { $widget->pointery() };
    my $current_y = defined $root_y ? $root_y : $y;
    return unless defined $current_y;

    my $dy = $current_y - $self->{atr_axis_drag_start_y};
    my $min = $self->{atr_axis_drag_min_y};
    my $max = $self->{atr_axis_drag_max_y};
    my $center = ($min + $max) / 2;
    my $half = ($max - $min) / 2;

    my $factor = exp($dy / 220);
    $factor = 0.000001 if $factor < 0.000001;
    $half *= $factor;

    $self->{atr_manual_min_y} = $center - $half;
    $self->{atr_manual_max_y} = $center + $half;
    if ($self->{is_atr_auto_scale}) {
        $self->set_atr_scale_mode('manual');
    } else {
        $self->request_render();
    }
}

sub _end_atr_axis_drag {
    my ($self) = @_;

    $self->_set_cursor($self->{atr_axis_canvas}, 'sb_v_double_arrow');
    $self->{atr_axis_drag_start_y} = undef;
    $self->{atr_axis_drag_min_y} = undef;
    $self->{atr_axis_drag_max_y} = undef;
}

sub _reset_atr_scale {
    my ($self) = @_;

    $self->set_atr_scale_mode('auto');
}

sub set_atr_scale_mode {
    my ($self, $mode) = @_;

    return unless defined $mode && ($mode eq 'auto' || $mode eq 'manual');
    if ($mode eq 'auto') {
        $self->{is_atr_auto_scale} = 1;
        $self->{atr_manual_min_y} = undef;
        $self->{atr_manual_max_y} = undef;
    } else {
        $self->{is_atr_auto_scale} = 0;
    }

    if (ref($self->{atr_scale_mode_callback}) eq 'CODE') {
        $self->{atr_scale_mode_callback}->($mode);
    }

    $self->request_render();
}

sub set_scale_mode {
    my ($self, $mode) = @_;

    return unless defined $mode && ($mode eq 'auto' || $mode eq 'manual');

    if ($mode eq 'auto') {
        $self->{is_auto_scale} = 1;
        $self->{manual_min_y} = undef;
        $self->{manual_max_y} = undef;
    } else {
        $self->{is_auto_scale} = 0;
    }

    if (ref($self->{scale_mode_callback}) eq 'CODE') {
        $self->{scale_mode_callback}->($mode);
    }

    $self->request_render();
}

sub _on_resize {
    my ($self, $widget) = @_;

    return if $self->{_resize_pending};
    $self->{_resize_pending} = 1;
    my $canvas = $self->{price_canvas} || $widget;
    if ($canvas) {
        $canvas->after(60, sub {
            $self->{_resize_pending} = 0;
            $self->request_render();
        });
        return;
    }
    $self->{_resize_pending} = 0;
    $self->request_render();
}

sub _end_drag {
    my ($self) = @_;

    if (defined $self->{drag_cursor_canvas}) {
        $self->_set_cursor($self->{drag_cursor_canvas}, 'crosshair');
    }
    $self->{drag_start_x} = undef;
    $self->{drag_start_y} = undef;
    $self->{drag_start_panel} = undef;
    $self->{drag_start_min_y} = undef;
    $self->{drag_start_max_y} = undef;
    $self->{atr_drag_start_min_y} = undef;
    $self->{atr_drag_start_max_y} = undef;
    $self->{drag_cursor_canvas} = undef;
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

sub _atr_vertical_drag {
    my ($self, $dy) = @_;

    return if $self->{is_atr_auto_scale};
    return if !$dy || $dy == 0;

    my $atr_scale = $self->{atr_panel}->{scale};
    return if !defined $atr_scale;

    my $val_at_zero = $atr_scale->y_to_value(0);
    my $val_at_one  = $atr_scale->y_to_value(1);
    my $units_per_pixel = $val_at_zero - $val_at_one;

    my $value_delta = $dy * $units_per_pixel;

    $self->{atr_manual_min_y} += $value_delta;
    $self->{atr_manual_max_y} += $value_delta;

    $self->request_render();
}

sub _atr_vertical_zoom {
    my ($self, $factor) = @_;

    return if $self->{is_atr_auto_scale};
    return if !$factor || $factor <= 0;

    my $min = $self->{atr_manual_min_y};
    my $max = $self->{atr_manual_max_y};
    return if !defined $min || !defined $max;

    my $center = ($min + $max) / 2;
    my $half_range = ($max - $min) / 2;

    $half_range *= $factor;

    $self->{atr_manual_min_y} = $center - $half_range;
    $self->{atr_manual_max_y} = $center + $half_range;

    $self->request_render();
}

sub _snap_crosshair_x {
    my ($self, $raw_x) = @_;

    return undef unless defined $raw_x;
    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    return $self->round($raw_x) if $bars < 1;

    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});
    $scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    my $local = $scale->x_to_index($raw_x);
    return $self->round($scale->index_to_center_x($local));
}

sub _on_mouse_move {
    my ($self, $widget, $raw_x, $raw_y) = @_;
    
    return if !defined $raw_x || !defined $raw_y;
    
    my $pixel_x = $self->_snap_crosshair_x($raw_x);
    my $pixel_y = $self->round($raw_y);
    
    $self->{last_mouse_x} = $pixel_x;
    $self->{last_mouse_y} = $pixel_y;
    $self->{active_canvas} = $widget;
    
    $self->_draw_crosshair_all();
    $self->_draw_pointer_symbol($widget, $pixel_x, $pixel_y, 'cross');
}

# _crosshair_time_label — texto de tiempo (HH:MM) de la vela bajo el cursor (Req. 7.4).
#
# Calcula el índice de dato bajo el cursor a partir de la posición horizontal
# almacenada en $self->{last_mouse_x}. Toda conversión X->índice vive en Scales
# (regla de oro de coordenadas): se instancia un Market::Panels::Scales con los
# mismos parámetros que usan render()/compute_intraday_labels —bars = nº de velas
# visibles (end - start + 1 de compute_window), right_margin => RIGHT_MARGIN y el
# ancho real del canvas de precios— y se usa x_to_index para obtener el índice
# LOCAL dentro de la ventana visible.
#
# El índice LOCAL se convierte a GLOBAL sumando 'start' (inicio de la ventana):
#   global = start + local
# Con ese índice global se obtiene el timestamp de MarketData (get_timestamp), se
# parsea con Time::Moment y se formatea como HH:MM (24h, cero a la izquierda)
# reutilizando el helper YA EXISTENTE _time_label_for_index($tm, 0) (is_date = 0).
#
# Devuelve la cadena 'HH:MM', o undef si:
#   * no hay cursor (last_mouse_x indefinido),
#   * la ventana visible no tiene barras,
#   * el índice global queda fuera del rango real de datos, o
#   * el timestamp no existe / no es parseable por Time::Moment.
sub _crosshair_time_label {
    my ($self) = @_;

    my $last_x = $self->{last_mouse_x};
    return undef unless defined $last_x;          # sin cursor => sin etiqueta

    # Ventana visible en índices GLOBALES; 'start' mapea local -> global.
    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    return undef if $bars < 1;                    # ventana vacía => sin etiqueta

    # Escala SOLO para convertir X -> índice (regla de oro: conversión en Scales).
    # Mismos parámetros que render()/compute_intraday_labels: right_margin reservado
    # y el ancho real del canvas de precios (bar_w = plot_width / bars).
    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});
    $scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;

    # X -> índice LOCAL (acotado por Scales a [0, bars-1]) -> índice GLOBAL.
    my $local  = $scale->x_to_index($last_x);
    my $global = $start + $local;

    # Defensa adicional: el índice global debe caer en el rango real de datos.
    my $size = $self->{market_data}->size();
    return undef if $global < 0 || $global >= $size;

    # Timestamp de MarketData -> Time::Moment -> 'HH:MM' (is_date = 0).
    my $ts = $self->{market_data}->get_timestamp($global);
    return undef unless defined $ts;
    my $tm = eval { Time::Moment->from_string($ts) };
    return undef unless $tm;

    return $self->_time_label_for_index($tm, 0);
}

sub _draw_crosshair_all {
    my ($self) = @_;

    my $last_x = $self->{last_mouse_x};
    my $last_y = $self->{last_mouse_y};

    if (!defined $last_x) {
        # Cursor fuera: limpiar el crosshair y la etiqueta de tiempo en ambos
        # paneles. Contrato acordado con la tarea 6.2 para PricePanel:
        # draw_crosshair($x, $y, $time_text) -> con todo undef se borra también la
        # etiqueta de tiempo. El ATRPanel conserva su firma de 2 argumentos.
        $self->{price_panel}->draw_crosshair(undef, undef, undef);
        $self->{atr_panel}->draw_crosshair(undef, undef);
        $self->_draw_price_axis_crosshair(undef);
        $self->_draw_atr_axis_crosshair(undef);
        return;
    }

    my $price_y = undef;
    my $atr_y = undef;

    if (defined $self->{active_canvas} && defined $self->{time_axis_canvas} && $self->{active_canvas} == $self->{time_axis_canvas}) {
        $price_y = undef;
        $atr_y = undef;
    } elsif (defined $self->{active_canvas} && $self->{active_canvas} == $self->{atr_canvas}) {
        $atr_y = $last_y;
    } else {
        $price_y = $last_y;
    }

    # Etiqueta de tiempo (HH:MM) de la vela bajo el cursor; undef si no aplica.
    my $time_text = $self->_crosshair_time_label();

    # PricePanel recibe la etiqueta de tiempo como TERCER argumento (Req. 7.4):
    # draw_crosshair($x, $y, $time_text). El ATRPanel mantiene su firma de 2
    # argumentos (NO recibe etiqueta de tiempo); la X sigue sincronizada entre
    # ambos paneles porque comparten $last_x.
    $self->{price_panel}->draw_crosshair($last_x, $price_y, $time_text);
    $self->{atr_panel}->draw_crosshair($last_x, $atr_y);
    $self->_draw_price_axis_crosshair($price_y);
    $self->_draw_atr_axis_crosshair($atr_y);
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
    $self->{is_atr_auto_scale} = 1;
    $self->{atr_manual_min_y} = undef;
    $self->{atr_manual_max_y} = undef;
    if (ref($self->{atr_scale_mode_callback}) eq 'CODE') {
        $self->{atr_scale_mode_callback}->('auto');
    }
    $self->_clear_ctrl_zoom_state();
    $self->reset_view();
}

sub reset_view {
    my ($self) = @_;

    $self->{visible_bars} = 60;
    $self->{offset} = 0;
    $self->{is_auto_scale} = 1;
    $self->{manual_min_y} = undef;
    $self->{manual_max_y} = undef;
    $self->{is_atr_auto_scale} = 1;
    $self->{atr_manual_min_y} = undef;
    $self->{atr_manual_max_y} = undef;
    if (ref($self->{atr_scale_mode_callback}) eq 'CODE') {
        $self->{atr_scale_mode_callback}->('auto');
    }
    $self->_clear_ctrl_zoom_state();
    $self->request_render();
}

# compute_intraday_labels — etiquetas del eje de tiempo inferior (Req. 5.2, 5.6, 5.7,
# 5.8, 6.1, 6.2, 6.4).
#
# Produce un arrayref de etiquetas enriquecidas con la forma:
#       { index => <índice LOCAL en la ventana visible>,
#         text  => <'HH:MM' o 'DD Mon'>,
#         is_date => 0|1,
#         grid => 0|1,
#         label => 0|1 }
#
# Convención de índice (CRÍTICA): el `index` de salida es LOCAL (0-based dentro de la
# ventana visible), porque las velas se dibujan con índices locales 0..N-1 y
# PricePanel::draw_time_axis centra cada etiqueta vía Scales->index_to_center_x(index).
# El índice local se obtiene como `global - start`, robusto frente a timestamps
# omitidos (no es la posición del bucle).
#
# Espaciado temporal (Req. 5.6): la cuadrícula usa timestamps reales alineados al
# reloj según una escalera de intervalos. En 1m con intervalo 5, marca :00, :05,
# :10, etc.; nunca fases arbitrarias como :02, :07 por efecto del zoom.
#
# Cambios de día (Req. 6.1, 6.4): en zoom amplio se muestran fechas sobre el mismo
# stride uniforme; no se insertan anclas extra fuera del ritmo para evitar distancias
# visuales irregulares entre líneas verticales.
#
# Casos límite:
#   * Ventana sin barras => lista vacía sin error (Req. 5.7).
#   * Timestamp no parseable => esa etiqueta se omite y continúan las demás (Req. 5.8;
#     get_all_timestamps ya descarta los no parseables).
sub compute_intraday_labels {
    my ($self) = @_;

    my @labels;

    # Elementos visibles: arrayref de { index => <GLOBAL>, ts => <Time::Moment> }.
    # get_all_timestamps ya descarta los timestamps no parseables (Req. 5.8).
    my $visible_elements = $self->get_all_timestamps();
    my $total = scalar(@$visible_elements);
    return \@labels if $total == 0;   # Req. 5.7: ventana sin barras => sin etiquetas.

    # Ventana visible en índices GLOBALES. 'start' permite convertir los índices
    # globales (velas y anclas de tiempo) a LOCALES (los que consume draw_time_axis).
    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    $bars = 1 if $bars < 1;

    # Escala temporal SOLO para medir la separación en píxeles entre etiquetas.
    # Regla de oro: la conversión de coordenadas vive en Scales, así que se
    # instancia Market::Panels::Scales con el mismo right_margin que usa render()
    # y se le inyecta el ancho real del canvas de precios (bar_w = plot_width/bars).
    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});

    # Mapa índice LOCAL => Time::Moment de cada vela visible con timestamp parseable.
    my %tm_by_local;
    for my $el (@$visible_elements) {
        $tm_by_local{ $el->{index} - $start } = $el->{ts};
    }

    my $bar_w = $bars > 0 ? $scale->plot_width() / $bars : 1;
    $bar_w = 1 if $bar_w <= 0;
    my $tf_minutes = $self->_timeframe_minutes();
    my $interval_minutes = $self->_time_axis_interval_minutes($tf_minutes, $bar_w);

    my @items;
    my $date_mode = ($interval_minutes >= 180) ? 1 : 0;
    my $last_day_key;

    for my $el (@$visible_elements) {
        my $global = $el->{index};
        next if $global < $start || $global > $end;
        my $local = $global - $start;
        my $tm = $tm_by_local{$local};
        next unless defined $tm;
        next unless $self->_is_time_axis_boundary($tm, $interval_minutes);

        my $day_key = sprintf('%04d-%02d-%02d', $tm->year, $tm->month, $tm->day_of_month);
        my $is_date = (!defined $last_day_key || $day_key ne $last_day_key) ? 1 : 0;
        my $show_label = $date_mode ? $is_date : 1;
        my $text = $self->_time_label_for_index($tm, $date_mode ? 1 : $is_date);
        next unless defined $text;

        push @items, {
            index   => $local,
            text    => $text,
            is_date => $date_mode ? 1 : $is_date,
            grid    => 1,
            label   => $show_label,
            x       => $scale->index_to_center_x($local),
            w       => length($text) * 7 + 16,
        };
        $last_day_key = $day_key;
    }

    my @label_boxes;
    for my $item (sort { $b->{is_date} <=> $a->{is_date} || $a->{x} <=> $b->{x} } @items) {
        my $left = $item->{x} - $item->{w} / 2;
        my $right = $item->{x} + $item->{w} / 2;
        my $ok = 1;
        for my $box (@label_boxes) {
            if ($left < $box->{right} + 8 && $right > $box->{left} - 8) {
                $ok = 0;
                last;
            }
        }
        $item->{label} = $ok ? 1 : 0;
        push @label_boxes, { left => $left, right => $right } if $ok;
    }

    my $visible_count = 0;
    for my $item (@items) {
        $visible_count++ if $item->{label};
    }
    if ($visible_count == 0 && @items) {
        $items[int(@items / 2)]->{label} = 1;
    }

    for my $item (sort { $a->{index} <=> $b->{index} } @items) {
        push @labels, { index => $item->{index}, text => $item->{text}, is_date => $item->{is_date}, grid => $item->{grid}, label => $item->{label} };
    }

    return \@labels;
}

# _time_label_for_index($tm, $is_date) — formatea el texto de UNA etiqueta del eje
# de tiempo (Req. 5.2, 5.8, 6.4).
#
# Firma elegida: recibe el objeto Time::Moment YA PARSEADO ($tm) y el flag $is_date.
# Se opta por el objeto (en vez del string ISO o el índice) porque
# compute_intraday_labels ya dispone de los Time::Moment construidos por
# get_all_timestamps; así se evita re-parsear y se centraliza la validación.
#
# Formato de salida:
#   * $is_date verdadero => fecha corta "DD Mon": día con dos dígitos (cero a la
#     izquierda) y abreviatura de mes en inglés de 3 letras, p.ej. "18 May".
#   * $is_date falso     => hora "HH:MM" en 24h con cero a la izquierda, rango
#     "00:00".."23:59", p.ej. "09:05".
#
# Devuelve undef si $tm no es un Time::Moment utilizable (timestamp no parseable),
# para que el llamador omita esa etiqueta y continúe con las demás (Req. 5.8).
sub _is_time_axis_boundary {
    my ($self, $tm, $interval_minutes) = @_;

    return 0 unless defined $tm && ref($tm) eq 'Time::Moment';
    return 0 unless defined $interval_minutes && $interval_minutes > 0;

    if ($interval_minutes < 1440) {
        my $minutes = $tm->hour * 60 + $tm->minute;
        return ($minutes % $interval_minutes) == 0 ? 1 : 0;
    }

    return $tm->hour == 0 && $tm->minute == 0 ? 1 : 0;
}

sub _time_axis_interval_minutes {
    my ($self, $tf_minutes, $bar_w) = @_;

    my @ladder = $tf_minutes == 1
        ? (1, 5, 15, 60, 180, 720, 1440)
        : $tf_minutes == 5
            ? (5, 15, 60, 180, 720, 1440)
            : (15, 30, 60, 90, 360, 720, 1440, 2880);
    my $target_px = 100;
    for my $interval (@ladder) {
        my $px = ($interval / $tf_minutes) * $bar_w;
        return $interval if $px >= $target_px;
    }
    return $ladder[-1];
}

sub _time_label_for_index {
    my ($self, $tm, $is_date) = @_;

    return undef unless defined $tm && ref($tm) eq 'Time::Moment';

    if ($is_date) {
        my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
        my $mon = $months[ $tm->month - 1 ];
        return undef unless defined $mon;          # mes fuera de rango (defensivo)
        return sprintf("%02d %s", $tm->day_of_month, $mon);
    }

    return sprintf("%02d:%02d", $tm->hour, $tm->minute);
}

sub get_all_timestamps {
    my ($self) = @_;

    my ($start, $end) = $self->compute_window();
    my @timestamps;
    my $last_index = eval { $self->{market_data}->last_index() };
    $last_index = ($self->{market_data}->size() || 0) - 1 if !defined $last_index;
    my $last_ts = $last_index >= 0 ? $self->{market_data}->get_timestamp($last_index) : undef;
    my $last_tm = defined $last_ts ? eval { Time::Moment->from_string($last_ts) } : undef;
    my $tf_minutes = $self->_timeframe_minutes();

    for (my $i = $start; $i <= $end; $i++) {
        my $ts = ($i >= 0 && $i <= $last_index) ? $self->{market_data}->get_timestamp($i) : undef;
        if (defined $ts) {
            my $parsed = eval { Time::Moment->from_string($ts) };
            push @timestamps, { index => $i, ts => $parsed } if $parsed;
        }
        elsif (defined $last_tm && $i > $last_index) {
            my $future = eval { $last_tm->plus_minutes(($i - $last_index) * $tf_minutes) };
            push @timestamps, { index => $i, ts => $future } if $future;
        }
    }

    return \@timestamps;

}

sub _timeframe_minutes {
    my ($self) = @_;

    my $tf = eval { $self->{market_data}->{active_tf} } || '1m';
    return 5  if $tf eq '5m';
    return 15 if $tf eq '15m';
    return 1;
}
1;
