package Market::Overlays::ZigZag;
use strict;
use warnings;

# =============================================================================
# Market::Overlays::ZigZag — render dirección interna (verde/rojo) + externa (azul)
# Task 0033: capa separada; toggles interno/externo; tag ov_zigzag.
# =============================================================================

my %ELEMENTS = map { $_ => 1 } qw(INTERNAL EXTERNAL CHANNEL);

sub new {
    my ($class, %args) = @_;
    die "Overlays::ZigZag->new: requiere 'indicator'"
        unless defined $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 0,
        _elements => { INTERNAL => 1, EXTERNAL => 1, CHANNEL => 0 },
        _start    => 0,
        _end      => 0,
        _density_pct => exists $args{density_pct} ? _clamp_density_pct($args{density_pct}) : 100,
        _density_elem_pct => { map { $_ => (exists $args{density_pct} ? _clamp_density_pct($args{density_pct}) : 100) } keys %ELEMENTS },
    };
    bless $self, $class;
    return $self;
}

sub tag { 'ov_zigzag' }

sub set_visible {
    my ($self, $bool) = @_;
    $self->{visible} = $bool ? 1 : 0;
    return $self;
}

sub is_visible { $_[0]->{visible} ? 1 : 0 }

sub _clamp_density_pct {
    my ($pct) = @_;
    return 100 unless defined $pct;
    $pct = int($pct + ($pct >= 0 ? 0.5 : -0.5));
    return 0 if $pct < 0;
    return 100 if $pct > 100;
    return $pct;
}

sub set_density_pct {
    my ($self, $pct) = @_;
    my $v = _clamp_density_pct($pct);
    $self->{_density_pct} = $v;
    $self->{_density_elem_pct} ||= {};
    for my $elem (keys %ELEMENTS) {
        $self->{_density_elem_pct}{$elem} = $v;
    }
    return $self;
}

sub density_pct {
    my ($self) = @_;
    return $self->{_density_pct} // 100;
}

sub set_element_density_pct {
    my ($self, $elem, $pct) = @_;
    return $self unless defined $elem && exists $ELEMENTS{$elem};
    $self->{_density_elem_pct} ||= {};
    $self->{_density_elem_pct}{$elem} = _clamp_density_pct($pct);
    return $self;
}

sub element_density_pct {
    my ($self, $elem) = @_;
    return $self->density_pct() unless defined $elem && exists $ELEMENTS{$elem};
    return $self->{_density_elem_pct}{$elem} // $self->density_pct();
}

sub _filter_by_element_density {
    my ($self, $elem, $items, $score_spec) = @_;
    my $old = $self->{_density_pct};
    $self->{_density_pct} = $self->element_density_pct($elem);
    my $out = $self->_filter_by_density($items, $score_spec);
    $self->{_density_pct} = $old;
    return $out;
}

