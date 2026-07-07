#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Tk;

use lib '.';
use Market::MarketData;
use Market::IndicatorManager;
use Market::Indicators::ATR;
use Market::ChartEngine;
use Market::UI::Callbacks;   # factorías de callbacks de la barra (TF/Replay/Overlays)
use Market::UI::ReplayPanel; # panel flotante Replay estilo TradingView (task 0043)

print "========== LAUNCHING FINANCIAL CHARTING ENGINE (Tk) ==========\n";

# ==========================================
# 1. DATOS E INDICADORES BASE (solo lo de Fase 1 para arranque instantáneo)
# ==========================================
# task 0018 (F3): el arranque solo precomputa lo imprescindible para pintar como
# en Fase 1 (velas + ATR). SMC/Liquidity se alimentan BAJO DEMANDA dentro de
# ChartEngine cuando el usuario activa su capa; aquí NO se registran ni se
# alimentan (antes había un SMC extra que duplicaba el cómputo sobre 29888 velas).
my $market_data = Market::MarketData->new();
my $indicator_manager = Market::IndicatorManager->new();
$indicator_manager->register('ATR', Market::Indicators::ATR->new(14));

my $archivo_csv = 'Data/2026_07_06.csv';
print "[*] Leyendo base de datos histórica...\n";
open my $fh, '<', $archivo_csv or die "CRÍTICO: No se pudo abrir $archivo_csv: $!";
my $header = <$fh>;
while (my $linea = <$fh>) {
    chomp $linea;
    my @columnas = split /,/, $linea;
    $market_data->add_candle(\@columnas);
}
close $fh;

print "[*] Construyendo temporalidades...\n";
$market_data->build_timeframes();
$market_data->set_timeframe('1m');
for (my $i = 0; $i < $market_data->size(); $i++) {
    $indicator_manager->update_last($market_data, $i);   # ATR es O(1)/vela
}

# ==========================================
# 2. VENTANA PRINCIPAL
# ==========================================
my $mw = MainWindow->new;
$mw->title("Plataforma de Gráficos Financieros - Motor de Charting Tk");
$mw->minsize(900, 600);

my $sw = eval { $mw->screenwidth }  || 1280;
my $sh = eval { $mw->screenheight } || 800;
my $screen_ok = ($sw >= 800 && $sw <= 10000 && $sh >= 600 && $sh <= 10000);
if ($screen_ok) {
    my $usable_w = $sw - 16;  my $usable_h = $sh - 96;
    $usable_w = 1280 if $usable_w < 1280;
    $usable_h = 720  if $usable_h < 720;
    $mw->geometry("${usable_w}x${usable_h}+0+0");
} else {
    $mw->geometry('1280x720+50+50');
}
$mw->deiconify; $mw->raise; $mw->focusForce;

# ==========================================
# PALETA DE TEMA CLARO
# ==========================================
my %theme = (
    bg => '#ffffff', grid => '#e6e6e6', date_grid => '#c4c9d1',
    axis_text => '#363a45', bull => '#26a69a', bear => '#ef5350',
    atr_line => '#2962ff', crosshair_line => '#9598a1',
    label_bg => '#363a45', label_fg => '#ffffff',
    last_price_bg => '#363a45', last_price_fg => '#ffffff',
);

my $time_axis_height = 18;
my $right_axis_width = 60;
my $atr_axis_width   = 48;

# ==========================================
# 3. LAYOUT: barra compacta abajo, chart arriba
# ==========================================
my $frame_controles = $mw->Frame(-relief => 'raised', -bd => 1)
    ->pack(-side => 'bottom', -fill => 'x');

my $chart_frame = $mw->Frame(-background => $theme{bg})->pack(-side => 'top', -expand => 1, -fill => 'both');

my $price_frame = $chart_frame->Frame(-background => $theme{bg})->pack(-side => 'top', -expand => 1, -fill => 'both');
my $price_axis_canvas = $price_frame->Canvas(
    -width => $right_axis_width, -background => $theme{bg},
    -relief => 'sunken', -bd => 1, -cursor => 'sb_v_double_arrow'
)->pack(-side => 'right', -fill => 'y');
my $price_canvas = $price_frame->Canvas(
    -background => $theme{bg}, -relief => 'sunken', -bd => 1
)->pack(-side => 'left', -expand => 1, -fill => 'both');

