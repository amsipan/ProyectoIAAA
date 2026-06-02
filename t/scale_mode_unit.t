use strict;
use warnings;

use lib '.';
use Test::More;

use Market::ChartEngine;

no warnings 'redefine';
local *Market::ChartEngine::request_render = sub { $_[0]->{render_requested}++ };

my $callback_mode;
my $engine = bless {
    is_auto_scale    => 1,
    manual_min_y     => 10,
    manual_max_y     => 20,
    scale_mode_callback => sub { $callback_mode = $_[0] },
    render_requested => 0,
}, 'Market::ChartEngine';

$engine->set_scale_mode('manual');
is($engine->{is_auto_scale}, 0, 'manual mode disables auto scale');
is($engine->{manual_min_y}, 10, 'manual mode retains current min');
is($engine->{manual_max_y}, 20, 'manual mode retains current max');
is($callback_mode, 'manual', 'manual mode notifies UI callback');
is($engine->{render_requested}, 1, 'manual mode requests render');

$engine->{render_requested} = 0;
$callback_mode = undef;
$engine->set_scale_mode('auto');
is($engine->{is_auto_scale}, 1, 'auto mode enables auto scale');
is($engine->{manual_min_y}, undef, 'auto mode clears manual min');
is($engine->{manual_max_y}, undef, 'auto mode clears manual max');
is($callback_mode, 'auto', 'auto mode notifies UI callback');
is($engine->{render_requested}, 1, 'auto mode requests render');

$engine->{render_requested} = 0;
$callback_mode = undef;
$engine->set_scale_mode('bad');
is($callback_mode, undef, 'invalid scale mode does not notify UI callback');
is($engine->{render_requested}, 0, 'invalid scale mode is ignored');

open my $fh, '<', 'market.pl' or die "Cannot open market.pl: $!";
my $market = do { local $/; <$fh> };
close $fh;

like($market, qr/Radiobutton\s*\(/, 'market.pl defines scale mode radiobuttons');
like($market, qr/-value\s*=>\s*'auto'/, 'auto radiobutton is wired');
like($market, qr/-value\s*=>\s*'manual'/, 'manual radiobutton is wired');
like($market, qr/set_scale_mode\('auto'\)/, 'auto control calls set_scale_mode');
like($market, qr/set_scale_mode\('manual'\)/, 'manual control calls set_scale_mode');
like($market, qr/scale_mode_callback\s*=>\s*sub/, 'chart engine updates scale mode UI callback');

done_testing();
