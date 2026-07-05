use strict;
use warnings;
use Test::More;

use lib '.';
use Market::ChartEngine;
use Market::Panels::Scales;
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
    package R40MarketData;
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
    sub get_candle { my ($s, $i) = @_; return $s->{data}->[$i] }
    sub get_slice {
        my ($self, $s, $e) = @_;
        my @out;
        for my $i ($s .. $e) {
            push @out, ($i >= 0 && $i < $self->size) ? $self->{data}->[$i] : undef;
        }
        return \@out;
    }
}

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
        $s->clear_replay_select_mode();
        return $s;
    }
    sub clear_replay_select_mode {
        my ($s) = @_;
        $s->{_replay_select_mode} = 0;
        return $s;
    }
    sub clear_replay_select_state {
        my ($s) = @_;
        $s->{_selected_bar} = undef;
        $s->clear_replay_select_mode();
        return $s;
    }
    sub frame_replay_view_at {
        my ($s, $idx) = @_;
        $s->{offset} = 0;
        $s->{ctrl_zoom_x_shift} = 0;
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

# task 0040-C: seleccionar vela desactiva modo Select Bar (conserva selección).
{
    my $chart = MockChartSelectBar->new();
    my $replay_select_mode = 1;
    my %vars = ( replay_select_mode => \$replay_select_mode );
    $chart->set_replay_select_mode(1);

    $chart->set_selected_bar(42);

    ok(!$chart->is_replay_select_mode(), 'tras selección: modo Select Bar OFF');
    is($chart->selected_bar(), 42, 'tras selección: vela conservada');
}

# task 0040-A: Salir limpia selección y modo; próximo Inicio no usa vela vieja.
{
    my $chart = MockChartSelectBar->new(market_data => MockMarketData->new(100));
    my $replay_on = 1;
    my $replay_select_mode = 1;
    my %vars = ( replay_on => \$replay_on, replay_select_mode => \$replay_select_mode );
    my $rc = $chart->{replay_controller};

    $chart->set_selected_bar(50);
    $rc->start(49);
    Market::UI::Callbacks->make_replay_exit($chart, \%vars)->();

    ok(!defined $chart->selected_bar(), 'Salir: selected_bar limpiado');
    ok(!$chart->is_replay_select_mode(), 'Salir: select mode limpiado');
    is($replay_on, 0, 'Salir: replay_on=0');
    is($replay_select_mode, 0, 'Salir: replay_select_mode=0');
    ok(!$rc->is_active(), 'Salir: replay inactivo');

    Market::UI::Callbacks->make_replay_start($chart, \%vars)->();
    is($rc->current_index(), 79, 'tras Salir: Inicio usa auto (79), no selected-1');
}

# task 0040-B: Inicio con offset heredado encuadra vista (ChartEngine real).
{
    my $md = R40MarketData->new(100);
    my $chart = bless {
        market_data       => $md,
        replay_controller => Market::ReplayController->new(market_data => $md),
        visible_bars      => 20,
        offset            => 80,
        ctrl_zoom_x_shift => 0,
    }, 'Market::ChartEngine';

    $chart->frame_replay_view_at(79);
    $chart->{replay_controller}->start(79);

    is($chart->{offset}, 0, 'frame_replay_view_at: offset reseteado');
    my ($s, $e) = $chart->compute_window();
    ok($s <= $e, 'frame+start: ventana válida con offset previo grande');
    ok($e >= 0, 'frame+start: end no negativo');
    is($e, 79, 'frame+start: end alineado con replay_idx');
}

# UX TradingView: Select Bar ancla ultima vela ~80% (hueco derecho para Play).
{
    my $md = R40MarketData->new(100);
    my $chart = bless {
        market_data       => $md,
        replay_controller => Market::ReplayController->new(market_data => $md),
        visible_bars      => 60,
        offset            => 0,
        ctrl_zoom_x_shift => 0,
    }, 'Market::ChartEngine';

    $chart->frame_replay_view_at(49);
    ok(!exists $chart->{replay_view_anchor}, 'sin anchor: flag ausente');

    $chart->frame_replay_view_at(49, { anchor => 1 });
    is($chart->{replay_view_anchor}, 0.80, 'anchor: replay_view_anchor=0.80');
    $chart->{replay_controller}->start(49);

    my ($s, $e) = $chart->compute_window();
    my $x_bars = $e - $s + 1;
    my $shift  = $chart->_replay_anchor_x_shift($x_bars, 1000);
    ok($shift < 0, 'anchor: x_shift negativo deja hueco a la derecha');

    my $scale = Market::Panels::Scales->new(min_y => 0, max_y => 1, bars => $x_bars);
    $scale->{width} = 1000;
    $scale->{x_shift} = $shift;
    my $cx = $scale->index_to_center_x($x_bars - 1);
    ok(abs($cx - 800) < 2, "anchor: centro ultima vela ~80% plot (cx=$cx)");
}

# =============================================================================
# task 0042: modo selección visual — geometría línea/velo/Re: y ops por tag.
# =============================================================================

{
    package R42MarketData;
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
    sub get_timestamp { my ($s, $i) = @_; return $s->{data}->[$i][0] }
}

{
    package R42RecCanvas;
    sub new { my ($c, $w, $h) = @_; bless { w => $w // 900, h => $h // 500, ops => [] }, $c }
    sub geometry { my ($s) = @_; return "$s->{w}x$s->{h}" }
    sub Width  { shift->{w} }
    sub Height { shift->{h} }
    sub delete {
        my ($s, $tag) = @_;
        push @{ $s->{ops} }, [ delete => $tag ];
    }
    sub createLine {
        my ($s, @a) = @_;
        push @{ $s->{ops} }, [ createLine => @a ];
        return scalar @{ $s->{ops} };
    }
    sub createRectangle {
        my ($s, @a) = @_;
        push @{ $s->{ops} }, [ createRectangle => @a ];
        return scalar @{ $s->{ops} };
    }
    sub createText {
        my ($s, @a) = @_;
        push @{ $s->{ops} }, [ createText => @a ];
        return scalar @{ $s->{ops} };
    }
    sub after { return }
    sub configure { return }
}

sub r42_op_tag {
    my ($op) = @_;
    my @a = @$op;
    for (my $i = 1; $i < @a; $i += 2) {
        return $a[$i + 1] if $i + 1 < @a && $a[$i] eq '-tags';
    }
    return undef;
}

sub r42_op_opt {
    my ($op, $key) = @_;
    my @a = @$op;
    for (my $i = 1; $i < @a; $i += 2) {
        return $a[$i + 1] if $i + 1 < @a && $a[$i] eq $key;
    }
    return undef;
}

sub r42_build_chart {
    my %a = @_;
    my $md = $a{market_data} || R42MarketData->new(100);
    my $price = R42RecCanvas->new(900, 500);
    my $atr   = R42RecCanvas->new(900, 200);
    my $time  = R42RecCanvas->new(900, 30);
    return bless {
        market_data        => $md,
        price_canvas       => $price,
        atr_canvas         => $atr,
        time_axis_canvas   => $time,
        visible_bars       => $a{visible_bars} // 20,
        offset             => 0,
        ctrl_zoom_x_shift  => 0,
        _replay_select_mode => 0,
        _selected_bar      => undef,
    }, 'Market::ChartEngine';
}

{
    my $chart = r42_build_chart();
    $chart->set_replay_select_mode(1);

    my ($start, $end) = $chart->compute_window();
    is($start, 80, '0042: ventana visible empieza en 80');
    is($end, 99, '0042: ventana visible termina en 99');

    use Market::Panels::Scales;
    my $scale = Market::Panels::Scales->new(bars => 20, right_margin => 0);
    $scale->{width} = 900;
    my $local = 5;
    my $raw_x = $scale->index_to_center_x($local);
    my $layout = $chart->_replay_select_hover_layout($raw_x);

    ok($layout, '0042: layout definido en select mode');
    is($layout->{global_index}, 80 + $local, '0042: índice global bajo cursor');
    is($layout->{line_x}, $chart->round($raw_x), '0042: línea X = centro de vela');
    is($layout->{veil_x0}, $layout->{line_x}, '0042: velo empieza en la línea');
    is($layout->{veil_x1}, 900, '0042: velo llega al borde derecho');

    $chart->{last_mouse_x} = $layout->{line_x};
    my $crosshair_time = $chart->_crosshair_time_label();
    like($layout->{re_text}, qr/^Re: \Q$crosshair_time\E$/, '0042: Re: usa _crosshair_time_label');
}

{
    my $chart = r42_build_chart();
    $chart->set_replay_select_mode(1);

    use Market::Panels::Scales;
    my $scale = Market::Panels::Scales->new(bars => 20, right_margin => 0);
    $scale->{width} = 900;
    my $raw_x = $scale->index_to_center_x(3);

    $chart->_draw_replay_select_hover(undef, $chart->round($raw_x), 250);

    my $price = $chart->{price_canvas};
    my @line_ops = grep { $_->[0] eq 'createLine' && r42_op_tag($_) eq 'replay_select_hover' } @{ $price->{ops} };
    ok(@line_ops >= 1, '0042: dibuja línea azul (replay_select_hover)');
    is($line_ops[0][1], $chart->round($raw_x), '0042: línea X coincide con cursor');

    my @veil_ops = grep { $_->[0] eq 'createRectangle' && r42_op_tag($_) eq 'replay_select_veil' } @{ $price->{ops} };
    ok(@veil_ops >= 1, '0042: dibuja velo (replay_select_veil)');
    is($veil_ops[0][1], $chart->round($raw_x), '0042: velo x0 en la línea');
    is($veil_ops[0][3], 900, '0042: velo x1 al borde derecho');

    my @sci_ops = grep { $_->[0] eq 'createText' && r42_op_tag($_) eq 'replay_select_scissors' } @{ $price->{ops} };
    ok(@sci_ops >= 1, '0042: dibuja símbolo tijeras en canvas');
    is(r42_op_opt($sci_ops[0], '-font'), 'Helvetica 18', 'UX: tijeras un poco mas grandes (18pt)');

    my $time = $chart->{time_axis_canvas};
    my @re_ops = grep { $_->[0] eq 'createText' && r42_op_tag($_) eq 'replay_select_re_label' } @{ $time->{ops} };
    ok(@re_ops >= 1, '0042: dibuja etiqueta Re: en eje temporal');
    like(r42_op_opt($re_ops[0], '-text'), qr/^Re: /, '0042: texto empieza con Re:');
}

{
    my $chart = r42_build_chart();
    $chart->set_replay_select_mode(1);

    use Market::Panels::Scales;
    my $scale = Market::Panels::Scales->new(bars => 20, right_margin => 0);
    $scale->{width} = 900;
    my $raw_x = $scale->index_to_center_x(7);
    $chart->_draw_replay_select_hover(undef, $chart->round($raw_x), 200);
    ok(@{ $chart->{price_canvas}{ops} } >= 1, '0042: hover genera ops');

    $chart->clear_replay_select_mode();
    my @del = grep { $_->[0] eq 'delete' } @{ $chart->{price_canvas}{ops} };
    ok((grep { $_ eq 'replay_select_hover' || $_ eq 'replay_select_veil' || $_ eq 'replay_select_scissors' } map { $_->[1] } @del),
       '0042: salir de select mode borra tags hover');
}

{
    my $chart = r42_build_chart();
    $chart->set_replay_select_mode(1);

    use Market::Panels::Scales;
    my $scale = Market::Panels::Scales->new(bars => 20, right_margin => 0);
    $scale->{width} = 900;
    my $raw_x = $scale->index_to_center_x(10);
    $chart->_draw_replay_select_hover(undef, $chart->round($raw_x), 300);

    $chart->set_selected_bar(90);
    ok(!$chart->is_replay_select_mode(), '0042: click fija selección y apaga modo');
    is($chart->selected_bar(), 90, '0042: vela seleccionada conservada');
    my @del = grep { $_->[0] eq 'delete' } @{ $chart->{price_canvas}{ops} };
    ok((grep { $_ eq 'replay_select_veil' } map { $_->[1] } @del),
       '0042: selección borra velo/línea hover');
}

# =============================================================================
# UX (pedido usuario): activar Replay muestra linea azul al instante; click trunca.
# =============================================================================

{
    my $chart = r42_build_chart(visible_bars => 60);
    $chart->{replay_controller} = Market::ReplayController->new(
        market_data => $chart->{market_data},
    );
    my $replay_on = 0;
    my $replay_select_mode = 0;
    my %vars = (
        replay_on          => \$replay_on,
        replay_select_mode => \$replay_select_mode,
    );
    $chart->{replay_bar_selected_callback} = sub {
        Market::UI::Callbacks->replay_confirm_bar_selection($chart, \%vars);
    };

    $chart->set_replay_select_mode(1);
    ok(defined $chart->{last_mouse_x}, 'UX: activar select mode siembra linea azul (last_mouse_x)');
    ok(defined $chart->{last_mouse_y}, 'UX: activar select mode siembra Y del cursor');

    use Market::Panels::Scales;
    my ($start, $end) = $chart->compute_window();
    my $target = 50;
    my $local  = $target - $start;
    my $scale  = Market::Panels::Scales->new(bars => $end - $start + 1, right_margin => 0);
    $scale->{width} = 900;
    my $raw_x = $scale->index_to_center_x($local);

    $chart->set_replay_select_mode(1);
    $chart->_start_horizontal_drag($chart->{price_canvas}, $raw_x, 250);

    my $rc = $chart->{replay_controller};
    ok($rc->is_active(), 'UX: click en vela arranca replay sin esperar Play');
    is($rc->current_index(), 49, 'UX: trunca en selected-1 (vela 50 -> replay_idx 49)');
    is($chart->selected_bar(), 50, 'UX: conserva vela seleccionada');
    is($replay_on, 1, 'UX: click marca replay_on=1');
    ok(!$chart->is_replay_select_mode(), 'UX: click apaga modo tijeras');

    my ($s, $e) = $chart->compute_window();
    is($e, 49, 'UX: ultima vela visible es la anterior a la seleccionada');
    ok($s <= $e, 'UX: ventana valida tras truncar');
}

# =============================================================================
# task 0044: Go-to — index_for_timestamp, random, first, bar, date.
# =============================================================================

sub r44_chart {
    my $chart = r42_build_chart();
    $chart->{replay_controller} = Market::ReplayController->new(
        market_data => $chart->{market_data},
    );
    return $chart;
}

{
    my $chart = r44_chart();
    is($chart->index_for_timestamp('2026-04-01T00:05:00-05:00'), 5,
       '0044: index_for_timestamp coincide con vela 5');
    is($chart->index_for_timestamp('2026-04-01T00:05:10-05:00'), 5,
       '0044: index_for_timestamp elige vela mas cercana');
    is($chart->index_for_timestamp('2026-04-01'), 0,
       '0044: fecha sin hora usa medianoche -> indice 0');
}

{
    my $chart = r44_chart();
    my $last = $chart->{market_data}->size() - 1;
    my $lo = 2;
    my $hi = $last - 1;
    for (1 .. 30) {
        my $idx = $chart->replay_random_start_index();
        ok($idx >= $lo && $idx <= $hi, "0044: random $idx en [$lo,$hi]");
    }
}

{
    my $chart = r44_chart();
    my $last = $chart->{market_data}->size() - 1;
    my $replay_on = 0;
    my $replay_select_mode = 0;
    my %vars = (
        replay_on          => \$replay_on,
        replay_select_mode => \$replay_select_mode,
    );
    my $rc = $chart->{replay_controller};

    Market::UI::Callbacks->make_replay_goto_first($chart, \%vars)->();
    ok($rc->is_active(), '0044: First activa replay');
    is($rc->current_index(), 0, '0044: First arranca en indice 0');
    is($replay_on, 1, '0044: First marca replay_on=1');
    ok(!$chart->is_replay_select_mode(), '0044: First apaga select mode');

    $rc->exit();
    Market::UI::Callbacks->make_replay_goto_random($chart, \%vars)->();
    ok($rc->is_active(), '0044: Random activa replay');
    ok($rc->current_index() >= 2 && $rc->current_index() <= $last,
       '0044: Random replay_idx en rango valido');

    $rc->exit();
    Market::UI::Callbacks->make_replay_goto_bar($chart, \%vars)->();
    ok($chart->is_replay_select_mode(), '0044: Bar entra en modo seleccion');
    is($replay_select_mode, 1, '0044: Bar sincroniza replay_select_mode');

    $rc->exit();
    my $date_cb = Market::UI::Callbacks->make_replay_goto_date(
        $chart, undef, \%vars,
        sub { return '2026-04-01T00:10:00-05:00' },
    );
    $date_cb->();
    ok($rc->is_active(), '0044: Date activa replay');
    is($rc->current_index(), 10, '0044: Date salta a vela mas cercana (10)');
}

done_testing();