sub _filter_segments_continuous_by_element_density {
    my ($self, $elem, $items) = @_;
    return [] unless $items && ref($items) eq 'ARRAY';
    my $pct = $self->element_density_pct($elem);
    return [] if $pct <= 0;
    my @sorted = sort { ($a->{from_index} // 0) <=> ($b->{from_index} // 0) } @$items;
    return \@sorted if $pct >= 100 || @sorted == 0;
    my $keep = int((scalar(@sorted) * $pct + 99) / 100);
    $keep = 1 if $keep < 1;
    my $first = @sorted - $keep;
    $first = 0 if $first < 0;
    return [ @sorted[$first .. $#sorted] ];
}

sub _filter_by_density {
    my ($self, $items, $score_spec) = @_;
    return [] unless $items && ref($items) eq 'ARRAY';
    my $pct = $self->density_pct();
    return [] if $pct <= 0;
    return $items if $pct >= 100 || @$items == 0;
    my $keep = int((scalar(@$items) * $pct + 99) / 100);
    $keep = 1 if $keep < 1;
    my $score_of = sub {
        my ($item) = @_;
        return $score_spec->($item) if ref($score_spec) eq 'CODE';
        return $item->{$score_spec} // 1 if defined $score_spec && length $score_spec;
        my $span = abs(($item->{to_index} // 0) - ($item->{from_index} // 0));
        return $span || $item->{index} || 1;
    };
    my @ranked = sort {
        my $sc = $score_of->($b) <=> $score_of->($a);
        return $sc if $sc;
        ($b->{to_index} // $b->{index} // 0) <=> ($a->{to_index} // $a->{index} // 0);
    } @$items;
    return [ sort {
        ($a->{from_index} // $a->{index} // 0) <=> ($b->{from_index} // $b->{index} // 0)
    } @ranked[0 .. $keep - 1] ];
}

sub set_element_visible {
    my ($self, $elem, $bool) = @_;
    return $self unless defined $elem && exists $self->{_elements}{$elem};
    $self->{_elements}{$elem} = $bool ? 1 : 0;
    return $self;
}

sub is_element_visible {
    my ($self, $elem) = @_;
    return 0 unless defined $elem && exists $self->{_elements}{$elem};
    return $self->{_elements}{$elem};
}

sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $self->{_start} = $start // 0;
    $self->{_end}   = $end   // 0;
    $self->{_compute_range} = [$self->{_start}, $self->{_end}];
    return $self;
}

sub compute_range {
    my ($self) = @_;
    return $self->{_compute_range};
}

sub _local_index {
    my ($self, $index) = @_;
    return $index - ($self->{_start} // 0);
}

sub _segment_visible {
    my ($self, $seg) = @_;
    my $s = $self->{_start} // 0;
    my $e = $self->{_end}   // 0;
    my $lo = $seg->{from_index} // $seg->{to_index};
    my $hi = $seg->{to_index}   // $lo;
    return 0 if $hi < $s;
    return 0 if $lo > $e;
    return 1;
}

sub visible_items {
    my ($self) = @_;
    return [] unless $self->{indicator};
    return $self->{indicator}->get_snapshot_items();
}

sub clear {
    my ($self, $canvas) = @_;
    return $self unless $canvas;
    $canvas->delete($self->tag());
    return $self;
}

sub draw {
    my ($self, $canvas, $scales) = @_;
    return $self unless $self->{visible} && $self->{indicator};
    return $self unless $canvas && $scales;
    return $self unless defined $scales->{height} && $scales->{height} > 0;

    $self->clear($canvas);
    my $vals = $self->{indicator}->get_values();
    return $self unless $vals;

    my $tag = $self->tag();
    my $up_int   = $self->{theme}{zz_int_up}   // '#26a69a';
    my $dn_int   = $self->{theme}{zz_int_down} // '#ef5350';
    my $ext_col  = $self->{theme}{zz_ext}      // '#2196f3';

    if ($self->is_element_visible('EXTERNAL')) {
        my @external_candidates = grep { $self->_segment_visible($_) } @{ $vals->{external_segments} || [] };
        my $external = $self->_filter_segments_continuous_by_element_density('EXTERNAL', \@external_candidates);
        for my $seg (@$external) {
            next unless defined $seg->{from_price} && defined $seg->{to_price};
            my $x1 = $scales->index_to_center_x($self->_local_index($seg->{from_index}));
            my $x2 = $scales->index_to_center_x($self->_local_index($seg->{to_index}));
            my $y1 = $scales->value_to_y($seg->{from_price});
            my $y2 = $scales->value_to_y($seg->{to_price});
            $canvas->createLine(
                $x1, $y1, $x2, $y2,
                -fill  => $ext_col,
                -width => 2,
                -tags  => $tag,
            );
        }
    }

    if ($self->is_element_visible('INTERNAL')) {
        my @internal_candidates = grep { $self->_segment_visible($_) } @{ $vals->{internal_segments} || [] };
        my $internal = $self->_filter_segments_continuous_by_element_density('INTERNAL', \@internal_candidates);
        for my $seg (@$internal) {
            my $color = $seg->{dir} eq 'up' ? $up_int : $dn_int;
            next unless defined $seg->{from_price} && defined $seg->{to_price};
            my $x1 = $scales->index_to_center_x($self->_local_index($seg->{from_index}));
            my $x2 = $scales->index_to_center_x($self->_local_index($seg->{to_index}));
            my $y1 = $scales->value_to_y($seg->{from_price});
            my $y2 = $scales->value_to_y($seg->{to_price});
            $canvas->createLine(
                $x1, $y1, $x2, $y2,
                -fill  => $color,
                -width => 2,
                -tags  => $tag,
            );
        }
    }

    if ($self->is_element_visible('CHANNEL')) {
        my $ch_col = $self->{theme}{zz_channel} // '#90a4ae';
        my @channel_candidates = grep { $self->_segment_visible($_) } @{ $vals->{trend_channels} || [] };
        my $channels = $self->_filter_by_element_density('CHANNEL', \@channel_candidates, sub {
            my ($ch) = @_;
            my $span = abs(($ch->{to_index} // 0) - ($ch->{from_index} // 0)) || 1;
            return 1 / $span;
        });
        for my $ch (@$channels) {
            for my $line (
                [$ch->{from_index}, $ch->{from_price}, $ch->{to_index}, $ch->{to_price}],
                [$ch->{parallel_from_index}, $ch->{parallel_from_price},
                 $ch->{parallel_to_index}, $ch->{parallel_to_price}],
            ) {
                my ($i1, $p1, $i2, $p2) = @$line;
                next unless defined $i1 && defined $i2 && defined $p1 && defined $p2;
                my $x1 = $scales->index_to_center_x($self->_local_index($i1));
                my $x2 = $scales->index_to_center_x($self->_local_index($i2));
                my $y1 = $scales->value_to_y($p1);
                my $y2 = $scales->value_to_y($p2);
                $canvas->createLine(
                    $x1, $y1, $x2, $y2,
                    -fill  => $ch_col,
                    -width => 2,
                    -tags  => $tag,
                );
            }
        }
    }

    return $self;
}

1;