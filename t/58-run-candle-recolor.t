use strict;
use warnings;
use Test::More;

use lib '.';
use Market::ChartEngine;
use Market::Indicators::Liquidity;
use Market::ReplayController;
use Market::Overlays::Liquidity;
use Market::Panels::PricePanel;
use Market::Panels::Scales;

# Task 0058: puente ChartEngine → PricePanel para recoloreo de velas RUN.

{
    package MockLiqIndicator;
    sub new { my ($class, $events) = @_; bless { events => $events || [] }, $class }
    sub get_events { shift->{events} }
}

sub bless_chart {
    my (%args) = @_;
    my $liq_ind = MockLiqIndicator->new($args{events});
    my $liq_ov  = Market::Overlays::Liquidity->new(
        indicator => Market::Indicators::Liquidity->new(k => 3),
    );
    $liq_ov->set_visible($args{liq_visible} // 1);
    $liq_ov->set_element_visible('RUN', $args{run_visible} // 1);
    $liq_ov->set_density_pct($args{density_pct}) if defined $args{density_pct};
    return bless {
        liq_indicator     => $liq_ind,
        liq_overlay       => $liq_ov,
        replay_controller => $args{replay},
    }, 'Market::ChartEngine';
}

sub map_keys {
    my ($map) = @_;
    return sort { $a <=> $b } keys %$map;
}

{
    my @events = (
        { type => 'RUN', index => 3, dir => 'up', relevant => 1 },
        { type => 'RUN', index => 7, dir => 'down', relevant => 0 },
        { type => 'GRAB', index => 5 },
        { type => 'RUN', index => 9, dir => 'up' },
    );
    my $chart = bless_chart(events => \@events);
    my $map = $chart->compute_run_candle_map();
    is_deeply([ map_keys($map) ], [ 3, 9 ], 'RUN map: relevantes o sin campo relevant');
    is($map->{3}, 'up', 'RUN map conserva dir');
    is($map->{9}, 'up', 'RUN sin relevant se incluye');
}

{
    my $chart = bless_chart(
        events => [ { type => 'RUN', index => 4, dir => 'down', relevant => 1 } ],
        run_visible => 0,
    );
    my $map = $chart->compute_run_candle_map();
    is(scalar(keys %$map), 0, 'RUN toggle OFF: mapa vacío');
}

{
    my $chart = bless_chart(
        events => [ { type => 'RUN', index => 4, dir => 'down', relevant => 1 } ],
        liq_visible => 0,
    );
    my $map = $chart->compute_run_candle_map();
    is(scalar(keys %$map), 0, 'Liquidez OFF: no recolorea RUN');
}

{
    my $chart = bless_chart(
        events => [
            { type => 'GRAB', index => 2, magnitude => 100, relevant => 1 },
            { type => 'RUN',  index => 4, magnitude => 1,   relevant => 1 },
        ],
        density_pct => 50,
    );
    my $map = $chart->compute_run_candle_map();
    is(scalar(keys %$map), 0, 'Densidad Liq 50%: RUN no se recolorea si quedó filtrado del render');
}

{
    package TestMarketDataReplay;
    sub new { bless { n => 20 }, shift }
    sub size { shift->{n} }
}

{
    my $md = TestMarketDataReplay->new();
    my $replay = Market::ReplayController->new(market_data => $md);
    $replay->start(5);
    my $chart = bless_chart(
        events => [
            { type => 'RUN', index => 4, relevant => 1 },
            { type => 'RUN', index => 6, relevant => 1 },
        ],
        replay => $replay,
    );
    my $map = $chart->compute_run_candle_map();
    is_deeply([ map_keys($map) ], [ 4 ], 'Replay activo: excluye RUN con index > replay_idx');
}

{
    my $chart = bless_chart(
        events => [ { type => 'RUN', index => 9, marker_index => 6, dir => 'up', relevant => 1 } ],
    );
    my $map = $chart->compute_run_candle_map();
    is_deeply([ map_keys($map) ], [ 6 ], 'RUN map: recolorea marker_index de trayecto, no confirm_index');
}

{
    my $md = TestMarketDataReplay->new();
    my $replay = Market::ReplayController->new(market_data => $md);
    $replay->start(7);
    my $chart = bless_chart(
        events => [ { type => 'RUN', index => 9, confirm_index => 9, marker_index => 6, relevant => 1 } ],
        replay => $replay,
    );
    my $map = $chart->compute_run_candle_map();
    is(scalar(keys %$map), 0, 'Replay activo: marker_index pasado no se muestra antes de confirm_index');
}

{
    package TestCanvas58;
    sub new { bless { w => 120, h => 200, ops => [] }, shift }
    sub geometry { my ($s) = @_; return $s->{w} . 'x' . $s->{h} }
    sub Width  { shift->{w} }
    sub Height { shift->{h} }
    sub delete { return }
    sub lower  { return }
    sub raise  { return }
    sub createLine {
        my ($self, @args) = @_;
        push @{ $self->{ops} }, [ createLine => @args ];
        return scalar @{ $self->{ops} };
    }
    sub createRectangle {
        my ($self, @args) = @_;
        push @{ $self->{ops} }, [ createRectangle => @args ];
        return scalar @{ $self->{ops} };
    }
    sub createText { return 1 }
}

sub op_fill {
    my ($op) = @_;
    my @a = @$op;
    for my $i (0 .. $#a - 1) {
        return $a[$i + 1] if defined $a[$i] && $a[$i] eq '-fill';
    }
    return undef;
}

{
    my @data = map { [ "t$_", 10, 12, 8, 11, 1 ] } 0 .. 9;
    $data[2] = [ 't2', 10, 12, 8, 9, 1 ];

    my $panel = Market::Panels::PricePanel->new(theme => {
        bull => '#aaaaaa',
        bear => '#bbbbbb',
        run_bull => '#7b1fa2',
        run_bear => '#ff6d00',
        run_wick => '#4a148c',
    });
    $panel->set_run_candles({ 2 => 'up' });

    my $scale = Market::Panels::Scales->new(min_y => 0, max_y => 20, bars => 10, right_margin => 0);
    $scale->{width}  = 120;
    $scale->{height} = 200;
    $scale->{slice_base_index} = 0;

    my $canvas = TestCanvas58->new();
    $panel->render($canvas, \@data, $scale);

    my @fills = map { op_fill($_) } grep { $_->[0] eq 'createRectangle' } @{ $canvas->{ops} };
    ok((grep { $_ eq '#7b1fa2' } @fills), 'PricePanel: vela RUN bull usa run_bull');
    ok((grep { $_ eq '#aaaaaa' } @fills), 'PricePanel: velas normales sin cambio');
}

{
    my @data = map { [ "t$_", 10, 12, 8, 11, 1 ] } 0 .. 79;
    $data[15] = [ 't15', 10, 12, 8, 9, 1 ];

    my $panel = Market::Panels::PricePanel->new(theme => {
        run_bull => '#7b1fa2',
        run_wick => '#4a148c',
    });
    $panel->set_run_candles({ 15 => 'up' });

    my $scale = Market::Panels::Scales->new(min_y => 0, max_y => 20, bars => 80, right_margin => 0);
    $scale->{width}  = 80;
    $scale->{height} = 200;
    $scale->{slice_base_index} = 0;

    my $canvas = TestCanvas58->new();
    $panel->render($canvas, \@data, $scale);

    my @line_fills = map { op_fill($_) } grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    ok((grep { $_ eq '#4a148c' } @line_fills), 'Downsample bar_w<2: bucket con RUN usa run_wick');
}

done_testing();