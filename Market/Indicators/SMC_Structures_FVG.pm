package Market::Indicators::SMC_Structures_FVG;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::SMC_Structures_FVG — paridad "SMC Structures and FVG"
# =============================================================================
# Source: docs/reference_indicators/smc_structures_and_fvg_ludogh68.txt (LudoGH68)
# Config canónica = captura del profesor (NO defaults Pine):
#   Display FVG ON, Reduce mitigated ON, max 5
#   Break with body OFF, Display current structure OFF
#   BOS gray, CHoCH bull green / bear red
#   Number of breaks 10, all structure fibs OFF
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $self = {
        show_fvg              => exists $opts{show_fvg} ? ($opts{show_fvg} ? 1 : 0) : 1,
        reduce_mitigated_fvg  => exists $opts{reduce_mitigated_fvg} ? ($opts{reduce_mitigated_fvg} ? 1 : 0) : 1,
        fvg_history           => $opts{fvg_history} // 5,
        break_with_body       => exists $opts{break_with_body} ? ($opts{break_with_body} ? 1 : 0) : 0, # captura OFF
        show_current_struct   => exists $opts{show_current_struct} ? ($opts{show_current_struct} ? 1 : 0) : 0,
        struct_history        => $opts{struct_history} // 10,
        show_fibs             => 0, # captura all OFF

        _o => [], _h => [], _l => [], _c => [],
        _last_index => -1,

        _struct_hi => undef,
        _struct_lo => undef,
        _struct_hi_i => 0,
        _struct_lo_i => 0,
        _struct_dir => 0, # 0 none, 1 bearish-after-low-break, 2 bullish-after-high-break

        _events => [],  # BOS/CHoCH lines
        _fvgs   => [],  # active FVG boxes
        _values => [],
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    my $class = ref $self;
    my %keep = map { $_ => $self->{$_} } qw(
        show_fvg reduce_mitigated_fvg fvg_history break_with_body
        show_current_struct struct_history show_fibs
    );
    %$self = %{ $class->new(%keep) };
    return $self;
}

sub update_last {
    my ($self, $market_data, $index) = @_;
    my $candle = defined $index
        ? $market_data->get_candle($index)
        : $market_data->last_candle();
    return unless $candle;

    my ($o, $h, $l, $c) = ($candle->[1], $candle->[2], $candle->[3], $candle->[4]);
    $self->{_o}[$index] = $o;
    $self->{_h}[$index] = $h;
    $self->{_l}[$index] = $l;
    $self->{_c}[$index] = $c;
    $self->{_last_index} = $index;
    $self->{_values}[$index] = undef;

    if ($index == 0) {
        $self->{_struct_hi} = $h;
        $self->{_struct_lo} = $l;
        $self->{_struct_hi_i} = 0;
        $self->{_struct_lo_i} = 0;
        $self->{_struct_dir} = 0;
    }

    $self->_process_fvg($index) if $self->{show_fvg};
    $self->_process_structure($index);
    return;
}

# LudoGH: isBullishFVG = high[3] < low[1]; isBearishFVG = low[3] > high[1]
# At bar index i: high[i-3] < low[i-1] etc.
sub _process_fvg {
    my ($self, $i) = @_;
    return if $i < 3;

    my $h3 = $self->{_h}[$i - 3];
    my $l3 = $self->{_l}[$i - 3];
    my $h1 = $self->{_h}[$i - 1];
    my $l1 = $self->{_l}[$i - 1];
    return unless defined $h3 && defined $l3 && defined $h1 && defined $l1;

    if ($h3 < $l1) {
        # Bullish FVG: top=low[1], bottom=high[3]
        push @{ $self->{_fvgs} }, {
            index   => $i,
            left    => $i - 2,
            right   => $i - 1,
            hi      => $l1,
            lo      => $h3,
            type    => 'bull',
            mitig   => 0,
            active  => 1,
            _orig_hi => $l1,
            _orig_lo => $h3,
        };
        $self->_trim_fvgs;
    }
    if ($l3 > $h1) {
        push @{ $self->{_fvgs} }, {
            index   => $i,
            left    => $i - 2,
            right   => $i - 1,
            hi      => $l3,
            lo      => $h1,
            type    => 'bear',
            mitig   => 0,
            active  => 1,
            _orig_hi => $l3,
            _orig_lo => $h1,
        };
        $self->_trim_fvgs;
    }

    # Mitigate / reduce / delete
    my $low  = $self->{_l}[$i];
    my $high = $self->{_h}[$i];
    my @keep;
    for my $fvg (@{ $self->{_fvgs} }) {
        next unless $fvg->{active};
        if ($fvg->{type} eq 'bull') {
            if ($low <= $fvg->{lo}) {
                next; # fully mitigated → drop
            }
            if ($low < $fvg->{hi}) {
                $fvg->{mitig} = 1;
                if ($self->{reduce_mitigated_fvg}) {
                    $fvg->{hi} = $low;
                }
            }
        } else {
            if ($high >= $fvg->{hi}) {
                next;
            }
            if ($high > $fvg->{lo}) {
                $fvg->{mitig} = 1;
                if ($self->{reduce_mitigated_fvg}) {
                    $fvg->{lo} = $high;
                }
            }
        }
        $fvg->{right} = $i; # extend to current bar
        push @keep, $fvg;
    }
    $self->{_fvgs} = \@keep;
}

sub _trim_fvgs {
    my ($self) = @_;
    my $max = $self->{fvg_history};
    while (@{ $self->{_fvgs} } > $max) {
        shift @{ $self->{_fvgs} };
    }
}

