package Market::Drawing::ParallelChannel;
use strict;
use warnings;

# Herramienta Parallel Channel (TradingView drawing tool).
# 3 anclas: p1-p2 = trendline base; p3 define la paralela (misma pendiente).
# Política Fase A: un solo canal activo (crear otro reemplaza).

sub new {
    my ( $class, %args ) = @_;
    my $self = {
        channel      => undef,    # hash p1,p2,p3,extend_*,colors
        draft        => [],       # 0..2 puntos mientras se dibuja
        tool_active  => 0,
        extend_right => exists $args{extend_right} ? ( $args{extend_right} ? 1 : 0 ) : 0,
        extend_left  => exists $args{extend_left}  ? ( $args{extend_left}  ? 1 : 0 ) : 0,
        show_mid     => $args{show_mid} ? 1 : 0,
        line_color   => $args{line_color} // '#42a5f5',
        fill_color   => $args{fill_color} // '#2196f3',
    };
    bless $self, $class;
    return $self;
}

sub is_tool_active { $_[0]->{tool_active} ? 1 : 0 }

sub start_tool {
    my ($self) = @_;
    $self->{tool_active} = 1;
    $self->{draft}       = [];
    return $self;
}

sub cancel_tool {
    my ($self) = @_;
    $self->{tool_active} = 0;
    $self->{draft}       = [];
    return $self;
}

sub clear_channel {
    my ($self) = @_;
    $self->{channel} = undef;
    return $self;
}

sub get_channel { $_[0]->{channel} }

# set_point($which, {index,price}) — reposiciona un ancla del canal (p1|p2|p3).
# p1/p2 definen la pendiente de la trendline base; p3 la paralela. Mover
# cualquiera recalcula toda la geometría en geometry_for.
sub set_point {
    my ( $self, $which, $pt ) = @_;
    return $self unless $self->{channel};
    return $self unless $which eq 'p1' || $which eq 'p2' || $which eq 'p3';
    return $self unless ref($pt) eq 'HASH';
    my $cur = $self->{channel}{$which};
    $self->{channel}{$which} = {
        index => 0 + ( defined $pt->{index} ? $pt->{index} : $cur->{index} ),
        price => 0 + ( defined $pt->{price} ? $pt->{price} : $cur->{price} ),
    };
    return $self;
}

# base_mid_index — índice medio del segmento base (p1-p2).
sub base_mid_index {
    my ($self) = @_;
    my $ch = $self->{channel} or return undef;
    return ( $ch->{p1}{index} + $ch->{p2}{index} ) / 2;
}

# base_mid_price — precio de la línea base en su índice medio.
sub base_mid_price {
    my ($self) = @_;
    my $ch = $self->{channel} or return undef;
    my $m  = $self->slope( $ch->{p1}, $ch->{p2} );
    return $self->price_on_line( $ch->{p1}, $m, $self->base_mid_index() );
}

# move_base_to_price($price) — desplaza la línea BASE verticalmente para que su
# punto medio pase por $price (mueve p1 y p2 por el mismo delta, conserva la
# pendiente). Es el handle de altura del lado de la base (segmento con p1/p2).
sub move_base_to_price {
    my ( $self, $price ) = @_;
    my $ch = $self->{channel} or return $self;
    return $self unless defined $price;
    my $cur = $self->base_mid_price();
    return $self unless defined $cur;
    my $dp = $price - $cur;
    $ch->{p1}{price} += $dp;
    $ch->{p2}{price} += $dp;
    return $self;
}

# move_channel($d_index, $d_price) — traslada TODO el canal (p1,p2,p3) por un
# delta. Usado al arrastrar el cuerpo (segmento superior o inferior).
sub move_channel {
    my ( $self, $di, $dp ) = @_;
    my $ch = $self->{channel} or return $self;
    for my $which (qw(p1 p2 p3)) {
        $ch->{$which}{index} += $di;
        $ch->{$which}{price} += $dp;
    }
    return $self;
}

sub draft_points { [ @{ $_[0]->{draft} || [] } ] }

sub draft_count {
    my ($self) = @_;
    return scalar @{ $self->{draft} || [] };
}

# add_point({ index => i, price => p }) — en modo tool.
# Retorna: 'draft' | 'done' | undef (ignorado)
sub add_point {
    my ( $self, $pt ) = @_;
    return undef unless $self->{tool_active};
    return undef unless ref($pt) eq 'HASH'
      && defined $pt->{index}
      && defined $pt->{price};

    push @{ $self->{draft} }, {
        index => 0 + $pt->{index},
        price => 0 + $pt->{price},
    };

    if ( @{ $self->{draft} } >= 3 ) {
        $self->_commit_draft;
        $self->{tool_active} = 0;
        $self->{draft}       = [];
        return 'done';
    }
    return 'draft';
}

