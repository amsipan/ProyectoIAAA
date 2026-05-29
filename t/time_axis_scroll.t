use strict;
use warnings;

use lib '.';
use Test::More;

use Market::ChartEngine;

{
    package TestMarketData;

    sub new {
        my ($class, $size) = @_;
        return bless { size => $size }, $class;
    }

    sub size { $_[0]->{size} }
    sub last_index { $_[0]->{size} - 1 }

    sub get_timestamp {
        my ($self, $index) = @_;
        return undef if $index < 0 || $index >= $self->{size};
        my $hour = int($index / 60);
        my $min  = $index % 60;
        return sprintf('2026-04-01T%02d:%02d:00-05:00', $hour, $min);
    }

    sub compute_time_anchors { return [] }
}

{
    package TestCanvas;
    sub new { bless { w => $_[1] || 800 }, $_[0] }
    sub geometry { return $_[0]->{w} . 'x400' }
    sub Width { $_[0]->{w} }
    sub width { $_[0]->{w} }
}

# Feature: tradingview-parity, Property 20: el eje temporal se desplaza con el drag horizontal

my $engine = bless {
    market_data  => TestMarketData->new(100),
    price_canvas => TestCanvas->new(800),
    visible_bars => 20,
    offset       => 10,
}, 'Market::ChartEngine';

my $labels_before = $engine->compute_intraday_labels();
my ($before) = grep { $_->{text} eq '01:10' } @$labels_before;
ok($before, 'label for global candle 70 is visible before scroll');
is($before->{index}, 0, 'global candle 70 starts at local index 0');

$engine->{offset} = 11;
my $labels_after = $engine->compute_intraday_labels();
my ($after) = grep { $_->{text} eq '01:10' } @$labels_after;
ok($after, 'same global label remains visible after one-bar scroll');
is($after->{index}, 1, 'same label moves one local bar with the grid');

$engine->{offset} = -18;
my $future_labels = $engine->compute_intraday_labels();
my ($future) = grep { $_->{text} eq '01:56' } @$future_labels;
ok($future, 'time axis synthesizes labels into future whitespace');
is($future->{index}, 18, 'future time label reaches the right side of the whitespace window');

done_testing();
