use strict;
use warnings;

use lib '.';
use Test::More;

use Market::Panels::Scales;

# Feature: tradingview-parity, Property 2: round-trip de coordenadas X.
for my $bars (2, 3, 5, 10, 60, 300) {
    for my $width (200, 768, 1024, 1920) {
        my $scale = Market::Panels::Scales->new(
            bars         => $bars,
            right_margin => 0,
        );
        $scale->{width} = $width;

        for my $i (0 .. $bars - 1) {
            is($scale->x_to_index($scale->index_to_x($i)), $i, "left edge round-trip bars=$bars width=$width i=$i");
            is($scale->x_to_index($scale->index_to_center_x($i)), $i, "center round-trip bars=$bars width=$width i=$i");
            ok($scale->index_to_center_x($i) <= $width, "center stays inside plot area bars=$bars width=$width i=$i");
        }
    }
}

done_testing();
