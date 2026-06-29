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

sub _local_index {
    my ($self, $global_idx) = @_;
    return $global_idx;
}

sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    return $self;
}

sub draw {
    my ($self, $canvas, $scales, $window) = @_;
    return $self unless $self->is_visible() && $self->{indicator};
    return $self unless $canvas && $scales;

    my $tag  = $self->tag();
    $self->clear($canvas);

    my $vals = $self->{indicator}->get_values();
    return $self unless $vals;

    my $start= (ref $window eq 'HASH') ? ($window->{start_index} // 0) : 0;
    my $end  = (ref $window eq 'HASH') ? ($window->{end_index}   // 0) : 0;

    my $st = $vals->{supertrend} // [];

    # 1. Draw SuperTrend Line
    if ($self->is_element_visible('SUPERTREND')) {
        for my $i ($start .. $end - 1) {
            next unless defined $st->[$i] && defined $st->[$i+1];
            next unless defined $st->[$i]->{value} && defined $st->[$i+1]->{value};
            my $x1 = $scales->index_to_center_x($self->_local_index($i));
            my $x2 = $scales->index_to_center_x($self->_local_index($i+1));
            my $y1 = $scales->value_to_y($st->[$i]->{value});
            my $y2 = $scales->value_to_y($st->[$i+1]->{value});
            my $col= ($st->[$i]->{dir} == 1) ? '#26a69a' : '#ef5350';

            $canvas->createLine(
                $x1, $y1, $x2, $y2,
                -fill  => $col,
                -width => 2,
                -tags  => $tag,
            );
        }
    }

    # 2. Draw Supply & Demand Zones
    if ($self->is_element_visible('SUPPLY_DEMAND')) {
        my $w = $scales->{width} || $scales->plot_width();
        for my $z (@{ $vals->{supply_zones} // [] }) {
            next if $z->{index} > $end;
            my $x0 = $scales->index_to_x($self->_local_index($z->{index}));
            my $y_hi = $scales->value_to_y($z->{hi});
            my $y_lo = $scales->value_to_y($z->{lo});
            $canvas->createRectangle(
                $x0, $y_hi, $w, $y_lo,
                -fill    => '#f77c80',
                -outline => '#b22833',
                -stipple => 'gray50',
                -tags    => $tag,
            );
        }
        for my $z (@{ $vals->{demand_zones} // [] }) {
            next if $z->{index} > $end;
            my $x0 = $scales->index_to_x($self->_local_index($z->{index}));
            my $y_hi = $scales->value_to_y($z->{hi});
            my $y_lo = $scales->value_to_y($z->{lo});
            $canvas->createRectangle(
                $x0, $y_hi, $w, $y_lo,
                -fill    => '#3179f5',
                -outline => '#1848cc',
                -stipple => 'gray50',
                -tags    => $tag,
            );
        }
    }

    return $self;
}

1;
