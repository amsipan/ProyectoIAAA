package Market::Indicators::PivotPointsHL;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::PivotPointsHL
#   Port causal de "Pivot Points High Low & Missed Reversal Levels [LuxAlgo]"
#   (Pine v5). Source: docs/reference_indicators/pivot_points_hl_missed_reversal_luxalgo.txt
#
#   - Pivots regulares: high (▼) / low (▲), confirmados length velas después.
#   - Pivots "missed" (perdidos): marcados con 👻 (fantasma).
#   - Zigzag entre pivots (sólido = confirmado, punteado = missed/pendiente).
#   - Ghost levels: líneas horizontales al nivel del pivote (semitransparentes).
#   - Fantasma provisional (barstate.islast en Pine): el pivote en formación del
#     último índice causal. "Mientras el fantasma se mueve no operar; cuando se
#     queda quieto, sí" (profe). Se recalcula en cada vela → se ve moverse en Replay.
#   - Rastro "1" (Josafa Ghosts_in_swings): al cambiar de punta el fantasma
#     provisional, deja marcador en la posición previa (conteo visual de saltos).
#
#   Cálculo PURO (sin Tk). Contrato: new / reset / update_last($md,$i) / get_values.
#   Totalmente causal: solo mira velas <= índice actual, así el feed incremental y
#   el rewind de Replay (reset + refeed) lo reconstruyen sin fuga de futuro.
#   Source rastro/AVWAP auto: docs/reference_indicators/ghosts_in_swings_josafa.txt
# =============================================================================

sub new {
    my ($class, %args) = @_;
    my $self = {
        length     => $args{length}    // 50,
        show_reg   => exists $args{show_reg}   ? ($args{show_reg}   ? 1 : 0) : 1,
        show_miss  => exists $args{show_miss}  ? ($args{show_miss}  ? 1 : 0) : 1,
        show_rastro => exists $args{show_rastro} ? ($args{show_rastro} ? 1 : 0) : 1,
    };
    bless $self, $class;
    $self->reset();
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_highs}  = [];
    $self->{_lows}   = [];
    $self->{_last}   = -1;

    # Estado de tracking (var … en Pine)
    $self->{_max} = undef;  $self->{_min} = undef;
    $self->{_max_x1} = undef; $self->{_min_x1} = undef;
    $self->{_follow_max} = undef; $self->{_follow_min} = undef;
    $self->{_follow_max_x1} = undef; $self->{_follow_min_x1} = undef;
    $self->{_os}  = undef;               # 1 = último pivote high, 0 = low
    $self->{_py1} = undef; $self->{_px1} = undef;   # último punto del zigzag
    $self->{_seeded_run} = 0;

    # Salidas
    $self->{_labels}       = [];   # {index, price, glyph, dir, color_key, missed}
    $self->{_zigzag}       = [];   # {from_index, from_price, to_index, to_price, color_key, style}
    $self->{_ghost_levels} = [];   # {index, price, color_key}
    $self->{_trails}       = [];   # rastro "1": {index, price, dir, color_key}
    $self->{_prev_prov}    = undef; # punta previa del fantasma provisional
    return $self;
}

sub _len { $_[0]->{length} }

