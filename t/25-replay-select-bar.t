use strict;
use warnings;
use Test::More;

use lib '.';
use Market::UI::Callbacks;
use Market::ReplayController;

# =============================================================================
# Task 0030: Replay Select Bar — cableado headless.
#
# Verifica:
#   - Toggle Select Bar activa/desactiva modo y pide re-render.
#   - Inicio/Play arrancan en (vela_seleccionada - 1).
#   - Sin selección, el índice automático (last - visible_bars) se conserva.
# =============================================================================

{
    package MockMarketData;
    sub new {
        my ($class, $n) = @_;
        my @data;
        for my $i (0 .. $n - 1) {
            push @data, [sprintf('2026-04-01T00:%02d:00-05:00', $i % 60),
                         100 + $i, 110 + $i, 95 + $i, 105 + $i, 100];
        }
        return bless { data => \@data }, $class;
    }
    sub size { scalar @{ shift->{data} } }
}

{
    package MockChartSelectBar;
    sub new {
        my ($class, %a) = @_;
        my $md = $a{market_data} || MockMarketData->new(100);
        return bless {
            market_data       => $md,
            replay_controller => Market::ReplayController->new(market_data => $md),
            visible_bars      => $a{visible_bars} || 20,
            _replay_select_mode => 0,
            _selected_bar       => undef,
            _calls            => [],
        }, $class;
    }
    sub request_render {
        my ($s) = @_;
        push @{ $s->{_calls} }, 'request_render';
        return;
    }
    sub set_replay_select_mode {
        my ($s, $on) = @_;
        $s->{_replay_select_mode} = $on ? 1 : 0;
        return $s;
    }
    sub is_replay_select_mode {
        my ($s) = @_;
        return $s->{_replay_select_mode} ? 1 : 0;
    }
    sub set_selected_bar {
        my ($s, $idx) = @_;
        return $s unless defined $idx;
        my $last = $s->{market_data}->size() - 1;
        $idx = 0 if $idx < 0;
        $idx = $last if $idx > $last;
        $s->{_selected_bar} = $idx;
        return $s;
    }
    sub selected_bar {
        my ($s) = @_;
        return $s->{_selected_bar};
    }
    sub replay_start_index {
        my ($s) = @_;
        if (defined $s->{_selected_bar}) {
            my $idx = $s->{_selected_bar} - 1;
            $idx = 0 if $idx < 0;
            my $last = $s->{market_data}->size() - 1;
            $idx = $last if $idx > $last;
            return $idx;
        }
        my $last = $s->{market_data}->size() - 1;
        my $vis = $s->{visible_bars} || 20;
        my $start = $last - $vis;
        return $start < 0 ? 0 : $start;
    }
    sub render_count {
        my ($s) = @_;
        return scalar grep { $_ eq 'request_render' } @{ $s->{_calls} };
    }
}

# Toggle Select Bar activa modo y re-render.
{
    my $chart = MockChartSelectBar->new();
    my $replay_select_mode = 0;
    my %vars = ( replay_select_mode => \$replay_select_mode );
    my $cb = Market::UI::Callbacks->make_replay_select_bar($chart, \%vars);

    ok(!$chart->is_replay_select_mode(), 'Select Bar off al inicio');
    $cb->();
    ok($chart->is_replay_select_mode(), 'primer click activa Select Bar');
    is($replay_select_mode, 1, 'ui_vars sincroniza replay_select_mode=1');
    ok($chart->render_count() >= 1, 'Select Bar dispara re-render');

    $cb->();
    ok(!$chart->is_replay_select_mode(), 'segundo click desactiva Select Bar');
    is($replay_select_mode, 0, 'ui_vars sincroniza replay_select_mode=0');
}

# Inicio sin selección: índice automático last - visible_bars = 79.
{
    my $chart = MockChartSelectBar->new(market_data => MockMarketData->new(100));
    my $replay_on = 0;
    my %vars = ( replay_on => \$replay_on );
    my $rc = $chart->{replay_controller};

    Market::UI::Callbacks->make_replay_start($chart, \%vars)->();
    is($rc->current_index(), 79, 'sin selección: Inicio en last - visible_bars = 79');
}

# Inicio con vela seleccionada: arranca en selected - 1.
{
    my $chart = MockChartSelectBar->new(market_data => MockMarketData->new(100));
    my $replay_on = 0;
    my %vars = ( replay_on => \$replay_on );
    my $rc = $chart->{replay_controller};

    $chart->set_selected_bar(50);
    Market::UI::Callbacks->make_replay_start($chart, \%vars)->();
    is($rc->current_index(), 49, 'con selección 50: Inicio en 49 (selected-1)');
    ok($rc->is_active(), 'Inicio activa replay');
    is($replay_on, 1, 'Inicio marca replay_on=1');
}

# Play auto-start con selección usa selected - 1.
{
    my $chart = MockChartSelectBar->new(market_data => MockMarketData->new(100));
    my $rc = $chart->{replay_controller};
    $chart->set_selected_bar(30);

    Market::UI::Callbacks->make_replay_play($chart, undef, {})->();
    is($rc->current_index(), 29, 'Play auto-start con selección 30 arranca en 29');
}

# selected=0 clampa start a 0 (selected-1 sería -1).
{
    my $chart = MockChartSelectBar->new(market_data => MockMarketData->new(100));
    my $rc = $chart->{replay_controller};
    $chart->set_selected_bar(0);

    Market::UI::Callbacks->make_replay_start($chart, {})->();
    is($rc->current_index(), 0, 'selección en 0: start clampa a 0');
}

done_testing();