sub _structure_highest_bar {
    my ($self, $i, $lookback) = @_;
    $lookback = 10;
    my $from = $i - $lookback;
    $from = 0 if $from < 0;
    my ($best_i, $best_h) = ($i, $self->{_h}[$i]);
    for my $j ($from .. $i) {
        next unless defined $self->{_h}[$j];
        if ($self->{_h}[$j] >= $best_h) {
            $best_h = $self->{_h}[$j];
            $best_i = $j;
        }
    }
    return $best_i;
}

sub _structure_lowest_bar {
    my ($self, $i, $lookback) = @_;
    $lookback = 10;
    my $from = $i - $lookback;
    $from = 0 if $from < 0;
    my ($best_i, $best_l) = ($i, $self->{_l}[$i]);
    for my $j ($from .. $i) {
        next unless defined $self->{_l}[$j];
        if ($self->{_l}[$j] <= $best_l) {
            $best_l = $self->{_l}[$j];
            $best_i = $j;
        }
    }
    return $best_i;
}

sub _process_structure {
    my ($self, $i) = @_;
    return if $i < 1;
    return unless defined $self->{_struct_hi} && defined $self->{_struct_lo};

    my $close = $self->{_c}[$i];
    my $high  = $self->{_h}[$i];
    my $low   = $self->{_l}[$i];
    my $body_break = $self->{break_with_body};
    my $low_break_px  = $body_break ? $close : $low;
    my $high_break_px = $body_break ? $close : $high;

    my $dir = $self->{_struct_dir};

    # Conditions adapted from LudoGH (simplified multi-bar confirm with body OFF)
    my $low_broken = 0;
    my $high_broken = 0;

    if ($dir == 2 && $low_break_px < $self->{_struct_lo}) {
        $low_broken = 1;
    } elsif ($low_break_px < $self->{_struct_lo} && $i > $self->{_struct_lo_i}) {
        # require previous bars not already far below — use simple cross
        my $prev = $i > 0 ? ($body_break ? $self->{_c}[$i-1] : $self->{_l}[$i-1]) : undef;
        $low_broken = 1 if !defined $prev || $prev >= $self->{_struct_lo};
    }

    if ($dir == 1 && $high_break_px > $self->{_struct_hi}) {
        $high_broken = 1;
    } elsif ($high_break_px > $self->{_struct_hi} && $i > $self->{_struct_hi_i}) {
        my $prev = $i > 0 ? ($body_break ? $self->{_c}[$i-1] : $self->{_h}[$i-1]) : undef;
        $high_broken = 1 if !defined $prev || $prev <= $self->{_struct_hi};
    }

    if ($low_broken) {
        my $tag = ($dir == 1) ? 'BOS' : 'CHoCH';
        my $color_role = 'bear'; # bearish break of low
        push @{ $self->{_events} }, {
            index => $i,
            type  => $tag,
            dir   => 'down',
            price => $self->{_struct_lo},
            start_index => $self->{_struct_lo_i},
            scope => 'structures',
            color_role => ($tag eq 'BOS' ? 'bos_bear' : 'choch_bear'),
        };
        $self->_trim_events;

        $self->{_struct_dir} = 1;
        my $max_bar = $self->_structure_highest_bar($i);
        $self->{_struct_hi_i} = $max_bar;
        $self->{_struct_hi}   = $self->{_h}[$max_bar];
        $self->{_struct_lo_i} = $i;
        $self->{_struct_lo}   = $low;
        return;
    }

    if ($high_broken) {
        my $tag = ($dir == 2) ? 'BOS' : 'CHoCH';
        push @{ $self->{_events} }, {
            index => $i,
            type  => $tag,
            dir   => 'up',
            price => $self->{_struct_hi},
            start_index => $self->{_struct_hi_i},
            scope => 'structures',
            color_role => ($tag eq 'BOS' ? 'bos_bull' : 'choch_bull'),
        };
        $self->_trim_events;

        $self->{_struct_dir} = 2;
        my $min_bar = $self->_structure_lowest_bar($i);
        $self->{_struct_lo_i} = $min_bar;
        $self->{_struct_lo}   = $self->{_l}[$min_bar];
        $self->{_struct_hi_i} = $i;
        $self->{_struct_hi}   = $high;
        return;
    }

    # Extend structure extremes (LudoGH else branch)
    if ($high > $self->{_struct_hi} && ($dir == 0 || $dir == 2)) {
        $self->{_struct_hi} = $high;
        $self->{_struct_hi_i} = $i;
    } elsif ($low < $self->{_struct_lo} && ($dir == 0 || $dir == 1)) {
        $self->{_struct_lo} = $low;
        $self->{_struct_lo_i} = $i;
    }
}

sub _trim_events {
    my ($self) = @_;
    my $max = $self->{struct_history};
    while (@{ $self->{_events} } > $max) {
        shift @{ $self->{_events} };
    }
}

sub get_events {
    my ($self) = @_;
    return [ @{ $self->{_events} } ];
}

sub get_fvg {
    my ($self) = @_;
    return [ grep { $_->{active} } @{ $self->{_fvgs} } ];
}

sub get_pivots { return []; }
sub get_major  { return []; }
sub get_fibonacci { return []; }
sub get_order_blocks { return []; }
sub get_eqhl { return []; }
sub get_strong_weak { return []; }
sub get_mtf_levels { return []; }

sub get_current_structure {
    my ($self) = @_;
    return [] unless $self->{show_current_struct};
    return [
        { side => 'high', price => $self->{_struct_hi}, index => $self->{_struct_hi_i} },
        { side => 'low',  price => $self->{_struct_lo}, index => $self->{_struct_lo_i} },
    ];
}

sub get_values {
    my ($self) = @_;
    return [ @{ $self->{_values} } ];
}

1;