sub update_last {
    my ($self, $md, $index) = @_;
    return $self unless $md && defined $index;
    my $c = $md->get_candle($index);
    return $self unless $c;
    my ($ts, $o, $h, $l, $cl) = @$c[0 .. 4];

    $self->{_highs}[$index] = $h;
    $self->{_lows}[$index]  = $l;
    $self->{_last}          = $index;

    my $len = $self->{length};
    my $Lh  = $index - $len;               # bar central (high[length] en Pine)
    return $self if $Lh < 0;               # aún no hay ventana derecha completa
    my $hL = $self->{_highs}[$Lh];
    my $lL = $self->{_lows}[$Lh];
    return $self unless defined $hL && defined $lL;

    # Semilla del tracking en la primera vela central válida (evita el artefacto
    # (0,0) del init literal de Pine; el resto de la lógica es fiel).
    unless ($self->{_seeded_run}) {
        $self->{_max} = $hL; $self->{_min} = $lL;
        $self->{_follow_max} = $hL; $self->{_follow_min} = $lL;
        $self->{_max_x1} = $Lh; $self->{_min_x1} = $Lh;
        $self->{_follow_max_x1} = $Lh; $self->{_follow_min_x1} = $Lh;
        $self->{_seeded_run} = 1;
    }

    my $max_prev  = $self->{_max};
    my $min_prev  = $self->{_min};
    my $fmax_prev = $self->{_follow_max};
    my $fmin_prev = $self->{_follow_min};

    $self->{_max} = $hL if $hL > $self->{_max};
    $self->{_min} = $lL if $lL < $self->{_min};
    $self->{_follow_max} = $hL if $hL > $self->{_follow_max};
    $self->{_follow_min} = $lL if $lL < $self->{_follow_min};

    if ($self->{_max} > $max_prev) { $self->{_max_x1} = $Lh; $self->{_follow_min} = $lL; }
    if ($self->{_min} < $min_prev) { $self->{_min_x1} = $Lh; $self->{_follow_max} = $hL; }
    if ($self->{_follow_min} < $fmin_prev) { $self->{_follow_min_x1} = $Lh; }
    if ($self->{_follow_max} > $fmax_prev) { $self->{_follow_max_x1} = $Lh; }

    my $ph = $self->_is_pivot_high($Lh) ? $hL : undef;
    my $pl = $self->_is_pivot_low($Lh)  ? $lL : undef;

    my $os_prev = $self->{_os};   # os[1] en Pine (valor de la barra previa)

    $self->_on_pivot_high($Lh, $ph, $os_prev) if defined $ph;
    $self->_on_pivot_low($Lh, $pl, $os_prev)  if defined $pl;

    $self->_update_rastro_from_provisional();

    return $self;
}

# Pivote high estricto: high[$p] mayor que sus $length vecinos a cada lado.
sub _is_pivot_high {
    my ($self, $p) = @_;
    my $len = $self->{length};
    return 0 if $p - $len < 0;
    my $hp = $self->{_highs}[$p];
    return 0 unless defined $hp;
    for my $j ($p - $len .. $p + $len) {
        next if $j == $p;
        my $hj = $self->{_highs}[$j];
        return 0 unless defined $hj;
        return 0 if $hj >= $hp;   # empate o mayor descalifica
    }
    return 1;
}

sub _is_pivot_low {
    my ($self, $p) = @_;
    my $len = $self->{length};
    return 0 if $p - $len < 0;
    my $lp = $self->{_lows}[$p];
    return 0 unless defined $lp;
    for my $j ($p - $len .. $p + $len) {
        next if $j == $p;
        my $lj = $self->{_lows}[$j];
        return 0 unless defined $lj;
        return 0 if $lj <= $lp;
    }
    return 1;
}

sub _add_label {
    my ($self, $index, $price, $glyph, $dir, $color_key, $missed) = @_;
    return unless defined $index && defined $price;
    push @{ $self->{_labels} }, {
        index     => $index,
        price     => $price,
        glyph     => $glyph,       # 'ghost' | 'reg_high' | 'reg_low'
        dir       => $dir,         # 'up' | 'down' (posición de la etiqueta)
        color_key => $color_key,   # 'reg_ph'|'reg_pl'|'miss_ph'|'miss_pl'
        missed    => $missed ? 1 : 0,
    };
}

sub _add_zigzag {
    my ($self, $x1, $y1, $x2, $y2, $color_key, $style) = @_;
    return unless defined $x1 && defined $y1 && defined $x2 && defined $y2;
    push @{ $self->{_zigzag} }, {
        from_index => $x1, from_price => $y1,
        to_index   => $x2, to_price   => $y2,
        color_key  => $color_key,
        style      => $style,      # 'solid' | 'dashed'
    };
}

sub _add_ghost_level {
    my ($self, $index, $price, $color_key) = @_;
    return unless defined $index && defined $price;
    push @{ $self->{_ghost_levels} }, {
        index     => $index,
        price     => $price,
        color_key => $color_key,
    };
}

