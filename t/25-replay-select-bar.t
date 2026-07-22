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

# UX TradingView: Select Bar deja la ultima vela ~80% mediante slots vacios,
# nunca trasladando el dominio completo con un x_shift fijo.
{
    my $md = R40MarketData->new(100);
    my $chart = bless {
        market_data       => $md,
        replay_controller => Market::ReplayController->new(market_data => $md),
        visible_bars      => 60,
        offset            => 0,
        ctrl_zoom_x_shift => 0,
    }, 'Market::ChartEngine';

    # Modelo robusto: la vista se gobierna por replay_view_end (borde derecho
    # LOGICO absoluto). Sin anchor el head queda pegado al borde (view_end=index);
    # con anchor se dejan slots vacios a la derecha (view_end > index, head ~80%).
    $chart->frame_replay_view_at(49);
    is($chart->{replay_view_end}, 49, 'sin anchor: head pegado al borde derecho');

    $chart->frame_replay_view_at(49, { anchor => 1 });
    ok($chart->{replay_view_end} > 49, 'anchor: hueco a la derecha (head ~80%)');
    $chart->{replay_controller}->start(49);

    my ($s, $e) = $chart->compute_window();
    my $x_bars = $e - $s + 1;
    is($x_bars, 60, 'anchor: viewport conserva 60 slots');
    is($e, 61, 'anchor: 12 slots vacios posteriores al replay_idx');
    is($chart->{ctrl_zoom_x_shift}, 0, 'anchor: no usa x_shift permanente');

    my $scale = Market::Panels::Scales->new(min_y => 0, max_y => 1, bars => $x_bars);
    $scale->{width} = 1000;
    $scale->{x_shift} = 0;
    my $head_local = 49 - $s;
    my $cx = $scale->index_to_center_x($head_local);
    my $bar_w = $scale->plot_width() / $x_bars;
    my $right_edge = $cx + $bar_w / 2;
    ok(abs($right_edge - 800) < 2, "anchor: borde derecho ultima vela ~80% plot ($right_edge)");
}

