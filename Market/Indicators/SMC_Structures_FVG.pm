package Market::Indicators::SMC_Structures_FVG;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::SMC_Structures_FVG — paridad "SMC Structures and FVG"
# =============================================================================
# Source: docs/reference_indicators/smc_structures_and_fvg_ludogh68.txt (LudoGH68)
#
# Config canónica = captura del profesor (NO defaults Pine si chocan):
#   Display FVG ON, Reduce mitigated ON, Number of FVG = 5
#   Break with body OFF, Display current structure OFF
#   BOS gray / CHoCH bull green / bear red, width 1
#   Number of breaks = 10, all Structure Fibonacci OFF
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $self = {
        # --- captura profe ---
        show_fvg             => exists $opts{show_fvg} ? ($opts{show_fvg} ? 1 : 0) : 1,
        reduce_mitigated_fvg => exists $opts{reduce_mitigated_fvg}
            ? ($opts{reduce_mitigated_fvg} ? 1 : 0) : 1,
        fvg_history          => $opts{fvg_history} // 5,
        break_with_body      => exists $opts{break_with_body}
            ? ($opts{break_with_body} ? 1 : 0) : 0,    # captura OFF
        show_current_struct  => exists $opts{show_current_struct}
            ? ($opts{show_current_struct} ? 1 : 0) : 0, # captura OFF
        struct_history       => $opts{struct_history} // 10,
        show_fibs            => 0,                      # captura all OFF
        struct_lookback      => $opts{struct_lookback} // 10,

        _o => [], _h => [], _l => [], _c => [],
        _last_index => -1,

        # structureHigh / structureLow / start indices / direction (0/1/2)
        _struct_hi   => undef,
        _struct_lo   => undef,
        _struct_hi_i => 0,
        _struct_lo_i => 0,
        _struct_dir  => 0,    # 0 none, 1 after low-break (bearish leg), 2 after high-break

        _events => [],        # BOS/CHoCH breaks (max struct_history)
        _fvgs   => [],        # FVG boxes
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
        show_current_struct struct_history show_fibs struct_lookback
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

    # Pine: bar_index == 0 init
    if ($index == 0) {
        $self->{_struct_hi}   = $h;
        $self->{_struct_lo}   = $l;
        $self->{_struct_hi_i} = 0;
        $self->{_struct_lo_i} = 0;
        $self->{_struct_dir}  = 0;
    }

    $self->_process_fvg($index) if $self->{show_fvg};
    $self->_process_structure($index);
    return;
}

