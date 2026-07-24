package Market::Overlays::VolumeProfile;
use strict;
use warnings;
use parent 'Market::Overlays::Base';

# =============================================================================
# Market::Overlays::VolumeProfile — Anchored Volume Profile (AVP render)
#
# Renderizado estilo TradingView AVP (captura profe Anchored_Volume_Profile.jpg):
#   - Caja de rango ancla -> última vela (fondo sutil)
#   - Histograma horizontal a la DERECHA (width: 30% del plot)
#   - Value Area Up/Down en Cyan (#4DD0E1)
#   - Up Volume exterior en Verde (#81C784), Down Volume exterior en Rojo (#E57373)
#   - Líneas negras sólidas para VAH, VAL y POC
#   - Mantiene capas por detrás de las velas (lower bajo tag 'candle')
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
            BOX        => 1,
            HISTOGRAM  => 1,
            POC        => 1,
            VALUE_AREA => 1,
        },
        # Colores ajustados a la captura de TradingView del profesor
        color_va_up     => $theme->{vp_va_up}     // '#00BCD4', # Cyan brillante TradingView
        color_va_down   => $theme->{vp_va_down}   // '#00BCD4', # Cyan brillante TradingView
        color_up        => $theme->{vp_up}        // '#81C784', # Verde suave TradingView
        color_down      => $theme->{vp_down}      // '#E57373', # Rosa/Rojo suave TradingView
        color_box       => $theme->{vp_box}       // '#E0F7FA', # Verde/Cyan pastel sutil transparente
        color_line      => $theme->{vp_line}      // '#000000', # Negro sólido para VAH/VAL/POC
        color_handle    => $theme->{vp_handle}    // '#00897B', # Círculo deslicable de ancla
        hist_width_frac => $theme->{vp_hist_frac} // 0.30,      # 30% en la captura de TV
        show_handle     => exists $args{show_handle} ? ( $args{show_handle} ? 1 : 0 ) : 1,
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
    my $anchor     = $prof->{anchor_idx} // 0;
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

    my $x_of_global = sub {
        my ($gidx, $edge) = @_;
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
    my $range_visible = ($x_right > 0 && $x_left < $plot_right && $x_right > $x_left);

    # 1) Caja de rango verde/cyan transparente (ancla -> última vela)
    if ($range_visible && $self->is_element_visible('BOX')) {
        eval {
            $canvas->createRectangle(
                $x_left, $y_top, $x_right, $y_bot,
                -fill    => $self->{color_box},
                -outline => '',
                -width   => 0,
                -stipple => 'gray12',
                -tags    => $tag,
            );
            1;
        };
    }

    # 2) Histograma horizontal a la DERECHA
    my $bins = $prof->{bins};
    my $max_vol = 0;
    for my $b (@$bins) {
        $max_vol = $b->{vol} if defined $b->{vol} && $b->{vol} > $max_vol;
    }

    if ($self->is_element_visible('HISTOGRAM') && $max_vol > 0) {
        my $frac = $self->{hist_width_frac} // 0.30;
        $frac = 0.30 if $frac <= 0 || $frac > 0.8;
        my $hist_max_w = int($plot_right * $frac);
        $hist_max_w = 12 if $hist_max_w < 12;

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

            # Separador de 1px entre filas al hacer zoom vertical (TradingView Imagen 1)
            my $span = $y2 - $y1;
            if ($span >= 1.5) {
                $y2 -= 1.0;
            }

            my $in_va = (defined $va_lo && defined $va_hi && $bi >= $va_lo && $bi <= $va_hi) ? 1 : 0;

            if ($in_va) {
                # Dentro de Value Area: barra completa en Cyan (#00BCD4)
                my $x2 = $hist_right;
                my $x1 = $hist_right - $bar_w_px;
                eval {
                    $canvas->createRectangle(
                        $x1, $y1, $x2, $y2,
                        -fill    => $self->{color_va_up},
                        -outline => '',
                        -width   => 0,
                        -tags    => $tag,
                    );
                    1;
                };
            } else {
                # Fuera de Value Area: desglose Up Volume (Verde) y Down Volume (Rosa/Rojo)
                my $w_up = int($hist_max_w * ($b->{vol_up} // 0) / $max_vol);
                my $w_dn = int($hist_max_w * ($b->{vol_down} // 0) / $max_vol);
                if ($w_up + $w_dn < 1) {
                    $w_up = $bar_w_px;
                }

                my $x_right_up = $hist_right;
                my $x_left_up  = $hist_right - $w_up;

                my $x_right_dn = $x_left_up;
                my $x_left_dn  = $x_right_dn - $w_dn;

                if ($w_up > 0) {
                    eval {
                        $canvas->createRectangle(
                            $x_left_up, $y1, $x_right_up, $y2,
                            -fill    => $self->{color_up},
                            -outline => '',
                            -width   => 0,
                            -tags    => $tag,
                        );
                        1;
                    };
                }
                if ($w_dn > 0) {
                    eval {
                        $canvas->createRectangle(
                            $x_left_dn, $y1, $x_right_dn, $y2,
                            -fill    => $self->{color_down},
                            -outline => '',
                            -width   => 0,
                            -tags    => $tag,
                        );
                        1;
                    };
                }
            }
        }
    }

    # 3) Líneas VAH / VAL / POC
    my $line_col = $self->{color_line};
    my $line_w   = 1;
    my $x_line_l = 0;
    my $x_line_r = $plot_right;
    my $draw_h_line = sub {
        my ($price) = @_;
        return unless defined $price;
        my $y = $scales->value_to_y($price);
        eval {
            $canvas->createLine(
                $x_line_l, $y, $x_line_r, $y,
                -fill  => $line_col,
                -width => $line_w,
                -tags  => $tag,
            );
            1;
        };
        return $y;
    };

    if ($self->is_element_visible('VALUE_AREA')) {
        $draw_h_line->($prof->{vah});
        $draw_h_line->($prof->{val});
    }
    if ($self->is_element_visible('POC') && defined $prof->{poc}) {
        $draw_h_line->($prof->{poc});
    }

    # 4) Handle deslicable de ancla (círculo sobre la línea del POC en el centro exacto de la vela)
    my $x_anchor_center = $x_of_global->($anchor, 'center');
    my $y_anchor_handle = defined $prof->{poc} ? $scales->value_to_y($prof->{poc}) : ($y_top + $y_bot) / 2;
    if ( ( $self->{show_handle} // 1 )
        && defined $x_anchor_center
        && defined $y_anchor_handle
        && $x_anchor_center >= 0
        && $x_anchor_center <= $plot_right )
    {
        eval {
            $canvas->createOval(
                $x_anchor_center - 4, $y_anchor_handle - 4,
                $x_anchor_center + 4, $y_anchor_handle + 4,
                -fill    => $self->{color_handle},
                -outline => '#FFFFFF',
                -width   => 1.5,
                -tags    => [$tag, 'vp_anchor_handle'],
            );
            1;
        };
    }

    # Detrás de las velas
    eval { $canvas->lower($tag, 'candle') };

    return $self;
}

1;