my $time_frame = $chart_frame->Frame(-background => $theme{bg})->pack(-side => 'top', -fill => 'x');
$time_frame->Canvas(
    -width => $right_axis_width, -height => $time_axis_height, -background => $theme{bg},
    -relief => 'sunken', -bd => 1, -highlightthickness => 0
)->pack(-side => 'right', -fill => 'y');
my $time_axis_canvas = $time_frame->Canvas(
    -height => $time_axis_height, -background => $theme{bg}, -relief => 'sunken',
    -bd => 1, -highlightthickness => 0, -cursor => 'sb_h_double_arrow'
)->pack(-side => 'left', -expand => 1, -fill => 'x');

my $atr_frame = $chart_frame->Frame(-background => $theme{bg})->pack(-side => 'top', -fill => 'x');
my $atr_axis_canvas = $atr_frame->Canvas(
    -width => $atr_axis_width, -height => 140, -background => $theme{bg}, -relief => 'sunken', -bd => 1
)->pack(-side => 'right', -fill => 'y');
$atr_frame->Frame(
    -width => $right_axis_width - $atr_axis_width, -height => 140, -background => $theme{bg},
)->pack(-side => 'right', -fill => 'y');
my $atr_canvas = $atr_frame->Canvas(
    -height => 140, -background => $theme{bg}, -relief => 'sunken', -bd => 1
)->pack(-side => 'left', -expand => 1, -fill => 'x');

# ==========================================
# 4. MOTOR ORQUESTADOR
# ==========================================
my $scale_mode = 'auto';
my $atr_scale_mode = 'auto';
my $active_tf = '1m';
my $htf_enabled = 0;
my $replay_on   = 0;
my $replay_select_mode = 0;
my $replay_watermark_on = 1;
my $replay_panel;
my %ui_vars = (
    active_tf => \$active_tf, htf_enabled => \$htf_enabled, replay_on => \$replay_on,
    replay_select_mode => \$replay_select_mode,
    replay_watermark_on => \$replay_watermark_on,
    replay_panel       => \$replay_panel,
);

my $chart_engine = Market::ChartEngine->new(
    market_data       => $market_data,
    indicator_manager => $indicator_manager,
    price_canvas      => $price_canvas,
    price_axis_canvas => $price_axis_canvas,
    atr_canvas        => $atr_canvas,
    atr_axis_canvas   => $atr_axis_canvas,
    time_axis_canvas  => $time_axis_canvas,
    scale_mode_callback => sub { $scale_mode = $_[0] },
    atr_scale_mode_callback => sub { $atr_scale_mode = $_[0] },
    replay_select_mode_callback => sub { $replay_select_mode = $_[0] ? 1 : 0 },
    theme             => \%theme
);

$chart_engine->{replay_watermark_on_ref} = \$replay_watermark_on;
$chart_engine->{replay_on_ref} = \$replay_on;
$chart_engine->{plot_frames} = [$price_frame, $atr_frame];
$chart_engine->init_plot_cursors();

$chart_engine->{replay_bar_selected_callback} = sub {
    Market::UI::Callbacks->replay_confirm_bar_selection($chart_engine, \%ui_vars);
};

$ui_vars{mw} = $mw;

$chart_engine->bind_replay_window_shortcuts($mw);

$mw->Tk::bind('<Configure>', sub { $chart_engine->request_render(); });

# Estado de visibilidad de capas (overlays OFF por defecto — task 0018 F4).
my $vis_smc = 0;
my $vis_liq = 0;
my $vis_strategy = 0;
my $vis_vp = 0;
my $vis_vwap = 0;
my $vis_mxwll = 0;
my $vis_zigzag = 0;
my %vis_elem = map { $_ => 1 } qw(BSL SSL EQH EQL SWEEP GRAB RUN);
# Feedback profe/QA: arrancar con pocas marcas, solo las más relevantes.
my $liq_density_pct = 20;
my $smc_density_pct = 35;
my $mxwll_density_pct = 35;
my $zigzag_density_pct = 35;
my %liq_elem_density_pct = map { $_ => $liq_density_pct } qw(BSL SSL EQH EQL SWEEP GRAB RUN);
my %smc_elem_density_pct = map { $_ => $smc_density_pct } qw(PIVOTS EVENTS FVG FIBS MAJOR);
my %mxwll_elem_density_pct = map { $_ => $mxwll_density_pct } qw(STRUCTURE SWINGS OB FVG AOE FIBS STRONG_WEAK);
my %zigzag_elem_density_pct = map { $_ => $zigzag_density_pct } qw(INTERNAL EXTERNAL CHANNEL);
$chart_engine->{liq_overlay}->set_density_pct($liq_density_pct)
    if $chart_engine->{liq_overlay} && $chart_engine->{liq_overlay}->can('set_density_pct');