# -----------------------------------------------------------------------------
# FVG — LudoGH: isBullishFVG = high[3] < low[1]; isBearishFVG = low[3] > high[1]
# box left=bar-2, right starts at bar-1, extends to current; max fvg_history
# -----------------------------------------------------------------------------
sub _process_fvg {
    my ($self, $i) = @_;
    return if $i < 3;

    my $h3 = $self->{_h}[$i - 3];
    my $l3 = $self->{_l}[$i - 3];
    my $h1 = $self->{_h}[$i - 1];
    my $l1 = $self->{_l}[$i - 1];
    return unless defined $h3 && defined $l3 && defined $h1 && defined $l1;

    # Create new gaps on this bar
    if ($h3 < $l1) {
        # Bullish: top=low[1], bottom=high[3]
        push @{ $self->{_fvgs} }, {
            index    => $i,
            left     => $i - 2,
            right    => $i - 1,
            hi       => $l1,
            lo       => $h3,
            type     => 'bull',
            mitig    => 0,
            active   => 1,
            _orig_hi => $l1,
            _orig_lo => $h3,
        };
        $self->_trim_fvgs;
    }
    if ($l3 > $h1) {
        # Bearish: top=low[3], bottom=high[1]
        push @{ $self->{_fvgs} }, {
            index    => $i,
            left     => $i - 2,
            right    => $i - 1,
            hi       => $l3,
            lo       => $h1,
            type     => 'bear',
            mitig    => 0,
            active   => 1,
            _orig_hi => $l3,
            _orig_lo => $h1,
        };
        $self->_trim_fvgs;
    }

    # Mitigate / reduce / extend right (FVGDraw loop)
    my $low  = $self->{_l}[$i];
    my $high = $self->{_h}[$i];
    return unless defined $low && defined $high;

    my @keep;
    for my $fvg (@{ $self->{_fvgs} }) {
        next unless $fvg->{active};
        if (($fvg->{type} // '') eq 'bull') {
            # full mitigate: low <= bottom
            if ($low <= $fvg->{lo}) {
                next;
            }
            if ($low < $fvg->{hi}) {
                $fvg->{mitig} = 1;
                if ($self->{reduce_mitigated_fvg}) {
                    $fvg->{hi} = $low;
                }
            }
        }
        else {
            # full mitigate: high >= top
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
        $fvg->{right} = $i;    # box.set_right(value, bar_index)
        push @keep, $fvg;
    }
    $self->{_fvgs} = \@keep;
}

sub _trim_fvgs {
    my ($self) = @_;
    # Pine (LudoGH): if array.size(fvgBoxes) > fvgHistoryNbr + 1 → remove oldest.
    # Con Number of FVG = 5 → se mantienen hasta 6 cajas (history+1), no 5.
    # Cap estricto a 5 hacía desaparecer FVGs aún no mitigados (p.ej. 16-jul 17:15
    # se recortaba el 17-jul 07:30 y no llegaba al final del chart como en TV).
    my $hist = $self->{fvg_history} // 5;
    $hist = 1 if $hist < 1;
    my $max = $hist + 1;
    while (@{ $self->{_fvgs} } > $max) {
        shift @{ $self->{_fvgs} };
    }
}

# -----------------------------------------------------------------------------
# Structure helpers — port of get_structure_highest/lowest_bar + highestbars
# Offsets are relative to current bar i (0 = current, -1 = prev, ...).
# Absolute bar = i + offset.
# -----------------------------------------------------------------------------
sub _highestbars_offset {
    my ($self, $i, $length) = @_;
    return 0 if $length < 1 || $i < 0;
    my $from = $i - $length + 1;
    $from = 0 if $from < 0;
    my ($best_h, $best_off);
    for my $j ($from .. $i) {
        my $h = $self->{_h}[$j];
        next unless defined $h;
        my $off = $j - $i;
        # Prefer most recent on ties (matches typical ta.highestbars)
        if (!defined $best_h || $h > $best_h || ($h == $best_h && $off > $best_off)) {
            $best_h   = $h;
            $best_off = $off;
        }
    }
    return $best_off // 0;
}

sub _lowestbars_offset {
    my ($self, $i, $length) = @_;
    return 0 if $length < 1 || $i < 0;
    my $from = $i - $length + 1;
    $from = 0 if $from < 0;
    my ($best_l, $best_off);
    for my $j ($from .. $i) {
        my $l = $self->{_l}[$j];
        next unless defined $l;
        my $off = $j - $i;
        if (!defined $best_l || $l < $best_l || ($l == $best_l && $off > $best_off)) {
            $best_l   = $l;
            $best_off = $off;
        }
    }
    return $best_off // 0;
}

# LudoGH get_structure_highest_bar(lookback)
sub _get_structure_highest_bar_abs {
    my ($self, $i, $lookback) = @_;
    $lookback //= $self->{struct_lookback} // 10;
    my $len = ($i >= $lookback) ? $lookback : ($i + 1);
    my $max_bar = $self->_highestbars_offset($i, $len);    # offset <= 0

    my $idx = 0;
    for my $k (0 .. $lookback - 1) {
        my $j1 = $i - ($k + 1);
        my $j2 = $i - ($k + 2);
        my $j0 = $i - $k;
        next if $j2 < 0;
        my $h0 = $self->{_h}[$j0];
        my $h1 = $self->{_h}[$j1];
        my $h2 = $self->{_h}[$j2];
        next unless defined $h0 && defined $h1 && defined $h2;
        my $cand = -($k + 1);
        if ($h1 > $h2 && $h0 <= $h1 && $cand >= $max_bar) {
            $idx = $cand;
        }
    }
    $idx = $max_bar if $idx == 0;
    return $i + $idx;
}

# LudoGH get_structure_lowest_bar(lookback)
sub _get_structure_lowest_bar_abs {
    my ($self, $i, $lookback) = @_;
    $lookback //= $self->{struct_lookback} // 10;
    my $len = ($i >= $lookback) ? $lookback : ($i + 1);
    my $min_bar = $self->_lowestbars_offset($i, $len);

    my $idx = 0;
    for my $k (0 .. $lookback - 1) {
        my $j1 = $i - ($k + 1);
        my $j2 = $i - ($k + 2);
        my $j0 = $i - $k;
        next if $j2 < 0;
        my $l0 = $self->{_l}[$j0];
        my $l1 = $self->{_l}[$j1];
        my $l2 = $self->{_l}[$j2];
        next unless defined $l0 && defined $l1 && defined $l2;
        my $cand = -($k + 1);
        if ($l1 < $l2 && $l0 >= $l1 && $cand >= $min_bar) {
            $idx = $cand;
        }
    }
    $idx = $min_bar if $idx == 0;
    return $i + $idx;
}

sub _break_price {
    my ($self, $i, $side) = @_;
    # side: 'high' | 'low'
    if ($self->{break_with_body}) {
        return $self->{_c}[$i];
    }
    return $side eq 'high' ? $self->{_h}[$i] : $self->{_l}[$i];
}

# -----------------------------------------------------------------------------
# Structure processing — full LudoGH break conditions
# -----------------------------------------------------------------------------
sub _process_structure {
    my ($self, $i) = @_;
    return if $i < 0;
    return unless defined $self->{_struct_hi} && defined $self->{_struct_lo};

    my $body = $self->{break_with_body} ? 1 : 0;
    my $px_lo = $self->_break_price($i, 'low');
    my $px_hi = $self->_break_price($i, 'high');
    return unless defined $px_lo && defined $px_hi;

    my $dir   = $self->{_struct_dir} // 0;
    my $s_lo  = $self->{_struct_lo};
    my $s_hi  = $self->{_struct_hi};
    my $s_lo_i = $self->{_struct_lo_i} // 0;
    my $s_hi_i = $self->{_struct_hi_i} // 0;

    # Prior break prices [1],[2],[3]
    my @px_lo_hist;
    my @px_hi_hist;
    for my $k (1 .. 3) {
        if ($i - $k >= 0) {
            push @px_lo_hist, $self->_break_price($i - $k, 'low');
            push @px_hi_hist, $self->_break_price($i - $k, 'high');
        }
        else {
            push @px_lo_hist, undef;
            push @px_hi_hist, undef;
        }
    }

    # isStructureLowBroken (Pine line 298)
    my $low_broken = 0;
    if ($dir == 2 && $px_lo < $s_lo) {
        $low_broken = 1;
    }
    elsif (
        $px_lo < $s_lo
        && defined $px_lo_hist[0] && $px_lo_hist[0] >= $s_lo
        && defined $px_lo_hist[1] && $px_lo_hist[1] >= $s_lo
        && defined $px_lo_hist[2] && $px_lo_hist[2] >= $s_lo
        && ($i - 1) > $s_lo_i
        && ($i - 2) > $s_lo_i
        && ($i - 3) > $s_lo_i
      )
    {
        $low_broken = 1;
    }

    # isStructureHighBroken (Pine line 299)
    my $high_broken = 0;
    if ($dir == 1 && $px_hi > $s_hi) {
        $high_broken = 1;
    }
    elsif (
        $px_hi > $s_hi
        && defined $px_hi_hist[0] && $px_hi_hist[0] <= $s_hi
        && defined $px_hi_hist[1] && $px_hi_hist[1] <= $s_hi
        && defined $px_hi_hist[2] && $px_hi_hist[2] <= $s_hi
        && ($i - 1) > $s_hi_i
        && ($i - 2) > $s_hi_i
        && ($i - 3) > $s_hi_i
      )
    {
        $high_broken = 1;
    }

    my $struct_max_bar = $self->_get_structure_highest_bar_abs($i);
    my $struct_min_bar = $self->_get_structure_lowest_bar_abs($i);

    if ($low_broken) {
        # dir==1 → BOS bearish; else CHoCH
        my $tag = ($dir == 1) ? 'BOS' : 'CHoCH';
        $self->_push_break({
            index       => $i,
            type        => $tag,
            dir         => 'down',
            price       => $s_lo,
            start_index => $s_lo_i,
            scope       => 'structures',
            color_role  => ($tag eq 'BOS' ? 'bos_bear' : 'choch_bear'),
        });

        $self->{_struct_dir}  = 1;
        $self->{_struct_hi_i} = $struct_max_bar;
        $self->{_struct_hi}   = $self->{_h}[$struct_max_bar];
        $self->{_struct_lo_i} = $i;
        $self->{_struct_lo}   = $self->{_l}[$i];
        return;
    }

    if ($high_broken) {
        my $tag = ($dir == 2) ? 'BOS' : 'CHoCH';
        $self->_push_break({
            index       => $i,
            type        => $tag,
            dir         => 'up',
            price       => $s_hi,
            start_index => $s_hi_i,
            scope       => 'structures',
            color_role  => ($tag eq 'BOS' ? 'bos_bull' : 'choch_bull'),
        });

        $self->{_struct_dir}  = 2;
        $self->{_struct_hi_i} = $i;
        $self->{_struct_hi}   = $self->{_h}[$i];
        $self->{_struct_lo_i} = $struct_min_bar;
        $self->{_struct_lo}   = $self->{_l}[$struct_min_bar];
        return;
    }

    # else: extend structure extremes (Pine 364–371)
    # With break_with_body OFF (captura), the inner "or not(body and bars>start)" is true.
    my $high = $self->{_h}[$i];
    my $low  = $self->{_l}[$i];
    if (defined $high && $high > $s_hi && ($dir == 0 || $dir == 2)) {
        my $allow = 1;
        if ($body) {
            $allow = (($i - 1) > $s_hi_i && ($i - 2) > $s_hi_i && ($i - 3) > $s_hi_i) ? 0 : 1;
            # Pine: if(not(body) or not(body and bars>start)) → update when NOT (body and bars>start)
            # i.e. update when !body OR !(bars>start)
            $allow = 1;    # simplified: with body ON, update unless all three bars after start
            if (($i - 1) > $s_hi_i && ($i - 2) > $s_hi_i && ($i - 3) > $s_hi_i) {
                $allow = 0;
            }
        }
        if ($allow) {
            $self->{_struct_hi}   = $high;
            $self->{_struct_hi_i} = $i;
        }
    }
    elsif (defined $low && $low < $s_lo && ($dir == 0 || $dir == 1)) {
        my $allow = 1;
        if ($body) {
            if (($i - 1) > $s_lo_i && ($i - 2) > $s_lo_i && ($i - 3) > $s_lo_i) {
                $allow = 0;
            }
        }
        if ($allow) {
            $self->{_struct_lo}   = $low;
            $self->{_struct_lo_i} = $i;
        }
    }
}

sub _push_break {
    my ($self, $ev) = @_;
    return unless ref($ev) eq 'HASH';
    push @{ $self->{_events} }, $ev;
    my $max = $self->{struct_history} // 10;
    $max = 1 if $max < 1;
    while (@{ $self->{_events} } > $max) {
        shift @{ $self->{_events} };
    }
}

# --- Public getters ---

sub get_events {
    my ($self) = @_;
    return [ grep { ref($_) eq 'HASH' } @{ $self->{_events} || [] } ];
}

sub get_fvg {
    my ($self) = @_;
    return [ grep { ref($_) eq 'HASH' && ($_->{active} // 1) } @{ $self->{_fvgs} || [] } ];
}

sub get_pivots       { return []; }
sub get_major        { return []; }
sub get_fibonacci    { return []; }
sub get_order_blocks { return []; }
sub get_eqhl         { return []; }
sub get_strong_weak  { return []; }
sub get_mtf_levels   { return []; }

sub get_current_structure {
    my ($self) = @_;
    return [] unless $self->{show_current_struct};
    return [
        {
            side  => 'high',
            price => $self->{_struct_hi},
            index => $self->{_struct_hi_i},
        },
        {
            side  => 'low',
            price => $self->{_struct_lo},
            index => $self->{_struct_lo_i},
        },
    ];
}

sub get_values {
    my ($self) = @_;
    return [ @{ $self->{_values} } ];
}

1;
