package Market::Overlays::VolumeProfile;
use strict;
use warnings;

# =============================================================================
# Market::Overlays::VolumeProfile — Anchored Volume Profile (render)
#
# Visual estilo TradingView AVP (captura profe):
#   - Caja semitransparente del rango ancla→fin
#   - Histograma horizontal a la DERECHA, barras AZULES (sin up/down rojo)
#   - Líneas negras VAH / VAL / POC
#   - Etiqueta POC en verde
# Detrás de velas (lower bajo tag 'candle').
# =============================================================================

sub new {
    my ($class, %args) = @_;
    die "Overlays::VolumeProfile->new: requiere 'indicator'"
        unless defined $args{indicator};
    my $theme = $args{theme} || {};
    my $self = {
        indicator => $args{indicator},
        theme     => $theme,
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 0,
        _elements => {
            BOX       => 1,
            HISTOGRAM => 1,
            POC       => 1,
            VALUE_AREA=> 1,
        },
        # Azul cian original (primera versión del AVP).
        color_hist     => $theme->{vp_hist}     // '#4FC3F7',
        color_hist_va  => $theme->{vp_hist_va}  // '#29B6F6',
        color_box      => $theme->{vp_box}      // '#BBDEFB',
        color_line     => $theme->{vp_line}     // '#212121',
        hist_width_frac=> $theme->{vp_hist_frac}// 0.18,
        _start => 0,
        _end   => 0,
    };
    bless $self, $class;
    return $self;
}

sub set_visible {
    my ($self, $val) = @_;
    $self->{visible} = $val ? 1 : 0;
}

sub is_visible {
    my ($self) = @_;
    return $self->{visible} ? 1 : 0;
}

sub tag { return 'ov_vp'; }

sub clear {
    my ($self, $canvas) = @_;
    return unless $canvas;
    $canvas->delete($self->tag());
}

sub is_element_visible {
    my ($self, $elem) = @_;
    return $self->{_elements}->{$elem} ? 1 : 0;
}

sub set_element_visible {
    my ($self, $elem, $on) = @_;
    return $self unless defined $elem && exists $self->{_elements}->{$elem};
    $self->{_elements}->{$elem} = $on ? 1 : 0;
    return $self;
}

sub _local_index {
    my ($self, $global_idx) = @_;
    return $global_idx - ($self->{_start} // 0);
}

sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $self->{_start} = $start // 0;
    $self->{_end}   = $end   // 0;
    return $self;
}