$chart_engine->{smc_overlay}->set_density_pct($smc_density_pct)
    if $chart_engine->{smc_overlay} && $chart_engine->{smc_overlay}->can('set_density_pct');
$chart_engine->{mxwll_overlay}->set_density_pct($mxwll_density_pct)
    if $chart_engine->{mxwll_overlay} && $chart_engine->{mxwll_overlay}->can('set_density_pct');
$chart_engine->{zigzag_overlay}->set_density_pct($zigzag_density_pct)
    if $chart_engine->{zigzag_overlay} && $chart_engine->{zigzag_overlay}->can('set_density_pct');
my %vis_zzelem = ( INTERNAL => 1, EXTERNAL => 1, CHANNEL => 0 );
my $zigzag_resolution = 30;
# ORDEN 9 (task 0021 I): sub-elementos de la capa Mxwll (todos ON por defecto).
my %vis_mxelem = ( STRUCTURE => 1, SWINGS => 1, OB => 1, FVG => 1, AOE => 1, FIBS => 1, STRONG_WEAK => 0 );

# Callbacks (factorías testeadas headless). F1: SIEMPRE pasamos el valor de la
# -variable explícito al callback (Tk no lo pasa solo en -command).
my $cb_smc = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'smc');
my $cb_liq = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'liq');
my $cb_strategy = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'strategy');
my $cb_vp = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'vp');
my $cb_vwap = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'vwap');
my $cb_mxwll = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'mxwll');
my $cb_zigzag = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'zigzag');
my %cb_elem = map { $_ => Market::UI::Callbacks->make_liq_element_toggle($chart_engine, $_) }
              qw(BSL SSL EQH EQL SWEEP GRAB RUN);
my %cb_mxelem = map { $_ => Market::UI::Callbacks->make_mxwll_element_toggle($chart_engine, $_) }
                qw(STRUCTURE SWINGS OB FVG AOE FIBS STRONG_WEAK);
my %cb_zzelem = map { $_ => Market::UI::Callbacks->make_zigzag_element_toggle($chart_engine, $_) }
                qw(INTERNAL EXTERNAL CHANNEL);
my %vis_strategy_elem = (
    SUPERTREND => 0, HALFTREND => 0, RANGEFILTER => 0, SUPPLY_DEMAND => 1,
);
my %cb_strategy_elem = map {
    my $elem = $_;
    $elem => sub {
        my ($on) = @_;
        my $ov = $chart_engine->{strategy_overlay};
        return unless $ov && $ov->can('set_element_visible');
        $ov->set_element_visible($elem, $on ? 1 : 0);
        $chart_engine->request_render();
    }
} qw(SUPERTREND HALFTREND RANGEFILTER SUPPLY_DEMAND);
my %overlay_state_ref = (
    smc => \$vis_smc, liq => \$vis_liq, strategy => \$vis_strategy,
    vp => \$vis_vp, vwap => \$vis_vwap, mxwll => \$vis_mxwll, zigzag => \$vis_zigzag,
);
my %overlay_cb = (
    smc => $cb_smc, liq => $cb_liq, strategy => $cb_strategy,
    vp => $cb_vp, vwap => $cb_vwap, mxwll => $cb_mxwll, zigzag => $cb_zigzag,
);
my %overlay_button;
my $overlay_button_text = sub { $_[0] ? 'Ocultar' : 'Mostrar' };
my $refresh_overlay_button = sub {
    my ($name) = @_;
    return unless $overlay_button{$name} && $overlay_state_ref{$name};
    $overlay_button{$name}->configure(-text => $overlay_button_text->(${ $overlay_state_ref{$name} }));
};
my $set_overlay_visible = sub {
    my ($name, $on) = @_;
    return unless $overlay_state_ref{$name} && $overlay_cb{$name};
    ${ $overlay_state_ref{$name} } = $on ? 1 : 0;
    $overlay_cb{$name}->($on ? 1 : 0);
    $refresh_overlay_button->($name);
};
my $toggle_overlay_visible = sub {
    my ($name) = @_;
    return unless $overlay_state_ref{$name};
    $set_overlay_visible->($name, ${ $overlay_state_ref{$name} } ? 0 : 1);
};
my %cb_zzres = map { $_ => Market::UI::Callbacks->make_zigzag_resolution_callback($chart_engine, $_) }
               qw(15 30 60);
my $cb_htf = Market::UI::Callbacks->make_htf_toggle($chart_engine, \%ui_vars);
my %tf_cb  = map { $_ => Market::UI::Callbacks->make_tf_callback($chart_engine, $_, \%ui_vars) }
             Market::UI::Callbacks->timeframes();

