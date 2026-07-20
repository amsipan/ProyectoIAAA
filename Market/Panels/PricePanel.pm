package Market::Panels::PricePanel;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        %args,
    };
    # El tema (paleta clara) se inyecta vía `theme => \%theme` desde ChartEngine.
    # Garantizar robustez: si no llega, dejar un hashref vacío para que las lecturas
    # posteriores (con defaults //) sean seguras.
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
# Recibe arrayref de velas [ts, open, high, low, close, vol].
# Devuelve (min_price, max_price) con un padding del 5%.
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

# set_run_candles(\%map) — task 0058: mapa global { index => run_dir } para recoloreo RUN.
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
# Inyecta width/height del canvas en el objeto scale antes de usarlo.
# Guarda la última vela en $self->{_last_candle} para render_last_visible_price.
sub render {
    my ($self, $canvas, $data, $scale) = @_;

    my ($canvas_w, $canvas_h) = $self->_canvas_size($canvas);
    $canvas->delete('all');

    return if !$data || !@$data;

    # ChartEngine puede inyectar un ancho compartido para sincronizar X con ATR.
    $scale->{width}  ||= $canvas_w;
    $scale->{height} = $canvas_h;

    # spec 0000i: overscan. draw_start_offset permite que el slice de dibujo
    # incluya velas extra (start-1, end+1). Los índices locales negativos o
    # >= visible_count posicionan las velas overscan correctamente.
    my $draw_offset = $scale->{draw_start_offset} || 0;
    my $visible_count = $scale->{visible_count} || scalar(@$data);

    # Guardar la última vela VISIBLE (no overscan) para render_last_visible_price.
    # El último elemento visible en el slice está en índice -draw_offset + visible_count - 1.
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

        for (my $i = 0; $i < $total; $i++) {
            next if defined $replay_max && ($slice_base + $i) > $replay_max;
            my $candle = $data->[$i];
            next unless defined $candle;

            my ($ts, $open, $high, $low, $close, $vol) = @$candle;

            my $cx  = $scale->index_to_center_x($i + $draw_offset);
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

            $canvas->createRectangle(
                $cx - $half, $top,
                $cx + $half, $bottom,
                -fill    => $body_color,
                -outline => $body_color,
                -tags    => 'candle',
            );
        }
    }

    # Inyectar colores de eje del tema en la escala antes de dibujar el eje Y.
    # La conversión datos↔píxeles sigue viviendo en Scales; aquí solo se le pasan
    # los colores claros (con defaults seguros si el tema no está disponible).
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
#
# Dibuja:
#   1. Línea horizontal entrecortada a todo el ancho del plot, a la altura del
#      close de la última vela visible, con el color del precio actual
#      (verde alcista / rojo bajista). Recorre todo el gráfico.
#   2. La cajita de precio en el margen derecho del plot, SOLO si no hay
#      price_axis_canvas separado (draw_last_label=1). Con eje separado, la
#      cajita vive en ChartEngine::_render_price_axis (tag axis_last_price).
#
# En Replay, $self->{_last_candle} es la última vela causal (replay_idx), así
# que la línea sigue al precio del replay sin fuga de futuro.
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

    # 1. Línea horizontal entrecortada full-width al nivel del precio actual.
    $canvas->createLine(
        0, $y, $w, $y,
        -fill  => $line_color,
        -dash  => $self->{theme}{last_price_dash} // [ 2, 3 ],
        -width => 1,
        -tags  => 'price_label',
    );

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
#
# Firma (contrato acordado con ChartEngine::_draw_crosshair_all, tarea 6.1):
#     draw_crosshair($x, $y, $time_text)
#   * $x         : coordenada X de pantalla del cursor. Si es undef, se borra TODO el
#                  crosshair (líneas + etiquetas, incluida la de tiempo) y se retorna.
#   * $y         : coordenada Y de pantalla. Si es undef, el cursor no está sobre este
#                  panel: se dibuja solo la línea vertical (sin línea/etiqueta de valor).
#   * $time_text : cadena ya formateada con el tiempo bajo el cursor (p.ej. "09:15" o
#                  "18 May"), o undef si no hay etiqueta de tiempo que mostrar.
#
# La coordenada X es compartida con el ATRPanel para sincronización temporal (Req. 7.1).
# Comportamiento (Req. 7.1, 7.2, 7.4, 7.5):
#   * Línea vertical punteada en $x a lo alto del canvas.
#   * Si $y definido: línea horizontal punteada + cajita de valor en el eje derecho con
#     el precio obtenido vía scale->y_to_value($y).
#   * Si $time_text definido: cajita oscura con el texto de tiempo centrada en $x dentro
#     de la banda inferior (alineada al borde inferior), bajo la línea vertical.
#
# Colores tomados del tema claro en $self->{theme}, con defaults seguros vía // por si la
# clave no está definida (no se hardcodean colores del tema oscuro):
#   * crosshair_line (líneas)            -> '#9598a1'
#   * label_bg / label_fg (cajitas)      -> '#363a45' / '#ffffff'
# Todo se etiqueta con el tag 'price_crosshair' para borrarse junto al resto.
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
    # Se dibuja una cajita oscura con el texto de tiempo alineada al borde inferior,
    # bajo la línea vertical del crosshair.
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

# draw_time_crosshair_label($canvas, $x, $time_text) — spec 0000d:
# Dibuja la caja negra con la etiqueta de tiempo del crosshair sobre el
# canvas del eje temporal (time_axis_canvas), centrada verticalmente en
# ese canvas y con clamp horizontal para no salirse por izquierda/derecha.
# Reemplaza la caja que antes se dibujaba al fondo del price_canvas.
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
#
# Entrada: arrayref de etiquetas enriquecidas producidas por
# ChartEngine::compute_intraday_labels, cada una con la forma:
#     { index   => <índice LOCAL 0-based en la ventana visible>,
#       text    => <'HH:MM' o 'DD Mon', ya formateado por ChartEngine>,
#       is_date => 0|1 }
#
# Reglas (Req. 5.1, 5.3, 5.4, 6.1, 6.2):
#   * La banda inferior ocupa el ANCHO COMPLETO del canvas y las etiquetas quedan
#     centradas verticalmente dentro del eje temporal compacto.
#   * Cada etiqueta se centra en scale->index_to_center_x(index) (tolerancia 1 px). El
#     index es LOCAL; la X NO se calcula a mano (regla de oro: coordenadas solo en
#     Scales), de modo que las etiquetas siguen a su barra ante scroll/zoom.
#   * El texto ya viene resuelto desde ChartEngine; aquí solo se dibuja $item->{text}
#     (no se reformatea). El texto de fecha "DD Mon" es más ancho y se centra con el
#     anchor 's' para que quede legible sobre su barra.
#   * Grid vertical (hora o fecha): mismo estilo TradingView que el horizontal —
#     punteado fino (casi puntos), width=1, color `grid`. Día/mes NO se engrosan
#     ni se oscurecen (a diferencia del antiguo date_grid sólido).
#   * Etiquetas de fecha (is_date=1): solo el TEXTO en negrita; la línea es idéntica.
#   * Crosshair (PricePanel::draw_crosshair) usa dash [4,4] y gris más oscuro
#     para no confundirse con el grid.
#
# Colores tomados del tema claro almacenado en $self->{theme}, con defaults seguros
# vía // por si el tema no define la clave (no se hardcodean colores del tema oscuro).
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

    # Mismo gris tenue para TODAS las verticales (día = hora).
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
        # spec 0000d: no dibujar grid si el label quedó oculto por thinning.
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
