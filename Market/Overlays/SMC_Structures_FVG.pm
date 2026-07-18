package Market::Overlays::SMC_Structures_FVG;
use strict;
use warnings;

# Render capa "SMC Structures and FVG" (LudoGH68) — config captura del profesor.
# FVG: bull green / bear red / mitigated gray, max 5, reduce mitigated ON.
# Structure: BOS gray, CHoCH bull green / bear red, width 1, max 10 breaks.
# Sin fibs, sin current structure.

sub new {
    my ($class, %args) = @_;
    die "Overlays::SMC_Structures_FVG->new: requiere 'indicator'"
        unless defined $args{indicator};
    my $self = {
        indicator      => $args{indicator},
        theme          => $args{theme} || {},
        visible        => exists $args{visible} ? ($args{visible} ? 1 : 0) : 0,
        _events        => [],
        _fvgs          => [],
        _compute_range => undef,
    };
    bless $self, $class;
    return $self;
}

sub tag { 'ov_smc_fvg' }

sub set_visible {
    my ($self, $bool) = @_;
    $self->{visible} = $bool ? 1 : 0;
    return $self;
}

sub is_visible { $_[0]->{visible} }

sub _segment_overlaps {
    my ($a, $b, $vs, $ve) = @_;
    return 0 unless defined $a && defined $b && defined $vs && defined $ve;
    my ($lo, $hi) = $a <= $b ? ($a, $b) : ($b, $a);
    return ( $hi >= $vs && $lo <= $ve ) ? 1 : 0;
}

sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $start //= 0;
    $end   //= 0;
    $self->{_compute_range} = [ $start, $end ];
    my $ind = $indicator // $self->{indicator};

    # Zoom-independiente: segmentos/cajas que cruzan el viewport (como TV).
    my @ev;
    for my $e ( @{ $ind->get_events() || [] } ) {
        next unless ref($e) eq 'HASH' && defined $e->{index};
        my $s = $e->{start_index} // $e->{index};
        next unless _segment_overlaps( $s, $e->{index}, $start, $end );
        push @ev, $e;
    }
    $self->{_events} = \@ev;

    $self->{_fvgs} = [
        grep {
            ref($_) eq 'HASH'
              && _segment_overlaps(
                $_->{left}  // $_->{index} // 0,
                $_->{right} // $_->{index} // 0,
                $start, $end
              )
        } @{ $ind->get_fvg() || [] }
    ];
    return $self;
}

sub clear {
    my ($self, $canvas) = @_;
    return unless $canvas;
    eval { $canvas->delete( $self->tag() ); 1 };
    return $self;
}

sub _plot_bounds {
    my ($self, $scales) = @_;
    my $w = $scales->{width} // 0;
    $w = 1 if $w < 1;
    return ( -120, $w + 120 );
}

sub _clip_x {
    my ($self, $scales, $x1, $x2) = @_;
    my ( $lo, $hi ) = $self->_plot_bounds($scales);
    return if ( $x1 < $lo && $x2 < $lo ) || ( $x1 > $hi && $x2 > $hi );
    $x1 = $lo if $x1 < $lo;
    $x1 = $hi if $x1 > $hi;
    $x2 = $lo if $x2 < $lo;
    $x2 = $hi if $x2 > $hi;
    return ( $x1, $x2 );
}

sub draw {
    my ($self, $canvas, $scales) = @_;
    return unless $self->{visible} && $canvas && $scales;
    $self->clear($canvas);
    my $tag       = $self->tag();
    my $win_start = ( $self->{_compute_range} || [0] )->[0] // 0;

    # Captura: BOS gray; CHoCH green/red; FVG green/red/mitigated gray
    my $bos_c    = $self->{theme}{fvg_bos}        // '#9e9e9e';
    my $choch_b  = $self->{theme}{fvg_choch_bull} // '#00c853';
    my $choch_r  = $self->{theme}{fvg_choch_bear} // '#f44336';
    my $fvg_bull = $self->{theme}{fvg_bull}       // '#4caf50';
    my $fvg_bear = $self->{theme}{fvg_bear}       // '#ef5350';
    my $fvg_mit  = $self->{theme}{fvg_mit}        // '#9e9e9e';

    my $x_center = sub {
        my ($g) = @_;
        return $scales->index_to_center_x( ( $g // 0 ) - $win_start );
    };
    my $x_left = sub {
        my ($g) = @_;
        return $scales->index_to_x( ( $g // 0 ) - $win_start );
    };
    my $x_right = sub {
        my ($g) = @_;
        return $scales->index_to_x( ( $g // 0 ) - $win_start + 1 );
    };
    my $y_of = sub {
        my ($p) = @_;
        return $scales->value_to_y($p);
    };

    # 1) FVG boxes
    for my $f ( @{ $self->{_fvgs} } ) {
        my $x1 = $x_left->( $f->{left}  // $f->{index} );
        my $x2 = $x_right->( $f->{right} // $f->{index} );
        my @cx = $self->_clip_x( $scales, $x1, $x2 );
        next unless @cx;
        ( $x1, $x2 ) = @cx;
        my $y1 = $y_of->( $f->{hi} );
        my $y2 = $y_of->( $f->{lo} );
        ( $y1, $y2 ) = ( $y2, $y1 ) if $y1 > $y2;
        my $fill =
            $f->{mitig} ? $fvg_mit
          : ( ( $f->{type} // '' ) eq 'bull' ? $fvg_bull : $fvg_bear );
        eval {
            $canvas->createRectangle(
                $x1, $y1, $x2, $y2,
                -outline => $fill,
                -fill    => $fill,
                -stipple => 'gray25',
                -width   => 1,
                -tags    => [ $tag, 'sfvg_box' ],
            );
            $canvas->createText(
                ( $x1 + $x2 ) / 2,
                ( $y1 + $y2 ) / 2,
                -text => 'FVG',
                -fill => '#ffffff',
                -font => [ 'TkDefaultFont', 7 ],
                -tags => [ $tag, 'sfvg_lbl' ],
            );
            1;
        };
    }

    # 2) Structure breaks — centro de vela, width 1
    for my $e ( @{ $self->{_events} } ) {
        my $role = $e->{color_role} // '';
        my $col  = $bos_c;
        $col = $choch_b if $role eq 'choch_bull';
        $col = $choch_r if $role eq 'choch_bear';
        $col = $bos_c   if $role =~ /^bos_/;

        my $x1 = $x_center->( $e->{start_index} // $e->{index} );
        my $x2 = $x_center->( $e->{index} );
        my @cx = $self->_clip_x( $scales, $x1, $x2 );
        next unless @cx;
        ( $x1, $x2 ) = @cx;
        my $y = $y_of->( $e->{price} );
        eval {
            $canvas->createLine(
                $x1, $y, $x2, $y,
                -fill  => $col,
                -width => 1,
                -tags  => [ $tag, 'sfvg_evt' ],
            );
            $canvas->createText(
                ( $x1 + $x2 ) / 2,
                $y - 8,
                -text => $e->{type} // '',
                -fill => $col,
                -font => [ 'TkDefaultFont', 7 ],
                -tags => [ $tag, 'sfvg_evt_lbl' ],
            );
            1;
        };
    }

    return $self;
}

# Densidad: no filtrar (paridad TV / captura). Stubs no-op.
sub set_density_pct         { $_[0] }
sub density_pct             { 100 }
sub set_element_density_pct { $_[0] }
sub element_density_pct     { 100 }

1;