# ============================================================================
# 5. BARRA DE CONTROLES INLINE (todo en la MISMA ventana) — task 0018b
# ============================================================================
# IMPORTANTE: NO se usa menubar nativo ($mw->Menu/-menu) ni Optionmenu. Bajo
# WSLg ambos abren ventanas X separadas (popups), que aparecen en posiciones
# erráticas, se traban o no cargan. Todos los controles van inline con widgets
# que NO crean ventanas: Radiobutton, Checkbutton, Button. La barra se organiza
# en dos filas para no saturar.
# DISEÑO DE PESTAÑAS (task 0032): antes había 2 filas saturadas que se salían de
# la pantalla (TF + 6 capas + 7 liq + 6 mxwll + HTF no cabían). Ahora:
#   - FILA SUPERIOR (siempre visible): selector TF + botones de PESTAÑA.
#   - FILA INFERIOR (área de panel): muestra SOLO el panel de la pestaña activa.
# Se emula un "notebook" con Frames + pack/packForget (NO se usa menubar nativo,
# Optionmenu ni Tk::NoteBook: bajo WSLg abren ventanas X aparte y fallan).
my $tab_row   = $frame_controles->Frame()->pack(-side => 'top', -fill => 'x', -pady => 1);
my $panel_row = $frame_controles->Frame()->pack(-side => 'top', -fill => 'x', -pady => 1);

# --- Selector de temporalidad: SIEMPRE visible (lo más usado) ---
my $tf_box = $tab_row->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
$tf_box->Label(-text => 'TF:')->pack(-side => 'left', -padx => 3);
for my $tf (Market::UI::Callbacks->timeframes()) {
    $tf_box->Radiobutton(
        -text => Market::UI::Callbacks->tf_label($tf),
        -value => $tf, -variable => \$active_tf,
        -indicatoron => 0, -padx => 4, -pady => 1,
        -command => sub { $tf_cb{$tf}->(); },
    )->pack(-side => 'left', -padx => 1);
}

# --- Paneles (uno por pestaña). Se construyen una vez; se muestran/ocultan. ---
my %panel;
$panel{$_} = $panel_row->Frame() for qw(Capas SMC Liq Mxwll ZigZag Estrategia Escala Replay);

my $active_tab = 'Capas';
my $show_panel = sub {
    my ($name) = @_;
    $active_tab = $name;
    $_->packForget for values %panel;
    $panel{$name}->pack(-side => 'left', -fill => 'x') if $panel{$name};
};

my $cb_replay_activate = Market::UI::Callbacks->make_replay_activate($chart_engine, \%ui_vars);
$ui_vars{show_replay_tab} = sub {
    $active_tab = 'Replay';
    $show_panel->('Replay');
};
$ui_vars{show_default_tab} = sub {
    $active_tab = 'Capas';
    $show_panel->('Capas');
};

# --- Botones de pestaña en la fila superior ---
# Etiquetas más explícitas para exposición; las claves internas se conservan para
# no tocar callbacks ni lógica de Replay.
my %tab_label = (
    Capas     => 'Capas',
    SMC       => 'SMC',
    Liq       => 'Liquidez',
    Mxwll     => 'Mxwll',
    ZigZag    => 'ZigZag',
    Estrategia=> 'Estrategia',
    Escala    => 'Escala',
    Replay    => 'Replay',
);
my $tabs_box = $tab_row->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 5);
for my $name (qw(Capas SMC Liq Mxwll ZigZag Estrategia Escala Replay)) {
    $tabs_box->Radiobutton(
        -text => $tab_label{$name}, -value => $name, -variable => \$active_tab,
        -indicatoron => 0, -padx => 8, -pady => 1,
        -command => sub {
            $show_panel->($name);
            $cb_replay_activate->() if $name eq 'Replay';
        },
    )->pack(-side => 'left', -padx => 1);
}

