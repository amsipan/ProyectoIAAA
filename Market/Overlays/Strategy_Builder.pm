package Market::Overlays::Strategy_Builder;
use strict;
use warnings;

# =============================================================================
# Market::Overlays::Strategy_Builder
# 
# Render Strategy Builder overlays (SuperTrend, HalfTrend, Range Filter, Supply & Demand)
# =============================================================================

sub new {
    my ($class, %args) = @_;
    die "Overlays::Strategy_Builder->new: requiere 'indicator'"
        unless defined $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 0,
        _elements => {
            SUPERTREND   => 1,
            HALFTREND    => 1,
            RANGEFILTER  => 1,
            SUPPLY_DEMAND=> 1,
        },
        _start    => 0,
        _end      => 0,
    };
    bless $self, $class;
    return $self;
}

sub set_visible {
    my ($self, $val) = @_;
    $self->{visible} = $val ? 1 : 0;
}

sub is_visible {
    my ($self) = @_;
    return $self->{visible} ? 1 : 0;
}

sub tag {
    return 'ov_strategy';
}

sub clear {
    my ($self, $canvas) = @_;
    return unless $canvas;
    $canvas->delete($self->tag());
}

sub is_element_visible {
    my ($self, $elem) = @_;
    return $self->{_elements}->{$elem} ? 1 : 0;
}

sub set_element_visible {
    my ($self, $elem, $on) = @_;
    return $self unless defined $elem && exists $self->{_elements}->{$elem};
    $self->{_elements}->{$elem} = $on ? 1 : 0;
    return $self;
}

sub _local_index {
    my ($self, $global_idx) = @_;
    return $global_idx - ($self->{_start} // 0);
}

sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $self->{_start} = $start // 0;
    $self->{_end}   = $end   // 0;
    my $last_real;
    if ($market_data && $market_data->can('last_index')) {
        $last_real = $market_data->last_index();
    } elsif ($market_data && $market_data->can('size')) {
        $last_real = $market_data->size() - 1;
    }
    $self->{_last_real_index} = $last_real;
    return $self;
}

sub _x_right_edge {
    my ($self, $scales) = @_;
    my $end = $self->{_end} // 0;
    my $right_idx = $end;
    my $last_real = $self->{_last_real_index};
    $right_idx = $last_real if defined $last_real && $last_real < $right_idx;
    my $w = $scales->{width} || $scales->plot_width();
    my $x = $scales->index_to_center_x($self->_local_index($right_idx));
    $x = $w if $x > $w;
    $x = 0 if $x < 0;
    return $x;
}

# task 0039-A: no unir segmentos cuando cambia dir (evita línea vertical en flip).
sub _draw_trend_series {
    my ($self, $canvas, $scales, $tag, $series, $start, $end, $bull_col, $bear_col) = @_;
    return unless $series && @$series;
    for my $i ($start .. $end - 1) {
        next if $i < 0 || $i + 1 < 0;
        next unless defined $series->[$i] && defined $series->[$i + 1];
        next unless defined $series->[$i]->{value} && defined $series->[$i + 1]->{value};
        next if ($series->[$i]->{dir} // 0) != ($series->[$i + 1]->{dir} // 0);
        my $x1 = $scales->index_to_center_x($self->_local_index($i));
        my $x2 = $scales->index_to_center_x($self->_local_index($i + 1));
        my $y1 = $scales->value_to_y($series->[$i]->{value});
        my $y2 = $scales->value_to_y($series->[$i + 1]->{value});
        my $col = ($series->[$i]->{dir} == 1) ? $bull_col : $bear_col;
        $canvas->createLine(
            $x1, $y1, $x2, $y2,
            -fill  => $col,
            -width => 2,
            -tags  => $tag,
        );
    }
    return;
}

sub draw {
    my ($self, $canvas, $scales) = @_;
    return $self unless $self->is_visible() && $self->{indicator};
    return $self unless $canvas && $scales;
    return $self unless defined $scales->{height} && $scales->{height} > 0;

    my $tag  = $self->tag();
    $self->clear($canvas);

    my $vals = $self->{indicator}->get_values();
    return $self unless $vals;

    my $start = $self->{_start} // 0;
    my $end   = $self->{_end}   // 0;
    my $x_cap = $self->_x_right_edge($scales);

    if ($self->is_element_visible('SUPERTREND')) {
        $self->_draw_trend_series(
            $canvas, $scales, $tag,
            $vals->{supertrend} // [],
            $start, $end, '#26a69a', '#ef5350',
        );
    }

    if ($self->is_element_visible('HALFTREND')) {
        $self->_draw_trend_series(
            $canvas, $scales, $tag,
            $vals->{halftrend} // [],
            $start, $end, '#7e57c2', '#ab47bc',
        );
    }

    if ($self->is_element_visible('RANGEFILTER')) {
        $self->_draw_trend_series(
            $canvas, $scales, $tag,
            $vals->{rangefilter} // [],
            $start, $end, '#42a5f5', '#1e88e5',
        );
    }

    if ($self->is_element_visible('SUPPLY_DEMAND')) {
        my @supplies = grep { $_->{index} >= 0 && $_->{index} >= $start - 40 && $_->{index} <= $end }
            @{ $vals->{supply_zones} // [] };
        @supplies = splice(@supplies, -6) if @supplies > 6;
        for my $z (@supplies) {
            next if $z->{index} < 0;
            my $x0 = $scales->index_to_x($self->_local_index($z->{index}));
            my $x1 = $scales->index_to_x($self->_local_index($z->{index} + 15));
            $x1 = $x_cap if $x1 > $x_cap;
            next if $x1 < 0;

            my $y_hi = $scales->value_to_y($z->{hi});
            my $y_lo = $scales->value_to_y($z->{lo});
            $canvas->createRectangle(
                $x0, $y_hi, $x1, $y_lo,
                -fill    => '',
                -outline => '#ef5350',
                -width   => 1,
                -tags    => $tag,
            );
        }

        my @demands = grep { $_->{index} >= 0 && $_->{index} >= $start - 40 && $_->{index} <= $end }
            @{ $vals->{demand_zones} // [] };
        @demands = splice(@demands, -6) if @demands > 6;
        for my $z (@demands) {
            next if $z->{index} < 0;
            my $x0 = $scales->index_to_x($self->_local_index($z->{index}));
            my $x1 = $scales->index_to_x($self->_local_index($z->{index} + 15));
            $x1 = $x_cap if $x1 > $x_cap;
            next if $x1 < 0;

            my $y_hi = $scales->value_to_y($z->{hi});
            my $y_lo = $scales->value_to_y($z->{lo});
            $canvas->createRectangle(
                $x0, $y_hi, $x1, $y_lo,
                -fill    => '',
                -outline => '#2962ff',
                -width   => 1,
                -tags    => $tag,
            );
        }
    }

    return $self;
}

1;