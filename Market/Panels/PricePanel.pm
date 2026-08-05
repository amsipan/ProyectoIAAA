package Market::Panels::PricePanel;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        %args,
        show_last_price_line => exists $args{show_last_price_line}
          ? ( $args{show_last_price_line} ? 1 : 0 )
          : 0,
    };
    # El tema (paleta clara) se inyecta vía `theme > \%theme` desde ChartEngine.
    $self->{theme} = {} unless defined $self->{theme};
    bless $self, $class;
    return $self;
}

# Inicializa los IDs de los objetos Tk del crosshair en undef.
sub _init_crosshair_objects {
    my ($self) = @_;
    $self->{_ch_vline}    = undef;
    $self->{_ch_hline}    = undef;
    $self->{_ch_label}    = undef;
    $self->{_ch_label_bg} = undef;
}

# Redondeo auxiliar al entero más cercano.
sub round {
    my ($self, $value) = @_;
    return 0 unless defined $value;
    return int($value + ($value >= 0 ? 0.5 : -0.5));
}

sub _canvas_size {
    my ($self, $canvas) = @_;
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

# Calcula el rango de precios (min, max) de las velas visibles para escalar el eje Y.
sub get_y_range {
    my ($self, $data) = @_;
    return (20000, 30000) if !$data || !@$data;

    my @defined = grep { defined $_ } @$data;
    return (20000, 30000) unless @defined;

    my $min = $defined[0]->[3];
    my $max = $defined[0]->[2];

    for my $candle (@defined) {
        $min = $candle->[3] if $candle->[3] < $min;
        $max = $candle->[2] if $candle->[2] > $max;
    }

    my $padding = ($max - $min) * 0.05 || 1;
    return ($min - $padding, $max + $padding);
}

# Asigna el objeto Scales a este panel.
sub set_scale {
    my ($self, $scale) = @_;
    $self->{scale} = $scale;
}

# set_run_candles(\%map) mapa global { index > run_dir } para recoloreo RUN.
sub set_run_candles {
    my ($self, $map) = @_;
    $self->{_run_candles} = (ref($map) eq 'HASH') ? $map : {};
    return $self;
}

sub _global_index_is_run {
    my ($self, $global_idx) = @_;
    my $run = $self->{_run_candles};
    return 0 unless $run && ref $run eq 'HASH';
    return exists $run->{$global_idx} ? 1 : 0;
}

sub _candle_colors {
    my ($self, $open, $close, $global_idx) = @_;
    if ($self->_global_index_is_run($global_idx)) {
        my $dir = $self->{_run_candles}{$global_idx};
        my $body = (defined $dir && $dir eq 'up')
            ? ($self->{theme}{run_bull} // '#7b1fa2')
            : (defined $dir && $dir eq 'down')
                ? ($self->{theme}{run_bear} // '#ff6d00')
                : ($close >= $open)
                    ? ($self->{theme}{run_bull} // '#7b1fa2')
                    : ($self->{theme}{run_bear} // '#ff6d00');
        my $wick = $self->{theme}{run_wick} // '#4a148c';
        return ($body, $wick);
    }
    my $color = ($close >= $open)
        ? ($self->{theme}{bull} // '#26a69a')
        : ($self->{theme}{bear} // '#ef5350');
    return ($color, $color);
}

# Dibuja todas las velas japonesas visibles sobre el canvas Tk.
sub render {
    my ($self, $canvas, $data, $scale) = @_;

    my ($canvas_w, $canvas_h) = $self->_canvas_size($canvas);
    $canvas->delete('all');

    return if !$data || !@$data;

    # ChartEngine puede inyectar un ancho compartido para sincronizar X con ATR.
    $scale->{width}  ||= $canvas_w;
    $scale->{height} = $canvas_h;

    # overscan. draw_start_offset permite que el slice de dibujo
    my $draw_offset = $scale->{draw_start_offset} || 0;
    my $visible_count = $scale->{visible_count} || scalar(@$data);

    # Guardar la última vela VISIBLE (no overscan) para render_last_visible_price.
    $self->{_last_candle} = undef;
    my $last_vis_idx = -$draw_offset + $visible_count - 1;
    $last_vis_idx = $#$data if $last_vis_idx > $#$data;
    $last_vis_idx = $#$data if $last_vis_idx < 0;
    for (my $i = $last_vis_idx; $i >= 0; $i--) {
        if (defined $data->[$i]) {
            $self->{_last_candle} = $data->[$i];
            last;
        }
    }
    if (defined $scale->{replay_head_candle}) {
        $self->{_last_candle} = $scale->{replay_head_candle};
    }

    my $total  = scalar(@$data);
    my $slice_base = $scale->{slice_base_index} // 0;
    my $replay_max = $scale->{replay_max_index};
    my $x_bars = $scale->{bars} || $total || 1;
    my $bar_w  = ($x_bars > 0) ? ($scale->plot_width() / $x_bars) : 1;

    if ($bar_w < 2) {
        my $plot_w = int($scale->plot_width());
        $plot_w = 1 if $plot_w < 1;
        for my $px (0 .. $plot_w - 1) {
            # Invertir la MISMA escala usada por grid/overlays; respeta x_shift.
            my ($from_local, $to_local) = $scale->local_range_for_pixel($px);
            my $from = $from_local - $draw_offset;
            my $to = $to_local - $draw_offset;
            $to = $from if $to < $from;
            $to = $total - 1 if $to >= $total;
            $from = 0 if $from < 0;

            my ($open, $high, $low, $close);
            my $run_ref_idx;
            for my $i ($from .. $to) {
                next if defined $replay_max && ($slice_base + $i) > $replay_max;
                my $candle = $data->[$i];
                next unless defined $candle;
                my $gidx = $slice_base + $i;
                $run_ref_idx = $gidx if !defined $run_ref_idx && $self->_global_index_is_run($gidx);
                $open = $candle->[1] if !defined $open;
                $high = $candle->[2] if !defined $high || $candle->[2] > $high;
                $low = $candle->[3] if !defined $low || $candle->[3] < $low;
                $close = $candle->[4];
            }
            next unless defined $open && defined $close;

            my $y_h = $scale->value_to_y($high);
            my $y_l = $scale->value_to_y($low);
            my ($body_color, $wick_color) = defined $run_ref_idx
                ? $self->_candle_colors($open, $close, $run_ref_idx)
                : $self->_candle_colors($open, $close, -1);
            $canvas->createLine($px + 0.5, $y_h, $px + 0.5, $y_l, -fill => $wick_color, -width => 1, -tags => 'candle');
        }
    } else {
        my $body_w = $bar_w * 0.6;
        $body_w = 1 if $body_w < 1;
        $body_w = $bar_w if $body_w > $bar_w;
        my $half   = $body_w / 2;
        # El canvas incluye right_margin; el overscan derecho cae en esa franja
        my $plot_w = $scale->plot_width();

        for (my $i = 0; $i < $total; $i++) {
            next if defined $replay_max && ($slice_base + $i) > $replay_max;
            my $candle = $data->[$i];
            next unless defined $candle;

            my ($ts, $open, $high, $low, $close, $vol) = @$candle;

            my $cx  = $scale->index_to_center_x($i + $draw_offset);
            # Fuera del plot (overscan derecho en el margen, o pan extremo).
            next if $cx >= $plot_w || $cx < 0;

            my $y_o = $scale->value_to_y($open);
            my $y_h = $scale->value_to_y($high);
            my $y_l = $scale->value_to_y($low);
            my $y_c = $scale->value_to_y($close);

            my $global_idx = $slice_base + $i;
            my ($body_color, $wick_color) = $self->_candle_colors($open, $close, $global_idx);

            $canvas->createLine(
                $cx, $y_h, $cx, $y_l,
                -fill  => $wick_color,
                -width => 1,
                -tags  => 'candle',
            );

            my $top    = ($y_o < $y_c) ? $y_o : $y_c;
            my $bottom = ($y_o > $y_c) ? $y_o : $y_c;
            $bottom = $top + 1 if ($bottom - $top) < 1;

            my $left  = $cx - $half;
            my $right = $cx + $half;
            $left  = 0 if $left < 0;
            $right = $plot_w if $right > $plot_w;
            next if $right <= $left;

            $canvas->createRectangle(
                $left, $top,
                $right, $bottom,
                -fill    => $body_color,
                -outline => $body_color,
                -tags    => 'candle',
            );
        }
    }

    # Inyectar colores de eje del tema en la escala antes de dibujar el eje Y.
    $scale->{grid_color}      = $self->{theme}{grid}      // '#d4d8de';
    $scale->{axis_text_color} = $self->{theme}{axis_text} // '#363a45';
    $scale->{grid_dash}       = $self->{theme}{grid_dash}  // [ 2, 3 ];
    $scale->{grid_width}      = $self->{theme}{grid_width} // 2;

    $scale->_draw_y_scale($canvas);
    $canvas->lower('y_grid');
    $canvas->raise('candle');
    $self->render_last_visible_price($canvas);
}

# Precio de cierre de la última vela visible.
sub render_last_visible_price {
    my ($self, $canvas) = @_;

    $canvas->delete('price_label');
    my $scale = $self->{scale};
    return unless defined $scale && defined $self->{_last_candle};

    my ($open, $close) = @{$self->{_last_candle}}[1, 4];
    return unless defined $close;

    my $y     = $scale->value_to_y($close);
    my $w     = $scale->{width};
    my $label = sprintf("%.2f", $close);
    my $line_color = (defined $open && $close >= $open)
        ? ($self->{theme}{bull} // '#26a69a')
        : ($self->{theme}{bear} // '#ef5350');
    my $label_bg   = $line_color;
    my $label_fg   = $self->{theme}{last_price_fg} // '#ffffff';

    # 1. Línea horizontal entrecortada full width al nivel del precio actual.
    if ( $self->{show_last_price_line} ) {
        $canvas->createLine(
            0, $y, $w, $y,
            -fill  => $line_color,
            -dash  => $self->{theme}{last_price_dash} // [ 2, 3 ],
            -width => 1,
            -tags  => 'price_label',
        );
    }

    # 2. Eje de precios separado: la cajita vive ahí; el plot solo lleva la hline.
    return if exists $scale->{draw_last_label} && !$scale->{draw_last_label};

    $canvas->createRectangle(
        $w - 68, $y - 7, $w, $y + 7,
        -fill    => $label_bg,
        -outline => $line_color,
        -tags    => 'price_label',
    );
    $canvas->createText(
        $w - 66, $y,
        -text   => $label,
        -anchor => 'w',
        -font   => 'Helvetica 9 bold',
        -fill   => $label_fg,
        -tags   => 'price_label',
    );
}

# Dibuja el crosshair en este panel y sus etiquetas (valor + tiempo).
sub draw_crosshair {
    my ($self, $x, $y, $time_text) = @_;

    my $canvas = $self->{canvas};
    return unless defined $canvas;

    $canvas->delete('price_crosshair');
    return unless defined $x;

    my ($w, $h) = $self->_canvas_size($canvas);
    my $scale = $self->{scale};

    # Colores del tema con defaults seguros (tema claro).
    my $line_color  = $self->{theme}{crosshair_line} // '#9598a1';
    my $label_bg    = $self->{theme}{label_bg}        // '#363a45';
    my $label_fg    = $self->{theme}{label_fg}        // '#ffffff';

    # Crosshair: largo de trazo [6,5] y color del tema; width fino (grid es width 2).
    my $ch_dash  = $self->{theme}{crosshair_dash}  // [ 6, 5 ];
    my $ch_width = $self->{theme}{crosshair_width} // 1;

    # Línea vertical (sincronizada con ATRPanel)
    $canvas->createLine(
        $x, 0, $x, $h,
        -fill  => $line_color,
        -dash  => $ch_dash,
        -width => $ch_width,
        -tags  => 'price_crosshair',
    );

    # Línea horizontal y etiqueta de precio bajo el cursor
    if (defined $y) {
        $canvas->createLine(
            0, $y, $w, $y,
            -fill  => $line_color,
            -dash  => $ch_dash,
            -width => $ch_width,
            -tags  => 'price_crosshair',
        );

        if (defined $scale && (!exists $scale->{draw_crosshair_label} || $scale->{draw_crosshair_label})) {
            my $value = $scale->y_to_value($y);
            my $label = sprintf("%.2f", $value);

            $canvas->createRectangle(
                $w - 68, $y - 7, $w, $y + 7,
                -fill    => $label_bg,
                -outline => $line_color,
                -tags    => 'price_crosshair',
            );
            $canvas->createText(
                $w - 66, $y,
                -text   => $label,
                -anchor => 'w',
                -font   => 'Helvetica 9 bold',
                -fill   => $label_fg,
                -tags   => 'price_crosshair',
            );
        }
    }

    # Etiqueta de tiempo en la banda inferior, centrada en $x (Req. 7.4).
    if (defined $time_text && length $time_text) {
        my $box_h     = 16;                 # alto de la cajita de tiempo
        my $char_w    = 7;                  # ancho aproximado por carácter (Helvetica 9 bold)
        my $pad_x     = 6;                  # padding horizontal a cada lado del texto
        my $half_w    = (length($time_text) * $char_w) / 2 + $pad_x;

        # Centro horizontal de la cajita: $x, ajustado para no salirse de los bordes.
        my $cx = $x;
        $cx = $half_w        if $cx - $half_w < 0;
        $cx = $w - $half_w   if $cx + $half_w > $w;

        my $top    = $h - $box_h;
        my $bottom = $h;

        $canvas->createRectangle(
            $cx - $half_w, $top, $cx + $half_w, $bottom,
            -fill    => $label_bg,
            -outline => $line_color,
            -tags    => 'price_crosshair',
        );
        $canvas->createText(
            $cx, $top + $box_h / 2,
            -text   => $time_text,
            -anchor => 'center',
            -font   => 'Helvetica 9 bold',
            -fill   => $label_fg,
            -tags   => 'price_crosshair',
        );
    }
}

# draw_time_crosshair_label($canvas, $x, $time_text)
sub draw_time_crosshair_label {
    my ($self, $canvas, $x, $time_text) = @_;

    return unless defined $canvas;
    $canvas->delete('time_axis_crosshair');
    return unless defined $x && defined $time_text && length $time_text;

    my ($w, $h) = $self->_canvas_size($canvas);

    my $line_color = $self->{theme}{crosshair_line} // '#9598a1';
    my $label_bg   = $self->{theme}{label_bg}        // '#363a45';
    my $label_fg   = $self->{theme}{label_fg}        // '#ffffff';

    my $char_w = 7;
    my $pad_x  = 6;
    my $half_w = (length($time_text) * $char_w) / 2 + $pad_x;

    my $cx = $x;
    $cx = $half_w      if $cx - $half_w < 0;
    $cx = $w - $half_w if $cx + $half_w > $w;

    $canvas->createRectangle(
        $cx - $half_w, 0, $cx + $half_w, $h,
        -fill    => $label_bg,
        -outline => $line_color,
        -tags    => 'time_axis_crosshair',
    );
    $canvas->createText(
        $cx, $h / 2,
        -text   => $time_text,
        -anchor => 'center',
        -font   => 'Helvetica 9 bold',
        -fill   => $label_fg,
        -tags   => 'time_axis_crosshair',
    );
}

# Dibuja las etiquetas del eje de tiempo en la banda inferior del panel de precios.
sub draw_time_axis {
    my ($self, $canvas, $labels, $opts) = @_;

    $canvas->delete('time_axis');
    return unless $labels && @$labels;

    $opts ||= {};
    my $draw_grid   = exists $opts->{draw_grid}   ? $opts->{draw_grid}   : 1;
    my $draw_labels = exists $opts->{draw_labels} ? $opts->{draw_labels} : 1;

    my $scale = $self->{scale};
    return unless defined $scale;

    my ($w, $h) = $self->_canvas_size($canvas);
    my $label_y = int($h / 2 + 0.5);

    # Mismo gris tenue para TODAS las verticales (día hora).
    my $grid_color = $self->{theme}{grid}      // '#d4d8de';
    my $text_color = $self->{theme}{axis_text} // '#363a45';
    my $grid_dash  = $self->{theme}{grid_dash}  // [ 2, 3 ];
    my $grid_width = $self->{theme}{grid_width} // 2;

    for my $item (@$labels) {
        my $idx        = $item->{index};
        my $text       = $item->{text};
        my $is_date    = $item->{is_date} ? 1 : 0;
        my $item_grid  = exists $item->{grid}  ? $item->{grid}  : 1;
        my $item_label = exists $item->{label} ? $item->{label} : 1;
        next unless defined $idx && defined $text;

        # Centro de la barra anclada: única fuente de coordenadas (Scales).
        my $x = $scale->index_to_center_x($idx);

        # Grid vertical unificado (TV): punteado fino, sin énfasis por día/mes.
        if ( $draw_grid && $item_grid && $item_label ) {
            $canvas->createLine(
                $x, 0, $x, $h,
                -fill  => $grid_color,
                -width => $grid_width,
                -dash  => $grid_dash,
                -tags  => [ 'time_axis', 'time_grid' ],
            );
        }

        next unless $draw_labels && $item_label;

        if ($is_date) {
            $canvas->createText(
                $x, $label_y,
                -text   => $text,
                -anchor => 'center',
                -font   => 'Helvetica 8 bold',
                -fill   => $text_color,
                -tags   => 'time_axis',
            );
        }
        else {
            $canvas->createText(
                $x, $label_y,
                -text   => $text,
                -anchor => 'center',
                -font   => 'Helvetica 8',
                -fill   => $text_color,
                -tags   => 'time_axis',
            );
        }
    }

    $canvas->lower('time_grid') if $draw_grid;
}

1;
