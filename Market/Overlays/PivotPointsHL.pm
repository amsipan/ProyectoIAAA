package Market::Overlays::PivotPointsHL;
use strict;
use warnings;

# =============================================================================
# Market::Overlays::PivotPointsHL — render de Pivot Points High Low & Missed
#   (LuxAlgo). Cálculo en Market::Indicators::PivotPointsHL.
#
#   Dibuja:
#     - Zigzag entre pivots: sólido (confirmado) / punteado (missed/pendiente).
#     - Ghost levels: líneas horizontales al nivel del pivote, semitransparentes
#       (stipple 'gray50' simula el color.new(...,50) de Pine).
#     - Etiquetas ▼ (high, rojo) / ▲ (low, verde), texto blanco (regular pivots).
#     - Fantasma 👻 en pivots "missed" y en el pivote provisional (barstate.islast).
#       Si Fedora35/Tk no renderiza el emoji (WSLg suele fallar con emoji a color),
#       se dibuja un fantasma con primitivas de canvas idéntico visualmente.
#
#   Colores del source LuxAlgo:
#     reg_ph/miss_ph = #ef5350 (rojo)   reg_pl/miss_pl = #26a69a (verde)
#     label text     = #ffffff (blanco)
#
#   Contrato: new / tag / set_visible / is_visible / compute_visible / draw / clear.
#   Causal: solo dibuja lo que el indicador acumuló hasta el índice alimentado.
# =============================================================================

# Interruptor de emoji: 1 = intentar 👻 real; si el entorno no lo renderiza,
# poner 0 y usa el fantasma dibujado. Por defecto dibujado (garantiza que se vea
# igual en Fedora35). Se puede forzar el emoji con use_emoji => 1 en new().
my $DEFAULT_USE_EMOJI = 0;

sub new {
    my ($class, %args) = @_;
    die "Overlays::PivotPointsHL->new: requiere 'indicator'"
        unless defined $args{indicator};
    my $theme = $args{theme} || {};
    my $self = {
        indicator => $args{indicator},
        theme     => $theme,
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 0,
        use_emoji => exists $args{use_emoji} ? ($args{use_emoji} ? 1 : 0) : $DEFAULT_USE_EMOJI,
        show_rastro => exists $args{show_rastro} ? ($args{show_rastro} ? 1 : 0) : 1,
        col_ph    => $theme->{pph_high}  // '#ef5350',
        col_pl    => $theme->{pph_low}   // '#26a69a',
        col_label => $theme->{pph_label} // '#ffffff',
        col_rastro => $theme->{pph_rastro} // '#9598a1',
        _start    => 0,
        _end      => 0,
    };
    bless $self, $class;
    return $self;
}

sub tag { 'ov_pph' }

sub set_visible {
    my ($self, $bool) = @_;
    $self->{visible} = $bool ? 1 : 0;
    return $self;
}

sub is_visible { $_[0]->{visible} ? 1 : 0 }

sub set_show_rastro {
    my ( $self, $on ) = @_;
    $self->{show_rastro} = $on ? 1 : 0;
    return $self;
}

sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $self->{_start} = $start // 0;
    $self->{_end}   = $end   // 0;
    return $self;
}

