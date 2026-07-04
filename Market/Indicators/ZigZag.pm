package Market::Indicators::ZigZag;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::ZigZag — dirección interna (MTF) + externa (swing/ATR)
# Task 0033: dos ZigZag conviven con SMC/Mxwll; cálculo puro sin Tk.
#
# Interno (ZZMTF): resolución HTF configurable (default 30m), period=2.
#   Pivotes ph/pl con ventana len desde newbar; dir +1/-1; vértices consolidados
#   vs último ajustable (add_to_zigzag / update_zigzag del .pine).
# Externo (ChartPrime simplificado): swingLength=150, solo línea zigzag azul.
#   isBullish por nuevo highest/lowest; último segmento se ajusta.
#
# Contrato: new / update_last($md,$i) / get_values / reset
# =============================================================================

use Time::Moment;

my $MAX_VERTICES = 50;

sub new {
    my ($class, %args) = @_;
    my $self = {
        internal_resolution => $args{internal_resolution} // 30,
        internal_period     => $args{internal_period}     // 2,
        swing_length        => $args{swing_length}        // 150,
        atr_period          => $args{atr_period}          // 200,
        channel_width       => $args{channel_width}       // 1,
        %args,
    };
    bless $self, $class;
    $self->reset();
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_int_dir}              = 0;
    $self->{_int_prev_dir}         = 0;
    $self->{_int_vertices}         = [];
    $self->{_int_segments}         = [];
    $self->{_int_newbar_indices}   = [];
    $self->{_last_mtf_bucket}      = undef;
    $self->{internal_direction}    = [];

    $self->{_ext_trend}            = undef;
    $self->{_ext_bullish}          = undef;
    $self->{_ext_vertices}         = [];
    $self->{_ext_segments}         = [];
    $self->{_ext_pivot_high_idx}   = undef;
    $self->{_ext_pivot_high_price} = undef;
    $self->{_ext_pivot_low_idx}    = undef;
    $self->{_ext_pivot_low_price}  = undef;
    $self->{_high_buf}             = [];
    $self->{_low_buf}              = [];
    $self->{_close_buf}            = [];
    $self->{_tr_buf}               = [];
    $self->{_atr}                  = undef;
    $self->{external_direction}    = [];
    return $self;
}

