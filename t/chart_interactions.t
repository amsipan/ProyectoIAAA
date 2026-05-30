use strict;
use warnings;

use lib '.';
use Test::More;

use Market::ChartEngine;
use Market::Panels::Scales;

{
    package TestMarketData;
    sub new { bless { size => $_[1] }, $_[0] }
    sub size { $_[0]->{size} }
}

{
    package TestCanvas;
    sub new {
        my ($class, %args) = @_;
        return bless { w => $args{w} || 800, h => $args{h} || 400, pointerx => $args{pointerx}, pointery => $args{pointery} }, $class;
    }
    sub geometry { return $_[0]->{w} . 'x' . $_[0]->{h} }
    sub Width { $_[0]->{w} }
    sub width { $_[0]->{w} }
    sub Height { $_[0]->{h} }
    sub height { $_[0]->{h} }
    sub pointerx { $_[0]->{pointerx} }
    sub pointery { $_[0]->{pointery} }
}

no warnings 'redefine';
local *Market::ChartEngine::request_render = sub { $_[0]->{render_requested}++ };
local *Market::ChartEngine::_on_mouse_move = sub { };
local *Market::ChartEngine::_draw_crosshair_all = sub { };

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

my $future = engine_with(total => 100, visible_bars => 20, offset => -999, width => 800);
($start, $end) = $future->compute_window();
is($future->{offset}, -18, 'future blank space clamps when only two real candles remain');
is_deeply([$start, $end], [98, 117], 'future blank window keeps two real candles at the left edge');

my $past = engine_with(total => 100, visible_bars => 20, offset => 999, width => 800);
($start, $end) = $past->compute_window();
is($past->{offset}, 98, 'past blank space clamps when only two real candles remain');
is_deeply([$start, $end], [-18, 1], 'past blank window keeps two real candles at the right edge');

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

my $past_zoom = engine_with(total => 100, visible_bars => 20, offset => 98, width => 800);
$past_zoom->_horizontal_zoom(5, undef);
is($past_zoom->{visible_bars}, 25, 'plain wheel zoom can zoom out at the past blank edge');
is($past_zoom->{offset}, 98, 'plain wheel zoom keeps first real candles anchored at the past blank edge');

my $vpan = engine_with(total => 100, visible_bars => 20, offset => 10, width => 800);
$vpan->{price_panel} = { scale => Market::Panels::Scales->new(min_y => 100, max_y => 200, bars => 20) };
my $drag_widget = TestCanvas->new(w => 800, h => 400, pointerx => 100, pointery => 100);
$vpan->_start_horizontal_drag($drag_widget, 100, 100);
$drag_widget->{pointery} = 500;
$vpan->_on_horizontal_drag($drag_widget, 100, 500);
is($vpan->{is_auto_scale}, 0, 'vertical mouse drag switches price scale to manual');
is($vpan->{manual_min_y}, 200, 'vertical mouse drag can move range downward by a full range');
is($vpan->{manual_max_y}, 300, 'vertical mouse drag preserves range width downward');

$drag_widget->{pointery} = -700;
$vpan->_on_horizontal_drag($drag_widget, 100, -700);
is($vpan->{manual_min_y}, -100, 'vertical mouse drag has no apparent lower clamp');
is($vpan->{manual_max_y}, 0, 'vertical mouse drag preserves range width upward');

my $axis_zoom = engine_with(total => 100, visible_bars => 20, offset => 10, width => 800);
$axis_zoom->{price_panel} = { scale => Market::Panels::Scales->new(min_y => 100, max_y => 200, bars => 20) };
my $axis_widget = TestCanvas->new(w => 78, h => 400, pointery => 100);
$axis_zoom->_start_price_axis_drag($axis_widget, 100);
$axis_widget->{pointery} = 320;
$axis_zoom->_on_price_axis_drag($axis_widget, 320);
is($axis_zoom->{is_auto_scale}, 0, 'price-axis drag switches to manual scale');
is(sprintf('%.6f', ($axis_zoom->{manual_min_y} + $axis_zoom->{manual_max_y}) / 2), '150.000000', 'price-axis drag keeps vertical center fixed');
ok(($axis_zoom->{manual_max_y} - $axis_zoom->{manual_min_y}) > 100, 'dragging price axis downward expands vertical range');
is($axis_zoom->{offset}, 10, 'price-axis drag does not move horizontally');

my $time_zoom = engine_with(total => 100, visible_bars => 20, offset => 10, width => 800);
my $time_widget = TestCanvas->new(w => 800, h => 24, pointerx => 100);
$time_zoom->_start_time_axis_drag($time_widget, 100, 10);
$time_widget->{pointerx} = 140;
$time_zoom->_on_time_axis_drag($time_widget, 140, 10);
is($time_zoom->{visible_bars}, 25, 'dragging time axis right zooms out horizontally with reduced sensitivity');
is($time_zoom->{offset}, 10, 'time-axis zoom keeps the right edge anchored like mouse wheel');

$time_widget->{pointerx} = 60;
$time_zoom->_on_time_axis_drag($time_widget, 60, 10);
is($time_zoom->{visible_bars}, 15, 'dragging time axis left zooms in horizontally with reduced sensitivity');

$time_zoom->_end_time_axis_drag();
$time_widget->{pointerx} = 180;
$time_zoom->_on_time_axis_drag($time_widget, 180, 10);
is($time_zoom->{visible_bars}, 15, 'time-axis release stops horizontal zoom updates');

done_testing();
