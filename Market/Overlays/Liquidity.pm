package Market::Overlays::Liquidity;
use strict;
use warnings;

# =============================================================================
# Market::Overlays::Liquidity — render de estructuras de liquidez
# (spec 0005 / task 0012 — Tabla 2 del PDF)
# =============================================================================
#
# Capa de RENDER sobre el Canvas. Consume el indicador de cálculo
# Market::Indicators::Liquidity (NO calcula nada) y dibuja, según la Tabla 2:
#
#   | Elemento    | Estilo                          | Color        | Etiqueta    |
#   |-------------|---------------------------------|--------------|-------------|
#   | BSL         | horizontal discontinua/punteada | Rojo         | BSL         |
#   | SSL         | horizontal discontinua/punteada | Verde        | SSL         |
#   | EQH         | línea que conecta los máximos   | Configurable | EQH         |
#   | EQL         | línea que conecta los mínimos   | Configurable | EQL         |
#   | Sweep Up    | marcador / línea de quiebre     | Rojo         | SWEEP ↑     |
#   | Sweep Down  | marcador / línea de quiebre     | Verde        | SWEEP ↓     |
#   | Liquidity Grab | destacado de rechazo rápido  | Naranja      | LQ GRAB     |
#   | Liquidity Run  | extensión de ruptura        | Azul         | LQ RUN      |
#
# CONTRATO DE OVERLAY (task 0003 / Overlays::Base):
#   new(%args)         — recibe `indicator` (Indicators::Liquidity), `theme` opcional.
#   set_visible($bool) — activa/desactiva TODO el overlay.
#   is_visible         — bool.
#   compute_visible($market_data, $indicator, $start, $end) — pide al indicador
#                        los niveles/eventos de la ventana [start, end] y los
#                        filtra por index <= end (respeta replay_idx).
#   draw($canvas, $scales) — dibuja en el Canvas usando Scales.
#   clear($canvas)     — borra sus ítems del Canvas (tag `ov_liq`).
#   tag                — retorna el tag namespaced (`ov_liq`).
#
# TOGGLES INDIVIDUALES: set_element_visible($element, $bool) activa/desactiva
# una familia concreta. $element ∈ {BSL, SSL, EQH, EQL, SWEEP, GRAB, RUN}.
# SWEEP agrupa SWEEP_UP y SWEEP_DOWN. EQH/EQL usan colores configurables vía
# tema (claves `liq_eqh`, `liq_eql`).
#
# TAGS DE CANVAS: todo lo que dibuja lleva el tag `ov_liq`, de forma que
# clear($canvas) lo elimina sin tocar a otros overlays ni a las velas.
# =============================================================================

# Familias de elementos dibujables y su mapeo de tipos del contrato.
my %ELEMENT_TYPES = (
    BSL    => [qw(BSL)],
    SSL    => [qw(SSL)],
    EQH    => [qw(EQH)],
    EQL    => [qw(EQL)],
    # ORDEN 6 (task 0021 G): EQH/EQL internos con texto literal I-EQH/I-EQL.
    # Se controlan con el mismo toggle EQH/EQL (comparten familia visual) pero
    # se dibujan con etiqueta y estilo internos.
    SWEEP  => [qw(SWEEP_UP SWEEP_DOWN)],
    GRAB   => [qw(GRAB)],
    RUN    => [qw(RUN)],
);