sub _on_pivot_high {
    my ($self, $Lh, $ph, $os_prev) = @_;

    if ($self->{show_miss}) {
        if (defined $os_prev && $os_prev == 1) {
            $self->_add_label($self->{_min_x1}, $self->{_min}, 'ghost', 'up', 'miss_pl', 1);
            $self->_add_zigzag($self->{_px1}, $self->{_py1}, $self->{_min_x1}, $self->{_min}, 'miss_ph', 'dashed');
            $self->{_px1} = $self->{_min_x1}; $self->{_py1} = $self->{_min};
            $self->_add_ghost_level($self->{_px1}, $self->{_py1}, 'reg_pl');
        }
        elsif (defined $self->{_max} && $ph < $self->{_max}) {
            $self->_add_label($self->{_max_x1}, $self->{_max}, 'ghost', 'down', 'miss_ph', 1);
            $self->_add_label($self->{_follow_min_x1}, $self->{_follow_min}, 'ghost', 'up', 'miss_pl', 1);
            $self->_add_zigzag($self->{_px1}, $self->{_py1}, $self->{_max_x1}, $self->{_max}, 'miss_pl', 'dashed');
            $self->{_px1} = $self->{_max_x1}; $self->{_py1} = $self->{_max};
            $self->_add_ghost_level($self->{_px1}, $self->{_py1}, 'reg_ph');
            $self->_add_zigzag($self->{_px1}, $self->{_py1}, $self->{_follow_min_x1}, $self->{_follow_min}, 'miss_ph', 'dashed');
            $self->{_px1} = $self->{_follow_min_x1}; $self->{_py1} = $self->{_follow_min};
            $self->_add_ghost_level($self->{_px1}, $self->{_py1}, 'reg_pl');
        }
    }

    if ($self->{show_reg}) {
        $self->_add_label($Lh, $ph, 'reg_high', 'down', 'reg_ph', 0);
        if (defined $self->{_px1}) {
            my $style = ((defined $self->{_max} && $ph < $self->{_max})
                         || (defined $os_prev && $os_prev == 1)) ? 'dashed' : 'solid';
            $self->_add_zigzag($self->{_px1}, $self->{_py1}, $Lh, $ph, 'miss_pl', $style);
        }
    }

    $self->{_py1} = $ph; $self->{_px1} = $Lh; $self->{_os} = 1;
    $self->{_max} = $ph; $self->{_min} = $ph;
}

sub _on_pivot_low {
    my ($self, $Lh, $pl, $os_prev) = @_;

    if ($self->{show_miss}) {
        if (defined $os_prev && $os_prev == 0) {
            $self->_add_label($self->{_max_x1}, $self->{_max}, 'ghost', 'down', 'miss_ph', 1);
            $self->_add_zigzag($self->{_px1}, $self->{_py1}, $self->{_max_x1}, $self->{_max}, 'miss_pl', 'dashed');
            $self->{_px1} = $self->{_max_x1}; $self->{_py1} = $self->{_max};
            $self->_add_ghost_level($self->{_px1}, $self->{_py1}, 'reg_ph');
        }
        elsif (defined $self->{_min} && $pl > $self->{_min}) {
            $self->_add_label($self->{_follow_max_x1}, $self->{_follow_max}, 'ghost', 'down', 'miss_ph', 1);
            $self->_add_label($self->{_min_x1}, $self->{_min}, 'ghost', 'up', 'miss_pl', 1);
            $self->_add_zigzag($self->{_px1}, $self->{_py1}, $self->{_min_x1}, $self->{_min}, 'miss_ph', 'dashed');
            $self->{_px1} = $self->{_min_x1}; $self->{_py1} = $self->{_min};
            $self->_add_ghost_level($self->{_px1}, $self->{_py1}, 'reg_pl');
            $self->_add_zigzag($self->{_px1}, $self->{_py1}, $self->{_follow_max_x1}, $self->{_follow_max}, 'miss_pl', 'dashed');
            $self->{_px1} = $self->{_follow_max_x1}; $self->{_py1} = $self->{_follow_max};
            $self->_add_ghost_level($self->{_px1}, $self->{_py1}, 'reg_ph');
        }
    }

    if ($self->{show_reg}) {
        $self->_add_label($Lh, $pl, 'reg_low', 'up', 'reg_pl', 0);
        if (defined $self->{_px1}) {
            my $style = ((defined $self->{_min} && $pl > $self->{_min})
                         || (defined $os_prev && $os_prev == 0)) ? 'dashed' : 'solid';
            $self->_add_zigzag($self->{_px1}, $self->{_py1}, $Lh, $pl, 'miss_ph', $style);
        }
    }

    $self->{_py1} = $pl; $self->{_px1} = $Lh; $self->{_os} = 0;
    $self->{_max} = $pl; $self->{_min} = $pl;
}