# Salir de replay restaura vista live (shift/anchor/offset).
{
    my $md = R40MarketData->new(100);
    my $chart = bless {
        market_data       => $md,
        replay_controller => Market::ReplayController->new(market_data => $md),
        visible_bars      => 60,
        offset            => 0,
        ctrl_zoom_x_shift => -150,
        replay_view_anchor => 0.80,
    }, 'Market::ChartEngine';

    $chart->{replay_controller}->start(49);
    $chart->restore_after_replay_exit();
    $chart->{replay_controller}->exit();

    ok(!exists $chart->{replay_view_anchor}, 'exit: replay_view_anchor limpiado');
    is($chart->{ctrl_zoom_x_shift}, 0, 'exit: ctrl_zoom_x_shift reseteado');
    is($chart->{offset}, 0, 'exit: offset reseteado');
    my ($s, $e) = $chart->compute_window();
    is($e, 99, 'exit: ventana hasta ultima vela del dataset');
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
    sub configure {
        my ($s, %opt) = @_;
        $s->{cursor} = $opt{-cursor} if exists $opt{-cursor};
        return $s;
    }
    sub cget {
        my ($s, $opt) = @_;
        return $s->{cursor} if $opt eq '-cursor';
        return undef;
    }
    sub focus { return }
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
    is(r42_op_opt($sci_ops[0], '-font'), 'Helvetica 22', '0053: tijeras Helvetica 22');
    is(r42_op_opt($sci_ops[0], '-fill'), 'black', '0053: tijeras negras (no azul linea)');

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
# task 0053: Select Bar — sin crosshair dibujado; cursor nativo oculto; tijera sola.
# =============================================================================

{
    package MockPricePanelCross;
    sub new { my ($c, $calls) = @_; bless { calls => $calls }, $c }
    sub draw_crosshair {
        my ($s, $x, $y, $t) = @_;
        push @{ $s->{calls} }, [ $x, $y, $t ];
    }
}

{
    package MockATRPanelCross;
    sub new { my ($c, $calls) = @_; bless { calls => $calls }, $c }
    sub draw_crosshair {
        my ($s, $x, $y) = @_;
        push @{ $s->{calls} }, [ 'atr', $x, $y ];
    }
}

{
    package main;
    my $chart = r42_build_chart();
    my @crosshair_calls;
    $chart->{price_panel} = MockPricePanelCross->new(\@crosshair_calls);
    $chart->{atr_panel}   = MockATRPanelCross->new(\@crosshair_calls);
    $chart->{last_mouse_x} = 400;
    $chart->{last_mouse_y} = 200;
    $chart->set_replay_select_mode(1);
    $chart->_draw_crosshair_all();
    ok(@crosshair_calls >= 1, '0053: select mode limpia crosshair (draw con coords undef)');
    ok(!defined $crosshair_calls[0][0], '0053: select mode no dibuja lineas crosshair en precio');
}

{
    my $chart = r42_build_chart();
    $chart->set_replay_select_mode(1);
    use Market::ChartEngine;
    my $ce_probe = bless {}, 'Market::ChartEngine';
    my @xbm = $ce_probe->_blank_cursor_xbm_paths();
    is(scalar(@xbm), 2, '0053: assets/blank_cursor.xbm + mask disponibles');

    isnt($chart->{price_canvas}{cursor}, 'crosshair',
        '0053: select mode NO usa cursor crosshair nativo en price');
    isnt($chart->{atr_canvas}{cursor}, 'crosshair',
        '0053: select mode NO usa cursor crosshair nativo en atr');
    my $pc = $chart->{price_canvas}{cursor};
    ok(ref($pc) eq 'ARRAY' && $pc->[0] =~ /^\@/,
        '0053: select mode usa cursor XBM invisible (arrayref con hotspot)');
    $chart->set_replay_select_mode(0);
    is($chart->{price_canvas}{cursor}, 'crosshair', '0053: salir select restaura crosshair');
}

# =============================================================================
# UX (pedido usuario): linea azul solo con cursor en chart; click trunca.
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
    ok(!defined $chart->{last_mouse_x}, 'UX TV: select mode sin cursor no muestra linea azul');
    ok(!defined $chart->{last_mouse_y}, 'UX TV: select mode sin cursor limpia last_mouse_y');

    $chart->{last_mouse_x} = 450;
    $chart->{last_mouse_y} = 200;
    ok($chart->_replay_select_hover_layout($chart->{last_mouse_x}),
       'UX TV: con cursor en chart el hover azul tiene layout');

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
    is($chart->_causal_end(), 49, 'UX: ultima vela causal es la anterior a la seleccionada');
    is($e, 61, 'UX: viewport conserva 12 slots vacios tras la ultima vela');
    ok($s <= $chart->_causal_end() && $chart->_causal_end() < $e,
       'UX: head causal queda dentro de la ventana logica');
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

# =============================================================================
# Replay: linea de precio sigue replay_idx; sin dibujar velas futuras.
# =============================================================================
{
    package R50MockCanvas;
    sub new { bless { ops => [] }, shift }
    sub delete { my ($s, $tag) = @_; push @{ $s->{ops} }, [ delete => $tag ]; return }
    sub _tk_opts {
        my (@args) = @_;
        my %o;
        for (my $i = 0; $i < @args; $i += 2) {
            my $k = $args[$i];
            $k =~ s/^-//;
            $o{$k} = $args[$i + 1];
        }
        return %o;
    }
    sub createLine {
        my ($s, @args) = @_;
        my %o = _tk_opts(@args[4 .. $#args]);
        push @{ $s->{ops} }, [ createLine => { %o } ];
        return 'ln';
    }
    sub createRectangle {
        my ($s, @args) = @_;
        my %o = _tk_opts(@args[4 .. $#args]);
        push @{ $s->{ops} }, [ createRectangle => { %o } ];
        return 'r';
    }
    sub createText { my ($s) = @_; push @{ $s->{ops} }, [ createText => {} ]; return 't' }
    sub lower { return shift }
    sub raise { return shift }

    package main;

    use Market::Panels::PricePanel;

    my $bull_candle = [ 0, 100, 110, 95, 108, 1 ];
    my $bear_candle = [ 0, 108, 109, 90,  92,  1 ];
    my $bull2       = [ 0,  92, 100, 91,  99,  1 ];
    my @data = ($bull_candle, $bear_candle, $bull2);

    my $panel = Market::Panels::PricePanel->new(
        theme => { bull => '#26a69a', bear => '#ef5350' },
        canvas => R50MockCanvas->new(),
    );
    my $canvas = $panel->{canvas};
    my $scale = Market::Panels::Scales->new(
        min_y => 80, max_y => 120, bars => 3, right_margin => 0,
    );
    $scale->{width} = 800;
    $scale->{height} = 400;
    $scale->{draw_start_offset} = 0;
    $scale->{visible_count} = 3;
    $scale->{slice_base_index} = 0;
    $scale->{replay_head_candle} = $bull_candle;
    $scale->{replay_max_index} = 0;
    $panel->{scale} = $scale;

    $panel->render($canvas, \@data, $scale);

    # La hline full-width del último precio SÍ se dibuja (restaurada a pedido):
    # línea horizontal punteada a la altura del close, con el color del precio
    # actual (verde alcista en replay_idx). Recorre todo el ancho del plot.
    my ($hline_op) = grep {
        $_->[0] eq 'createLine' && ( $_->[1]{tags} // '' ) eq 'price_label'
    } @{ $canvas->{ops} };
    ok( $hline_op, 'replay: dibuja linea horizontal last-price full-width' );
    is( $hline_op->[1]{fill}, '#26a69a', 'replay: color hline = vela replay_idx (verde)' )
      if $hline_op;

    my ($box_op) = grep {
        $_->[0] eq 'createRectangle' && ( $_->[1]{tags} // '' ) eq 'price_label'
    } @{ $canvas->{ops} };
    ok( $box_op, 'replay: cajita de precio (fallback plot) si no hay eje separado' );
    is( $box_op->[1]{fill}, '#26a69a', 'replay: color cajita = vela replay_idx (verde)' )
      if $box_op;

    my @candle_ops = grep {
        ($_->[0] eq 'createLine' || $_->[0] eq 'createRectangle')
        && ($_->[1]{tags} // '') eq 'candle'
    } @{ $canvas->{ops} };
    ok(scalar(@candle_ops) >= 1, 'replay: dibuja vela en replay_idx');
    my $drew_bear = grep { ($_->[1]{fill} // '') eq '#ef5350' } @candle_ops;
    ok(!$drew_bear, 'replay: vela futura (idx>replay_idx) no se dibuja');
}

# =============================================================================
# REGRESIONES (bugs reportados por el usuario): estado de Replay que se filtra.
# =============================================================================

# BUG 1: la marca de agua "Replay" y el velo de Select Bar no deben quedar
# colgados. _purge_replay_visuals borra todos los tags de Replay en los canvas.
{
    my $chart = r42_build_chart();
    # Simular artefactos colgados en el canvas de precio y en el eje temporal.
    $chart->{price_canvas}->createText(1, 1, -tags => 'replay_watermark');
    $chart->{price_canvas}->createRectangle(0, 0, 1, 1, -tags => 'replay_select_veil');
    $chart->{time_axis_canvas}->createText(1, 1, -tags => 'replay_select_re_label');

    $chart->_purge_replay_visuals();

    my @del_price = grep { $_->[0] eq 'delete' } @{ $chart->{price_canvas}{ops} };
    my %deleted = map { ($_->[1] // '') => 1 } @del_price;
    ok($deleted{replay_watermark},      'BUG1: purga borra la marca de agua Replay');
    ok($deleted{replay_select_veil},    'BUG1: purga borra el velo de Select Bar');
    ok($deleted{replay_select_hover},   'BUG1: purga borra la linea de hover');
    ok($deleted{replay_select_scissors},'BUG1: purga borra el cursor tijeras');
    my @del_time = grep { $_->[0] eq 'delete' && ($_->[1]//'') eq 'replay_select_re_label' }
        @{ $chart->{time_axis_canvas}{ops} };
    ok(@del_time >= 1, 'BUG1: purga borra la etiqueta Re: del eje temporal');
}

# BUG 2: restore_after_replay_exit limpia estado Y artefactos de inmediato.
{
    my $chart = r42_build_chart();
    $chart->{price_canvas}->createText(1, 1, -tags => 'replay_watermark');
    $chart->{ctrl_zoom_x_shift} = 33;
    $chart->{offset} = 5;
    $chart->{replay_view_anchor} = 0.8;

    $chart->restore_after_replay_exit();

    is($chart->{ctrl_zoom_x_shift}, 0, 'BUG2: exit resetea x_shift');
    is($chart->{offset}, 0, 'BUG2: exit resetea offset');
    ok(!defined $chart->{replay_view_anchor}, 'BUG2: exit borra replay_view_anchor');
    my @del = grep { $_->[0] eq 'delete' && ($_->[1]//'') eq 'replay_watermark' }
        @{ $chart->{price_canvas}{ops} };
    ok(@del >= 1, 'BUG2: exit purga la marca Replay sin esperar al render');
}

# BUG 3: clic en Select Bar en zona sin vela no debe dejar atrapado; resuelve a
# la ultima vela visible y confirma (apaga el modo tijeras).
{
    my $chart = r42_build_chart();
    my $confirmed;
    $chart->{replay_bar_selected_callback} = sub { $confirmed = $_[0] };
    $chart->set_replay_select_mode(1);
    ok($chart->is_replay_select_mode(), 'BUG3: en modo select antes del clic');

    # x muy a la derecha (zona vacia tras la ultima vela) → _global_index_from_x undef.
    $chart->_start_horizontal_drag($chart->{price_canvas}, 100000, 250);

    ok(defined $confirmed, 'BUG3: clic en zona vacia igual confirma (no se traba)');
    ok(!$chart->is_replay_select_mode(), 'BUG3: tras confirmar, sale del modo tijeras');
}

done_testing();