sub new {
    my ($class, %args) = @_;
    die "Overlays::Liquidity->new: requiere 'indicator' (Indicators::Liquidity)"
        unless defined $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 1,
        # Toggles individuales por familia (todos visibles por defecto).
        _elem_visible => { map { $_ => 1 } keys %ELEMENT_TYPES },
        # Items visibles, separados por familia para draw().
        _levels => [],
        _events => [],
        _compute_range => undef,
        _replay_idx    => undef,
        # ORDEN 4 (task 0021 F): mostrar solo tomas relevantes (magnitud >=
        # factor*ATR, marcadas por el indicador). Por defecto ON para reducir el
        # aglomeramiento (5000 eventos en 1m). Se puede apagar via set_only_relevant.
        _only_relevant => exists $args{only_relevant} ? ($args{only_relevant} ? 1 : 0) : 1,
        # ORDEN 7 (task 0021 H): los EQH/EQL mas largos horizontalmente (mas velas
        # entre los dos pivotes) son mas importantes; los cortos dan menos info.
        #   - eqhl_min_span: pares con span < N velas NO se dibujan. Default 0
        #     (sin filtro: el profe pidio RESALTAR los largos, no ocultar cortos;
        #     el filtro queda opt-in para quien quiera limpiar mas la vista).
        #   - eqhl_long_span: pares con span >= N velas se resaltan (linea gruesa).
        _eqhl_min_span  => exists $args{eqhl_min_span}  ? $args{eqhl_min_span}  : 0,
        _eqhl_long_span => exists $args{eqhl_long_span} ? $args{eqhl_long_span} : 20,
        # task 0027: agrupar BSL/SSL cercanos en banda sombreada.
        _band_mode => exists $args{band_mode} ? ($args{band_mode} ? 1 : 0) : 1,
        _band_atr  => defined $args{band_atr} ? $args{band_atr} : 0.5,
        # task 0062: densidad de render (1–100%). Solo filtra al dibujar; 100% = sin cambio.
        _density_pct => exists $args{density_pct} ? _clamp_density_pct($args{density_pct}) : 100,
        _draw_end_idx => 0,
    };
    bless $self, $class;
    return $self;
}

# set_only_relevant($bool) — activar/desactivar el filtro de relevancia (ORDEN 4).
sub set_only_relevant {
    my ($self, $bool) = @_;
    $self->{_only_relevant} = $bool ? 1 : 0;
    return $self;
}

# set_eqhl_span($min, $long) — umbrales de longitud EQH/EQL (ORDEN 7).
sub set_eqhl_span {
    my ($self, $min, $long) = @_;
    $self->{_eqhl_min_span}  = $min  if defined $min;
    $self->{_eqhl_long_span} = $long if defined $long;
    return $self;
}

# set_band_mode($bool) — bandas sombreadas BSL/SSL vs líneas sueltas (task 0027).
sub set_band_mode {
    my ($self, $bool) = @_;
    $self->{_band_mode} = $bool ? 1 : 0;
    return $self;
}

sub band_mode {
    my ($self) = @_;
    return $self->{_band_mode} ? 1 : 0;
}

sub _clamp_density_pct {
    my ($pct) = @_;
    return 100 unless defined $pct;
    $pct = int($pct + ($pct >= 0 ? 0.5 : -0.5));
    return 1   if $pct < 1;
    return 100 if $pct > 100;
    return $pct;
}

# set_density_pct($pct) — control de densidad de etiquetas en render (task 0062).
sub set_density_pct {
    my ($self, $pct) = @_;
    $self->{_density_pct} = _clamp_density_pct($pct);
    return $self;
}

sub density_pct {
    my ($self) = @_;
    return $self->{_density_pct} // 100;
}

sub tag { 'ov_liq' }

sub set_visible {
    my ($self, $bool) = @_;
    $self->{visible} = $bool ? 1 : 0;
    return $self;
}

sub is_visible {
    my ($self) = @_;
    return $self->{visible};
}

# set_element_visible($element, $bool) — toggle individual de una familia.
sub set_element_visible {
    my ($self, $element, $bool) = @_;
    return $self unless defined $element && exists $ELEMENT_TYPES{$element};
    $self->{_elem_visible}{$element} = $bool ? 1 : 0;
    return $self;
}

# is_element_visible($element) — bool de visibilidad de una familia.
sub is_element_visible {
    my ($self, $element) = @_;
    return 0 unless defined $element && exists $ELEMENT_TYPES{$element};
    return $self->{_elem_visible}{$element};
}

