use strict;
use warnings;

use lib '.';
use Test::More;

use Market::ChartEngine;

{
    package TestMarketData;
    sub new { bless { size => $_[1] }, $_[0] }
    sub size { $_[0]->{size} }
}

{
    package TestCanvas;
    sub new {
        my ($class, %args) = @_;
        return bless { w => $args{w} || 800, h => $args{h} || 400, pointerx => $args{pointerx} }, $class;
    }
    sub geometry { return $_[0]->{w} . 'x' . $_[0]->{h} }
    sub Width { $_[0]->{w} }
    sub width { $_[0]->{w} }
    sub Height { $_[0]->{h} }
    sub height { $_[0]->{h} }
    sub pointerx { $_[0]->{pointerx} }
}

no warnings 'redefine';
local *Market::ChartEngine::request_render = sub { $_[0]->{render_requested}++ };
local *Market::ChartEngine::_on_mouse_move = sub { };

sub engine_with {
    my (%args) = @_;
    my $canvas = TestCanvas->new(w => $args{width} || 800, h => 400);
    return bless {
        market_data       => TestMarketData->new($args{total} || 100),
        price_canvas      => $canvas,
        atr_canvas        => $canvas,
        visible_bars      => $args{visible_bars} || 20,
        offset            => $args{offset} || 0,
        drag_start_x      => undef,
        drag_start_y      => undef,
        drag_start_offset => 0,
        render_requested  => 0,
    }, 'Market::ChartEngine';
}

my $e = engine_with(total => 100, visible_bars => 20, offset => 10, width => 800);
my ($start, $end) = $e->compute_window();
is_deeply([$start, $end], [70, 89], 'compute_window keeps the requested 20-bar window at offset 10');

$e->{drag_start_x} = 100;
$e->{drag_start_offset} = 10;
my $widget = TestCanvas->new(w => 800, h => 400, pointerx => 180);
$e->_on_horizontal_drag($widget, 180, 0);
is($e->{offset}, 12, 'dragging right increases offset by integer bars');
is($e->{visible_bars}, 20, 'dragging does not change visible_bars');

$e->{offset} = 10;
$e->{drag_start_x} = 100;
$e->{drag_start_offset} = 10;
$widget->{pointerx} = 20;
$e->_on_horizontal_drag($widget, 20, 0);
is($e->{offset}, 8, 'dragging left decreases offset by integer bars');
is($e->{visible_bars}, 20, 'visible_bars remains constant after opposite drag');

$e->_end_drag();
$e->{offset} = 8;
$widget->{pointerx} = 300;
$e->_on_horizontal_drag($widget, 300, 0);
is($e->{offset}, 8, 'drag release stops offset updates until a new drag begins');

my $z = engine_with(total => 100, visible_bars => 20, offset => 0, width => 800);
$z->_horizontal_zoom(-500, undef);
is($z->{visible_bars}, 2, 'zoom-in clamps to MIN_VISIBLE_BARS');

$z->_horizontal_zoom(500, undef);
is($z->{visible_bars}, 100, 'zoom-out clamps to available history when below MAX_VISIBLE_BARS');
is($z->{offset}, 0, 'zoom-out at latest edge keeps offset clamped');

my $small = engine_with(total => 1, visible_bars => 60, offset => 0, width => 800);
($start, $end) = $small->compute_window();
is_deeply([$start, $end], [0, 0], 'single-candle data remains renderable');

my $wheel = engine_with(total => 100, visible_bars => 20, offset => 10, width => 800);
$wheel->{last_mouse_x} = 10;
$wheel->_wheel_zoom(TestCanvas->new(w => 800, h => 400), 5, 500, 100, 0);
is($wheel->{last_mouse_x}, 500, 'wheel zoom records event x instead of stale mouse x');
is($wheel->{active_canvas}->Width(), 800, 'wheel zoom records active event canvas');
is($wheel->{visible_bars}, 25, 'wheel zoom still updates horizontal zoom');
is($wheel->{offset}, 10, 'plain wheel zoom anchors the last visible candle');

my $ctrl_wheel = engine_with(total => 100, visible_bars => 20, offset => 10, width => 800);
$ctrl_wheel->_wheel_zoom(TestCanvas->new(w => 800, h => 400), 5, 100, 100, 4);
is($ctrl_wheel->{visible_bars}, 25, 'ctrl wheel zoom updates horizontal zoom');
is($ctrl_wheel->{offset}, 6, 'ctrl wheel zoom anchors the candle under the cursor');

done_testing();