# --- Densidad: resumen SIEMPRE visible a la derecha + detalle DESPLEGABLE ---
# Sin Optionmenu/menubar nativo (WSLg): el "desplegable" se emula mostrando u
# ocultando una fila inferior con pack/packForget. La barra superior solo deja
# un resumen compacto (grupo/item + valor); el detalle (grupos, específicos y
# la barra 1..100) aparece bajo demanda para ahorrar espacio.
my $density_global_box = $tab_row->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'right', -padx => 4);
$density_global_box->Label(-text => 'Densidad:')->pack(-side => 'left', -padx => 3);
my %density_items = (
    liq    => [qw(GLOBAL BSL SSL EQH EQL SWEEP GRAB RUN)],
    smc    => [qw(GLOBAL PIVOTS EVENTS FVG FIBS MAJOR)],
    mxwll  => [qw(GLOBAL STRUCTURE SWINGS OB FVG AOE FIBS STRONG_WEAK)],
    zigzag => [qw(GLOBAL INTERNAL EXTERNAL CHANNEL)],
);
my %density_group_label = ( liq => 'Liq', smc => 'SMC', mxwll => 'Mxwll', zigzag => 'ZigZag' );
my $density_group = 'liq';
my $density_item  = 'GLOBAL';
my $density_slider_value = $liq_density_pct;
my ($density_value_label, $density_scale, $density_summary_label);
my %density_item_frame;
# Fila de detalle (oculta por defecto). Contiene grupos + específicos + barra.
my $density_detail_row = $frame_controles->Frame();
my $density_rows_box = $density_detail_row->Frame()->pack(-side => 'left', -padx => 2);
my $density_groups_box = $density_rows_box->Frame()->pack(-side => 'top', -anchor => 'w');
my $density_items_box = $density_rows_box->Frame()->pack(-side => 'top', -anchor => 'w');
my $density_summary_text = sub {
    my $g = $density_group_label{$density_group} // $density_group;
    my $i = $density_item eq 'GLOBAL' ? 'Global' : $density_item;
    return "$g/$i $density_slider_value%";
};
my $density_cfg = sub { return [ $density_group, $density_item ]; };
my $density_value_for = sub {
    my ($group, $elem) = @_;
    return $group eq 'liq'    ? ($elem eq 'GLOBAL' ? $liq_density_pct    : $liq_elem_density_pct{$elem})
         : $group eq 'smc'    ? ($elem eq 'GLOBAL' ? $smc_density_pct    : $smc_elem_density_pct{$elem})
         : $group eq 'mxwll'  ? ($elem eq 'GLOBAL' ? $mxwll_density_pct  : $mxwll_elem_density_pct{$elem})
         : $group eq 'zigzag' ? ($elem eq 'GLOBAL' ? $zigzag_density_pct : $zigzag_elem_density_pct{$elem})
         : 1;
};
my $sync_density_slider = sub {
    my $v = $density_value_for->($density_group, $density_item);
    $density_slider_value = $v;
    $density_scale->set($v) if $density_scale;
    $density_value_label->configure(-text => "$v%") if $density_value_label;
    $density_summary_label->configure(-text => $density_summary_text->()) if $density_summary_label;
};
my $show_density_items = sub {
    $_->packForget for values %density_item_frame;
    $density_item = 'GLOBAL' unless grep { $_ eq $density_item } @{ $density_items{$density_group} };
    $density_item_frame{$density_group}->pack(-side => 'left') if $density_item_frame{$density_group};
    $sync_density_slider->();
};
my $apply_density = sub {
    my ($v) = @_;
    $v = int(($v // 1) + 0.5);
    $v = 1 if $v < 1;
    $v = 100 if $v > 100;
    my %overlay_for = (
        liq    => 'liq_overlay',
        smc    => 'smc_overlay',
        mxwll  => 'mxwll_overlay',
        zigzag => 'zigzag_overlay',
    );
    my $ov = $chart_engine->{ $overlay_for{$density_group} };
    return unless $ov;
    if ($density_group eq 'liq') {
        if ($density_item eq 'GLOBAL') {
            $liq_density_pct = $v;
            $liq_elem_density_pct{$_} = $v for keys %liq_elem_density_pct;
            $ov->set_density_pct($v) if $ov->can('set_density_pct');
        } else {
            $liq_elem_density_pct{$density_item} = $v;
            $ov->set_element_density_pct($density_item, $v) if $ov->can('set_element_density_pct');
        }
    } elsif ($density_group eq 'smc') {
        if ($density_item eq 'GLOBAL') {
            $smc_density_pct = $v;
            $smc_elem_density_pct{$_} = $v for keys %smc_elem_density_pct;
            $ov->set_density_pct($v) if $ov->can('set_density_pct');
        } else {
            $smc_elem_density_pct{$density_item} = $v;
            $ov->set_element_density_pct($density_item, $v) if $ov->can('set_element_density_pct');
        }
    } elsif ($density_group eq 'mxwll') {
        if ($density_item eq 'GLOBAL') {
            $mxwll_density_pct = $v;
            $mxwll_elem_density_pct{$_} = $v for keys %mxwll_elem_density_pct;
            $ov->set_density_pct($v) if $ov->can('set_density_pct');
        } else {
            $mxwll_elem_density_pct{$density_item} = $v;
            $ov->set_element_density_pct($density_item, $v) if $ov->can('set_element_density_pct');
        }
    } elsif ($density_group eq 'zigzag') {
        if ($density_item eq 'GLOBAL') {
            $zigzag_density_pct = $v;
            $zigzag_elem_density_pct{$_} = $v for keys %zigzag_elem_density_pct;
            $ov->set_density_pct($v) if $ov->can('set_density_pct');
        } else {
            $zigzag_elem_density_pct{$density_item} = $v;
            $ov->set_element_density_pct($density_item, $v) if $ov->can('set_element_density_pct');
        }
    }
    $density_value_label->configure(-text => "$v%") if $density_value_label;
    $density_summary_label->configure(-text => $density_summary_text->()) if $density_summary_label;
    $chart_engine->request_render();
};
for my $group (qw(liq smc mxwll zigzag)) {
    $density_groups_box->Radiobutton(
        -text => $density_group_label{$group}, -value => $group, -variable => \$density_group,
        -indicatoron => 0, -padx => 4, -pady => 1,
        -command => $show_density_items,
    )->pack(-side => 'left', -padx => 1);
    $density_item_frame{$group} = $density_items_box->Frame();
    for my $item (@{ $density_items{$group} }) {
        my $txt = $item eq 'GLOBAL' ? 'Global' : $item;
        $density_item_frame{$group}->Radiobutton(
            -text => $txt, -value => $item, -variable => \$density_item,
            -indicatoron => 0, -padx => 3, -pady => 1,
            -command => $sync_density_slider,
        )->pack(-side => 'left', -padx => 1);
    }
}
# La barra 1..100 vive en la fila de detalle (desplegable), más larga y cómoda.
$density_scale = $density_rows_box->Scale(
    -from      => 1,
    -to        => 100,
    -orient    => 'horizontal',
    -length    => 240,
    -showvalue => 0,
    -variable  => \$density_slider_value,
    -command   => sub { $apply_density->(shift); },
)->pack(-side => 'left', -padx => 4);
$density_value_label = $density_rows_box->Label(-text => "$density_slider_value%")
    ->pack(-side => 'left', -padx => 3);

# Resumen compacto + botón desplegable en la barra superior (ahorra espacio).
my $density_open = 0;
my $density_toggle_btn;
my $toggle_density_detail = sub {
    $density_open = !$density_open;
    if ($density_open) {
        $density_detail_row->pack(-side => 'top', -fill => 'x', -pady => 1);
        $density_toggle_btn->configure(-text => 'Ajustar [-]') if $density_toggle_btn;
    } else {
        $density_detail_row->packForget;
        $density_toggle_btn->configure(-text => 'Ajustar [+]') if $density_toggle_btn;
    }
};
$density_summary_label = $density_global_box->Label(-text => $density_summary_text->())
    ->pack(-side => 'left', -padx => 3);
$density_toggle_btn = $density_global_box->Button(
    -text => 'Ajustar [+]', -padx => 4, -pady => 1,
    -command => sub { $toggle_density_detail->(); },
)->pack(-side => 'left', -padx => 3);
$show_density_items->();

# ---- Panel "Capas": overlays principales + HTF ----
{
    my $p = $panel{Capas};
    $p->Label(-text => 'Capas:')->pack(-side => 'left', -padx => 3);
    $p->Checkbutton(-text => 'SMC', -variable => \$vis_smc,
        -command => sub { $set_overlay_visible->('smc', $vis_smc ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'Liquidez', -variable => \$vis_liq,
        -command => sub { $set_overlay_visible->('liq', $vis_liq ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'Estrategia', -variable => \$vis_strategy,
        -command => sub { $set_overlay_visible->('strategy', $vis_strategy ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'Perfil Vol', -variable => \$vis_vp,
        -command => sub { $set_overlay_visible->('vp', $vis_vp ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'VWAP', -variable => \$vis_vwap,
        -command => sub { $set_overlay_visible->('vwap', $vis_vwap ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'Mxwll', -variable => \$vis_mxwll,
        -command => sub { $set_overlay_visible->('mxwll', $vis_mxwll ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'ZigZag', -variable => \$vis_zigzag,
        -command => sub { $set_overlay_visible->('zigzag', $vis_zigzag ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'HTF sobre LTF', -variable => \$htf_enabled,
        -command => sub { $cb_htf->($htf_enabled ? 1 : 0); })->pack(-side => 'left', -padx => 6);
}

# ---- Panel "SMC": capa principal y familias controladas por densidad ----
{
    my $p = $panel{SMC};
    my $main_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $main_box->Label(-text => 'SMC:')->pack(-side => 'left', -padx => 3);
    $overlay_button{smc} = $main_box->Button(
        -text => $overlay_button_text->($vis_smc),
        -command => sub { $toggle_overlay_visible->('smc'); },
    )->pack(-side => 'left');
    my $info_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $info_box->Label(-text => 'Densidad: Global, Pivots, Events, FVG, Fibs, Major')->pack(-side => 'left', -padx => 3);
}

# ---- Panel "Liquidez": capa principal + densidad por familia ----
{
    my $p = $panel{Liq};
    my $main_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $main_box->Label(-text => 'Liquidez:')->pack(-side => 'left', -padx => 3);
    $overlay_button{liq} = $main_box->Button(
        -text => $overlay_button_text->($vis_liq),
        -command => sub { $toggle_overlay_visible->('liq'); },
    )->pack(-side => 'left');

    my $families_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $families_box->Label(-text => 'Tipos:')->pack(-side => 'left', -padx => 3);
    for my $elem (qw(BSL SSL EQH EQL SWEEP GRAB RUN)) {
        $families_box->Checkbutton(-text => $elem, -variable => \$vis_elem{$elem},
            -command => sub { $cb_elem{$elem}->($vis_elem{$elem} ? 1 : 0); })->pack(-side => 'left');
    }
}

# ---- Panel "Mxwll": sub-filtros de la capa Mxwll (ORDEN 9 / task 0021 I) ----
{
    my $p = $panel{Mxwll};
    my %mx_label = (
        STRUCTURE => 'Estr', SWINGS => 'Swings', OB => 'OB',
        FVG => 'FVG', AOE => 'AOE', FIBS => 'Fibs', STRONG_WEAK => 'S/W',
    );
    my $main_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $main_box->Label(-text => 'Mxwll:')->pack(-side => 'left', -padx => 3);
    $overlay_button{mxwll} = $main_box->Button(
        -text => $overlay_button_text->($vis_mxwll),
        -command => sub { $toggle_overlay_visible->('mxwll'); },
    )->pack(-side => 'left');
    my $filters_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $filters_box->Label(-text => 'Tipos:')->pack(-side => 'left', -padx => 3);
    for my $elem (qw(STRUCTURE SWINGS OB FVG AOE FIBS STRONG_WEAK)) {
        $filters_box->Checkbutton(-text => $mx_label{$elem}, -variable => \$vis_mxelem{$elem},
            -command => sub { $cb_mxelem{$elem}->($vis_mxelem{$elem} ? 1 : 0); })->pack(-side => 'left');
    }
}

# ---- Panel "ZigZag": interno/externo + resolución MTF (task 0033) ----
{
    my $p = $panel{ZigZag};
    my $main_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $main_box->Label(-text => 'ZigZag:')->pack(-side => 'left', -padx => 3);
    $overlay_button{zigzag} = $main_box->Button(
        -text => $overlay_button_text->($vis_zigzag),
        -command => sub { $toggle_overlay_visible->('zigzag'); },
    )->pack(-side => 'left');
    my $filters_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $filters_box->Label(-text => 'Tipos:')->pack(-side => 'left', -padx => 3);
    $filters_box->Checkbutton(-text => 'Interno', -variable => \$vis_zzelem{INTERNAL},
        -command => sub { $cb_zzelem{INTERNAL}->($vis_zzelem{INTERNAL} ? 1 : 0); })->pack(-side => 'left');
    $filters_box->Checkbutton(-text => 'Externo', -variable => \$vis_zzelem{EXTERNAL},
        -command => sub { $cb_zzelem{EXTERNAL}->($vis_zzelem{EXTERNAL} ? 1 : 0); })->pack(-side => 'left', -padx => 4);
    $filters_box->Checkbutton(-text => 'Canal', -variable => \$vis_zzelem{CHANNEL},
        -command => sub { $cb_zzelem{CHANNEL}->($vis_zzelem{CHANNEL} ? 1 : 0); })->pack(-side => 'left', -padx => 4);
    $p->Label(-text => 'Res MTF:')->pack(-side => 'left', -padx => 3);
    for my $res (qw(15 30 60)) {
        $p->Radiobutton(-text => "${res}m", -value => $res, -variable => \$zigzag_resolution,
            -indicatoron => 0, -padx => 4,
            -command => sub { $cb_zzres{$res}->(); })->pack(-side => 'left');
    }
}

# ---- Panel "Estrategia": capa principal + subcapas técnicas ----
{
    my $p = $panel{Estrategia};
    my %strategy_label = (
        SUPERTREND => 'SuperTrend', HALFTREND => 'HalfTrend',
        RANGEFILTER => 'RangeFilter', SUPPLY_DEMAND => 'Supply/Demand',
    );
    my $main_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $main_box->Label(-text => 'Estrategia:')->pack(-side => 'left', -padx => 3);
    $overlay_button{strategy} = $main_box->Button(
        -text => $overlay_button_text->($vis_strategy),
        -command => sub { $toggle_overlay_visible->('strategy'); },
    )->pack(-side => 'left');
    my $filters_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $filters_box->Label(-text => 'Elementos:')->pack(-side => 'left', -padx => 3);
    for my $elem (qw(SUPPLY_DEMAND SUPERTREND HALFTREND RANGEFILTER)) {
        $filters_box->Checkbutton(-text => $strategy_label{$elem}, -variable => \$vis_strategy_elem{$elem},
            -command => sub { $cb_strategy_elem{$elem}->($vis_strategy_elem{$elem} ? 1 : 0); })->pack(-side => 'left');
    }
}

# ---- Panel "Escala": Precio/ATR Auto-Manual + Reset Vista ----
{
    my $p = $panel{Escala};
    my $price_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $price_box->Label(-text => 'Precio:')->pack(-side => 'left', -padx => 3);
    $price_box->Radiobutton(-text => 'Auto', -value => 'auto', -variable => \$scale_mode,
        -indicatoron => 0, -padx => 5, -command => sub { $chart_engine->set_scale_mode('auto') })->pack(-side => 'left', -padx => 1);
    $price_box->Radiobutton(-text => 'Manual', -value => 'manual', -variable => \$scale_mode,
        -indicatoron => 0, -padx => 5, -command => sub { $chart_engine->set_scale_mode('manual') })->pack(-side => 'left', -padx => 1);

    my $atr_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $atr_box->Label(-text => 'ATR:')->pack(-side => 'left', -padx => 3);
    $atr_box->Radiobutton(-text => 'Auto', -value => 'auto', -variable => \$atr_scale_mode,
        -indicatoron => 0, -padx => 5, -command => sub { $chart_engine->set_atr_scale_mode('auto') })->pack(-side => 'left', -padx => 1);
    $atr_box->Radiobutton(-text => 'Manual', -value => 'manual', -variable => \$atr_scale_mode,
        -indicatoron => 0, -padx => 5, -command => sub { $chart_engine->set_atr_scale_mode('manual') })->pack(-side => 'left', -padx => 1);

    $p->Button(-text => 'Reset Vista', -command => sub { $chart_engine->reset_view() })
        ->pack(-side => 'left', -padx => 10);

    my $grid_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $grid_box->Label(-text => 'Grid:')->pack(-side => 'left', -padx => 3);
    my $grid_btn;
    $grid_btn = $grid_box->Button(
        -text        => 'Ocultar',
        -padx        => 5,
        -command     => sub {
            my $on = $chart_engine->toggle_grid();
            $grid_btn->configure(-text => $on ? 'Ocultar' : 'Mostrar');
        },
    )->pack(-side => 'left', -padx => 1);
}

# ---- Panel "Replay": barra de controles inline (task 0045; sin << Bar Replay) ----
{
    my $p = $panel{Replay};
    $replay_panel = Market::UI::ReplayPanel->new(
        parent      => $p,
        menu_parent => $mw,
        chart       => $chart_engine,
        mw          => $mw,
        root        => $mw,
        ui_vars     => \%ui_vars,
        inline      => 1,
    );
}

# Mostrar la pestaña inicial.
$show_panel->('Capas');

# ==========================================
# 7. RENDER INICIAL + LOOP
# ==========================================
print "[*] Abriendo ventana...\n";
$mw->update;
my $maximized = eval { $mw->state('zoomed'); 1 };
$maximized ||= eval { $mw->attributes('-zoomed', 1); 1 };
$mw->update if $maximized;
$mw->after(200, sub {
    print "[*] Render inicial (Fase 1: velas + ATR; capas bajo demanda)...\n";
    $chart_engine->render();
    # Precálculo no bloqueante: Liquidez/SMC se alimentan por pedazos mientras la
    # app queda interactiva. Así activar Liquidez o subir densidad no congela la UI.
    $chart_engine->enable_liquidity_background_feed(chunk_size => 300, after_ms => 40)
        if $chart_engine->can('enable_liquidity_background_feed');
    $mw->after(200,  sub { $chart_engine->request_render(); });
    $mw->after(800,  sub { $chart_engine->request_render(); });
});

MainLoop;
