package Market::Drawing::TrendLine;
use strict;
use warnings;

# =============================================================================
# TrendLine — herramienta de línea de tendencia (drawing tool TV).
# 2 clics = una línea (p1 → p2). A diferencia del canal, se pueden colocar
# VARIAS líneas a la vez. Cada línea es independiente y sus 2 extremos son
# arrastrables (patrón idéntico a los handles del Fib).
#
# Estado:
#   lines       => [ { p1 => {index,price}, p2 => {index,price} }, ... ]
#   draft       => [ 0..1 puntos mientras se dibuja la línea actual ]
#   tool_active => 1 mientras el usuario está colocando líneas
#
# El índice de línea + nombre de extremo ('0:p1', '2:p2'...) sirve de handle.
# =============================================================================

sub new {
    my ( $class, %args ) = @_;
    my $self = {
        lines       => [],
        draft       => [],
        tool_active => 0,
        line_color  => $args{line_color} // '#ff9800',
        line_width  => $args{line_width} // 2,
    };
    bless $self, $class;
    return $self;
}

sub is_tool_active { $_[0]->{tool_active} ? 1 : 0 }

# start_tool — activa el modo colocar líneas. NO borra las líneas existentes
# (se pueden ir agregando varias).
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

sub clear_all {
    my ($self) = @_;
    $self->{lines} = [];
    $self->{draft} = [];
    return $self;
}

# clear_last — borra la última línea colocada (deshacer sencillo).
sub clear_last {
    my ($self) = @_;
    pop @{ $self->{lines} } if @{ $self->{lines} };
    return $self;
}

sub lines { [ @{ $_[0]->{lines} || [] } ] }

sub line_count { scalar @{ $_[0]->{lines} || [] } }

sub draft_points { [ @{ $_[0]->{draft} || [] } ] }

sub draft_count { scalar @{ $_[0]->{draft} || [] } }

# add_point({index,price}) en modo tool. Commit al 2.º clic → nueva línea.
# Retorna 'draft' | 'done' | undef.
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
        my @d = @{ $self->{draft} };
        push @{ $self->{lines} }, {
            p1 => { %{ $d[0] } },
            p2 => { %{ $d[1] } },
        };
        $self->{draft} = [];
        # tool_active sigue en 1: permite encadenar varias líneas. La UI/Esc
        # o cancel_tool lo apagan cuando el usuario termina.
        return 'done';
    }
    return 'draft';
}

# set_point($line_idx, $which, {index,price}) — mueve un extremo (p1|p2).
sub set_point {
    my ( $self, $li, $which, $pt ) = @_;
    return $self unless defined $li && $self->{lines}[$li];
    return $self unless $which eq 'p1' || $which eq 'p2';
    return $self unless ref($pt) eq 'HASH';
    my $cur = $self->{lines}[$li]{$which};
    $self->{lines}[$li]{$which} = {
        index => 0 + ( defined $pt->{index} ? $pt->{index} : $cur->{index} ),
        price => 0 + ( defined $pt->{price} ? $pt->{price} : $cur->{price} ),
    };
    return $self;
}

1;
