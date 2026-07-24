package Market::Drawing::FibRetracement;
use strict;
use warnings;

# =============================================================================
# Fib Retracement — clone herramienta nativa TradingView
# 2 anclas: p1 = nivel 1 (1.er clic), p2 = nivel 0 (2.º clic).
# price(level) = p2.price + level * (p1.price - p2.price)
# extend_to_last: proyecta la caja hasta la última vela (data_end), no infinito.
# =============================================================================

my @DEFAULT_LEVELS = (
    { ratio => 0,     color => '#787b86', fill => '#b2b5be' },
    { ratio => 0.236, color => '#f23645', fill => '#f23645' },
    { ratio => 0.382, color => '#ff9800', fill => '#ff9800' },
    { ratio => 0.5,   color => '#4caf50', fill => '#81c784' },
    { ratio => 0.618, color => '#089981', fill => '#26a69a' },
    { ratio => 0.786, color => '#2962ff', fill => '#42a5f5' },
    { ratio => 1,     color => '#787b86', fill => '#b2b5be' },
);

sub default_levels {
    return [ map { { %$_ } } @DEFAULT_LEVELS ];
}

sub new {
    my ( $class, %args ) = @_;
    my $self = {
        fib            => undef,
        draft          => [],
        tool_active    => 0,
        extend_to_last => exists $args{extend_to_last}
        ? ( $args{extend_to_last} ? 1 : 0 )
        : 0,
        background  => exists $args{background}  ? ( $args{background}  ? 1 : 0 ) : 1,
        show_prices => exists $args{show_prices} ? ( $args{show_prices} ? 1 : 0 ) : 1,
        opacity     => $args{opacity} // 0.28,
        levels      => $args{levels} // default_levels(),
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

sub clear_fib {
    my ($self) = @_;
    $self->{fib} = undef;
    return $self;
}

sub get_fib { $_[0]->{fib} }

sub draft_points { [ @{ $_[0]->{draft} || [] } ] }

sub draft_count {
    my ($self) = @_;
    return scalar @{ $self->{draft} || [] };
}

# price_at_level — TV: 0 en p2, 1 en p1
sub price_at_level {
    my ( $class_or_self, $p1, $p2, $level ) = @_;
    return undef unless ref($p1) eq 'HASH' && ref($p2) eq 'HASH';
    my $a = $p1->{price};
    my $b = $p2->{price};
    return undef unless defined $a && defined $b && defined $level;
    return $b + $level * ( $a - $b );
}

# add_point — 2 clics → commit (p1=1.er clic=nivel 1, p2=2.º=nivel 0)
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

    if ( @{ $self->{draft} } >= 2 ) {
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
    return unless @d >= 2;
    $self->set_from_points( $d[0], $d[1] );
    return $self->{fib};
}

# set_from_points($p1, $p2) — p1 = nivel 1, p2 = nivel 0 (convención TV)
# El ancho de la caja = siempre min/max de p1.index y p2.index (como TV).
# No hay bordes de ancho independientes de los anclajes.
sub set_from_points {
    my ( $self, $p1, $p2 ) = @_;
    return undef unless ref($p1) eq 'HASH' && ref($p2) eq 'HASH';
    my $i1 = 0 + ( $p1->{index} // 0 );
    my $i2 = 0 + ( $p2->{index} // 0 );
    $self->{fib} = {
        p1             => { index => $i1, price => 0 + $p1->{price} },
        p2             => { index => $i2, price => 0 + $p2->{price} },
        extend_to_last => $self->{extend_to_last} ? 1 : 0,
        background     => $self->{background}     ? 1 : 0,
        show_prices    => $self->{show_prices}    ? 1 : 0,
        opacity        => $self->{opacity},
        levels         => [ map { { %$_ } } @{ $self->{levels} || default_levels() } ],
    };
    return $self->{fib};
}

# Span horizontal de la caja: min/max de los índices de p1 y p2
sub _span_indices {
    my ( $self, $fib ) = @_;
    $fib //= $self->{fib};
    return ( 0, 0 ) unless $fib && $fib->{p1} && $fib->{p2};
    my $i1 = $fib->{p1}{index} // 0;
    my $i2 = $fib->{p2}{index} // 0;
    return $i1 <= $i2 ? ( $i1, $i2 ) : ( $i2, $i1 );
}

# set_from_zz_leg($seg) — pierna del ZZ externo (from→to = impulso = 1→0)
# Orientación TV: 1.er extremo de la pierna = nivel 1, 2.º = nivel 0.
# En bajista: from=high → to=low ⇒ 1 arriba, 0 abajo (colores correctos).
sub set_from_zz_leg {
    my ( $self, $leg ) = @_;
    return undef unless ref($leg) eq 'HASH'
      && defined $leg->{from_index}
      && defined $leg->{to_index}
      && defined $leg->{from_price}
      && defined $leg->{to_price};

    my $a = {
        index => 0 + $leg->{from_index},
        price => 0 + $leg->{from_price},
    };
    my $b = {
        index => 0 + $leg->{to_index},
        price => 0 + $leg->{to_price},
    };
    # Convención impulso: inicio de la pierna = 1, fin = 0 (como 2 clics A→B en TV)
    return $self->set_from_points( $a, $b );
}

# zz_leg_signature($leg) — firma estable para detectar cambio de impulso consolidado
sub zz_leg_signature {
    my ( $class_or_self, $leg ) = @_;
    return undef unless ref($leg) eq 'HASH';
    return undef
      unless defined $leg->{from_index}
      && defined $leg->{to_index}
      && defined $leg->{from_price}
      && defined $leg->{to_price};
    return join ':',
      map { 0 + $leg->{$_} } qw(from_index to_index from_price to_price);
}

sub set_extend_to_last {
    my ( $self, $on ) = @_;
    $self->{extend_to_last} = $on ? 1 : 0;
    $self->{fib}{extend_to_last} = $self->{extend_to_last} if $self->{fib};
    return $self;
}

# Mover p1: precio e índice; la caja (ancho + labels) se recalcula desde p1/p2
sub set_p1 {
    my ( $self, $pt ) = @_;
    return $self unless $self->{fib} && ref($pt) eq 'HASH';
    $self->{fib}{p1} = {
        index => 0 + ( $pt->{index} // $self->{fib}{p1}{index} ),
        price => 0 + ( $pt->{price} // $self->{fib}{p1}{price} ),
    };
    return $self;
}

sub set_p2 {
    my ( $self, $pt ) = @_;
    return $self unless $self->{fib} && ref($pt) eq 'HASH';
    $self->{fib}{p2} = {
        index => 0 + ( $pt->{index} // $self->{fib}{p2}{index} ),
        price => 0 + ( $pt->{price} // $self->{fib}{p2}{price} ),
    };
    return $self;
}

sub level_prices {
    my ( $self, $fib ) = @_;
    $fib //= $self->{fib};
    return [] unless $fib && $fib->{p1} && $fib->{p2};
    my @out;
    for my $lv ( @{ $fib->{levels} || default_levels() } ) {
        my $r     = $lv->{ratio};
        my $price = price_at_level( $self, $fib->{p1}, $fib->{p2}, $r );
        next unless defined $price;
        push @out, {
            ratio => $r,
            price => $price,
            color => $lv->{color} // '#787b86',
            fill  => $lv->{fill}  // $lv->{color} // '#787b86',
        };
    }
    @out = sort { $a->{ratio} <=> $b->{ratio} } @out;
    return \@out;
}

# geometry_for — ancho = min/max de p1.index y p2.index (TV).
# extend_to_last ⇒ right = data_end (última vela), sin handles de ancho.
sub geometry_for {
    my ( $self, $fib, %opts ) = @_;
    $fib //= $self->{fib};
    return undef unless $fib && $fib->{p1} && $fib->{p2};

    my $view_end = $opts{view_end} // 0;
    my $data_end = $opts{data_end} // $view_end;

    my ( $left, $right ) = $self->_span_indices($fib);

    if ( $fib->{extend_to_last} ) {
        my $last = defined $data_end ? $data_end : $view_end;
        $right = $last if defined $last && $last > $right;
    }

    return {
        left_index     => $left,
        right_index    => $right,
        levels         => $self->level_prices($fib),
        p1             => $fib->{p1},
        p2             => $fib->{p2},
        background     => $fib->{background} ? 1 : 0,
        show_prices    => $fib->{show_prices} ? 1 : 0,
        opacity        => $fib->{opacity} // 0.28,
        extend_to_last => $fib->{extend_to_last} ? 1 : 0,
    };
}

# last_consolidated_zz_segment(\@segs) — última pierna cerrada del ZZ externo
# (ignora el tramo vivo aún en ajuste).
sub last_consolidated_zz_segment {
    my ( $class_or_self, $segs ) = @_;
    return undef unless $segs && ref($segs) eq 'ARRAY' && @$segs;
    for ( my $i = $#$segs ; $i >= 0 ; $i-- ) {
        my $seg = $segs->[$i];
        next unless defined $seg->{from_index} && defined $seg->{to_index};
        next unless defined $seg->{from_price} && defined $seg->{to_price};
        next unless $seg->{consolidated};
        return $seg;
    }
    return undef;
}

# last_impulse_zz_segment_for_fib(\@segs) — impulso para Fib ZZ ext.
# Regla simple (producto):
#   - Última pierna consolidada UP → anclar ahí.
#   - Si la última cerrada es DOWN → devolver la UP consolidada previa
#     (el follow no cambia de firma → se mantiene el Fib anterior).
#   - Nunca el tramo vivo. Sin Fib en bajadas (el retroceso no ancla).
sub last_impulse_zz_segment_for_fib {
    my ( $class_or_self, $segs ) = @_;
    return undef unless $segs && ref($segs) eq 'ARRAY' && @$segs;

    for ( my $i = $#$segs ; $i >= 0 ; $i-- ) {
        my $seg = $segs->[$i];
        next unless defined $seg->{from_index} && defined $seg->{to_index};
        next unless defined $seg->{from_price} && defined $seg->{to_price};
        next unless $seg->{consolidated};
        my $dir = $seg->{dir};
        if ( !defined $dir || $dir eq '' ) {
            $dir = ( $seg->{to_price} >= $seg->{from_price} ) ? 'up' : 'down';
        }
        return $seg if $dir eq 'up';
    }
    return undef;
}

# nearest_zz_segment(\@segs, $index, $price) — pierna externa más cercana al clic
sub nearest_zz_segment {
    my ( $class_or_self, $segs, $index, $price ) = @_;
    return undef unless $segs && ref($segs) eq 'ARRAY' && @$segs;
    return undef unless defined $index && defined $price;

    my $best;
    my $best_d = 1e99;
    for my $seg (@$segs) {
        next unless defined $seg->{from_index} && defined $seg->{to_index};
        next unless defined $seg->{from_price} && defined $seg->{to_price};
        my $i0 = $seg->{from_index};
        my $i1 = $seg->{to_index};
        my ( $ilo, $ihi ) = $i0 < $i1 ? ( $i0, $i1 ) : ( $i1, $i0 );
        # Distancia en índice: 0 si está en el span, si no al extremo más cercano
        my $di = 0;
        if ( $index < $ilo ) {
            $di = $ilo - $index;
        }
        elsif ( $index > $ihi ) {
            $di = $index - $ihi;
        }
        # Precio interpolado en la pierna (aprox. en el índice del clic)
        my $t = 0;
        if ( $ihi != $ilo ) {
            my $clamped = $index;
            $clamped = $ilo if $clamped < $ilo;
            $clamped = $ihi if $clamped > $ihi;
            $t = ( $clamped - $i0 ) / ( $i1 - $i0 );
        }
        my $p_line = $seg->{from_price} + $t * ( $seg->{to_price} - $seg->{from_price} );
        my $dp     = abs( $price - $p_line );
        # Escala: 1 índice ≈ peso; precio en unidades del activo (NQ ~ puntos)
        my $d = $di * 50 + $dp;
        if ( $d < $best_d ) {
            $best_d = $d;
            $best   = $seg;
        }
    }
    return $best;
}

1;