sub set_internal_resolution {
    my ($self, $minutes) = @_;
    return $self unless defined $minutes && $minutes =~ /^\d+$/ && $minutes > 0;
    return $self if ($self->{internal_resolution} // 0) == $minutes;
    $self->{internal_resolution} = $minutes;
    $self->reset();
    return $self;
}

sub update_last {
    my ($self, $market_data, $index) = @_;
    return unless $market_data && defined $index;

    my $candle = $market_data->get_candle($index);
    return unless $candle;
    my ($ts, $open, $high, $low, $close) = @$candle[0 .. 4];

    $self->_update_internal($market_data, $index, $ts, $high, $low);
    $self->_update_external($index, $high, $low, $close);

    $self->{internal_direction}[$index] = $self->{_int_dir}
        ? $self->{_int_dir}
        : ($index > 0 ? ($self->{internal_direction}[$index - 1] // 0) : 0);
    $self->{external_direction}[$index] = defined $self->{_ext_bullish}
        ? ($self->{_ext_bullish} ? 1 : -1)
        : ($index > 0 ? ($self->{external_direction}[$index - 1] // 0) : 0);
    return $self;
}

sub get_values {
    my ($self) = @_;
    return {
        internal_vertices   => [ @{ $self->{_int_vertices} } ],
        external_vertices   => [ @{ $self->{_ext_vertices} } ],
        internal_segments   => [ @{ $self->{_int_segments} } ],
        external_segments   => [ @{ $self->{_ext_segments} } ],
        internal_direction  => [ @{ $self->{internal_direction} } ],
        external_direction  => [ @{ $self->{external_direction} } ],
    };
}

# Items para IndicatorSnapshot / tests (vértices + segmentos consolidados).
sub get_snapshot_items {
    my ($self) = @_;
    my @items;
    for my $seg (@{ $self->{_int_segments} }) {
        push @items, {
            index => $seg->{to_index},
            type  => $seg->{dir} eq 'up' ? 'ZZ_INT_UP' : 'ZZ_INT_DOWN',
            dir   => $seg->{dir},
            price => $seg->{to_price},
            meta  => {
                from_index => $seg->{from_index},
                from_price => $seg->{from_price},
                consolidated => $seg->{consolidated} ? 1 : 0,
                kind => 'internal',
            },
        };
    }
    for my $seg (@{ $self->{_ext_segments} }) {
        push @items, {
            index => $seg->{to_index},
            type  => $seg->{dir} eq 'up' ? 'ZZ_EXT_UP' : 'ZZ_EXT_DOWN',
            dir   => $seg->{dir},
            price => $seg->{to_price},
            meta  => {
                from_index => $seg->{from_index},
                from_price => $seg->{from_price},
                consolidated => $seg->{consolidated} ? 1 : 0,
                kind => 'external',
            },
        };
    }
    return \@items;
}

# --- MTF bucket (fronteras de reloj, estilo MarketData) -----------------------

sub _mtf_bucket_id {
    my ($self, $ts) = @_;
    my $res = $self->{internal_resolution} // 30;
    my $tm  = Time::Moment->from_string($ts);
    my $min = $tm->hour * 60 + $tm->minute;
    my $bucket_min = int($min / $res) * $res;
    return join ':', $tm->year, $tm->month, $tm->day_of_month, $bucket_min;
}

sub _range_extreme {
    my ($md, $from, $to, $kind) = @_;
    my ($best_val, $best_is) = (undef, 0);
    for my $i ($from .. $to) {
        my $c = $md->get_candle($i);
        next unless $c;
        my $v = $kind eq 'high' ? $c->[2] : $c->[3];
        if (!defined $best_val || ($kind eq 'high' ? $v > $best_val : $v < $best_val)) {
            $best_val = $v;
            $best_is  = $i;
        }
    }
    return ($best_val, $best_is);
}

sub _update_internal {
    my ($self, $md, $index, $ts, $high, $low) = @_;

    my $bucket = $self->_mtf_bucket_id($ts);
    my $newbar = !defined $self->{_last_mtf_bucket} || $bucket ne $self->{_last_mtf_bucket};
    $self->{_last_mtf_bucket} = $bucket;
    if ($newbar) {
        push @{ $self->{_int_newbar_indices} }, $index;
        shift @{ $self->{_int_newbar_indices} }
            while @{ $self->{_int_newbar_indices} } > 20;
    }

    my $prd = $self->{internal_period} // 2;
    my $bi  = 0;
    if (@{ $self->{_int_newbar_indices} } >= $prd) {
        $bi = $self->{_int_newbar_indices}[-$prd];
    }
    my $len = $index - $bi + 1;
    $len = 1 if $len < 1;

    my ($max_h, $max_i) = _range_extreme($md, $index - $len + 1, $index, 'high');
    my ($min_l, $min_i) = _range_extreme($md, $index - $len + 1, $index, 'low');

    my $ph = (defined $max_h && $max_i == $index && $high == $max_h) ? $high : undef;
    my $pl = (defined $min_l && $min_i == $index && $low == $min_l)  ? $low  : undef;

    my $dir = $self->{_int_dir};
    if (defined $ph && !defined $pl) {
        $dir = 1;
    } elsif (defined $pl && !defined $ph) {
        $dir = -1;
    }

    return unless defined $ph || defined $pl;

    my $dir_changed = $dir != ($self->{_int_prev_dir} // 0);
    if ($dir_changed) {
        $self->_int_add_vertex($dir > 0 ? $ph : $pl, $index);
    } else {
        $self->_int_update_vertex($dir > 0 ? $ph : $pl, $index, $dir);
    }
    $self->{_int_prev_dir} = $dir;
    $self->{_int_dir}      = $dir;
    $self->_rebuild_internal_segments();
}

sub _int_add_vertex {
    my ($self, $price, $index) = @_;
    return unless defined $price;
    unshift @{ $self->{_int_vertices} }, { index => $index, price => $price };
    pop @{ $self->{_int_vertices} } while @{ $self->{_int_vertices} } > $MAX_VERTICES;
}

sub _int_update_vertex {
    my ($self, $price, $index, $dir) = @_;
    return unless defined $price;
    if (!@{ $self->{_int_vertices} }) {
        $self->_int_add_vertex($price, $index);
        return;
    }
    my $v = $self->{_int_vertices}[0];
    if (($dir > 0 && $price > $v->{price}) || ($dir < 0 && $price < $v->{price})) {
        $v->{price} = $price;
        $v->{index} = $index;
    }
}

sub _rebuild_internal_segments {
    my ($self) = @_;
    my @verts = reverse @{ $self->{_int_vertices} };
    my @segs;
    for my $i (1 .. $#verts) {
        my $a = $verts[$i - 1];
        my $b = $verts[$i];
        my $dir = $b->{price} >= $a->{price} ? 'up' : 'down';
        push @segs, {
            from_index   => $a->{index},
            from_price   => $a->{price},
            to_index     => $b->{index},
            to_price     => $b->{price},
            dir          => $dir,
            consolidated => ($i < $#verts) ? 1 : 0,
        };
    }
    $self->{_int_segments} = \@segs;
}

# --- Externo: swingLength + lógica ChartPrime (solo línea) --------------------

sub _push_buf {
    my ($buf, $val, $max) = @_;
    push @$buf, $val;
    shift @$buf while @$buf > $max;
}

sub _buf_max { my ($b) = @_; return undef unless $b && @$b; my $m = $b->[0]; $m = $_ > $m ? $_ : $m for @$b; return $m; }
sub _buf_min { my ($b) = @_; return undef unless $b && @$b; my $m = $b->[0]; $m = $_ < $m ? $_ : $m for @$b; return $m; }

sub _update_atr {
    my ($self, $high, $low, $close) = @_;
    my $prev = $self->{_close_buf}[-1];
    my $tr;
    if (defined $prev) {
        my $hl  = $high - $low;
        my $hpc = abs($high - $prev);
        my $lpc = abs($low - $prev);
        $tr = $hl;
        $tr = $hpc if $hpc > $tr;
        $tr = $lpc if $lpc > $tr;
    } else {
        $tr = $high - $low;
    }
    _push_buf($self->{_tr_buf}, $tr, $self->{atr_period});
    my $n = @{ $self->{_tr_buf} };
    return if $n < $self->{atr_period};
    if (!defined $self->{_atr}) {
        my $sum = 0; $sum += $_ for @{ $self->{_tr_buf} };
        $self->{_atr} = $sum / $self->{atr_period};
    } else {
        my $p = $self->{atr_period};
        $self->{_atr} = ($self->{_atr} * ($p - 1) + $tr) / $p;
    }
}

sub _update_external {
    my ($self, $index, $high, $low, $close) = @_;
    my $slen = $self->{swing_length} // 150;

    _push_buf($self->{_high_buf},  $high,  $slen);
    _push_buf($self->{_low_buf},   $low,   $slen);
    $self->_update_atr($high, $low, $close);
    _push_buf($self->{_close_buf}, $close, $slen + 1);

    return if @{ $self->{_high_buf} } < $slen;

    my $swing_high = _buf_max($self->{_high_buf});
    my $swing_low  = _buf_min($self->{_low_buf});
    my $at_high = defined $swing_high && $high >= $swing_high - 1e-9;
    my $at_low  = defined $swing_low  && $low  <= $swing_low  + 1e-9;

    if ($at_high) {
        $self->{_ext_pivot_high_idx}   = $index;
        $self->{_ext_pivot_high_price} = $high;
    }
    if ($at_low) {
        $self->{_ext_pivot_low_idx}    = $index;
        $self->{_ext_pivot_low_price}  = $low;
    }

    my $trend     = $self->{_ext_trend};
    my $new_trend = $trend;
    if ($at_high && (!$at_low || ($trend // -1) <= 0)) {
        $new_trend = 1;
    } elsif ($at_low && (!$at_high || ($trend // 1) >= 0)) {
        $new_trend = -1;
    }

    if (defined $new_trend && (!defined $trend || $new_trend != $trend)) {
        if ($new_trend > 0
            && defined $self->{_ext_pivot_low_idx}
            && defined $self->{_ext_pivot_high_idx}) {
            $self->_ext_start_segment(
                $self->{_ext_pivot_low_idx},  $self->{_ext_pivot_low_price},
                $self->{_ext_pivot_high_idx}, $self->{_ext_pivot_high_price},
                'up',
            );
        } elsif ($new_trend < 0
            && defined $self->{_ext_pivot_high_idx}
            && defined $self->{_ext_pivot_low_idx}) {
            $self->_ext_start_segment(
                $self->{_ext_pivot_high_idx}, $self->{_ext_pivot_high_price},
                $self->{_ext_pivot_low_idx},  $self->{_ext_pivot_low_price},
                'down',
            );
        }
        $self->{_ext_trend} = $new_trend;
    } elsif (defined $new_trend) {
        if ($new_trend > 0 && $at_high) {
            $self->_ext_update_last($index, $high);
        } elsif ($new_trend < 0 && $at_low) {
            $self->_ext_update_last($index, $low);
        }
    }

    $self->{_ext_bullish} = defined $new_trend ? ($new_trend > 0 ? 1 : 0) : undef;
}

sub _ext_start_segment {
    my ($self, $i0, $p0, $i1, $p1, $dir) = @_;
    return unless defined $i0 && defined $p0 && defined $i1 && defined $p1;
    push @{ $self->{_ext_vertices} }, { index => $i0, price => $p0 };
    push @{ $self->{_ext_vertices} }, { index => $i1, price => $p1 };
    shift @{ $self->{_ext_vertices} } while @{ $self->{_ext_vertices} } > $MAX_VERTICES * 2;
    $self->_rebuild_external_segments();
}

sub _ext_update_last {
    my ($self, $index, $price) = @_;
    return unless @{ $self->{_ext_vertices} };
    $self->{_ext_vertices}[-1] = { index => $index, price => $price };
    $self->_rebuild_external_segments();
}

sub _rebuild_external_segments {
    my ($self) = @_;
    my @verts = @{ $self->{_ext_vertices} };
    my @segs;
    for (my $i = 1; $i < @verts; $i += 2) {
        my $a = $verts[$i - 1];
        my $b = $verts[$i];
        next unless $a && $b;
        my $dir = $b->{price} >= $a->{price} ? 'up' : 'down';
        push @segs, {
            from_index   => $a->{index},
            from_price   => $a->{price},
            to_index     => $b->{index},
            to_price     => $b->{price},
            dir          => $dir,
            consolidated => ($i < @verts - 2) ? 1 : 0,
        };
    }
    $self->{_ext_segments} = \@segs;
}

1;