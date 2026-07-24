package Market::Overlays::SMC_Pro;
use strict;
use warnings;

# Render capa SMC Pro [Neon] — config captura del profesor.
#
# Anclaje X: centro de vela (index_to_center_x).
# EQH/EQL: diagonal prev → new (Pine drawEqualHighLow).
# OB: borde izquierdo de la caja = centro de la vela del bloque (paridad TV
#     bar_time / chart.point), NO el borde izquierdo de la barra.
#
# Extremos:
#   BOS/CHoCH → solo vela de rotura (event.index). NUNCA data_end.
#   Strong/Weak, MTF, OB → hasta última vela con OHLC (data_end).
#
# Orden de dibujo (crítico):
#   OB → MTF → Strong/Weak → EQ → BOS/CHoCH → pivots
# Si PDH comparte precio con un BOS (high del día = pivote de estructura),
# MTF debajo + estilo acento/dotted evita que la extensión a data_end
# parezca un BOS que “no corta” en la rotura.

sub new {
    my ($class, %args) = @_;
    die "Overlays::SMC_Pro->new: requiere 'indicator'"
        unless defined $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 0,
        _pivots => [], _events => [], _eqhl => [], _obs => [],
        _strong_weak => [], _mtf => [],
        _compute_range => undef,
        _data_end => undef,
    };
    bless $self, $class;
    return $self;
}

sub tag { 'ov_smc_pro' }

sub set_visible {
    my ($self, $bool) = @_;
    $self->{visible} = $bool ? 1 : 0;
    return $self;
}

sub is_visible { $_[0]->{visible} }

sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $start //= 0;
    $end   //= 0;
    $self->{_compute_range} = [$start, $end];

    # data_end = última vela de la SERIE (o tope de feed Replay), NUNCA el fin
    # del zoom. Si se usa el viewport, BOS largos con rotura fuera de pantalla
    # se saltan en draw (break_i > data_end) y desaparecen — TV sí los muestra.
    my $last_data;
    if ($market_data && $market_data->can('last_index')) {
        my $li = $market_data->last_index();
        $last_data = $li if defined $li;
    }
    if (!defined $last_data && $market_data && $market_data->can('size')) {
        my $n = $market_data->size();
        $last_data = $n - 1 if defined $n && $n > 0;
    }
    $last_data //= $end;
    # Replay / feed parcial (ChartEngine setea _feed_end antes de compute_all)
    if (defined $self->{_feed_end} && $self->{_feed_end} >= 0
        && $self->{_feed_end} < $last_data)
    {
        $last_data = $self->{_feed_end};
    }
    $self->{_data_end}   = $last_data;
    $self->{_replay_end} = $end;

    my $ind = $indicator // $self->{indicator};
    my $cap = $last_data;

    # Pivotes/labels: solo si el ancla cae en el viewport (texto puntual)
    $self->{_pivots} = _window($ind->get_pivots(), $start, $end);
    # Segmentos (BOS/CHoCH/EQ): independientes del zoom — solape con viewport (como TV)
    $self->{_events} = _events_window($ind->get_events(), $start, $end);
    $self->{_eqhl}   = _eq_window($ind->get_eqhl(), $start, $end);
    # OB: caja desde index hasta data_end — visible si cruza el viewport
    $self->{_obs} = [
        grep {
            defined $_->{index}
            && ($_->{active} // 1)
            && _segment_overlaps($_->{index}, $cap, $start, $end)
        } @{ $ind->get_order_blocks() || [] }
    ];
    # Strong/Weak y MTF: rayo [anchor, data_end] — visible si cruza el viewport
    $self->{_strong_weak} = [
        grep {
            defined $_->{index}
            && _segment_overlaps($_->{index}, $cap, $start, $end)
        } @{ $ind->get_strong_weak() || [] }
    ];
    $self->{_mtf} = [
        grep {
            defined $_->{index}
            && _segment_overlaps($_->{index}, $cap, $start, $end)
        } @{ $ind->get_mtf_levels() || [] }
    ];
    return $self;
}

# Segmento [a,b] (índices globales) intersecta viewport [vs,ve] (TV: se ve aunque
# los extremos queden fuera de pantalla).
sub _segment_overlaps {
    my ($a, $b, $vs, $ve) = @_;
    return 0 unless defined $a && defined $b && defined $vs && defined $ve;
    my ($lo, $hi) = $a <= $b ? ($a, $b) : ($b, $a);
    return ($hi >= $vs && $lo <= $ve) ? 1 : 0;
}

