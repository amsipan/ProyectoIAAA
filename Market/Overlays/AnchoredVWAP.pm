package Market::Overlays::AnchoredVWAP;
use strict;
use warnings;

# =============================================================================
# Market::Overlays::AnchoredVWAP
# 
# Render smooth Anchored VWAP curve across the chart.
# =============================================================================

sub new {
    my ($class, %args) = @_;
    die "Overlays::AnchoredVWAP->new: requiere 'indicator'"
        unless defined $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 0,
        _elements => {
            VWAP_LINE => 1,
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
    return 'ov_vwap';
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

    my $tag   = $self->tag();
    $self->clear($canvas);

    my $vwap  = $self->{indicator}->get_values();
    return $self unless $vwap && @$vwap;

    my $start = (ref $window eq 'HASH') ? ($window->{start_index} // 0) : 0;
    my $end   = (ref $window eq 'HASH') ? ($window->{end_index}   // 0) : 0;

    for my $i ($start .. $end - 1) {
        next unless defined $vwap->[$i] && defined $vwap->[$i+1];
        next unless defined $vwap->[$i]->{value} && defined $vwap->[$i+1]->{value};

        my $x1 = $scales->index_to_center_x($self->_local_index($i));
        my $x2 = $scales->index_to_center_x($self->_local_index($i+1));
        my $y1 = $scales->value_to_y($vwap->[$i]->{value});
        my $y2 = $scales->value_to_y($vwap->[$i+1]->{value});

        $canvas->createLine(
            $x1, $y1, $x2, $y2,
            -fill  => '#ff9800', # Orange VWAP curve
            -width => 2,
            -tags  => $tag,
        );
    }

    return $self;
}

1;