# Fantasma provisional (barstate.islast del Pine, líneas 121-152).
# os==1 → busca el low mínimo desde px1 (👻 abajo, style_label_up);
# os==0 → busca el high máximo (👻 arriba, style_label_down).
# Se mueve en cada vela hasta que un pivote real lo confirma ("se queda quieto").
#
# Colores (fiel al source):
#   ghost (etiqueta 👻): os==1 → miss_pl (verde) ; os==0 → miss_ph (rojo)
#   líneas diagonal (l.150) y horizontal (l.152): color OPUESTO al ghost →
#     os==1 → miss_ph (rojo) ; os==0 → miss_pl (verde)
#   La horizontal va desde (x,y) hasta n, semitransparente (color.new(...,50)).
sub _provisional {
    my ($self) = @_;
    my $n = $self->{_last};
    return undef unless defined $n && $n >= 0;
    return undef unless defined $self->{_px1} && defined $self->{_os};
    my $from = $self->{_px1};
    return undef if $from > $n;

    my ($best_x, $best_y);
    my ($dir, $ghost_key, $line_key);
    if ($self->{_os} == 1) {
        for my $i ($from .. $n) {
            my $v = $self->{_lows}[$i];
            next unless defined $v;
            if (!defined $best_y || $v < $best_y) { $best_y = $v; $best_x = $i; }
        }
        ($dir, $ghost_key, $line_key) = ('up', 'miss_pl', 'miss_ph');
    }
    else {
        for my $i ($from .. $n) {
            my $v = $self->{_highs}[$i];
            next unless defined $v;
            if (!defined $best_y || $v > $best_y) { $best_y = $v; $best_x = $i; }
        }
        ($dir, $ghost_key, $line_key) = ('down', 'miss_ph', 'miss_pl');
    }
    return undef unless defined $best_x;
    return {
        from_index => $self->{_px1}, from_price => $self->{_py1},
        index      => $best_x,       price      => $best_y,
        dir        => $dir,
        ghost_key  => $ghost_key,    # color del fantasma 👻
        line_key   => $line_key,     # color de la diagonal + horizontal
        last_index => $n,            # extensión horizontal hasta la vela actual
    };
}

# Rastro Josafa: si la punta provisional cambió, deja "1" en la posición previa.
sub _update_rastro_from_provisional {
    my ($self) = @_;
    return unless $self->{show_miss};
    my $prov = $self->_provisional();
    my $prev = $self->{_prev_prov};

    if ( $prov && $prev
      && ( ( $prev->{index} // -1 ) != ( $prov->{index} // -2 )
        || abs( ( $prev->{price} // 0 ) - ( $prov->{price} // 0 ) ) > 1e-9 ) )
    {
        push @{ $self->{_trails} }, {
            index     => $prev->{index},
            price     => $prev->{price},
            dir       => $prev->{dir},
            color_key => $prev->{ghost_key} // 'miss_pl',
            glyph     => '1',
        };
    }

    $self->{_prev_prov} = $prov
      ? {
        index     => $prov->{index},
        price     => $prov->{price},
        dir       => $prov->{dir},
        ghost_key => $prov->{ghost_key},
      }
      : undef;
    return $self;
}

# Último pivot REGULAR consolidado (high o low) — ancla Auto-1 AVWAP.
sub last_regular_pivot {
    my ($self) = @_;
    my $labels = $self->{_labels} || [];
    for ( my $i = $#$labels ; $i >= 0 ; $i-- ) {
        my $lb = $labels->[$i];
        next unless $lb;
        next if $lb->{missed};
        my $g = $lb->{glyph} // '';
        next unless $g eq 'reg_high' || $g eq 'reg_low';
        return {
            index => $lb->{index},
            price => $lb->{price},
            dir   => $lb->{dir},
            glyph => $g,
            side  => ( $g eq 'reg_high' ) ? 'high' : 'low',
        };
    }
    return undef;
}

# Ghost levels con to_index encadenado (Pine: cada nivel se congela donde nace
# el siguiente vía set_x2; el último se extiende a n). Sin esto, todas las líneas
# llegarían hasta el final del gráfico, cuando en TV se cortan en el próximo pivote.
sub _ghost_levels_chained {
    my ($self) = @_;
    my @lv = @{ $self->{_ghost_levels} };
    my @out;
    for my $k (0 .. $#lv) {
        my $to = ($k < $#lv) ? $lv[$k + 1]{index} : $self->{_last};
        push @out, {
            index     => $lv[$k]{index},
            price     => $lv[$k]{price},
            color_key => $lv[$k]{color_key},
            to_index  => $to,
        };
    }
    return \@out;
}

sub get_values {
    my ($self) = @_;
    return {
        labels        => $self->{_labels},
        zigzag        => $self->{_zigzag},
        ghost_levels  => $self->_ghost_levels_chained(),
        provisional   => $self->_provisional(),
        trails        => [ @{ $self->{_trails} || [] } ],
        last_regular  => $self->last_regular_pivot(),
        last_index    => $self->{_last},
    };
}

1;
