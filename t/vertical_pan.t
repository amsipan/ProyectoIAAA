use strict;
use warnings;

use lib '.';
use Test::More;

use Market::ChartEngine;
use Market::Panels::Scales;

# Feature: tradingview-parity, Property 16: desplazamiento vertical manual conserva el ancho de rango

no warnings 'redefine';
local *Market::ChartEngine::request_render = sub { $_[0]->{render_requested}++ };

for my $case (
    [100, 200, 100, -25],
    [1,   9,   400, 80],
    [-50, 50,  250, 13],
    [10,  11,  500, -120],
) {
    my ($min, $max, $height, $dy) = @$case;
    my $scale = Market::Panels::Scales->new(min_y => $min, max_y => $max, bars => 10);
    $scale->{height} = $height;

    my $engine = bless {
        is_auto_scale    => 0,
        manual_min_y     => $min,
        manual_max_y     => $max,
        price_panel      => { scale => $scale },
        render_requested => 0,
    }, 'Market::ChartEngine';

    my $width_before  = $engine->{manual_max_y} - $engine->{manual_min_y};
    my $center_before = ($engine->{manual_min_y} + $engine->{manual_max_y}) / 2;
    my $units_per_px  = $scale->y_to_value(0) - $scale->y_to_value(1);

    $engine->_vertical_drag($dy);

    my $width_after  = $engine->{manual_max_y} - $engine->{manual_min_y};
    my $center_after = ($engine->{manual_min_y} + $engine->{manual_max_y}) / 2;

    is(sprintf('%.10f', $width_after), sprintf('%.10f', $width_before), 'vertical drag preserves range width');
    is(sprintf('%.10f', $center_after), sprintf('%.10f', $center_before + $dy * $units_per_px), 'vertical drag shifts center by dy units');
    is($engine->{render_requested}, 1, 'vertical drag requests render');
}

done_testing();
