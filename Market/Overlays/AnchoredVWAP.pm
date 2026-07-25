package Market::Overlays::AnchoredVWAP;
use strict;
use warnings;

# Market::Overlays::AnchoredVWAP
# Render visual (no cambia la fórmula del indicador)
# Polilínea única por serie (mismos puntos centro-de-vela).
# Grosor uniforme (estilo TV).
# Centro azul; banda ±1σ verde; bandas ±2/±3σ verde oliva/amarillento.
# Relleno semitransparente entre upper1 y lower1 (stipple Tk).
# Círculo handle deslicable en la vela ancla.

sub new {
    my ($class, %args) = @_;
    die "Overlays::AnchoredVWAP->new: requiere 'indicator'"
        unless defined $args{indicator};
    my $theme = $args{theme} || {};
    my $self = {
        indicator => $args{indicator},
        theme     => $theme,
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 0,
        _tag      => $args{tag} // 'ov_avwap',
        show_handle => exists $args{show_handle} ? ($args{show_handle} ? 1 : 0) : 1,
        _elements => {
            VWAP_LINE => 1,
            BAND_1    => 1,
            BAND_2    => 1,
            BAND_3    => 1,
            BAND_FILL => 1,
        },
        color_vwap   => $args{color_vwap}  // $theme->{vwap_line}   // '#2962FF',
        color_band1  => $args{color_band1} // $theme->{vwap_band1}  // '#26A69A',
        color_band2  => $args{color_band2} // $theme->{vwap_band2}  // '#9E9D24',
        color_band3  => $args{color_band3} // $theme->{vwap_band3}  // '#827717',
        color_fill   => $args{color_fill}  // $theme->{vwap_fill}   // '#B2DFDB',
        line_width   => $args{line_width}  // $theme->{vwap_width}  // 1,
        fill_stipple => $args{fill_stipple} // $theme->{vwap_fill_stipple} // 'gray12',
        # Handle TV: fill blanco + outline azul (feedback §8 / mismo que AVP §7)
        color_handle_fill    => $args{color_handle_fill}
          // $theme->{vwap_handle_fill}    // '#FFFFFF',
        color_handle_outline => $args{color_handle_outline}
          // $theme->{vwap_handle_outline} // '#2962FF',
        # Estilo de trazo: undef/'' = continuo; '-' = guiones (AVWAP Auto-2 §9)
        line_dash => exists $args{line_dash} ? $args{line_dash}
          : ( $theme->{vwap_dash} // undef ),
        _start       => 0,
        _end         => 0,
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

sub tag {
    my ($self) = @_;
    return $self->{_tag} // 'ov_avwap';
}

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

sub _collect_xy {
    my ($self, $scales, $series, $start, $end, $field) = @_;
    my @xy;
    for my $i ($start .. $end) {
        next if $i < 0;
        my $pt = $series->[$i];
        next unless $pt && defined $pt->{$field};
        my $x = $scales->index_to_center_x($self->_local_index($i));
        my $y = $scales->value_to_y($pt->{$field});
        push @xy, $x, $y;
    }
    return @xy;
}

sub _draw_polyline {
    my ($self, $canvas, $scales, $series, $start, $end, $field, $color, $width) = @_;
    my @xy = $self->_collect_xy($scales, $series, $start, $end, $field);
    return if @xy < 4;

    my %opts = (
        -fill      => $color,
        -width     => $width,
        -capstyle  => 'round',
        -joinstyle => 'round',
        -tags      => $self->tag(),
    );
    my $dash = $self->{line_dash};
    $opts{-dash} = $dash if defined $dash && length $dash;

    $canvas->createLine( @xy, %opts );
    return;
}

sub _draw_band_fill {
    my ($self, $canvas, $scales, $series, $start, $end, $n, $color) = @_;
    my @upper = $self->_collect_xy($scales, $series, $start, $end, "upper$n");
    my @lower = $self->_collect_xy($scales, $series, $start, $end, "lower$n");
    return if @upper < 4 || @lower < 4;
    return if @upper != @lower;

    my @poly = @upper;
    for (my $i = $#lower - 1; $i >= 0; $i -= 2) {
        push @poly, $lower[$i], $lower[$i + 1];
    }

    $canvas->createPolygon(
        @poly,
        -fill    => $color,
        -outline => '',
        -stipple => ($self->{fill_stipple} // 'gray12'),
        -tags    => $self->tag(),
    );
    return;
}

sub _band_color {
    my ($self, $n) = @_;
    return $self->{color_band1} if $n == 1;
    return $self->{color_band2} if $n == 2;
    return $self->{color_band3};
}

sub draw {
    my ($self, $canvas, $scales) = @_;
    return $self unless $self->is_visible() && $self->{indicator};
    return $self unless $canvas && $scales;
    return $self unless defined $scales->{height} && $scales->{height} > 0;

    my $ind = $self->{indicator};
    return $self unless $ind->can('has_anchor') && $ind->has_anchor();

    my $series = $ind->get_values();
    return $self unless $series && @$series;

    $self->clear($canvas);

    my $start  = $self->{_start} // 0;
    my $end    = $self->{_end}   // 0;
    my $anchor = $ind->anchor_index();

    $start = $anchor if defined $anchor && $anchor > $start;
    return $self if $start > $end;

    my $w = $self->{line_width} // 1;

    # 1) Relleno primero (debajo de las líneas)
    if ($self->is_element_visible('BAND_FILL') && $self->is_element_visible('BAND_1')) {
        my $has_band1;
        for my $i ($start .. $end) {
            my $pt = $series->[$i];
            if ($pt && defined $pt->{upper1} && defined $pt->{lower1}) {
                $has_band1 = 1;
                last;
            }
        }
        if ($has_band1) {
            $self->_draw_band_fill(
                $canvas, $scales, $series, $start, $end, 1,
                $self->{color_fill},
            );
        }
    }

    # 2) Líneas de bandas
    for my $n (1 .. 3) {
        next unless $self->is_element_visible("BAND_$n");
        my $bcol = $self->_band_color($n);
        $self->_draw_polyline($canvas, $scales, $series, $start, $end, "upper$n", $bcol, $w);
        $self->_draw_polyline($canvas, $scales, $series, $start, $end, "lower$n", $bcol, $w);
    }

    # 3) Línea central VWAP
    if ($self->is_element_visible('VWAP_LINE')) {
        $self->_draw_polyline(
            $canvas, $scales, $series, $start, $end, 'value',
            $self->{color_vwap}, $w + 1,
        );
    }

    # 4) Handle ancla estilo TradingView (blanco + borde azul, encima de velas)
    my $drew_handle = 0;
    if ( $self->{show_handle}
      && defined $anchor
      && $anchor >= ( $self->{_start} // 0 )
      && $anchor <= ( $self->{_end}   // 0 ) )
    {
        my $local_idx = $self->_local_index($anchor);
        my $x = $scales->index_to_center_x($local_idx);
        my $pt = $series->[$anchor];
        if (defined $x && $pt && defined $pt->{value}) {
            my $y = $scales->value_to_y($pt->{value});
            my $fill = $self->{color_handle_fill}    // '#FFFFFF';
            my $outl = $self->{color_handle_outline} // '#2962FF';
            eval {
                $canvas->createOval(
                    $x - 5, $y - 5, $x + 5, $y + 5,
                    -fill    => $fill,
                    -outline => $outl,
                    -width   => 2,
                    -tags    => [ $self->tag(), 'avwap_anchor_handle' ],
                );
                $drew_handle = 1;
                1;
            };
        }
    }
    eval { $canvas->raise('avwap_anchor_handle') } if $drew_handle;

    return $self;
}

1;
