package Market::Overlays::FibRetracement;
use strict;
use warnings;

# =============================================================================
# Render Fib Retracement estilo TradingView:
# bandas + líneas + labels FUERA a la izquierda (misma altura) + handles
# =============================================================================

# Espacio a la izquierda de las cajas para las etiquetas (px)
my $LABEL_OUTSIDE_PX = 110;

sub new {
    my ( $class, %args ) = @_;
    my $self = {
        drawing   => $args{drawing},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ( $args{visible} ? 1 : 0 ) : 1,
        _range    => [ 0, 0 ],
        _data_end => undef,
    };
    die "Overlays::FibRetracement: requiere 'drawing'"
      unless $self->{drawing};
    bless $self, $class;
    return $self;
}

sub tag { 'draw_fib' }

sub set_visible {
    my ( $self, $bool ) = @_;
    $self->{visible} = $bool ? 1 : 0;
    return $self;
}

sub is_visible { $_[0]->{visible} }

sub compute_visible {
    my ( $self, $market_data, $indicator, $start, $end ) = @_;
    $self->{_range} = [ $start // 0, $end // 0 ];
    return $self;
}

sub clear {
    my ( $self, $canvas ) = @_;
    return unless $canvas;
    eval { $canvas->delete( $self->tag() ); 1 };
    eval { $canvas->delete('draw_fib_preview'); 1 };
    return $self;
}

sub draw {
    my ( $self, $canvas, $scales ) = @_;
    return unless $self->{visible} && $canvas && $scales;
    $self->clear($canvas);

    my $draw = $self->{drawing};
    my $tag  = $self->tag();
    my ( $win_start, $win_end ) = @{ $self->{_range} || [ 0, 0 ] };

    my $x_of = sub {
        my ($gi) = @_;
        return $scales->index_to_center_x( ( $gi // 0 ) - $win_start );
    };
    my $y_of = sub {
        my ($p) = @_;
        return $scales->value_to_y($p);
    };

    my $fib = $draw->get_fib();
    if ($fib) {
        my $geo = $draw->geometry_for(
            $fib,
            data_end   => $self->{_data_end} // $win_end,
            view_start => $win_start,
            view_end   => $win_end,
        );
        $self->_paint_fib( $canvas, $scales, $geo, $x_of, $y_of, $tag )
          if $geo;
    }

    my $draft = $draw->draft_points();
    if ( $draw->is_tool_active() && @$draft ) {
        $self->_paint_draft( $canvas, $draft, $x_of, $y_of );
    }

    return $self;
}

sub _paint_fib {
    my ( $self, $canvas, $scales, $geo, $x_of, $y_of, $tag ) = @_;
    my $levels = $geo->{levels} || [];
    return unless @$levels;

    my $x0 = $x_of->( $geo->{left_index} );
    my $x1 = $x_of->( $geo->{right_index} );
    if ( $x1 < $x0 ) {
        ( $x0, $x1 ) = ( $x1, $x0 );
    }
    $x1 = $x0 + 40 if $x1 - $x0 < 40;

    # Cajas empiezan un poco a la derecha si hace falta sitio para labels
    # Labels van FUERA a la izquierda de x0 (anchor e), misma Y que la línea.
    my $box_left = $x0;
    if ( $box_left < $LABEL_OUTSIDE_PX + 4 ) {
        # Si el ancla está muy a la izquierda, no empujar la caja (evitar overflow);
        # el label puede quedar parcialmente en el margen.
    }

    # Bandas entre niveles consecutivos
    if ( $geo->{background} ) {
        for my $i ( 0 .. $#$levels - 1 ) {
            my $lo  = $levels->[$i];
            my $hi  = $levels->[ $i + 1 ];
            my $y_a = $y_of->( $lo->{price} );
            my $y_b = $y_of->( $hi->{price} );
            my ( $yt, $yb ) = $y_a < $y_b ? ( $y_a, $y_b ) : ( $y_b, $y_a );
            my $fill = $hi->{fill} // $hi->{color} // '#787b86';
            eval {
                $canvas->createRectangle(
                    $box_left, $yt, $x1, $yb,
                    -fill    => $fill,
                    -outline => '',
                    -stipple => 'gray25',
                    -tags    => [ $tag, 'fib_fill' ],
                );
                1;
            };
        }
    }

    # Líneas + labels FUERA a la izquierda, a la misma altura
    for my $lv (@$levels) {
        my $y   = $y_of->( $lv->{price} );
        my $col = $lv->{color} // '#787b86';
        eval {
            $canvas->createLine(
                $box_left, $y, $x1, $y,
                -fill  => $col,
                -width => 2,
                -tags  => [ $tag, 'fib_line' ],
            );
            1;
        };
        if ( $geo->{show_prices} && $canvas->can('createText') ) {
            my $r = $lv->{ratio} // 0;
            my $r_txt = sprintf( '%.3f', $r );
            $r_txt =~ s/0+$//;
            $r_txt =~ s/\.$//;
            $r_txt = '0' if $r_txt eq '' || $r_txt eq '-';
            my $p_txt = _fmt_price( $lv->{price} );
            my $label = "$r_txt ($p_txt)";
            # Fuera de las cajitas: a la izquierda del borde, ancla este (derecha del texto)
            my $lx = $box_left - 6;
            eval {
                $canvas->createText(
                    $lx, $y,
                    -text   => $label,
                    -anchor => 'e',
                    -fill   => $col,
                    -font   => [ 'Helvetica', 9, 'bold' ],
                    -tags   => [ $tag, 'fib_lbl' ],
                );
                1;
            };
        }
    }

    # Handles anclas p1 / p2
    for my $name (qw(p1 p2)) {
        my $pt = $geo->{$name} or next;
        my $x  = $x_of->( $pt->{index} );
        my $y  = $y_of->( $pt->{price} );
        eval {
            $canvas->createOval(
                $x - 5, $y - 5, $x + 5, $y + 5,
                -outline => '#ffffff',
                -fill    => '#2962ff',
                -width   => 2,
                -tags    => [ $tag, "fib_handle_$name" ],
            );
            1;
        };
    }

    # Solo handle derecho para ampliar (sin Ext L/R fijos)
    my $ymid = @$levels
      ? $y_of->( ( $levels->[0]{price} + $levels->[-1]{price} ) / 2 )
      : 100;
    eval {
        $canvas->createRectangle(
            $x1 - 3, $ymid - 10, $x1 + 3, $ymid + 10,
            -outline => '#ffffff',
            -fill    => '#ff9800',
            -tags    => [ $tag, 'fib_handle_right' ],
        );
        1;
    };
}

sub _fmt_price {
    my ($p) = @_;
    return '' unless defined $p;
    my $s = sprintf( '%.2f', $p );
    $s = reverse $s;
    $s =~ s/(\d{3})(?=\d)/$1,/g;
    return reverse $s;
}

sub _paint_draft {
    my ( $self, $canvas, $draft, $x_of, $y_of ) = @_;
    my $ptag = 'draw_fib_preview';
    eval { $canvas->delete($ptag); 1 };

    for my $pt (@$draft) {
        my $x = $x_of->( $pt->{index} );
        my $y = $y_of->( $pt->{price} );
        eval {
            $canvas->createOval(
                $x - 5, $y - 5, $x + 5, $y + 5,
                -outline => '#ffeb3b',
                -fill    => '#ffeb3b',
                -tags    => $ptag,
            );
            1;
        };
    }
    if ( @$draft >= 2 ) {
        my $a = $draft->[0];
        my $b = $draft->[1];
        eval {
            $canvas->createLine(
                $x_of->( $a->{index} ), $y_of->( $a->{price} ),
                $x_of->( $b->{index} ), $y_of->( $b->{price} ),
                -fill  => '#ffeb3b',
                -width => 2,
                -dash  => '-',
                -tags  => $ptag,
            );
            1;
        };
    }
}

# hit_test → 'p1'|'p2'|'right'|undef  (left handle eliminado)
sub hit_test {
    my ( $self, $x, $y, $scales, $win_start ) = @_;
    my $draw = $self->{drawing};
    my $fib  = $draw->get_fib();
    return undef unless $fib && $scales;

    $win_start //= ( $self->{_range}[0] // 0 );
    my $x_of = sub {
        my ($gi) = @_;
        return $scales->index_to_center_x( ( $gi // 0 ) - $win_start );
    };
    my $y_of = sub { $scales->value_to_y( $_[0] ) };
    my $near = sub {
        my ( $px, $py, $tol ) = @_;
        $tol //= 10;
        return abs( $x - $px ) <= $tol && abs( $y - $py ) <= $tol;
    };

    my $p1 = $fib->{p1};
    my $p2 = $fib->{p2};
    if ( $p1 && $near->( $x_of->( $p1->{index} ), $y_of->( $p1->{price} ), 12 ) ) {
        return 'p1';
    }
    if ( $p2 && $near->( $x_of->( $p2->{index} ), $y_of->( $p2->{price} ), 12 ) ) {
        return 'p2';
    }

    my $geo = $draw->geometry_for(
        $fib,
        data_end   => $self->{_data_end} // ( $self->{_range}[1] // 0 ),
        view_start => $win_start,
        view_end   => $self->{_range}[1] // 0,
    );
    return undef unless $geo;
    my $x1   = $x_of->( $geo->{right_index} );
    my @lv   = @{ $geo->{levels} || [] };
    my $ymid = @lv ? $y_of->( ( $lv[0]{price} + $lv[-1]{price} ) / 2 ) : 0;
    if ( $near->( $x1, $ymid, 14 ) ) { return 'right' }
    return undef;
}

1;
