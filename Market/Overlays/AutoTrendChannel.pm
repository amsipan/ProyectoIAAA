package Market::Overlays::AutoTrendChannel;
use strict;
use warnings;

# =============================================================================
# Market::Overlays::AutoTrendChannel — render de Trendline/Canal automáticos.
#   Tag: ov_auto_tc
#   Oral (Lumina 20-jul): UN canal activo que acompaña la última vela causal;
#   al tomar liquidez DESAPARECE (“para no quedarse muchos canales”). Toques
#   en riel inferior; superior variable; mediana punteada. Solo ACTIVE.
# =============================================================================

sub new {
    my ( $class, %args ) = @_;
    die "Overlays::AutoTrendChannel->new: requiere 'indicator'"
      unless defined $args{indicator};
    my $theme = $args{theme} || {};
    my $self = {
        indicator => $args{indicator},
        theme     => $theme,
        visible   => exists $args{visible} ? ( $args{visible} ? 1 : 0 ) : 0,
        show_trendline => exists $args{show_trendline} ? ( $args{show_trendline} ? 1 : 0 ) : 1,
        show_channel   => exists $args{show_channel}   ? ( $args{show_channel}   ? 1 : 0 ) : 1,
        # Trendline auto: naranja (distinto del canal)
        col_tl => $theme->{auto_tl} // '#FB8C00',
        # Canal auto: mismos defaults que Drawing::ParallelChannel
        col_ch_line => $theme->{auto_canal_line} // $theme->{pchan_line} // '#42a5f5',
        col_ch_fill => $theme->{auto_canal_fill} // $theme->{pchan_fill} // '#2196f3',
        _start => 0,
        _end   => 0,
    };
    bless $self, $class;
    return $self;
}

sub tag { 'ov_auto_tc' }

sub set_visible {
    my ( $self, $bool ) = @_;
    $self->{visible} = $bool ? 1 : 0;
    return $self;
}

sub is_visible { $_[0]->{visible} ? 1 : 0 }

sub set_show_trendline {
    my ( $self, $on ) = @_;
    $self->{show_trendline} = $on ? 1 : 0;
    return $self;
}

sub set_show_channel {
    my ( $self, $on ) = @_;
    $self->{show_channel} = $on ? 1 : 0;
    return $self;
}

sub compute_visible {
    my ( $self, $market_data, $indicator, $start, $end ) = @_;
    $self->{_start} = $start // 0;
    $self->{_end}   = $end   // 0;
    return $self;
}

sub clear {
    my ( $self, $canvas ) = @_;
    return $self unless $canvas;
    eval { $canvas->delete( $self->tag() ); 1 };
    return $self;
}

