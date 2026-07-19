package Market::Overlays::HLD;
use strict;
use warnings;

# Overlay HLD: resistencia (high) + soporte (low) de la vela HTF elegida.
# Tag ov_hld — no SMC.

sub new {
    my ( $class, %args ) = @_;
    die "Overlays::HLD: requiere 'indicator'" unless $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ( $args{visible} ? 1 : 0 ) : 0,
        _result   => undef,
        _range    => [ 0, 0 ],
    };
    bless $self, $class;
    return $self;
}

sub tag { 'ov_hld' }

sub set_visible {
    my ( $self, $bool ) = @_;
    $self->{visible} = $bool ? 1 : 0;
    return $self;
}

sub is_visible { $_[0]->{visible} }

sub compute_visible {
    my ( $self, $market_data, $indicator, $start, $end ) = @_;
    $self->{_range}  = [ $start // 0, $end // 0 ];
    $self->{_result} = undef;
    return $self unless $self->{visible} && $market_data;

    my $ind = $indicator // $self->{indicator};
    my $tf  = $market_data->{active_tf} // '';
    unless ( $tf eq '4h' || $tf eq 'D' ) {
        $self->{_result} = { ok => 0, reason => 'wrong_tf', tf => $tf };
        return $self;
    }

    my $end_i = $end;
    if ( defined $self->{_feed_end} && $self->{_feed_end} >= 0 ) {
        $end_i = $self->{_feed_end};
    }
    elsif ( $market_data->can('last_index') ) {
        $end_i = $market_data->last_index();
    }

    $self->{_result} = $ind->compute(
        $market_data,
        tf        => $tf,
        end_index => $end_i,
    );
    return $self;
}

sub clear {
    my ( $self, $canvas ) = @_;
    return unless $canvas;
    eval { $canvas->delete( $self->tag() ); 1 };
    return $self;
}

sub draw {
    my ( $self, $canvas, $scales ) = @_;
    return unless $self->{visible} && $canvas && $scales;
    $self->clear($canvas);

    my $r = $self->{_result};
    return $self unless $r && $r->{ok};

    my $tag       = $self->tag();
    my $win_start = ( $self->{_range} || [0] )->[0] // 0;
    my $res_c     = $self->{theme}{hld_resistance} // '#ef5350';
    my $sup_c     = $self->{theme}{hld_support}    // '#66bb6a';
    my $near_c    = $self->{theme}{hld_nearest}    // '#ffb74d';

    my $x_of = sub {
        my ($gi) = @_;
        return $scales->index_to_center_x( ( $gi // 0 ) - $win_start );
    };
    my $y_of = sub {
        my ($p) = @_;
        return $scales->value_to_y($p);
    };

    my $i1 = $r->{anchor_index};
    my $i2 = $r->{end_index};
    $i2 = $i1 + 1 if !defined $i2 || $i2 <= $i1;

    my $x1 = $x_of->($i1);
    my $x2 = $x_of->($i2);

    # Resistencia (high)
    my $y_r = $y_of->( $r->{resistance} );
    eval {
        $canvas->createLine(
            $x1, $y_r, $x2, $y_r,
            -fill  => $res_c,
            -width => 1,
            -tags  => [ $tag, 'hld_res' ],
        );
        $canvas->createText(
            $x2 - 4, $y_r - 8,
            -text   => 'HLD R',
            -fill   => $res_c,
            -anchor => 'e',
            -font   => [ 'TkDefaultFont', 7 ],
            -tags   => [ $tag, 'hld_lbl' ],
        );
        1;
    };

    # Soporte (low)
    my $y_s = $y_of->( $r->{support} );
    eval {
        $canvas->createLine(
            $x1, $y_s, $x2, $y_s,
            -fill  => $sup_c,
            -width => 1,
            -tags  => [ $tag, 'hld_sup' ],
        );
        $canvas->createText(
            $x2 - 4, $y_s + 10,
            -text   => 'HLD S',
            -fill   => $sup_c,
            -anchor => 'e',
            -font   => [ 'TkDefaultFont', 7 ],
            -tags   => [ $tag, 'hld_lbl' ],
        );
        1;
    };

    # Nivel OHLC más cercano (si no es high/low y show_nearest)
    if ( $r->{show_nearest} && $r->{nearest_ohlc} ) {
        my $nv = $r->{nearest_ohlc}{value};
        my $nf = $r->{nearest_ohlc}{field} // '';
        if ( defined $nv
            && abs( $nv - $r->{resistance} ) > 1e-9
            && abs( $nv - $r->{support} ) > 1e-9 )
        {
            my $y_n = $y_of->($nv);
            eval {
                $canvas->createLine(
                    $x1, $y_n, $x2, $y_n,
                    -fill  => $near_c,
                    -width => 1,
                    -dash  => '.',
                    -tags  => [ $tag, 'hld_near' ],
                );
                $canvas->createText(
                    $x2 - 4, $y_n - 8,
                    -text   => "HLD $nf",
                    -fill   => $near_c,
                    -anchor => 'e',
                    -font   => [ 'TkDefaultFont', 7 ],
                    -tags   => [ $tag, 'hld_lbl' ],
                );
                1;
            };
        }
    }

    return $self;
}

1;
