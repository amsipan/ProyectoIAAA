package Market::Overlays::ParallelChannel;
use strict;
use warnings;

# Render de Parallel Channel (drawing tool TV).
# Tag: draw_pchan — no ov_smc_* / zz_*.

sub new {
    my ( $class, %args ) = @_;
    my $self = {
        drawing => $args{drawing},    # Market::Drawing::ParallelChannel
        theme   => $args{theme} || {},
        visible => exists $args{visible} ? ( $args{visible} ? 1 : 0 ) : 1,
        _range  => [ 0, 0 ],
    };
    die "Overlays::ParallelChannel: requiere 'drawing'"
      unless $self->{drawing};
    bless $self, $class;
    return $self;
}

sub tag { 'draw_pchan' }

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
    eval { $canvas->delete('draw_pchan_preview'); 1 };
    return $self;
}

sub draw {
    my ( $self, $canvas, $scales ) = @_;
    return unless $self->{visible} && $canvas && $scales;
    $self->clear($canvas);

    my $draw = $self->{drawing};
    my $tag  = $self->tag();
    my ( $win_start, $win_end ) = @{ $self->{_range} || [ 0, 0 ] };

    my $data_end = $win_end;
    if ( $scales && defined $scales->{bars} ) {
        # data_end real lo pasa ChartEngine vía drawing; fallback view
    }

    my $x_of = sub {
        my ($gi) = @_;
        return $scales->index_to_center_x( ( $gi // 0 ) - $win_start );
    };
    my $y_of = sub {
        my ($p) = @_;
        return $scales->value_to_y($p);
    };

    my $ch = $draw->get_channel();
    if ($ch) {
        my $geo = $draw->geometry_for(
            $ch,
            data_end   => $self->{_data_end} // $win_end,
            view_start => $win_start,
            view_end   => $win_end,
        );
        $self->_paint_channel( $canvas, $scales, $geo, $ch, $x_of, $y_of, $tag )
          if $geo;
    }

    # Preview del draft
    my $draft = $draw->draft_points();
    if ( $draw->is_tool_active() && @$draft ) {
        # Con 2 puntos fijos + cursor: previsualizar el canal completo (p3 = cursor).
        # Así el usuario ve la altura/ancho siguiendo el ratón hasta el 3.er clic.
        if ( @$draft == 2 && $self->{_preview_cursor} ) {
            # p3 preview: precio = cursor; índice = medio del segmento base, para
            # que la altura se vea centrada igual que al fijar el 3.er clic.
            my $mid_index = ( $draft->[0]{index} + $draft->[1]{index} ) / 2;
            my $prev = {
                p1           => { %{ $draft->[0] } },
                p2           => { %{ $draft->[1] } },
                p3           => { index => $mid_index, price => 0 + $self->{_preview_cursor}{price} },
                extend_right => $draw->{extend_right} ? 1 : 0,
                extend_left  => $draw->{extend_left}  ? 1 : 0,
                show_mid     => $draw->{show_mid}     ? 1 : 0,
                line_color   => $draw->{line_color},
                fill_color   => $draw->{fill_color},
            };
            my $geo = $draw->geometry_for(
                $prev,
                data_end   => $self->{_data_end} // $win_end,
                view_start => $win_start,
                view_end   => $win_end,
            );
            $self->_paint_channel( $canvas, $scales, $geo, $prev, $x_of, $y_of, $tag )
              if $geo;
        }
        $self->_paint_draft( $canvas, $scales, $draft, $x_of, $y_of, $draw );
    }

    return $self;
}

sub _paint_channel {
    my ( $self, $canvas, $scales, $geo, $ch, $x_of, $y_of, $tag ) = @_;
    my $line_c = $ch->{line_color} // '#42a5f5';
    my $fill_c = $ch->{fill_color} // '#2196f3';

    my @poly;
    for my $pt ( @{ $geo->{poly_prices} || [] } ) {
        push @poly, $x_of->( $pt->[0] ), $y_of->( $pt->[1] );
    }
    if ( @poly >= 8 ) {
        eval {
            $canvas->createPolygon(
                @poly,
                -fill    => $fill_c,
                -outline => '',
                -stipple => 'gray25',
                -tags    => [ $tag, 'pchan_fill' ],
            );
            1;
        };
    }

    my ( $i0a, $p0a, $i0b, $p0b ) = @{ $geo->{line0} };
    my ( $i1a, $p1a, $i1b, $p1b ) = @{ $geo->{line1} };
    eval {
        $canvas->createLine(
            $x_of->($i0a), $y_of->($p0a), $x_of->($i0b), $y_of->($p0b),
            -fill  => $line_c,
            -width => 2,
            -tags  => [ $tag, 'pchan_l0' ],
        );
        $canvas->createLine(
            $x_of->($i1a), $y_of->($p1a), $x_of->($i1b), $y_of->($p1b),
            -fill  => $line_c,
            -width => 2,
            -tags  => [ $tag, 'pchan_l1' ],
        );
        1;
    };

    if ( $geo->{mid} ) {
        my ( $ia, $pa, $ib, $pb ) = @{ $geo->{mid} };
        eval {
            $canvas->createLine(
                $x_of->($ia), $y_of->($pa), $x_of->($ib), $y_of->($pb),
                -fill  => $line_c,
                -width => 1,
                -dash  => '.',
                -tags  => [ $tag, 'pchan_mid' ],
            );
            1;
        };
    }

    # Handles arrastrables en las 3 anclas (p1/p2 = base, p3 = paralela).
    for my $name (qw(p1 p2 p3)) {
        my $pt = $ch->{$name} or next;
        my $x  = $x_of->( $pt->{index} );
        my $y  = $y_of->( $pt->{price} );
        eval {
            $canvas->createOval(
                $x - 5, $y - 5, $x + 5, $y + 5,
                -outline => '#ffffff',
                -fill    => $line_c,
                -width   => 2,
                -tags    => [ $tag, "pchan_handle_$name" ],
            );
            1;
        };
    }

    # Punto medio de la línea BASE (altura del lado base). El lado de la paralela
    # ya tiene su handle de altura en p3, que está centrado en el índice medio.
    my $mid_i = ( $geo->{i_min} + $geo->{i_max} ) / 2;
    my ( undef, $mb0, undef, $mb1 ) = @{ $geo->{line0} };
    {
        my $x = $x_of->($mid_i);
        my $y = $y_of->( ( $mb0 + $mb1 ) / 2 );
        eval {
            $canvas->createRectangle(
                $x - 4, $y - 4, $x + 4, $y + 4,
                -outline => '#ffffff',
                -fill    => $line_c,
                -width   => 2,
                -tags    => [ $tag, 'pchan_mid_base' ],
            );
            1;
        };
    }
}

# hit_test → handle bajo el cursor, o undef. Prioridad:
#   'p1'|'p2'|'p3'  → esquinas y altura de la paralela (p3 ya está centrado)
#   'mid_base'      → punto medio de la línea base (altura del lado base)
#   'body'          → cuerpo de un segmento (arrastrar todo el canal)
sub hit_test {
    my ( $self, $x, $y, $scales, $win_start ) = @_;
    my $draw = $self->{drawing};
    my $ch   = $draw ? $draw->get_channel() : undef;
    return undef unless $ch && $scales;

    $win_start //= ( $self->{_range}[0] // 0 );
    my $x_of = sub {
        my ($gi) = @_;
        return $scales->index_to_center_x( ( $gi // 0 ) - $win_start );
    };
    my $y_of = sub { $scales->value_to_y( $_[0] ) };
    my $near = sub {
        my ( $px, $py, $tol ) = @_;
        $tol //= 12;
        return abs( $x - $px ) <= $tol && abs( $y - $py ) <= $tol;
    };

    # 1) Esquinas
    for my $name (qw(p1 p2 p3)) {
        my $pt = $ch->{$name} or next;
        return $name
          if $near->( $x_of->( $pt->{index} ), $y_of->( $pt->{price} ) );
    }

    # Geometría de las dos líneas para medios y cuerpo.
    my $geo = $draw->geometry_for(
        $ch,
        data_end   => $self->{_data_end} // ( $self->{_range}[1] // 0 ),
        view_start => $win_start,
        view_end   => ( $self->{_range}[1] // 0 ),
    );
    return undef unless $geo;
    my ( $i0a, $p0a, $i0b, $p0b ) = @{ $geo->{line0} };   # base (p1-p2)
    my ( $i1a, $p1a, $i1b, $p1b ) = @{ $geo->{line1} };   # paralela (p3)

    # 2) Punto medio de la línea base (altura del lado base). El lado paralela
    #    usa p3, ya cubierto arriba como esquina (está centrado en el medio).
    my $mid_i = ( $geo->{i_min} + $geo->{i_max} ) / 2;
    my $base_mid_p = ( $p0a + $p0b ) / 2;
    return 'mid_base'
      if $near->( $x_of->($mid_i), $y_of->($base_mid_p) );

    # 3) Cuerpo: sobre cualquiera de los dos segmentos (perpendicular <= tol)
    my $on_seg = sub {
        my ( $ia, $pa, $ib, $pb ) = @_;
        return _dist_to_segment(
            $x, $y,
            $x_of->($ia), $y_of->($pa), $x_of->($ib), $y_of->($pb),
        ) <= 6;
    };
    return 'body' if $on_seg->( $i0a, $p0a, $i0b, $p0b );
    return 'body' if $on_seg->( $i1a, $p1a, $i1b, $p1b );

    return undef;
}

# Distancia de un punto al segmento en píxeles.
sub _dist_to_segment {
    my ( $px, $py, $ax, $ay, $bx, $by ) = @_;
    my $dx = $bx - $ax;
    my $dy = $by - $ay;
    my $len2 = $dx * $dx + $dy * $dy;
    return sqrt( ( $px - $ax )**2 + ( $py - $ay )**2 ) if $len2 < 1e-9;
    my $t = ( ( $px - $ax ) * $dx + ( $py - $ay ) * $dy ) / $len2;
    $t = 0 if $t < 0;
    $t = 1 if $t > 1;
    my $cx = $ax + $t * $dx;
    my $cy = $ay + $t * $dy;
    return sqrt( ( $px - $cx )**2 + ( $py - $cy )**2 );
}

sub _paint_draft {
    my ( $self, $canvas, $scales, $draft, $x_of, $y_of, $draw ) = @_;
    my $ptag = 'draw_pchan_preview';
    eval { $canvas->delete($ptag); 1 };

    for my $pt (@$draft) {
        my $x = $x_of->( $pt->{index} );
        my $y = $y_of->( $pt->{price} );
        eval {
            $canvas->createOval(
                $x - 4, $y - 4, $x + 4, $y + 4,
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
                -width => 1,
                -dash  => '-',
                -tags  => $ptag,
            );
            1;
        };
    }

    if ( @$draft >= 3 ) {
        # no debería ocurrir (commit al 3er punto); por si acaso
    }
    elsif ( @$draft == 2 && $draw->is_tool_active() ) {
        # esperando p3 — sin paralela aún
    }
}

1;
