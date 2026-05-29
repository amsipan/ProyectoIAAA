use strict;
use warnings;

use lib '.';
use Test::More;

use Market::ChartEngine;

# Feature: tradingview-parity, Property 17: zoom vertical manual escala respecto al centro

no warnings 'redefine';
local *Market::ChartEngine::request_render = sub { $_[0]->{render_requested}++ };

for my $case (
    [100, 200, 0.5],
    [1,   9,   2.0],
    [-50, 50,  1.25],
    [10,  11,  0.1],
) {
    my ($min, $max, $factor) = @$case;
    my $engine = bless {
        is_auto_scale    => 0,
        manual_min_y     => $min,
        manual_max_y     => $max,
        render_requested => 0,
    }, 'Market::ChartEngine';

    my $center_before = ($min + $max) / 2;
    my $half_before   = ($max - $min) / 2;

    $engine->_vertical_zoom($factor);

    my $center_after = ($engine->{manual_min_y} + $engine->{manual_max_y}) / 2;
    my $half_after   = ($engine->{manual_max_y} - $engine->{manual_min_y}) / 2;

    is(sprintf('%.10f', $center_after), sprintf('%.10f', $center_before), 'vertical zoom keeps center invariant');
    is(sprintf('%.10f', $half_after), sprintf('%.10f', $half_before * $factor), 'vertical zoom scales half-range by factor');
    is($engine->{render_requested}, 1, 'vertical zoom requests render');
}

done_testing();