sub _window {
    my ($items, $start, $end) = @_;
    return [] unless $items;
    return [ grep { defined $_->{index} && $_->{index} >= $start && $_->{index} <= $end } @$items ];
}

sub _events_window {
    my ($events, $start, $end) = @_;
    return [] unless $events;
    my @out;
    for my $e (@$events) {
        next unless defined $e->{index};
        my $s = $e->{start_index} // $e->{index};
        # Como TV: mostrar si el tramo pivote→rotura cruza el zoom, aunque
        # ninguna de las dos velas esté en pantalla.
        next unless _segment_overlaps($s, $e->{index}, $start, $end);
        push @out, $e;
    }
    return \@out;
}

sub _eq_window {
    my ($items, $start, $end) = @_;
    return [] unless $items;
    my @out;
    for my $eq (@$items) {
        my $a = $eq->{prev_index} // $eq->{index};
        my $b = $eq->{index};
        next unless defined $b;
        next unless _segment_overlaps($a, $b, $start, $end);
        push @out, $eq;
    }
    return \@out;
}

sub _win_start {
    my ($self) = @_;
    my $range = $self->{_compute_range} || [0, 0];
    return $range->[0] // 0;
}

sub _data_end {
    my ($self) = @_;
    return $self->{_data_end} // ($self->{_compute_range} || [0, 0])->[1] // 0;
}