sub _local {
    my ( $self, $g ) = @_;
    return ( $g // 0 ) - ( $self->{_start} // 0 );
}

sub _seg_visible {
    my ( $self, $a, $b ) = @_;
    my $s = $self->{_start} // 0;
    my $e = $self->{_end}   // 0;
    my ( $lo, $hi ) = $a <= $b ? ( $a, $b ) : ( $b, $a );
    return 0 if $hi < $s;
    return 0 if $lo > $e;
    return 1;
}

sub _line_at {
    my ( $slope, $intercept, $idx ) = @_;
    return $slope * $idx + $intercept;
}

sub draw {
    my ( $self, $canvas, $scales ) = @_;
    return $self unless $self->{visible} && $self->{indicator};
    return $self unless $canvas && $scales;
    $self->clear($canvas);

    my $vals = $self->{indicator}->get_values() || {};
    my $tag  = $self->tag();
    my $x_of = sub { $scales->index_to_center_x( $self->_local( $_[0] ) ) };
    my $y_of = sub { $scales->value_to_y( $_[0] ) };

    if ( $self->{show_trendline} ) {
        for my $tl ( @{ $vals->{trendlines} || [] } ) {
            my $i0 = $tl->{from_index} // next;
            my $i1 = $tl->{to_index}   // next;
            next unless $self->_seg_visible( $i0, $i1 );
            my $y0 = _line_at( $tl->{slope}, $tl->{intercept}, $i0 );
            my $y1 = _line_at( $tl->{slope}, $tl->{intercept}, $i1 );
            eval {
                $canvas->createLine(
                    $x_of->($i0), $y_of->($y0),
                    $x_of->($i1), $y_of->($y1),
                    -fill  => $self->{col_tl},
                    -width => 2,
                    -tags  => [ $tag, 'auto_tl' ],
                );
                1;
            };
        }
    }

    if ( $self->{show_channel} ) {
        for my $ch ( @{ $vals->{channels} || [] } ) {
            $self->_paint_channel( $canvas, $ch, $x_of, $y_of, $tag );
        }
    }

    return $self;
}

# Estilo ParallelChannel manual: fill stipple + 2 rieles + mediana (siempre ON).
sub _paint_channel {
    my ( $self, $canvas, $ch, $x_of, $y_of, $tag ) = @_;
    my $i0 = $ch->{from_index} // return;
    my $i1 = $ch->{to_index}   // return;
    return unless $self->_seg_visible( $i0, $i1 );
    return unless defined $ch->{slope} && defined $ch->{base_int} && defined $ch->{par_int};

    my $slope = $ch->{slope};
    my $yb0   = _line_at( $slope, $ch->{base_int}, $i0 );
    my $yb1   = _line_at( $slope, $ch->{base_int}, $i1 );
    my $yp0   = _line_at( $slope, $ch->{par_int},  $i0 );
    my $yp1   = _line_at( $slope, $ch->{par_int},  $i1 );

    my $line_c = $self->{col_ch_line};
    my $fill_c = $self->{col_ch_fill};

    # Polígono: base-izq → base-der → par-der → par-izq (igual que manual)
    eval {
        $canvas->createPolygon(
            $x_of->($i0), $y_of->($yb0),
            $x_of->($i1), $y_of->($yb1),
            $x_of->($i1), $y_of->($yp1),
            $x_of->($i0), $y_of->($yp0),
            -fill    => $fill_c,
            -outline => '',
            -stipple => 'gray25',
            -tags    => [ $tag, 'auto_canal_fill' ],
        );
        1;
    };

    eval {
        $canvas->createLine(
            $x_of->($i0), $y_of->($yb0),
            $x_of->($i1), $y_of->($yb1),
            -fill  => $line_c,
            -width => 2,
            -tags  => [ $tag, 'auto_canal' ],
        );
        $canvas->createLine(
            $x_of->($i0), $y_of->($yp0),
            $x_of->($i1), $y_of->($yp1),
            -fill  => $line_c,
            -width => 2,
            -tags  => [ $tag, 'auto_canal' ],
        );
        1;
    };

    # Mediana punteada (profe); estilo dash del mid manual ('.')
    my $mid_int = $ch->{mid_int};
    $mid_int = ( $ch->{base_int} + $ch->{par_int} ) / 2 unless defined $mid_int;
    my $ym0 = _line_at( $slope, $mid_int, $i0 );
    my $ym1 = _line_at( $slope, $mid_int, $i1 );
    eval {
        $canvas->createLine(
            $x_of->($i0), $y_of->($ym0),
            $x_of->($i1), $y_of->($ym1),
            -fill  => $line_c,
            -width => 1,
            -dash  => '.',
            -tags  => [ $tag, 'auto_median' ],
        );
        1;
    };

    # 3 puntos en lows REALES (mechas inferiores), no proyectados sobre la recta.
    # Si se pintan sobre la línea LS, un toque con error residual queda “en el aire”.
    my $touches = $ch->{touches} || [];
    for my $t (@$touches) {
        my $ti = $t->{index};
        my $tp = $t->{price};
        next unless defined $ti && defined $tp;
        next if $ti < ( $self->{_start} // 0 ) || $ti > ( $self->{_end} // 0 );
        my $x = $x_of->($ti);
        my $y = $y_of->($tp);
        eval {
            $canvas->createOval(
                $x - 5, $y - 5, $x + 5, $y + 5,
                -outline => '#ffffff',
                -fill    => $line_c,
                -width   => 2,
                -tags    => [ $tag, 'auto_canal_touch' ],
            );
            1;
        };
    }

    return $self;
}

1;
