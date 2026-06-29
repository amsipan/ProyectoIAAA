package Market::Indicators::AnchoredVWAP;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::AnchoredVWAP
# 
# Multipivot Anchored VWAP engine generating smooth continuous series
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $anchor_type = $opts{anchor_type} // 'session';

    my $self = {
        anchor_type => $anchor_type,
        _highs      => [],
        _lows       => [],
        _closes     => [],
        _volumes    => [],
        _vwap       => [], # array of { value => num, anchor_idx => idx }
        _cum_pv     => 0,
        _cum_vol    => 0,
        _anchor_idx => 0,
        _market_data=> undef,
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_highs}      = [];
    $self->{_lows}       = [];
    $self->{_closes}     = [];
    $self->{_volumes}    = [];
    $self->{_vwap}       = [];
    $self->{_cum_pv}     = 0;
    $self->{_cum_vol}    = 0;
    $self->{_anchor_idx} = 0;
    return;
}

sub update_last {
    my ($self, $market_data, $index) = @_;
    my $candle = defined $index ? $market_data->get_candle($index) : $market_data->last_candle();
    return unless $candle;

    $self->{_market_data} = $market_data;
    my $high  = $candle->[2];
    my $low   = $candle->[3];
    my $close = $candle->[4];
    my $vol   = $candle->[5] // 1;

    $self->{_highs}->[$index]   = $high;
    $self->{_lows}->[$index]    = $low;
    $self->{_closes}->[$index]  = $close;
    $self->{_volumes}->[$index] = $vol;

    my $tp = ($high + $low + $close) / 3;
    $self->{_cum_pv}  += ($tp * $vol);
    $self->{_cum_vol} += $vol;

    my $vwap_val = ($self->{_cum_vol} > 0) ? ($self->{_cum_pv} / $self->{_cum_vol}) : $close;
    $self->{_vwap}->[$index] = {
        value      => $vwap_val,
        anchor_idx => 0,
    };
    return;
}

sub get_values {
    my ($self) = @_;
    return $self->{_vwap};
}

1;