# compute_visible($market_data, $indicator, $start, $end)
#
# Pide al indicador los niveles (BSL/SSL/EQH/EQL) y eventos (SWEEP/GRAB/RUN) ya
# calculados y los filtra por la ventana visible [start, end]. $end ya viene
# truncado por ChartEngine.compute_window cuando Replay está activo; respetar
# `index <= end` equivale a respetar replay_idx. El overlay NO alimenta al
# indicador: eso es responsabilidad de ChartEngine antes de renderizar.
sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $start //= 0;
    $end   //= 0;
    $self->{_compute_range} = [$start, $end];
    $self->{_replay_idx}    = $end;
    $self->{_draw_end_idx}  = $end;
    $self->{_market_data}   = $market_data;

    my $ind = defined $indicator ? $indicator : $self->{indicator};

    my $levels = $ind->can('get_levels') ? $ind->get_levels() : [];
    my $events = $ind->can('get_events') ? $ind->get_events() : [];
    
    # Nivel de liquidez se dibuja horizontalmente; se mantiene mientras esté en pantalla
    my $filtered_levels = _levels_window_filter($levels, $start, $end);
    $self->{_levels} = $filtered_levels;
    
    # Eventos son etiquetas en el punto de ruptura, usamos filtro estándar
    $self->{_events} = _window_filter($events, $start, $end);

    my $last_real;
    if ($market_data && $market_data->can('last_index')) {
        $last_real = $market_data->last_index();
    } elsif ($market_data && $market_data->can('size')) {
        $last_real = $market_data->size() - 1;
    }
    $self->{_last_real_index} = $last_real;

    return $self;
}

