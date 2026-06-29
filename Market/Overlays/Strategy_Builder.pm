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

sub _local_index {
    my ($self, $global_idx) = @_;
    return $global_idx - ($self->{_start} // 0);
}

sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $self->{_start} = $start // 0;
    $self->{_end}   = $end   // 0;
    return $self;
}

sub draw {
    my ($self, $canvas, $scales) = @_;
    return $self unless $self->is_visible() && $self->{indicator};
    return $self unless $canvas && $scales;

    my $tag  = $self->tag();
    $self->clear($canvas);

    my $vals = $self->{indicator}->get_values();
    return $self unless $vals;

    my $start = $self->{_start} // 0;
    my $end   = $self->{_end}   // 0;

    my $st = $vals->{supertrend} // [];

    # 1. Draw SuperTrend Line
    if ($self->is_element_visible('SUPERTREND')) {
        for my $i ($start .. $end - 1) {
            next if $i < 0 || $i + 1 < 0; # Guard against Perl negative array wrapping
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

    # 2. Draw Supply & Demand Zones (Transparent interior order blocks bounded to 15 bars)
    if ($self->is_element_visible('SUPPLY_DEMAND')) {
        my $w_total = $scales->{width} || $scales->plot_width();
        
        # Supply Zones (Sell blocks - Red transparent boxes)
        my @supplies = grep { $_->{index} >= 0 && $_->{index} >= $start - 40 && $_->{index} <= $end } @{ $vals->{supply_zones} // [] };
        @supplies = splice(@supplies, -6) if @supplies > 6; # Keep max 6 recent visible zones
        for my $z (@supplies) {
            next if $z->{index} < 0;
            my $x0 = $scales->index_to_x($self->_local_index($z->{index}));
            my $x1 = $scales->index_to_x($self->_local_index($z->{index} + 15));
            $x1 = $w_total if $x1 > $w_total;
            next if $x1 < 0;
            
            my $y_hi = $scales->value_to_y($z->{hi});
            my $y_lo = $scales->value_to_y($z->{lo});
            $canvas->createRectangle(
                $x0, $y_hi, $x1, $y_lo,
                -fill    => '',        # Transparent interior (does not cover candles)
                -outline => '#ef5350', # Crisp red outline
                -width   => 1,
                -tags    => $tag,
            );
        }
        
        # Demand Zones (Buy blocks - Blue transparent boxes)
        my @demands = grep { $_->{index} >= 0 && $_->{index} >= $start - 40 && $_->{index} <= $end } @{ $vals->{demand_zones} // [] };
        @demands = splice(@demands, -6) if @demands > 6; # Keep max 6 recent visible zones
        for my $z (@demands) {
            next if $z->{index} < 0;
            my $x0 = $scales->index_to_x($self->_local_index($z->{index}));
            my $x1 = $scales->index_to_x($self->_local_index($z->{index} + 15));
            $x1 = $w_total if $x1 > $w_total;
            next if $x1 < 0;

            my $y_hi = $scales->value_to_y($z->{hi});
            my $y_lo = $scales->value_to_y($z->{lo});
            $canvas->createRectangle(
                $x0, $y_hi, $x1, $y_lo,
                -fill    => '',        # Transparent interior (does not cover candles)
                -outline => '#2962ff', # Crisp blue outline
                -width   => 1,
                -tags    => $tag,
            );
        }
    }

    return $self;
}

1;
