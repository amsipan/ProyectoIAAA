package Market::Overlays::DIY;
use strict;
use warnings;

# Overlay DIY: visualización de Supply & Demand Zones
# 
# Renderiza:
#   - Rectángulos semitransparentes (con stipple) para las zonas activas:
#     - Supply: Gris claro (#CCCCCC) con texto "SUPPLY".
#     - Demand: Cian (#00FFFF) con texto "DEMAND".
#   - Línea discontinua horizontal en el nivel POI (centro de la caja activa) con etiqueta "POI".
#   - Líneas de mitigación históricas (BOS) a nivel POI para zonas rotas.
# 
# Contrato de Overlays:
#   new(%args)
#   tag()
#   set_visible($bool)
#   is_visible()
#   compute_visible($market_data, $indicator, $start, $end)
#   draw($canvas, $scales)
#   clear($canvas)

sub new {
    my ($class, %args) = @_;
    die "Overlays::DIY->new: requiere 'indicator'" unless defined $args{indicator};
    my $self = {
        indicator      => $args{indicator},
        theme          => $args{theme} || {},
        visible        => exists $args{visible} ? ($args{visible} ? 1 : 0) : 0,
        _active_supply => [],
        _active_demand => [],
        _broken_supply => [],
        _broken_demand => [],
        _compute_range => undef,
    };
    bless $self, $class;
    return $self;
}

sub tag { 'ov_diy' }

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
    return $self unless $self->{visible} && $market_data;

    my $ind = $indicator // $self->{indicator};
    my $vals = $ind->get_values();

    # Filtrar cajas que tengan solapamiento con el rango visible
    $self->{_active_supply} = [ grep { _segment_overlaps($_->{left}, $_->{right}, $start, $end) } @{ $vals->{active_supply} || [] } ];
    $self->{_active_demand} = [ grep { _segment_overlaps($_->{left}, $_->{right}, $start, $end) } @{ $vals->{active_demand} || [] } ];
    $self->{_broken_supply} = [ grep { _segment_overlaps($_->{left}, $_->{right}, $start, $end) } @{ $vals->{broken_supply} || [] } ];
    $self->{_broken_demand} = [ grep { _segment_overlaps($_->{left}, $_->{right}, $start, $end) } @{ $vals->{broken_demand} || [] } ];

    return $self;
}

sub clear {
    my ($self, $canvas) = @_;
    return unless $canvas;
    eval { $canvas->delete($self->tag()); 1 };
    return $self;
}

sub _plot_bounds {
    my ($self, $scales) = @_;
    my $w = $scales->{width} // $scales->{plot_right} // $scales->{plot_width} // 0;
    $w = 1 if $w < 1;
    return (-120, $w + 120);
}

sub _clip_x {
    my ($self, $scales, $x1, $x2) = @_;
    my ($lo, $hi) = $self->_plot_bounds($scales);
    return if ($x1 < $lo && $x2 < $lo) || ($x1 > $hi && $x2 > $hi);
    $x1 = $lo if $x1 < $lo;
    $x1 = $hi if $x1 > $hi;
    $x2 = $lo if $x2 < $lo;
    $x2 = $hi if $x2 > $hi;
    return ($x1, $x2);
}

