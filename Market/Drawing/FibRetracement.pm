package Market::Drawing::FibRetracement;
use strict;
use warnings;

# =============================================================================
# Fib Retracement — clone de la herramienta nativa TradingView
# 2 anclas (p1=nivel 1, p2=nivel 0); bandas entre ratios; extend L/R.
# price(level) = p2.price + level * (p1.price - p2.price)
# =============================================================================

# Colores aproximados a captura TV del usuario (bandas + líneas)
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
        fib          => undef,
        draft        => [],
        tool_active  => 0,
        extend_right => exists $args{extend_right} ? ( $args{extend_right} ? 1 : 0 ) : 0,
        extend_left  => exists $args{extend_left}  ? ( $args{extend_left}  ? 1 : 0 ) : 0,
        background   => exists $args{background} ? ( $args{background} ? 1 : 0 ) : 1,
        show_prices  => exists $args{show_prices} ? ( $args{show_prices} ? 1 : 0 ) : 1,
        opacity      => $args{opacity} // 0.28,
        levels       => $args{levels} // default_levels(),
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

# price_at_level($p1, $p2, $level) — TV: 0 en p2, 1 en p1
sub price_at_level {
    my ( $class_or_self, $p1, $p2, $level ) = @_;
    return undef unless ref($p1) eq 'HASH' && ref($p2) eq 'HASH';
    my $a = $p1->{price};
    my $b = $p2->{price};
    return undef unless defined $a && defined $b && defined $level;
    return $b + $level * ( $a - $b );
}

# add_point({index, price}) — 2 clics → commit
# Retorna: 'draft' | 'done' | undef
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

# set_from_points($p1, $p2) — crea/reemplaza fib (un solo activo)
sub set_from_points {
    my ( $self, $p1, $p2 ) = @_;
    return undef unless ref($p1) eq 'HASH' && ref($p2) eq 'HASH';
    my $i1 = 0 + ( $p1->{index} // 0 );
    my $i2 = 0 + ( $p2->{index} // 0 );
    my $lo = $i1 < $i2 ? $i1 : $i2;
    my $hi = $i1 > $i2 ? $i1 : $i2;
    $self->{fib} = {
        p1           => { index => $i1, price => 0 + $p1->{price} },
        p2           => { index => $i2, price => 0 + $p2->{price} },
        left_index   => $lo,
        right_index  => $hi,
        extend_left  => $self->{extend_left}  ? 1 : 0,
        extend_right => $self->{extend_right} ? 1 : 0,
        background   => $self->{background}   ? 1 : 0,
        show_prices  => $self->{show_prices}  ? 1 : 0,
        opacity      => $self->{opacity},
        levels       => [ map { { %$_ } } @{ $self->{levels} || default_levels() } ],
    };
    return $self->{fib};
}

sub set_extend_left {
    my ( $self, $on ) = @_;
    $self->{extend_left} = $on ? 1 : 0;
    $self->{fib}{extend_left} = $self->{extend_left} if $self->{fib};
    return $self;
}

sub set_extend_right {
    my ( $self, $on ) = @_;
    $self->{extend_right} = $on ? 1 : 0;
    $self->{fib}{extend_right} = $self->{extend_right} if $self->{fib};
    return $self;
}

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

sub set_left_index {
    my ( $self, $i ) = @_;
    return $self unless $self->{fib} && defined $i;
    $self->{fib}{left_index} = 0 + $i;
    return $self;
}

sub set_right_index {
    my ( $self, $i ) = @_;
    return $self unless $self->{fib} && defined $i;
    $self->{fib}{right_index} = 0 + $i;
    return $self;
}

# level_prices($fib) → [ { ratio, price, color, fill }, ... ] ordenados por ratio
sub level_prices {
    my ( $self, $fib ) = @_;
    $fib //= $self->{fib};
    return [] unless $fib && $fib->{p1} && $fib->{p2};
    my @out;
    for my $lv ( @{ $fib->{levels} || default_levels() } ) {
        my $r = $lv->{ratio};
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

# geometry_for — x range en índices de barra (para overlay)
sub geometry_for {
    my ( $self, $fib, %opts ) = @_;
    $fib //= $self->{fib};
    return undef unless $fib && $fib->{p1} && $fib->{p2};

    my $view_start = $opts{view_start} // 0;
    my $view_end   = $opts{view_end}   // 0;
    my $data_end   = $opts{data_end}   // $view_end;

    my $left  = $fib->{left_index}  // $fib->{p1}{index};
    my $right = $fib->{right_index} // $fib->{p2}{index};
    $left  = $right if $left > $right;

    if ( $fib->{extend_left} ) {
        $left = $view_start;
    }
    if ( $fib->{extend_right} ) {
        $right = $data_end > $view_end ? $data_end : $view_end;
    }

    return {
        left_index  => $left,
        right_index => $right,
        levels      => $self->level_prices($fib),
        p1          => $fib->{p1},
        p2          => $fib->{p2},
        background  => $fib->{background} ? 1 : 0,
        show_prices => $fib->{show_prices} ? 1 : 0,
        opacity     => $fib->{opacity} // 0.28,
    };
}

1;