sub _commit_draft {
    my ($self) = @_;
    my @d = @{ $self->{draft} || [] };
    return unless @d >= 3;
    # p3 = altura del canal: el 3.er clic aporta solo el PRECIO; su índice se
    # fija al punto MEDIO del segmento base (p1-p2), como en TradingView, para
    # que el handle de altura quede centrado en la línea superior/inferior.
    my $mid_index = ( $d[0]{index} + $d[1]{index} ) / 2;
    # Un solo canal: reemplaza el anterior
    $self->{channel} = {
        p1           => { %{ $d[0] } },
        p2           => { %{ $d[1] } },
        p3           => { index => $mid_index, price => 0 + $d[2]{price} },
        extend_right => $self->{extend_right} ? 1 : 0,
        extend_left  => $self->{extend_left}  ? 1 : 0,
        show_mid     => $self->{show_mid}     ? 1 : 0,
        line_color   => $self->{line_color},
        fill_color   => $self->{fill_color},
    };
    return $self->{channel};
}

# slope / geometry helpers (públicos para tests)
sub slope {
    my ( $class_or_self, $p1, $p2 ) = @_;
    my $di = ( $p2->{index} // 0 ) - ( $p1->{index} // 0 );
    return 0 if abs($di) < 1e-12;
    return ( ( $p2->{price} // 0 ) - ( $p1->{price} // 0 ) ) / $di;
}

sub price_on_line {
    my ( $class_or_self, $anchor, $m, $index ) = @_;
    return ( $anchor->{price} // 0 )
      + $m * ( ( $index // 0 ) - ( $anchor->{index} // 0 ) );
}

# geometry_for($channel, %opts) — rangos de dibujo
# opts: data_end (último índice), view_start, view_end
sub geometry_for {
    my ( $self, $ch, %opts ) = @_;
    return undef unless ref($ch) eq 'HASH'
      && ref( $ch->{p1} ) eq 'HASH'
      && ref( $ch->{p2} ) eq 'HASH'
      && ref( $ch->{p3} ) eq 'HASH';

    my $p1 = $ch->{p1};
    my $p2 = $ch->{p2};
    my $p3 = $ch->{p3};
    my $m  = $self->slope( $p1, $p2 );

    my $i_min = $p1->{index};
    $i_min = $p2->{index} if $p2->{index} < $i_min;
    $i_min = $p3->{index} if $p3->{index} < $i_min;
    my $i_max = $p1->{index};
    $i_max = $p2->{index} if $p2->{index} > $i_max;
    $i_max = $p3->{index} if $p3->{index} > $i_max;

    if ( $ch->{extend_right} ) {
        my $end = $opts{data_end};
        $end = $opts{view_end} if !defined $end && defined $opts{view_end};
        $i_max = $end if defined $end && $end > $i_max;
    }
    if ( $ch->{extend_left} ) {
        my $start = $opts{view_start} // 0;
        $i_min = $start if $start < $i_min;
    }

    # Evitar rango degenerado
    $i_max = $i_min + 1 if $i_max <= $i_min;

    my $y0_l = $self->price_on_line( $p1, $m, $i_min );
    my $y0_r = $self->price_on_line( $p1, $m, $i_max );
    my $y1_l = $self->price_on_line( $p3, $m, $i_min );
    my $y1_r = $self->price_on_line( $p3, $m, $i_max );

    my $mid_l;
    my $mid_r;
    if ( $ch->{show_mid} ) {
        $mid_l = ( $y0_l + $y1_l ) / 2;
        $mid_r = ( $y0_r + $y1_r ) / 2;
    }

    return {
        m       => $m,
        i_min   => $i_min,
        i_max   => $i_max,
        line0   => [ $i_min, $y0_l, $i_max, $y0_r ],
        line1   => [ $i_min, $y1_l, $i_max, $y1_r ],
        mid     => ( defined $mid_l ? [ $i_min, $mid_l, $i_max, $mid_r ] : undef ),
        # polígono fill: L0 left -> L0 right -> L1 right -> L1 left
        poly_prices => [
            [ $i_min, $y0_l ],
            [ $i_max, $y0_r ],
            [ $i_max, $y1_r ],
            [ $i_min, $y1_l ],
        ],
    };
}

# slopes_parallel($ch) — test helper
sub slopes_equal {
    my ( $self, $ch ) = @_;
    my $m0 = $self->slope( $ch->{p1}, $ch->{p2} );
    # paralela: p3 + m; precio en p2.index sobre L1 vs L0 offset constante
    my $y0_at_p2 = $self->price_on_line( $ch->{p1}, $m0, $ch->{p2}{index} );
    my $y1_at_p2 = $self->price_on_line( $ch->{p3}, $m0, $ch->{p2}{index} );
    my $y0_at_p1 = $ch->{p1}{price};
    my $y1_at_p1 = $self->price_on_line( $ch->{p3}, $m0, $ch->{p1}{index} );
    my $d1 = $y1_at_p1 - $y0_at_p1;
    my $d2 = $y1_at_p2 - $y0_at_p2;
    return abs( $d1 - $d2 ) < 1e-6;
}

1;