sub draw {
    my ($self, $canvas, $scales) = @_;
    return unless $self->{visible} && $canvas && $scales;
    $self->clear($canvas);

    my $tag = $self->tag();
    my $win_start = ($self->{_compute_range} || [0])->[0] // 0;

    # Configuración de Colores
    my $c_supply = $self->{theme}{diy_supply} // '#CCCCCC';
    my $c_demand = $self->{theme}{diy_demand} // '#00FFFF';
    my $c_label  = $self->{theme}{diy_label}  // '#000000';
    my $c_poi    = $self->{theme}{diy_poi}    // '#FFFFFF';

    my $x_center = sub {
        my ($g) = @_;
        return $scales->index_to_center_x(($g // 0) - $win_start);
    };
    my $y_of = sub {
        my ($p) = @_;
        return $scales->value_to_y($p);
    };

    # 1. Dibujar Zonas de Oferta (Supply) Activas
    for my $box (@{ $self->{_active_supply} }) {
        my $x1 = $x_center->($box->{left});
        my $x2 = $x_center->($box->{right});
        my @cx = $self->_clip_x($scales, $x1, $x2);
        next unless @cx;
        ($x1, $x2) = @cx;

        my $y1 = $y_of->($box->{top});
        my $y2 = $y_of->($box->{bottom});
        ($y1, $y2) = ($y2, $y1) if $y1 > $y2;

        eval {
            # Caja de Supply
            $canvas->createRectangle(
                $x1, $y1, $x2, $y2,
                -outline => $c_supply,
                -fill    => $c_supply,
                -stipple => 'gray25',
                -width   => 1,
                -tags    => [$tag, 'diy_box'],
            );
            # Texto SUPPLY
            $canvas->createText(
                ($x1 + $x2) / 2, ($y1 + $y2) / 2,
                -text => 'SUPPLY',
                -fill => $c_label,
                -font => ['TkDefaultFont', 7, 'bold'],
                -tags => [$tag, 'diy_text'],
            );
            # Línea POI
            my $y_poi = $y_of->($box->{poi});
            $canvas->createLine(
                $x1, $y_poi, $x2, $y_poi,
                -fill  => $c_poi,
                -width => 1,
                -dash  => '.',
                -tags  => [$tag, 'diy_poi_line'],
            );
            # Etiqueta POI
            $canvas->createText(
                $x1 + 10, $y_poi - 6,
                -text => 'POI',
                -fill => $c_poi,
                -font => ['TkDefaultFont', 6],
                -anchor => 'w',
                -tags => [$tag, 'diy_poi_lbl'],
            );
            1;
        };
    }

    # 2. Dibujar Zonas de Demanda (Demand) Activas
    for my $box (@{ $self->{_active_demand} }) {
        my $x1 = $x_center->($box->{left});
        my $x2 = $x_center->($box->{right});
        my @cx = $self->_clip_x($scales, $x1, $x2);
        next unless @cx;
        ($x1, $x2) = @cx;

        my $y1 = $y_of->($box->{top});
        my $y2 = $y_of->($box->{bottom});
        ($y1, $y2) = ($y2, $y1) if $y1 > $y2;

        eval {
            # Caja de Demand
            $canvas->createRectangle(
                $x1, $y1, $x2, $y2,
                -outline => $c_demand,
                -fill    => $c_demand,
                -stipple => 'gray25',
                -width   => 1,
                -tags    => [$tag, 'diy_box'],
            );
            # Texto DEMAND
            $canvas->createText(
                ($x1 + $x2) / 2, ($y1 + $y2) / 2,
                -text => 'DEMAND',
                -fill => $c_label,
                -font => ['TkDefaultFont', 7, 'bold'],
                -tags => [$tag, 'diy_text'],
            );
            # Línea POI
            my $y_poi = $y_of->($box->{poi});
            $canvas->createLine(
                $x1, $y_poi, $x2, $y_poi,
                -fill  => $c_poi,
                -width => 1,
                -dash  => '.',
                -tags  => [$tag, 'diy_poi_line'],
            );
            # Etiqueta POI
            $canvas->createText(
                $x1 + 10, $y_poi - 6,
                -text => 'POI',
                -fill => $c_poi,
                -font => ['TkDefaultFont', 6],
                -anchor => 'w',
                -tags => [$tag, 'diy_poi_lbl'],
            );
            1;
        };
    }

    # 3. Dibujar Líneas Históricas BOS de Zonas de Oferta Mitigadas
    for my $box (@{ $self->{_broken_supply} }) {
        my $x1 = $x_center->($box->{left});
        my $x2 = $x_center->($box->{right});
        my @cx = $self->_clip_x($scales, $x1, $x2);
        next unless @cx;
        ($x1, $x2) = @cx;

        my $y_poi = $y_of->($box->{poi});
        eval {
            $canvas->createLine(
                $x1, $y_poi, $x2, $y_poi,
                -fill  => $c_supply,
                -width => 1,
                -dash  => '-',
                -tags  => [$tag, 'diy_bos_line'],
            );
            1;
        };
    }

    # 4. Dibujar Líneas Históricas BOS de Zonas de Demanda Mitigadas
    for my $box (@{ $self->{_broken_demand} }) {
        my $x1 = $x_center->($box->{left});
        my $x2 = $x_center->($box->{right});
        my @cx = $self->_clip_x($scales, $x1, $x2);
        next unless @cx;
        ($x1, $x2) = @cx;

        my $y_poi = $y_of->($box->{poi});
        eval {
            $canvas->createLine(
                $x1, $y_poi, $x2, $y_poi,
                -fill  => $c_demand,
                -width => 1,
                -dash  => '-',
                -tags  => [$tag, 'diy_bos_line'],
            );
            1;
        };
    }

    return $self;
}

1;