sub _local {
    my ($self, $global_i) = @_;
    return ($global_i // 0) - $self->_win_start;
}

sub _center_x {
    my ($self, $scales, $global_i) = @_;
    return $scales->index_to_center_x($self->_local($global_i));
}

# Clip a píxeles del plot (± margen). No cambia la lógica de datos: solo evita
# geometría de decenas de miles de px que degrada Tk (crosshair/pan).
sub _plot_x_bounds {
    my ($self, $scales) = @_;
    my $w = $scales->{width} // 0;
    $w = 1 if $w < 1;
    return (-120, $w + 120);
}

sub _clip_seg_x {
    my ($self, $scales, $x1, $x2) = @_;
    my ($lo, $hi) = $self->_plot_x_bounds($scales);
    # Completamente fuera
    return if ($x1 < $lo && $x2 < $lo) || ($x1 > $hi && $x2 > $hi);
    $x1 = $lo if $x1 < $lo;
    $x1 = $hi if $x1 > $hi;
    $x2 = $lo if $x2 < $lo;
    $x2 = $hi if $x2 > $hi;
    return ($x1, $x2);
}

sub _bar_left_x {
    my ($self, $scales, $global_i) = @_;
    return $scales->index_to_x($self->_local($global_i));
}

sub _bar_right_x {
    my ($self, $scales, $global_i) = @_;
    return $scales->index_to_x($self->_local($global_i) + 1);
}

sub _x_data_right {
    my ($self, $scales) = @_;
    return $self->_bar_right_x($scales, $self->_data_end);
}

sub clear {
    my ($self, $canvas) = @_;
    return unless $canvas;
    eval { $canvas->delete($self->tag()); 1 };
    return $self;
}

sub draw {
    my ($self, $canvas, $scales) = @_;
    return unless $self->{visible} && $canvas && $scales;
    $self->clear($canvas);
    my $tag = $self->tag();

    # Pine: structure = themeBull/Bear; MTF levels = accentCol (no bull green).
    my $bull   = $self->{theme}{smc_bull} // '#00c853';
    my $bear   = $self->{theme}{smc_bear} // '#ff1744';
    my $ob_bull = $self->{theme}{smc_ob_bull} // '#00c853';
    my $ob_bear = $self->{theme}{smc_ob_bear} // '#ff1744';
    my $mtf_c  = $self->{theme}{smc_mtf} // '#5c6bc0';

    my $y_of = sub {
        my ($price) = @_;
        return $scales->value_to_y($price);
    };

    my $data_end     = $self->_data_end;
    my $x_data_right = $self->_x_data_right($scales);

    # 1) Order blocks (fondo) — escalón de mitigación (capturas profe):
    #    Izquierda (ya comido): zona RESTANTE hi/lo → "delgado".
    #    Derecha (proyección): zona ORIGINAL orig_hi/orig_lo → "grueso".
    #    Corte en last_mitig_index. Sin mitigar: un solo rectángulo original.
    #    Labels: "OB i" / "OB" (mismo criterio que BOS/CHoCH).
    for my $ob (@{ $self->{_obs} }) {
        next if ($ob->{index} // 0) > $data_end;
        my $fill = ($ob->{bias} // '') eq 'bull' ? $ob_bull : $ob_bear;
        my $scope = $ob->{scope} // 'swing';
        my $stipple = ($scope eq 'internal') ? 'gray50' : 'gray25';
        my $lbl = ($scope eq 'internal') ? 'OB i' : 'OB';

        my $orig_hi = $ob->{orig_hi} // $ob->{hi};
        my $orig_lo = $ob->{orig_lo} // $ob->{lo};
        my $hi      = $ob->{hi};
        my $lo      = $ob->{lo};
        next unless defined $hi && defined $lo;

        my $x_left = $self->_center_x($scales, $ob->{index});
        my $x_right = $x_data_right;
        my $mit_i = $ob->{last_mitig_index};
        my $stepped = $ob->{mitig}
          && defined $mit_i
          && defined $orig_hi
          && defined $orig_lo
          && ( abs( $hi - $orig_hi ) > 1e-9 || abs( $lo - $orig_lo ) > 1e-9 );

        my $draw_rect = sub {
            my ( $xa, $xb, $price_hi, $price_lo ) = @_;
            return unless defined $xa && defined $xb && defined $price_hi && defined $price_lo;
            my @cx = $self->_clip_seg_x( $scales, $xa, $xb );
            return unless @cx;
            ( $xa, $xb ) = @cx;
            return if $xb < $xa;
            my $ya = $y_of->($price_hi);
            my $yb = $y_of->($price_lo);
            ( $ya, $yb ) = ( $yb, $ya ) if $ya > $yb;
            eval {
                $canvas->createRectangle(
                    $xa, $ya, $xb, $yb,
                    -outline => $fill,
                    -fill    => $fill,
                    -stipple => $stipple,
                    -width   => 1,
                    -tags    => [ $tag, 'smc_ob' ],
                );
                1;
            };
            return ( $xa, $ya );
        };

        my ( $lbl_x, $lbl_y );
        if ($stepped) {
            my $x_step = $self->_center_x( $scales, $mit_i );
            # Tramo izquierdo: restante (delgado).
            my @left = $draw_rect->( $x_left, $x_step, $hi, $lo );
            ( $lbl_x, $lbl_y ) = @left if @left;
            # Tramo derecho: original (grueso), desde el corte hasta ahora.
            $draw_rect->( $x_step, $x_right, $orig_hi, $orig_lo );
        }
        else {
            my @one = $draw_rect->( $x_left, $x_right, $orig_hi // $hi, $orig_lo // $lo );
            ( $lbl_x, $lbl_y ) = @one if @one;
        }

        if ( defined $lbl_x && defined $lbl_y ) {
            eval {
                $canvas->createText(
                    $lbl_x + 2, $lbl_y + 1,
                    -text   => $lbl,
                    -fill   => $fill,
                    -anchor => 'nw',
                    -font   => [ 'TkDefaultFont', 7 ],
                    -tags   => [ $tag, 'smc_ob_lbl' ],
                );
                1;
            };
        }
    }

    # 2) MTF (PDH/PDL/…) — acento + dotted, DEBAJO de estructura
    for my $lv (@{ $self->{_mtf} }) {
        my $anchor = $lv->{index} // 0;
        next if $anchor > $data_end;
        my $x1 = $self->_center_x($scales, $anchor);
        my $x2 = $x_data_right;
        my @cx = $self->_clip_seg_x($scales, $x1, $x2);
        next unless @cx;
        ($x1, $x2) = @cx;
        next if $x2 < $x1;
        my $y = $y_of->($lv->{price});
        eval {
            $canvas->createLine(
                $x1, $y, $x2, $y,
                -fill  => $mtf_c,
                -width => 1,
                -dash  => '.',
                -tags  => [$tag, 'smc_mtf'],
            );
            $canvas->createText(
                $x2 - 4, $y + 10,
                -text   => $lv->{label} // 'MTF',
                -fill   => $mtf_c,
                -font   => ['TkDefaultFont', 7],
                -anchor => 'e',
                -tags   => [$tag, 'smc_mtf_lbl'],
            );
            1;
        };
    }

    # 3) Strong / Weak — debajo de estructura
    for my $sw (@{ $self->{_strong_weak} }) {
        my $anchor = $sw->{index};
        next unless defined $anchor && $anchor <= $data_end;
        my $col = ($sw->{side} // '') eq 'high' ? $bear : $bull;
        my $x1 = $self->_center_x($scales, $anchor);
        my $x2 = $x_data_right;
        my @cx = $self->_clip_seg_x($scales, $x1, $x2);
        next unless @cx;
        ($x1, $x2) = @cx;
        next if $x2 < $x1;
        my $y = $y_of->($sw->{price});
        eval {
            $canvas->createLine(
                $x1, $y, $x2, $y,
                -fill  => $col,
                -width => 1,
                -dash  => '-',
                -tags  => [$tag, 'smc_sw'],
            );
            $canvas->createText(
                $x2 - 4, $y - 10,
                -text   => $sw->{type} // '',
                -fill   => $col,
                -font   => ['TkDefaultFont', 7],
                -anchor => 'e',
                -tags   => [$tag, 'smc_sw_lbl'],
            );
            1;
        };
    }

    # 4) EQH / EQL
    for my $eq (@{ $self->{_eqhl} }) {
        my $i2 = $eq->{index};
        next unless defined $i2 && $i2 <= $data_end;
        my $col = ($eq->{type} // '') eq 'EQH' ? $bear : $bull;
        my $i1 = $eq->{prev_index} // $i2;
        $i1 = $i2 if $i1 > $data_end;
        my $p1 = defined $eq->{prev_price} ? $eq->{prev_price} : $eq->{price};
        my $p2 = $eq->{price};
        my $x1 = $self->_center_x($scales, $i1);
        my $x2 = $self->_center_x($scales, $i2);
        my @cx = $self->_clip_seg_x($scales, $x1, $x2);
        next unless @cx;
        ($x1, $x2) = @cx;
        my $y1 = $y_of->($p1);
        my $y2 = $y_of->($p2);
        eval {
            $canvas->createLine(
                $x1, $y1, $x2, $y2,
                -fill  => $col,
                -width => 1,
                -dash  => '.',
                -tags  => [$tag, 'smc_eq'],
            );
            $canvas->createText(
                ($x1 + $x2) / 2, ($y1 + $y2) / 2 - 8,
                -text => $eq->{type},
                -fill => $col,
                -font => ['TkDefaultFont', 7],
                -tags => [$tag, 'smc_eq_lbl'],
            );
            1;
        };
    }

    # 5) BOS/CHoCH ENCIMA — segmento cerrado pivote → rotura
    for my $e (@{ $self->{_events} }) {
        my $break_i = $e->{index};
        my $start_i = $e->{start_index} // $break_i;
        next unless defined $break_i;
        next if $break_i > $data_end;
        $start_i = $break_i if !defined $start_i || $start_i > $break_i;

        my $col  = ($e->{dir} // '') eq 'up' ? $bull : $bear;
        my $dash = (($e->{scope} // '') eq 'internal') ? '.' : '';
        my $x1 = $self->_center_x($scales, $start_i);
        my $x2 = $self->_center_x($scales, $break_i);
        my @cx = $self->_clip_seg_x($scales, $x1, $x2);
        next unless @cx;
        ($x1, $x2) = @cx;
        my $y  = $y_of->($e->{price});
        eval {
            $canvas->createLine(
                $x1, $y, $x2, $y,
                -fill  => $col,
                -width => 1,   # Pine default (mismo grosor que el resto)
                -dash  => $dash,
                -tags  => [$tag, 'smc_evt'],
            );
            my $lbl = $e->{type} // 'BOS';
            $lbl .= ' i' if ($e->{scope} // '') eq 'internal';  # internos: dejar " i"
            my $mid_x = ($x1 + $x2) / 2;
            $canvas->createText(
                $mid_x, $y - 8,
                -text => $lbl,
                -fill => $col,
                -font => ['TkDefaultFont', 7],
                -tags => [$tag, 'smc_evt_lbl'],
            );
            1;
        };
    }

    # 6) Pivotes HH/HL/LH/LL
    for my $p (@{ $self->{_pivots} }) {
        next if ($p->{index} // 0) > $data_end;
        my $col = ($p->{type} eq 'HH' || $p->{type} eq 'LH') ? $bear : $bull;
        my $x = $self->_center_x($scales, $p->{index});
        my $y = $y_of->($p->{price});
        my $dy = ($p->{type} eq 'HH' || $p->{type} eq 'LH') ? -10 : 10;
        eval {
            $canvas->createText(
                $x, $y + $dy,
                -text => $p->{type},
                -fill => $col,
                -font => ['TkDefaultFont', 7],
                -tags => [$tag, 'smc_pivot'],
            );
            1;
        };
    }

    return $self;
}

# Densidad: a eliminar. No filtrar SMC (paridad TV). Stubs no-op al 100%.
sub set_density_pct { $_[0] }
sub density_pct { 100 }
sub set_element_density_pct { $_[0] }
sub element_density_pct { 100 }

1;
