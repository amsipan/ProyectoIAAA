package Market::Indicators::AnchoredVWAP;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::AnchoredVWAP
#
# Anchored VWAP estilo TradingView (drawing tool):
#   - El usuario fija una vela de ancla (anchor_idx).
#   - Desde esa vela en adelante: VWAP acumulado ponderado por volumen.
#   - Source por defecto: HLC3 = (H+L+C)/3  (como TV y DIY).
#   - Bandas de desviación estándar (modo Standard):
#       variance = E[p²] - VWAP²  (ponderado por vol)
#       upper/lower = VWAP ± mult * stdev
#   - Multiplicadores #1/#2/#3 (TV defaults: 1 on, 2/3 off).
#
# Sin ancla: no hay valores (nada que dibujar). Respeta Replay vía feed_to.
# Feed incremental O(1) por vela; set_anchor recalcula el tramo anchor..last.
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $self = {
        source => $opts{source} // 'hlc3',  # hlc3 | hl2 | close | ohlc4
        band1_on   => exists $opts{band1_on} ? ($opts{band1_on} ? 1 : 0) : 1,
        band1_mult => $opts{band1_mult} // 1.0,
        band2_on   => exists $opts{band2_on} ? ($opts{band2_on} ? 1 : 0) : 0,
        band2_mult => $opts{band2_mult} // 2.0,
        band3_on   => exists $opts{band3_on} ? ($opts{band3_on} ? 1 : 0) : 0,
        band3_mult => $opts{band3_mult} // 3.0,

        anchor_idx => undef,
        _highs     => [],
        _lows      => [],
        _opens     => [],
        _closes    => [],
        _volumes   => [],
        # Por índice global: { value, stdev, upper1..3, lower1..3, anchor_idx }
        _series    => [],
        _last_data_idx => -1,
        # Acumuladores desde la ancla (solo válidos si anchor definido)
        _sum_vol => 0,
        _sum_pv  => 0,
        _sum_p2v => 0,
        _acc_to  => -1,  # último índice incluido en los acumuladores
        _market_data => undef,
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    # Preservar ancla: el feed de Replay/TF hace reset()+realimentación.
    # La vela de anclaje elegida por el usuario debe sobrevivir; solo se
    # invalidan datos/serie (se recalcularán al re-alimentar).
    my $keep_anchor = $self->{anchor_idx};
    $self->{_highs}        = [];
    $self->{_lows}         = [];
    $self->{_opens}        = [];
    $self->{_closes}       = [];
    $self->{_volumes}      = [];
    $self->{_series}       = [];
    $self->{_last_data_idx} = -1;
    $self->_reset_accumulators();
    $self->{anchor_idx} = $keep_anchor;
    return;
}

sub _reset_accumulators {
    my ($self) = @_;
    $self->{_sum_vol} = 0;
    $self->{_sum_pv}  = 0;
    $self->{_sum_p2v} = 0;
    $self->{_acc_to}  = -1;
    return;
}

sub clear_series {
    my ($self) = @_;
    $self->{_series} = [];
    $self->_reset_accumulators();
    return $self;
}

sub anchor_index {
    my ($self) = @_;
    return $self->{anchor_idx};
}

sub has_anchor {
    my ($self) = @_;
    return defined $self->{anchor_idx} ? 1 : 0;
}

sub set_anchor {
    my ($self, $idx) = @_;
    return $self unless defined $idx;
    $idx = int($idx);
    $idx = 0 if $idx < 0;
    my $last = $self->{_last_data_idx};
    $idx = $last if $last >= 0 && $idx > $last;
    $self->{anchor_idx} = $idx;
    $self->_recompute_from_anchor();
    return $self;
}

sub clear_anchor {
    my ($self) = @_;
    $self->{anchor_idx} = undef;
    $self->{_series}    = [];
    $self->_reset_accumulators();
    return $self;
}

sub set_band {
    my ($self, $n, %opts) = @_;
    return $self unless $n && $n >= 1 && $n <= 3;
    my $on_key   = "band${n}_on";
    my $mult_key = "band${n}_mult";
    $self->{$on_key}   = $opts{on} ? 1 : 0 if exists $opts{on};
    $self->{$mult_key} = 0 + $opts{mult} if exists $opts{mult};
    $self->_recompute_from_anchor() if $self->has_anchor();
    return $self;
}

