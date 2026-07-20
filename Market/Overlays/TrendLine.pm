package Market::Overlays::TrendLine;
use strict;
use warnings;

# =============================================================================
# Render de TrendLine (drawing tool TV). Tag: draw_trend.
# Dibuja todas las líneas colocadas + handles arrastrables en cada extremo +
# preview del draft (1.er punto y línea elástica al 2.º clic).
# =============================================================================

sub new {
    my ( $class, %args ) = @_;
    my $self = {
        drawing => $args{drawing},
        theme   => $args{theme} || {},
        visible => exists $args{visible} ? ( $args{visible} ? 1 : 0 ) : 1,
        _range  => [ 0, 0 ],
    };
    die "Overlays::TrendLine: requiere 'drawing'" unless $self->{drawing};
    bless $self, $class;
    return $self;
}

sub tag { 'draw_trend' }

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
    eval { $canvas->delete('draw_trend_preview'); 1 };
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
    my $y_of = sub { $scales->value_to_y( $_[0] ) };

    my $line_c = $self->{theme}{trend_line} // $draw->{line_color} // '#ff9800';
    my $line_w = $draw->{line_width} // 2;

    my $lines = $draw->lines();
    for my $ln (@$lines) {
        my $p1 = $ln->{p1};
        my $p2 = $ln->{p2};
        next unless $p1 && $p2;
        eval {
            $canvas->createLine(
                $x_of->( $p1->{index} ), $y_of->( $p1->{price} ),
                $x_of->( $p2->{index} ), $y_of->( $p2->{price} ),
                -fill  => $line_c,
                -width => $line_w,
                -tags  => [ $tag, 'trend_line' ],
            );
            1;
        };
        # Handles en ambos extremos
        for my $pt ( $p1, $p2 ) {
            my $x = $x_of->( $pt->{index} );
            my $y = $y_of->( $pt->{price} );
            eval {
                $canvas->createOval(
                    $x - 5, $y - 5, $x + 5, $y + 5,
                    -outline => '#ffffff',
                    -fill    => $line_c,
                    -width   => 2,
                    -tags    => [ $tag, 'trend_handle' ],
                );
                1;
            };
        }
    }

    my $draft = $draw->draft_points();
    if ( $draw->is_tool_active() && @$draft ) {
        $self->_paint_draft( $canvas, $draft, $x_of, $y_of );
    }

    return $self;
}

sub _paint_draft {
    my ( $self, $canvas, $draft, $x_of, $y_of ) = @_;
    my $ptag = 'draw_trend_preview';
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
}

# hit_test → índice de línea + extremo ("$li:p1" | "$li:p2"), o undef.
# Recorre en orden inverso para priorizar la última línea dibujada.
sub hit_test {
    my ( $self, $x, $y, $scales, $win_start ) = @_;
    my $draw = $self->{drawing};
    return undef unless $draw && $scales;

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

    my $lines = $draw->lines();
    # Prioridad: primero extremos (más específicos), luego cuerpo de la línea.
    for ( my $li = $#$lines; $li >= 0; $li-- ) {
        my $ln = $lines->[$li];
        for my $which (qw(p1 p2)) {
            my $pt = $ln->{$which} or next;
            if ( $near->( $x_of->( $pt->{index} ), $y_of->( $pt->{price} ) ) ) {
                return "$li:$which";
            }
        }
    }
    # Cuerpo de la línea: distancia perpendicular del clic al segmento <= tol.
    for ( my $li = $#$lines; $li >= 0; $li-- ) {
        my $ln = $lines->[$li];
        next unless $ln->{p1} && $ln->{p2};
        my $x1 = $x_of->( $ln->{p1}{index} ); my $y1 = $y_of->( $ln->{p1}{price} );
        my $x2 = $x_of->( $ln->{p2}{index} ); my $y2 = $y_of->( $ln->{p2}{price} );
        if ( _dist_to_segment( $x, $y, $x1, $y1, $x2, $y2 ) <= 6 ) {
            return "$li:body";
        }
    }
    return undef;
}

# Distancia de un punto (px,py) al segmento (ax,ay)-(bx,by), en píxeles.
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

1;
