use strict;
use warnings;

use lib '.';
use Test::More;

use Market::ChartEngine;

# Feature: tradingview-parity, Property 19: el resize preserva los indices en vista

{
    package TestMarketData;
    sub new { bless { size => $_[1] }, $_[0] }
    sub size { $_[0]->{size} }
}

{
    package TestCanvas;
    sub new { bless {}, $_[0] }
    sub after { my ($self, $delay, $callback) = @_; $callback->(); return 1 }
}

no warnings 'redefine';
local *Market::ChartEngine::request_render = sub { $_[0]->{render_requested}++ };

for my $case (
    [100, 20, 0],
    [100, 20, 10],
    [7,   60, 0],
    [500, 300, 120],
) {
    my ($total, $visible, $offset) = @$case;
    my $canvas = TestCanvas->new();
    my $engine = bless {
        market_data      => TestMarketData->new($total),
        price_canvas     => $canvas,
        visible_bars     => $visible,
        offset           => $offset,
        render_requested => 0,
    }, 'Market::ChartEngine';

    my @before = $engine->compute_window();
    $engine->_on_resize($canvas);
    my @after = $engine->compute_window();

    is_deeply(\@after, \@before, 'resize preserves visible window indices');
    is($engine->{render_requested}, 1, 'resize requests render');
}

done_testing();
