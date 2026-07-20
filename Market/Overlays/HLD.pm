package Market::Overlays::HLD;
use strict;
use warnings;

# Overlay HLD: resistencia (high) + soporte (low) de la vela HTF elegida.
# Etiquetas: chip a la DERECHA de cada línea, misma altura Y que la línea
# (así se ve qué etiqueta corresponde a qué trazo).

sub new {
    my ( $class, %args ) = @_;
    die "Overlays::HLD: requiere 'indicator'" unless $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ( $args{visible} ? 1 : 0 ) : 0,
        _result   => undef,
        _range    => [ 0, 0 ],
        _md       => undef,
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
    $self->{_md}     = $market_data;
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

    my $res_c  = $self->{theme}{hld_resistance} // '#c2185b';
    my $sup_c  = $self->{theme}{hld_support}    // '#1565c0';
    my $near_c = $self->{theme}{hld_nearest}    // '#e65100';
    my $lbl_c  = $self->{theme}{hld_label}      // '#000000';
    my $chip_c = $self->{theme}{hld_label_bg}   // '#ffffff';
    my $lbl_font = [ 'TkDefaultFont', 8, 'bold' ];

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

    # --- Líneas ---
    my $y_r = $y_of->( $r->{resistance} );
    eval {
        $canvas->createLine(
            $x1, $y_r, $x2, $y_r,
            -fill  => $res_c,
            -width => 2,
            -tags  => [ $tag, 'hld_res' ],
        );
        1;
    };

    my @labels;    # { text, price, y_nat }  y_nat = altura natural de la línea
    push @labels,
      { text => 'HLD R', price => $r->{resistance}, y_nat => $y_r };

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
                    -width => 2,
                    -dash  => '.-',
                    -tags  => [ $tag, 'hld_near' ],
                );
                1;
            };
            push @labels,
              { text => "HLD $nf", price => $nv, y_nat => $y_n };
        }
    }

    my $y_s = $y_of->( $r->{support} );
    eval {
        $canvas->createLine(
            $x1, $y_s, $x2, $y_s,
            -fill  => $sup_c,
            -width => 2,
            -tags  => [ $tag, 'hld_sup' ],
        );
        1;
    };
    push @labels, { text => 'HLD S', price => $r->{support}, y_nat => $y_s };

    # --- Etiquetas a la DERECHA, misma altura que su línea ---
    # Si se solapan: ordenar por Y de pantalla (arriba→abajo) y empujar SOLO
    # hacia abajo a las de más abajo, sin invertir el orden (evita HLD S
    # encima de HLD close cuando la línea S está debajo).
    my $th      = 14;
    my $min_gap = $th + 6;
    @labels = sort { $a->{y_nat} <=> $b->{y_nat} } @labels;    # top first

    my $prev_y;
    for my $lb (@labels) {
        my $y = $lb->{y_nat};
        if ( defined $prev_y && $y < $prev_y + $min_gap ) {
            $y = $prev_y + $min_gap;    # solo empuja hacia abajo
        }
        $lb->{y_draw} = $y;
        $prev_y = $y;
    }

    for my $lb (@labels) {
        my $text = $lb->{text};
        my $tw   = 7 * length($text) + 12;
        my $x    = $x2 + 10 + $tw / 2;
        my $y    = $lb->{y_draw};
        my $x0   = $x - $tw / 2;
        my $y_top = $y - $th / 2;
        eval {
            $canvas->createRectangle(
                $x0 - 2, $y_top - 1, $x0 + $tw + 2, $y_top + $th + 1,
                -fill    => $chip_c,
                -outline => '#424242',
                -width   => 1,
                -tags    => [ $tag, 'hld_lbl_bg' ],
            );
            $canvas->createText(
                $x, $y,
                -text   => $text,
                -fill   => $lbl_c,
                -anchor => 'center',
                -font   => $lbl_font,
                -tags   => [ $tag, 'hld_lbl' ],
            );
            1;
        };
    }

    return $self;
}

1;