# Mantiene los $n items más recientes (mayor index), preservando orden ascendente.
sub _recent {
    my ($items, $n) = @_;
    return $items unless defined $n && @$items > $n;
    my @sorted = sort { ($b->{index} // 0) <=> ($a->{index} // 0) } @$items;
    my @keep = @sorted[0 .. $n - 1];
    return [ sort { ($a->{index} // 0) <=> ($b->{index} // 0) } @keep ];
}

# Filtra niveles de liquidez según solapamiento con la ventana visible.
sub _levels_window_filter {
    my ($levels, $start, $end) = @_;
    return [] unless defined $levels;
    my @filtered;
    for my $lvl (@$levels) {
        next unless defined $lvl->{index};
        
        # El nivel debe iniciar antes o durante la ventana actual
        next if $lvl->{index} > $end;
        
        # Si fue barrido, su final debe ser en o después del inicio de la ventana
        if (defined $lvl->{swept_index}) {
            next if $lvl->{swept_index} < $start;
        }
        
        push @filtered, $lvl;
    }
    return \@filtered;
}

# Filtra items por index dentro de [start, end]. Un item sin index se descarta.
sub _window_filter {
    my ($items, $start, $end) = @_;
    return [] unless defined $items;
    return [ grep { defined $_->{index} && $_->{index} >= $start && $_->{index} <= $end } @$items ];
}

# _filter_by_density($items, $score_key_or_cb) — top ceil(N*pct/100) por score desc.
# $score_key_or_cb: nombre de campo hash, coderef, o undef (usa magnitude, fallback 1).
# Con pct=100 devuelve @$items sin reordenar (idéntico al comportamiento previo).
sub _filter_by_density {
    my ($self, $items, $score_spec) = @_;
    return [] unless $items && ref($items) eq 'ARRAY';
    my $pct = $self->{_density_pct} // 100;
    return $items if $pct >= 100 || @$items == 0;

    my $n = scalar @$items;
    my $keep = int(($n * $pct + 99) / 100);
    $keep = 1 if $keep < 1;
    return [] if $keep <= 0;

    my $score_of = sub {
        my ($item) = @_;
        if (ref($score_spec) eq 'CODE') {
            return $score_spec->($item);
        }
        if (defined $score_spec && length $score_spec) {
            return $item->{$score_spec} // 1;
        }
        return $item->{magnitude} // 1;
    };

    my @ranked = sort {
        my $sc = $score_of->($b) <=> $score_of->($a);
        return $sc if $sc;
        ($a->{index} // 0) <=> ($b->{index} // 0);
    } @$items;

    return [ @ranked[0 .. $keep - 1] ];
}

sub _local_index {
    my ($self, $index) = @_;
    my $range = $self->{_compute_range};
    my $start = $range ? ($range->[0] // 0) : 0;
    return $index - $start;
}

# --- helpers de tema (defaults de la Tabla 2, override por tema inyectado) ------

sub _color {
    my ($self, $key, $default) = @_;
    return $self->{theme}{$key} // $default;
}

# draw($canvas, $scales) — dibuja las estructuras visibles con tag `ov_liq`.
sub draw {
    my ($self, $canvas, $scales) = @_;
    return unless $self->{visible};
    return unless $canvas && $scales;
    return unless defined $scales->{height} && $scales->{height} > 0;

    $self->clear($canvas);

    my $tag = $self->tag();
    my $w   = $scales->{width} || $scales->plot_width();
    my $ev  = $self->{_elem_visible};

    # --- BSL / SSL: bandas agrupadas (default) o líneas sueltas (task 0027) ----
    my $right_idx = $self->{_draw_end_idx} // 0;
    my $last_real = $self->{_last_real_index};
    $right_idx = $last_real if defined $last_real && $last_real < $right_idx;
    my $x_right = $scales->index_to_center_x($self->_local_index($right_idx));
    $x_right = $w if $x_right > $w;
    $x_right = 0 if $x_right < 0;
    my $atr = ($self->{indicator} && $self->{indicator}->can('current_atr'))
        ? $self->{indicator}->current_atr()
        : undef;
    my $use_bands = $self->{_band_mode} && defined $atr && $atr > 0;

    for my $fam (
        [ BSL => '#ef5350', 'liq_bsl', 'liq_bsl_label' ],
        [ SSL => '#26a69a', 'liq_ssl', 'liq_ssl_label' ],
    ) {
        my ($elem, $def_col, $theme_k, $label_k) = @$fam;
        next unless $ev->{$elem};
        my @lvls = grep {
            defined $_->{type} && $_->{type} eq $elem
                && defined $_->{index} && defined $_->{price}
        } @{ $self->{_levels} };
        @lvls = @{ $self->_filter_by_density(\@lvls, 'magnitude') };
        next unless @lvls;
        my $col = $self->_color($theme_k, $def_col);
        my $lbl_col = $self->_color($label_k, $def_col);
        if ($use_bands) {
            my $thr = ($self->{_band_atr} // 0.5) * $atr;
            for my $band (@{ $self->_cluster_bsl_ssl(\@lvls, $thr) }) {
                $self->_draw_bsl_ssl_band($canvas, $scales, $tag, $x_right,
                    $band, $elem, $col, $lbl_col);
            }
        }
        else {
            for my $lvl (@lvls) {
                $self->_draw_hline_label($canvas, $scales, $tag, $w,
                    $lvl, $elem, $col, $lbl_col);
            }
        }
    }

    # --- EQH / EQL (+ internos I-EQH / I-EQL) --------------------------------
    # ORDEN 6: los internos comparten toggle con su externo (EQH controla
    # EQH+I-EQH, EQL controla EQL+I-EQL) pero se dibujan con etiqueta literal
    # distinta ('I-EQH'/'I-EQL') y estilo interno (linea mas fina/tenue).
    if ($ev->{EQH} || $ev->{EQL}) {
        for my $type (qw(EQH EQL I-EQH I-EQL)) {
            my $base = ($type eq 'I-EQH') ? 'EQH'
                     : ($type eq 'I-EQL') ? 'EQL'
                     : $type;
            next unless $ev->{$base};
            my $internal = ($type =~ /^I-/) ? 1 : 0;
            my @items = sort { ($a->{index} // 0) <=> ($b->{index} // 0) }
                        grep { defined $_->{type} && $_->{type} eq $type } @{ $self->{_levels} };

            my %groups;
            my $has_gid = 1;
            for my $item (@items) {
                if (!defined $item->{group_id}) { $has_gid = 0; last; }
            }

            if ($has_gid && @items) {
                for my $item (@items) {
                    push @{ $groups{$item->{group_id}} }, $item;
                }
            } else {
                # Fallback para mocks de test sin group_id: agrupar de a pares consecutivos
                for my $i (0 .. $#items) {
                    my $gid = "group_" . int($i / 2);
                    push @{ $groups{$gid} }, $items[$i];
                }
            }

            for my $gid (sort keys %groups) {
                $self->_draw_pair_line($canvas, $scales, $tag, $type, $groups{$gid}, $internal);
            }
        }
    }

    # --- Eventos: SWEEP_UP / SWEEP_DOWN / GRAB / RUN --------------------------
    # ORDEN 12 (task 0024): cuando varios marcadores caen en la MISMA vela se
    # solapan y se vuelven ilegibles. Llevamos un contador por indice para
    # apilarlos verticalmente (offset incremental) y que no se encimen.
    my @event_candidates;
    for my $e (@{ $self->{_events} }) {
        next unless defined $e->{index} && defined $e->{type};
        # ORDEN 4 (task 0021 F): si only_relevant esta activo, solo dibujar las
        # tomas marcadas como relevantes por el indicador (magnitud >= factor*ATR).
        # Eventos sin campo `relevant` (indicador viejo/mock) se tratan como
        # relevantes para no romper compatibilidad.
        next if $self->{_only_relevant}
             && defined $e->{relevant} && !$e->{relevant};
        my $type = $e->{type};
        next if ($type eq 'SWEEP_UP'   || $type eq 'SWEEP_DOWN') && !$ev->{SWEEP};
        next if $type eq 'GRAB' && !$ev->{GRAB};
        next if $type eq 'RUN'  && !$ev->{RUN};
        push @event_candidates, $e;
    }
    my @events_draw = @{ $self->_filter_by_density(\@event_candidates, 'magnitude') };

    my %stack;
    for my $e (@events_draw) {
        my $type = $e->{type};
        my $level = $stack{$e->{index}}++;   # 0 el primero, 1 el segundo, ...

        if ($type eq 'SWEEP_UP' && $ev->{SWEEP}) {
            $self->_draw_event_marker($canvas, $scales, $tag, $e,
                "SWEEP \x{2191}",
                $self->_color('liq_sweep_up', '#ef5350'), $level,
            );
        } elsif ($type eq 'SWEEP_DOWN' && $ev->{SWEEP}) {
            $self->_draw_event_marker($canvas, $scales, $tag, $e,
                "SWEEP \x{2193}",
                $self->_color('liq_sweep_down', '#26a69a'), $level,
            );
        } elsif ($type eq 'GRAB' && $ev->{GRAB}) {
            $self->_draw_event_marker($canvas, $scales, $tag, $e,
                'LQ GRAB',
                $self->_color('liq_grab', '#ff9800'), $level,
            );
        } elsif ($type eq 'RUN' && $ev->{RUN}) {
            $self->_highlight_run_candle($canvas, $scales, $tag, $e);
            $self->_draw_event_marker($canvas, $scales, $tag, $e,
                'LQ RUN',
                $self->_color('liq_run', '#2962ff'), $level,
            );
        }
    }

    return $self;
}

# _cluster_bsl_ssl — agrupa niveles del mismo tipo si |precio| <= threshold.
sub _cluster_bsl_ssl {
    my ($self, $levels, $threshold) = @_;
    return [] unless $levels && @$levels;
    my @sorted = sort { $a->{price} <=> $b->{price} } @$levels;
    my @bands;
    my $cur = [ $sorted[0] ];
    for my $i (1 .. $#sorted) {
        my $lvl = $sorted[$i];
        my $max_p = (sort { $b->{price} <=> $a->{price} } @$cur)[0]{price};
        if (($lvl->{price} - $max_p) <= $threshold + 1e-9) {
            push @$cur, $lvl;
        }
        else {
            push @bands, $cur;
            $cur = [ $lvl ];
        }
    }
    push @bands, $cur;
    return \@bands;
}

# _draw_bsl_ssl_band — rectángulo tenue + una etiqueta por banda (task 0027).
sub _draw_bsl_ssl_band {
    my ($self, $canvas, $scales, $tag, $x_right, $group, $label, $outline, $text_color) = @_;
    return unless $group && @$group;
    my @prices = map { $_->{price} } @$group;
    my $min_p = (sort { $a <=> $b } @prices)[0];
    my $max_p = (sort { $b <=> $a } @prices)[0];
    my $min_idx = (sort { ($a->{index} // 0) <=> ($b->{index} // 0) } @$group)[0]{index};
    my $x0 = $scales->index_to_center_x($self->_local_index($min_idx));
    return if $x_right < 0;
    $x0 = 0 if $x0 < 0;
    my $yt = $scales->value_to_y($max_p);
    my $yb = $scales->value_to_y($min_p);
    $canvas->createRectangle(
        $x0, $yt, $x_right, $yb,
        -fill    => $outline,
        -stipple => 'gray12',
        -outline => $outline,
        -width   => 1,
        -tags    => $tag,
    );
    $canvas->createText(
        $x0 + 4, ($yt + $yb) / 2,
        -text   => $label,
        -anchor => 'w',
        -font   => 'Helvetica 8 bold',
        -fill   => $text_color,
        -tags   => $tag,
    );
    return;
}

# _draw_hline_label: línea horizontal punteada + etiqueta de texto al inicio.
sub _draw_hline_label {
    my ($self, $canvas, $scales, $tag, $w, $lvl, $label, $line_color, $text_color) = @_;
    my $price = $lvl->{price};
    return unless defined $price;
    my $y = $scales->value_to_y($price);
    
    my $x_start = $scales->index_to_center_x($self->_local_index($lvl->{index}));
    my $x_end = $w;
    if (defined $lvl->{swept_index}) {
        $x_end = $scales->index_to_center_x($self->_local_index($lvl->{swept_index}));
    }
    
    return if $x_end < 0;

    $canvas->createLine(
        $x_start, $y, $x_end, $y,
        -fill  => $line_color,
        -dash  => [4, 4],
        -width => 1,
        -tags  => $tag,
    );
    $canvas->createText(
        $x_start + 4, $y,
        -text   => $label,
        -anchor => 'w',
        -font   => 'Helvetica 8 bold',
        -fill   => $text_color,
        -tags   => $tag,
    );
    return;
}

# _draw_pair_line: conecta los pivotes de un par (EQH/EQL) con una línea.
# $type puede ser EQH/EQL o I-EQH/I-EQL (interno). $internal ajusta etiqueta y
# estilo (linea mas fina) pero el color se toma del tipo base (EQH/EQL).
sub _draw_pair_line {
    my ($self, $canvas, $scales, $tag, $type, $items, $internal) = @_;
    return unless @$items >= 2;
    $internal ||= 0;
    my $is_high = ($type =~ /EQH/) ? 1 : 0;
    my @sorted = sort { ($a->{index} // 0) <=> ($b->{index} // 0) } @$items;
    my $color = $self->_color($is_high ? 'liq_eqh' : 'liq_eql',
                             $is_high ? '#ef5350' : '#26a69a');
    my $label_color = $self->_color($is_high ? 'liq_eqh_label' : 'liq_eql_label',
                                    $color);

    my $first = $sorted[0];
    my $last  = $sorted[-1];

    # ORDEN 7 (task 0021 H): longitud del par en velas. Filtrar cortos, resaltar
    # largos. El interno tiene un umbral proporcional (mitad) para no ocultarlo
    # de mas, ya que por diseño es mas granular.
    my $span = abs(($last->{index} // 0) - ($first->{index} // 0));
    my $min_span  = $self->{_eqhl_min_span}  // 0;
    my $long_span = $self->{_eqhl_long_span} // 1e9;
    $min_span = int($min_span / 2) if $internal;   # internos: umbral mas permisivo
    return if $min_span > 0 && $span < $min_span;
    my $is_long = ($span >= $long_span) ? 1 : 0;

    my $x_start = $scales->index_to_center_x($self->_local_index($first->{index}));
    my $x_end   = $scales->index_to_center_x($self->_local_index($last->{index}));
    my $y       = $scales->value_to_y($first->{price});
    
    my $w = $scales->{width} || $scales->plot_width();
    return if $x_end < 0 || $x_start > $w;

    # Grosor: interno=1; externo=2; externo largo (mas importante)=3.
    my $width = $internal ? 1 : ($is_long ? 3 : 2);
    # ORDEN 10 (task 0022): externo EQH/EQL = linea SOLIDA; interno I-EQH/I-EQL =
    # entrecortada. Coherente con la estructura del Mxwll.
    my @line_opts = (-fill => $color, -width => $width, -tags => $tag);
    push @line_opts, (-dash => [2, 3]) if $internal;
    $canvas->createLine($x_start, $y, $x_end, $y, @line_opts);

    # Etiqueta sobre el punto medio de los extremos del par (texto LITERAL).
    my $x1 = $scales->index_to_center_x($self->_local_index($first->{index}));
    my $x2 = $scales->index_to_center_x($self->_local_index($last->{index}));
    my $x_mid = ($x1 + $x2) / 2;
    $canvas->createText(
        $x_mid, $is_high ? $y - 6 : $y + 6,
        -text   => $type,
        -anchor => $is_high ? 's' : 'n',
        -font   => $internal ? 'Helvetica 7' : 'Helvetica 8 bold',
        -fill   => $label_color,
        -tags   => $tag,
    );
    return;
}

# Borde izquierdo de la barra local (alineado con PricePanel, incl. downsample).
sub _bar_left_x {
    my ($self, $scales, $local) = @_;
    my $bars  = $scales->{bars} || 1;
    my $bar_w = $scales->plot_width() / $bars;
    if ($bar_w < 2) {
        my $plot_w = int($scales->plot_width());
        $plot_w = 1 if $plot_w < 1;
        my $x_shift = $scales->{x_shift} || 0;
        return $local * $plot_w / $bars + $x_shift;
    }
    return $scales->index_to_x($local);
}

# Borde derecho de la barra local (extremo derecho de la vela).
sub _bar_right_x {
    my ($self, $scales, $local) = @_;
    return $self->_bar_left_x($scales, $local + 1);
}

# _highlight_run_candle — resalta la vela del RUN (task 0025, overlay halo).
sub _highlight_run_candle {
    my ($self, $canvas, $scales, $tag, $e) = @_;
    my $md = $self->{_market_data};
    return unless $md && $md->can('get_candle');
    my $idx = $e->{index};
    return unless defined $idx;
    my $candle = $md->get_candle($idx);
    return unless $candle && @$candle >= 5;
    my (undef, $open, $high, $low, $close) = @$candle[0 .. 4];
    my $local = $self->_local_index($idx);
    my $bars  = $scales->{bars} || 1;
    my $bar_w = $scales->plot_width() / $bars;
    my $color = $self->_color('liq_run_highlight', '#2962ff');
    my $y_h = $scales->value_to_y($high);
    my $y_l = $scales->value_to_y($low);

    my $x_left  = $self->_bar_left_x($scales, $local);
    my $x_right = $self->_bar_right_x($scales, $local);

    if ($bar_w < 2) {
        my $cx = ($x_left + $x_right) / 2;
        my $w  = $x_right - $x_left;
        $w = 3 if $w < 3;
        $canvas->createLine(
            $cx, $y_h, $cx, $y_l,
            -fill => $color, -width => int($w + 0.5), -tags => $tag,
        );
        return;
    }

    my $cx   = ($x_left + $x_right) / 2;
    my $half = $bar_w * 0.3;
    $half = 1 if $half < 1;
    $canvas->createRectangle(
        $cx - $half, $y_h, $cx + $half, $y_l,
        -fill    => $color,
        -stipple => 'gray50',
        -outline => $color,
        -width   => 2,
        -tags    => $tag,
    );
    return;
}

# _draw_event_marker: marcador de evento (línea vertical de quiebre + etiqueta).
# Se traza una línea vertical breve en la vela del evento a la altura del nivel
# roto, y la etiqueta de la Tabla 2.
# ORDEN 3 (task 0021 F2/D): si el evento trae level_index/level_price (el pivote
# swing barrido = HH/HL/LH/LL), se dibuja ademas una linea horizontal punteada
# que ANCLA la toma a su nivel, desde el pivote hasta la vela del evento. Asi la
# toma de liquidez queda "vinculada a un nivel" como pedia el profe.
sub _draw_event_marker {
    my ($self, $canvas, $scales, $tag, $e, $label, $color, $level) = @_;
    $level ||= 0;
    my $x = $scales->index_to_center_x($self->_local_index($e->{index}));

    my $price = $e->{extreme} // $e->{price};
    return unless defined $price;
    my $y = $scales->value_to_y($price);
    my $dir = $e->{dir} // 'up';

    # ORDEN 12 (task 0024): apilar verticalmente marcadores de la misma vela para
    # que no se solapen. Cada nivel aleja el marcador 18px mas del extremo.
    my $stack_off = $level * 18;

    # Ancla al nivel: linea horizontal punteada desde el pivote barrido.
    if (defined $e->{level_index} && defined $e->{level_price}) {
        my $lx = $scales->index_to_center_x($self->_local_index($e->{level_index}));
        my $ly = $scales->value_to_y($e->{level_price});
        if ($lx <= $x) {
            $canvas->createLine(
                $lx, $ly, $x, $ly,
                -fill  => $color,
                -dash  => [2, 2],
                -width => 1,
                -tags  => $tag,
            );
        }
    }

    if ($dir eq 'up') {
        # BSL: Línea vertical que va hacia arriba desde el High de la vela.
        my $y_tip = $y - 20 - $stack_off;
        $canvas->createLine(
            $x, $y, $x, $y_tip,
            -fill  => $color,
            -width => 2,
            -tags  => $tag,
        );
        $canvas->createText(
            $x, $y_tip - 4,
            -text   => $label,
            -anchor => 's',
            -font   => 'Helvetica 8 bold',
            -fill   => $color,
            -tags   => $tag,
        );
    } else {
        # SSL: Línea vertical que va hacia abajo desde el Low de la vela.
        my $y_tip = $y + 20 + $stack_off;
        $canvas->createLine(
            $x, $y, $x, $y_tip,
            -fill  => $color,
            -width => 2,
            -tags  => $tag,
        );
        $canvas->createText(
            $x, $y_tip + 4,
            -text   => $label,
            -anchor => 'n',
            -font   => 'Helvetica 8 bold',
            -fill   => $color,
            -tags   => $tag,
        );
    }
    return;
}

# clear($canvas) — borra solo los ítems de este overlay (tag `ov_liq`).
sub clear {
    my ($self, $canvas) = @_;
    return unless $canvas;
    $canvas->delete($self->tag());
    return $self;
}

# --- helpers para tests -------------------------------------------------------
# compute_range: retorna [start, end] recibido en compute_visible.
sub compute_range {
    my ($self) = @_;
    return $self->{_compute_range};
}

# filter_by_density: expone _filter_by_density para tests (task 0062).
sub filter_by_density {
    my ($self, $items, $score_spec) = @_;
    return $self->_filter_by_density($items, $score_spec);
}

# visible_items: retorna todos los items que el overlay dibujará en draw(),
# combinados (para replay guard vía IndicatorSnapshot->replay_violations).
sub visible_items {
    my ($self) = @_;
    return [
        @{ $self->{_levels} },
        @{ $self->{_events} },
    ];
}

1;