sub draw {
    my ($self, $canvas, $scales) = @_;
    return $self unless $self->is_visible() && $self->{indicator};
    return $self unless $canvas && $scales;
    return $self unless defined $scales->{height} && $scales->{height} > 0;

    my $ind = $self->{indicator};
    return $self unless $ind->can('has_anchor') && $ind->has_anchor();

    my $prof = $ind->get_values();
    return $self unless $prof && $prof->{bins} && @{ $prof->{bins} };

    my $tag = $self->tag();
    $self->clear($canvas);

    my $view_start = $self->{_start} // 0;
    my $view_end   = $self->{_end}   // 0;
    my $anchor     = $prof->{anchor_idx};
    my $end_idx    = $prof->{end_idx};
    $end_idx = $anchor if !defined $end_idx && defined $anchor;

    my $w = $scales->{width} || ($scales->can('plot_width') ? $scales->plot_width() : 400);
    my $plot_right = $w;
    if ($scales->can('plot_width')) {
        $plot_right = $scales->plot_width();
    }
    my $bars_vis = ($view_end - $view_start + 1);
    $bars_vis = 1 if $bars_vis < 1;
    my $bar_w = ($scales->can('plot_width') ? $scales->plot_width() : $plot_right) / $bars_vis;

    my $y_top = $scales->value_to_y($prof->{max_p});
    my $y_bot = $scales->value_to_y($prof->{min_p});
    ($y_top, $y_bot) = ($y_bot, $y_top) if $y_top > $y_bot;

    # X del ancla y de la ÚLTIMA vela del perfil (no el borde infinito del plot).
    # Así al paneo a la derecha se ve el final del cuadrado en la última vela.
    my $x_of_global = sub {
        my ($gidx, $edge) = @_;  # edge: 'center' | 'right' | 'left'
        return undef unless defined $gidx;
        if ($gidx < $view_start) {
            return ($edge && $edge eq 'right') ? 0 : 0;
        }
        if ($gidx > $view_end) {
            return $plot_right;
        }
        my $cx = $scales->index_to_center_x($self->_local_index($gidx));
        return $cx if !$edge || $edge eq 'center';
        return $cx + $bar_w * 0.5 if $edge eq 'right';
        return $cx - $bar_w * 0.5 if $edge eq 'left';
        return $cx;
    };

    my $x_left  = $x_of_global->($anchor, 'left');
    my $x_right = $x_of_global->($end_idx, 'right');
    $x_left  = 0 unless defined $x_left;
    $x_right = $plot_right unless defined $x_right;
    if ($x_right < $x_left) {
        ($x_left, $x_right) = ($x_right, $x_left);
    }
    # Caja/histograma solo si el rango ancla→fin intersecta la vista.
    # Las líneas POC/VAH/VAL se dibujan siempre (todo el ancho del plot).
    my $range_visible = ($x_right > 0 && $x_left < $plot_right && $x_right > $x_left);

    # Ancho del histograma: fracción del ancho del RANGO del perfil (no del plot entero)
    my $range_w = $x_right - $x_left;
    $range_w = $bar_w if $range_w < $bar_w;

    # 1) Caja de rango: ancla → última vela (inclusive)
    if ($range_visible && $self->is_element_visible('BOX')) {
        $canvas->createRectangle(
            $x_left, $y_top, $x_right, $y_bot,
            -fill    => $self->{color_box},
            -outline => '',
            -width   => 0,
            -stipple => 'gray12',
            -tags    => $tag,
        );
    }

    # 2) Histograma SIEMPRE pegado al borde derecho del plot (crece a la izq.).
    # Independiente de la caja: la zona sombreada termina en la última vela;
    # el histograma no se mueve con el paneo del rango.
    my $bins = $prof->{bins};
    my $max_vol = 0;
    for my $b (@$bins) {
        $max_vol = $b->{vol} if defined $b->{vol} && $b->{vol} > $max_vol;
    }

    if ($self->is_element_visible('HISTOGRAM') && $max_vol > 0) {
        my $frac = $self->{hist_width_frac} // 0.18;
        $frac = 0.18 if $frac <= 0 || $frac > 0.5;
        my $hist_max_w = int($plot_right * $frac);
        $hist_max_w = 8 if $hist_max_w < 8;

        my $va_lo = $prof->{va_low_idx};
        my $va_hi = $prof->{va_high_idx};
        my $hist_right = $plot_right;

        for my $bi (0 .. $#$bins) {
            my $b = $bins->[$bi];
            next unless defined $b->{vol} && $b->{vol} > 0;
            my $bar_w_px = int($hist_max_w * $b->{vol} / $max_vol);
            next if $bar_w_px < 1;

            my $y1 = $scales->value_to_y($b->{hi});
            my $y2 = $scales->value_to_y($b->{lo});
            ($y1, $y2) = ($y2, $y1) if $y1 > $y2;
            # Gap entre filas (estilo TV)
            my $gap = 1;
            my $span = $y2 - $y1;
            if ($span > $gap + 1) {
                $y1 += $gap * 0.5;
                $y2 -= $gap * 0.5;
            }
            $y2 = $y1 + 1 if $y2 - $y1 < 1;

            my $x2 = $hist_right;
            my $x1 = $hist_right - $bar_w_px;

            my $in_va = (defined $va_lo && defined $va_hi
                && $bi >= $va_lo && $bi <= $va_hi) ? 1 : 0;
            my $fill = $in_va ? $self->{color_hist_va} : $self->{color_hist};

            $canvas->createRectangle(
                $x1, $y1, $x2, $y2,
                -fill    => $fill,
                -outline => '',
                -width   => 0,
                -tags    => $tag,
            );
        }
    }

    # 3) Líneas VAH / VAL / POC: todo el ancho, mismo grosor (sin etiqueta de precio).
    my $line_col = $self->{color_line};
    my $line_w   = 1;
    my $x_line_l = 0;
    my $x_line_r = $plot_right;
    my $draw_h_line = sub {
        my ($price) = @_;
        return unless defined $price;
        my $y = $scales->value_to_y($price);
        $canvas->createLine(
            $x_line_l, $y, $x_line_r, $y,
            -fill  => $line_col,
            -width => $line_w,
            -tags  => $tag,
        );
        return $y;
    };

    if ($self->is_element_visible('VALUE_AREA')) {
        $draw_h_line->($prof->{vah});
        $draw_h_line->($prof->{val});
    }
    if ($self->is_element_visible('POC') && defined $prof->{poc}) {
        $draw_h_line->($prof->{poc});
    }

    # Detrás de las velas
    eval { $canvas->lower($tag, 'candle') };

    return $self;
}

1;
