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

    my $prof = $self->{indicator}->get_values();
    return $self unless $prof && $prof->{bins};

    my $w = $scales->{width} || $scales->plot_width();

    # 1. Draw POC (Point of Control) line
    if ($self->is_element_visible('POC') && defined $prof->{poc}) {
        my $y = $scales->value_to_y($prof->{poc});
        $canvas->createLine(
            0, $y, $w, $y,
            -fill  => '#ea3943', # Red POC line
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

    # 2. Draw VAH and VAL lines
    if ($self->is_element_visible('VALUE_AREA')) {
        if (defined $prof->{vah}) {
            my $y = $scales->value_to_y($prof->{vah});
            $canvas->createLine(
                0, $y, $w, $y,
                -fill  => '#2962ff', # Blue VAH line
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
                -fill  => '#2962ff', # Blue VAL line
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
