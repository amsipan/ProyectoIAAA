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

my $archivo_csv = 'Data/2026_06_29.csv';
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
my $liq_density_pct = 100;
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
$panel{$_} = $panel_row->Frame() for qw(Capas Liq Mxwll ZigZag Escala Replay);

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
my $tabs_box = $tab_row->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 8);
for my $name (qw(Capas Liq Mxwll ZigZag Escala Replay)) {
    $tabs_box->Radiobutton(
        -text => $name, -value => $name, -variable => \$active_tab,
        -indicatoron => 0, -padx => 8, -pady => 1,
        -command => sub {
            $show_panel->($name);
            $cb_replay_activate->() if $name eq 'Replay';
        },
    )->pack(-side => 'left', -padx => 1);
}

# ---- Panel "Capas": overlays principales + HTF ----
{
    my $p = $panel{Capas};
    $p->Label(-text => 'Capas:')->pack(-side => 'left', -padx => 3);
    $p->Checkbutton(-text => 'SMC', -variable => \$vis_smc,
        -command => sub { $cb_smc->($vis_smc ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'Liquidez', -variable => \$vis_liq,
        -command => sub { $cb_liq->($vis_liq ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'Estrategia', -variable => \$vis_strategy,
        -command => sub { $cb_strategy->($vis_strategy ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'Perfil Vol', -variable => \$vis_vp,
        -command => sub { $cb_vp->($vis_vp ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'VWAP', -variable => \$vis_vwap,
        -command => sub { $cb_vwap->($vis_vwap ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'Mxwll', -variable => \$vis_mxwll,
        -command => sub { $cb_mxwll->($vis_mxwll ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'ZigZag', -variable => \$vis_zigzag,
        -command => sub { $cb_zigzag->($vis_zigzag ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'HTF sobre LTF', -variable => \$htf_enabled,
        -command => sub { $cb_htf->($htf_enabled ? 1 : 0); })->pack(-side => 'left', -padx => 6);
}

# ---- Panel "Liq": sub-filtros de liquidez ----
{
    my $p = $panel{Liq};
    $p->Label(-text => 'Liq:')->pack(-side => 'left', -padx => 3);
    for my $elem (qw(BSL SSL EQH EQL SWEEP GRAB RUN)) {
        $p->Checkbutton(-text => $elem, -variable => \$vis_elem{$elem},
            -command => sub { $cb_elem{$elem}->($vis_elem{$elem} ? 1 : 0); })->pack(-side => 'left');
    }
    $p->Label(-text => 'Densidad %')->pack(-side => 'left', -padx => 6);
    $p->Scale(
        -from     => 1,
        -to       => 100,
        -orient   => 'horizontal',
        -length   => 120,
        -variable => \$liq_density_pct,
        -command  => sub {
            my $v = shift;
            $v = $liq_density_pct unless defined $v;
            my $liq = $chart_engine->{liq_overlay};
            return unless $liq && $liq->can('set_density_pct');
            $liq->set_density_pct($v);
            $chart_engine->request_render();
        },
    )->pack(-side => 'left', -padx => 2);
}

# ---- Panel "Mxwll": sub-filtros de la capa Mxwll (ORDEN 9 / task 0021 I) ----
{
    my $p = $panel{Mxwll};
    my %mx_label = (
        STRUCTURE => 'Estr', SWINGS => 'Swings', OB => 'OB',
        FVG => 'FVG', AOE => 'AOE', FIBS => 'Fibs', STRONG_WEAK => 'S/W',
    );
    $p->Label(-text => 'Mxwll:')->pack(-side => 'left', -padx => 3);
    for my $elem (qw(STRUCTURE SWINGS OB FVG AOE FIBS STRONG_WEAK)) {
        $p->Checkbutton(-text => $mx_label{$elem}, -variable => \$vis_mxelem{$elem},
            -command => sub { $cb_mxelem{$elem}->($vis_mxelem{$elem} ? 1 : 0); })->pack(-side => 'left');
    }
}

# ---- Panel "ZigZag": interno/externo + resolución MTF (task 0033) ----
{
    my $p = $panel{ZigZag};
    $p->Label(-text => 'ZigZag:')->pack(-side => 'left', -padx => 3);
    $p->Checkbutton(-text => 'Interno', -variable => \$vis_zzelem{INTERNAL},
        -command => sub { $cb_zzelem{INTERNAL}->($vis_zzelem{INTERNAL} ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'Externo', -variable => \$vis_zzelem{EXTERNAL},
        -command => sub { $cb_zzelem{EXTERNAL}->($vis_zzelem{EXTERNAL} ? 1 : 0); })->pack(-side => 'left', -padx => 4);
    $p->Checkbutton(-text => 'Canal', -variable => \$vis_zzelem{CHANNEL},
        -command => sub { $cb_zzelem{CHANNEL}->($vis_zzelem{CHANNEL} ? 1 : 0); })->pack(-side => 'left', -padx => 4);
    $p->Label(-text => 'Res MTF:')->pack(-side => 'left', -padx => 3);
    for my $res (qw(15 30 60)) {
        $p->Radiobutton(-text => "${res}m", -value => $res, -variable => \$zigzag_resolution,
            -indicatoron => 0, -padx => 4,
            -command => sub { $cb_zzres{$res}->(); })->pack(-side => 'left');
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
    $mw->after(200,  sub { $chart_engine->request_render(); });
    $mw->after(800,  sub { $chart_engine->request_render(); });
});

MainLoop;