sub _local_index {
    my ($self, $global) = @_;
    return $global - ($self->{_start} // 0);
}

sub clear {
    my ($self, $canvas) = @_;
    return $self unless $canvas;
    $canvas->delete($self->tag());
    return $self;
}

sub _color_for {
    my ($self, $key) = @_;
    return $self->{col_ph} if $key eq 'reg_ph' || $key eq 'miss_ph';
    return $self->{col_pl} if $key eq 'reg_pl' || $key eq 'miss_pl';
    return '#9598a1';
}

# ¿El segmento/índice cae dentro de la ventana visible? (evita dibujar fuera)
sub _idx_visible {
    my ($self, $idx) = @_;
    return 0 unless defined $idx;
    return ($idx >= ($self->{_start} // 0) && $idx <= ($self->{_end} // 0)) ? 1 : 0;
}

sub _seg_visible {
    my ($self, $a, $b) = @_;
    my $s = $self->{_start} // 0;
    my $e = $self->{_end}   // 0;
    my ($lo, $hi) = $a <= $b ? ($a, $b) : ($b, $a);
    return 0 if $hi < $s;
    return 0 if $lo > $e;
    return 1;
}

sub draw {
    my ($self, $canvas, $scales) = @_;
    return $self unless $self->{visible} && $self->{indicator};
    return $self unless $canvas && $scales;
    return $self unless defined $scales->{height} && $scales->{height} > 0;

    $self->clear($canvas);
    my $vals = $self->{indicator}->get_values();
    return $self unless $vals;

    my $tag = $self->tag();
    my $x_of = sub { $scales->index_to_center_x($self->_local_index($_[0])) };
    my $y_of = sub { $scales->value_to_y($_[0]) };

    # 1) Ghost levels (líneas horizontales semitransparentes) — al fondo.
    #    Cada nivel va de su índice hasta el siguiente pivote (to_index), NO
    #    hasta el final del gráfico (paridad TV: se cortan donde nace el próximo).
    #    Culling por SOLAPAMIENTO del segmento con la ventana visible: si el tramo
    #    cruza la pantalla se dibuja aunque su origen esté fuera (independiente del zoom).
    for my $g (@{ $vals->{ghost_levels} || [] }) {
        my $to = $g->{to_index} // $self->{_end};
        next unless $self->_seg_visible($g->{index}, $to);
        my $x1 = $x_of->($g->{index});
        my $x2 = $x_of->($to);
        my $y  = $y_of->($g->{price});
        eval {
            $canvas->createLine(
                $x1, $y, $x2, $y,
                -fill    => $self->_color_for($g->{color_key}),
                -width   => 2,
                -stipple => 'gray50',
                -tags    => $tag,
            );
            1;
        };
    }

    # 2) Zigzag (sólido confirmado / punteado missed-pendiente).
    for my $s (@{ $vals->{zigzag} || [] }) {
        next unless $self->_seg_visible($s->{from_index}, $s->{to_index});
        next unless defined $s->{from_price} && defined $s->{to_price};
        my @opts = (
            -fill  => $self->_color_for($s->{color_key}),
            -width => 2,
            -tags  => $tag,
        );
        push @opts, (-dash => '-') if ($s->{style} // '') eq 'dashed';
        eval {
            $canvas->createLine(
                $x_of->($s->{from_index}), $y_of->($s->{from_price}),
                $x_of->($s->{to_index}),   $y_of->($s->{to_price}),
                @opts,
            );
            1;
        };
    }

    # 3) Etiquetas de pivots (▼ / ▲ / 👻).
    for my $lb (@{ $vals->{labels} || [] }) {
        next unless $self->_idx_visible($lb->{index});
        $self->_draw_label($canvas, $x_of->($lb->{index}), $y_of->($lb->{price}),
            $lb->{glyph}, $lb->{dir}, $self->_color_for($lb->{color_key}));
    }

    # 3b) Rastro "1" (Josafa): saltos previos del fantasma provisional.
    if ( $self->{show_rastro} ) {
        for my $tr ( @{ $vals->{trails} || [] } ) {
            next unless $self->_idx_visible( $tr->{index} );
            my $col = $self->{col_rastro} // $self->_color_for( $tr->{color_key} // 'miss_pl' );
            my $dy  = ( ( $tr->{dir} // 'up' ) eq 'down' ) ? -12 : 12;
            eval {
                $canvas->createText(
                    $x_of->( $tr->{index} ),
                    $y_of->( $tr->{price} ) + $dy,
                    -text => '1',
                    -fill => $col,
                    -font => [ 'TkDefaultFont', 8 ],
                    -tags => $tag,
                );
                1;
            };
        }
    }

    # 4) Fantasma provisional (barstate.islast, source l.121-152):
    #    a) diagonal punteada px1→(x,y) en color OPUESTO al fantasma (line_key)
    #    b) horizontal semitransparente (x,y)→n en el mismo line_key
    #    c) etiqueta 👻 en (x,y) con el color del fantasma (ghost_key)
    if (my $p = $vals->{provisional}) {
        my $line_col  = $self->_color_for($p->{line_key}  // $p->{color_key});
        my $ghost_col = $self->_color_for($p->{ghost_key} // $p->{color_key});
        my $to        = $p->{last_index} // $self->{_end};

        # a) diagonal punteada
        if ($self->_seg_visible($p->{from_index}, $p->{index})) {
            eval {
                $canvas->createLine(
                    $x_of->($p->{from_index}), $y_of->($p->{from_price}),
                    $x_of->($p->{index}),      $y_of->($p->{price}),
                    -fill => $line_col,
                    -width => 2, -dash => '-', -tags => $tag,
                );
                1;
            };
        }
        # b) horizontal semitransparente desde el fantasma hasta la vela actual
        if ($self->_seg_visible($p->{index}, $to)) {
            eval {
                $canvas->createLine(
                    $x_of->($p->{index}), $y_of->($p->{price}),
                    $x_of->($to),         $y_of->($p->{price}),
                    -fill => $line_col,
                    -width => 2, -stipple => 'gray50', -tags => $tag,
                );
                1;
            };
        }
        # c) etiqueta fantasma
        if ($self->_idx_visible($p->{index})) {
            $self->_draw_label($canvas, $x_of->($p->{index}), $y_of->($p->{price}),
                'ghost', $p->{dir}, $ghost_col);
        }
    }

    return $self;
}

# Dibuja la etiqueta de un pivote. dir 'down' → sobre el precio (marca de high),
# 'up' → bajo el precio (marca de low). Offset ~12px como en TV.
sub _draw_label {
    my ($self, $canvas, $x, $y, $glyph, $dir, $color) = @_;
    my $dy = ($dir eq 'down') ? -12 : 12;
    my $ly = $y + $dy;

    if ($glyph eq 'ghost') {
        if ($self->{use_emoji}) {
            eval {
                $canvas->createText(
                    $x, $ly, -text => "\x{1F47B}",
                    -fill => $color, -font => ['TkDefaultFont', 10],
                    -tags => $self->tag(),
                );
                1;
            } and return;
        }
        return $self->_draw_ghost_shape($canvas, $x, $ly, $color);
    }

    # Regular pivots: triángulos Unicode con texto blanco encima del color.
    my $sym = ($glyph eq 'reg_high') ? "\x{25BC}" : "\x{25B2}";  # ▼ / ▲
    eval {
        $canvas->createText(
            $x, $ly, -text => $sym,
            -fill => $color, -font => ['TkDefaultFont', 9, 'bold'],
            -tags => $self->tag(),
        );
        1;
    };
    return;
}

# Fantasma dibujado con primitivas (fallback cuando el emoji no renderiza).
# Cabeza redondeada + base ondulada + 2 ojos. ~14px de alto.
sub _draw_ghost_shape {
    my ($self, $canvas, $cx, $cy, $color) = @_;
    my $w = 5;    # medio ancho
    my $h = 6;    # medio alto
    eval {
        # Cuerpo (arco superior + base). Polígono con ondas en la base.
        my @body = (
            $cx - $w, $cy + $h,           # base izq
            $cx - $w, $cy - $h * 0.3,     # subida izq
            $cx - $w * 0.6, $cy - $h,     # hombro izq
            $cx, $cy - $h * 1.15,         # tope
            $cx + $w * 0.6, $cy - $h,     # hombro der
            $cx + $w, $cy - $h * 0.3,     # subida der
            $cx + $w, $cy + $h,           # base der
            $cx + $w * 0.5, $cy + $h * 0.5,
            $cx, $cy + $h,
            $cx - $w * 0.5, $cy + $h * 0.5,
        );
        $canvas->createPolygon(
            @body,
            -fill => $color, -outline => $color,
            -tags => $self->tag(),
        );
        # Ojos (blancos).
        my $er = 1.1;
        for my $ex (-$w * 0.4, $w * 0.4) {
            $canvas->createOval(
                $cx + $ex - $er, $cy - $er - 1,
                $cx + $ex + $er, $cy + $er - 1,
                -fill => '#ffffff', -outline => '#ffffff',
                -tags => $self->tag(),
            );
        }
        1;
    };
    return;
}

1;