sub update_last {
    my ($self, $market_data, $index) = @_;
    my $candle = defined $index ? $market_data->get_candle($index) : $market_data->last_candle();
    return unless $candle;
    return unless defined $index;

    $self->{_market_data} = $market_data;
    $self->{_opens}->[$index]   = $candle->[1];
    $self->{_highs}->[$index]   = $candle->[2];
    $self->{_lows}->[$index]    = $candle->[3];
    $self->{_closes}->[$index]  = $candle->[4];
    $self->{_volumes}->[$index] = defined $candle->[5] ? $candle->[5] : 0;

    if ($index > ($self->{_last_data_idx} // -1)) {
        $self->{_last_data_idx} = $index;
    }

    return unless $self->has_anchor();
    my $anchor = $self->{anchor_idx};

    if ($index < $anchor) {
        $self->{_series}->[$index] = undef;
        return;
    }

    # Si el feed avanza de forma secuencial tras _acc_to, extender O(1).
    # Si hay hueco, retroceso o re-ancla parcial → recalcular tramo.
    my $acc_to = $self->{_acc_to} // -1;
    if ($acc_to < $anchor - 1 || $index < $acc_to) {
        $self->_recompute_from_anchor();
        return;
    }
    if ($index == $acc_to) {
        # Misma vela re-alimentada: rehacer solo ese punto desde cero del tramo
        # (caso raro). Más simple: recompute.
        $self->_recompute_from_anchor();
        return;
    }
    # Extender de acc_to+1 .. index
    for my $i (($acc_to + 1) .. $index) {
        $self->_accumulate_index($i);
    }
    return;
}

sub get_values {
    my ($self) = @_;
    return $self->{_series};
}

sub get_point {
    my ($self, $i) = @_;
    return undef unless defined $i && $i >= 0;
    return $self->{_series}->[$i];
}

sub _price_at {
    my ($self, $i) = @_;
    my $h = $self->{_highs}->[$i];
    my $l = $self->{_lows}->[$i];
    my $c = $self->{_closes}->[$i];
    my $o = $self->{_opens}->[$i];
    return undef unless defined $h && defined $l && defined $c;

    my $src = $self->{source} // 'hlc3';
    return $c if $src eq 'close';
    return ($h + $l) / 2 if $src eq 'hl2';
    return ($o + $h + $l + $c) / 4 if $src eq 'ohlc4' && defined $o;
    return ($h + $l + $c) / 3;
}

sub _recompute_from_anchor {
    my ($self) = @_;
    my $anchor = $self->{anchor_idx};
    my $last   = $self->{_last_data_idx};
    $self->{_series} = [];
    $self->_reset_accumulators();
    return unless defined $anchor && $last >= 0;
    return if $anchor > $last;

    for my $i ($anchor .. $last) {
        $self->_accumulate_index($i);
    }
    return $self;
}

sub _accumulate_index {
    my ($self, $i) = @_;
    my $anchor = $self->{anchor_idx};
    return unless defined $anchor;
    return if $i < $anchor;

    my $p = $self->_price_at($i);
    if (!defined $p) {
        $self->{_series}->[$i] = undef;
        $self->{_acc_to} = $i;
        return;
    }

    my $v = $self->{_volumes}->[$i];
    $v = 0 unless defined $v;
    my $wv = ($v > 0) ? $v : 0;
    if (($self->{_sum_vol} // 0) <= 0 && $wv <= 0) {
        $wv = 1;
    }

    $self->{_sum_vol} += $wv;
    $self->{_sum_pv}  += $p * $wv;
    $self->{_sum_p2v} += $p * $p * $wv;
    $self->{_acc_to}   = $i;

    my $sum_vol = $self->{_sum_vol};
    my $vwap = ($sum_vol > 0) ? ($self->{_sum_pv} / $sum_vol) : $p;
    my $var  = ($sum_vol > 0) ? ($self->{_sum_p2v} / $sum_vol - $vwap * $vwap) : 0;
    $var = 0 if $var < 0;
    my $stdev = sqrt($var);

    my $pt = {
        value      => $vwap,
        stdev      => $stdev,
        anchor_idx => $anchor,
    };
    for my $n (1, 2, 3) {
        if ($self->{"band${n}_on"}) {
            my $mult = $self->{"band${n}_mult"} // $n;
            $pt->{"upper$n"} = $vwap + $mult * $stdev;
            $pt->{"lower$n"} = $vwap - $mult * $stdev;
        }
        else {
            $pt->{"upper$n"} = undef;
            $pt->{"lower$n"} = undef;
        }
    }
    $self->{_series}->[$i] = $pt;
    return;
}

1;
