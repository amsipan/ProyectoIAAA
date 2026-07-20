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
}

# hit_test → 'p1'|'p2'|'p3' si el clic cae sobre un ancla, o undef.
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

    for my $name (qw(p1 p2 p3)) {
        my $pt = $ch->{$name} or next;
        return $name
          if $near->( $x_of->( $pt->{index} ), $y_of->( $pt->{price} ) );
    }
    return undef;
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
