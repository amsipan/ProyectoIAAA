package Market::Overlays::VolumeProfile;
use strict;
use warnings;

# =============================================================================
# Market::Overlays::VolumeProfile
# 
# Render Volume Profile horizontal histograms, POC (red), VAH/VAL (blue) lines.
# =============================================================================

sub new {
    my ($class, %args) = @_;
    die "Overlays::VolumeProfile->new: requiere 'indicator'"
        unless defined $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 0,
        _elements => {
            HISTOGRAM => 1,
            POC       => 1,
            VALUE_AREA=> 1,
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
    return 'ov_vp';
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
    return $self unless defined $scales->{height} && $scales->{height} > 0;

    my $tag  = $self->tag();
    $self->clear($canvas);

    my $prof = $self->{indicator}->get_values();
    return $self unless $prof && $prof->{bins};

    my $w = $scales->{width} || $scales->plot_width();

    if ($self->is_element_visible('HISTOGRAM')) {
        my $bins = $prof->{bins};
        my $max_vol = 0;
        for my $b (@$bins) {
            $max_vol = $b->{vol} if defined $b->{vol} && $b->{vol} > $max_vol;
        }
        my $hist_max_w = int($w * 0.22);
        $hist_max_w = 1 if $hist_max_w < 1;
        for my $b (@$bins) {
            next unless defined $b->{vol} && $b->{vol} > 0;
            next unless defined $b->{price};
            my $bar_w = $max_vol > 0 ? int($hist_max_w * $b->{vol} / $max_vol) : 0;
            next unless $bar_w > 0;
            my $y = $scales->value_to_y($b->{price});
            $canvas->createRectangle(
                0, $y - 2, $bar_w, $y + 2,
                -fill    => '#b0bec5',
                -outline => '#90a4ae',
                -width   => 1,
                -tags    => $tag,
            );
        }
    }

    if ($self->is_element_visible('POC') && defined $prof->{poc}) {
        my $y = $scales->value_to_y($prof->{poc});
        $canvas->createLine(
            0, $y, $w, $y,
            -fill  => '#ea3943',
            -width => 2,
            -tags  => $tag,
        );
        $canvas->createText(
            $w - 40, $y - 6,
            -text   => 'POC',
            -anchor => 'w',
            -font   => 'Helvetica 8 bold',
            -fill   => '#ea3943',
            -tags   => $tag,
        );
    }

    if ($self->is_element_visible('VALUE_AREA')) {
        if (defined $prof->{vah}) {
            my $y = $scales->value_to_y($prof->{vah});
            $canvas->createLine(
                0, $y, $w, $y,
                -fill  => '#2962ff',
                -dash  => [4, 4],
                -width => 1,
                -tags  => $tag,
            );
            $canvas->createText(
                $w - 40, $y - 6,
                -text   => 'VAH',
                -anchor => 'w',
                -font   => 'Helvetica 8 bold',
                -fill   => '#2962ff',
                -tags   => $tag,
            );
        }
        if (defined $prof->{val}) {
            my $y = $scales->value_to_y($prof->{val});
            $canvas->createLine(
                0, $y, $w, $y,
                -fill  => '#2962ff',
                -dash  => [4, 4],
                -width => 1,
                -tags  => $tag,
            );
            $canvas->createText(
                $w - 40, $y + 6,
                -text   => 'VAL',
                -anchor => 'w',
                -font   => 'Helvetica 8 bold',
                -fill   => '#2962ff',
                -tags   => $tag,
            );
        }
    }

    return $self;
}

1;