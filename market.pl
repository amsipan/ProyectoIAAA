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

# Dataset largo (1m): Abr–Jul 2026 (~100k velas) para probar TF altos (1h/4h/D/W).
# Mar + Abr–Jul 2026 (warm-up). TV aún tiene más historial pre-2026.
my @csv_hist = ('Data/2026_03.csv', 'Data/2026_04_to_07.csv');
print "[*] Leyendo base de datos histórica...\n";
for my $archivo_csv (@csv_hist) {
    next unless -f $archivo_csv;
    open my $fh, '<', $archivo_csv or die "CRÍTICO: No se pudo abrir $archivo_csv: $!";
    my $header = <$fh>;
    while (my $linea = <$fh>) {
        chomp $linea;
        my @columnas = split /,/, $linea;
        $market_data->add_candle(\@columnas);
    }
    close $fh;
    print "[*]   + $archivo_csv\n";
}

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
# spec 0013: SMC Pro + FVG(Structures); Mxwll eliminado de la UI de producto.
my $vis_smc_pro = 0;
my $vis_smc_fvg = 0;
my $vis_liq = 0;
my $vis_strategy = 0;
my $vis_vp = 0;
my $vis_vwap = 0;
my $vis_zigzag = 0;
my %vis_elem = map { $_ => 1 } qw(BSL SSL EQH EQL SWEEP GRAB RUN);
# Densidad: funcionalidad a eliminar. No panel UI. No usar en paridad SMC/TV
# ni en features nuevas. API interna Liq/ZigZag queda al 100% (sin recorte)
# hasta borrar el código en una iteración posterior.
if ($chart_engine->{liq_overlay} && $chart_engine->{liq_overlay}->can('set_density_pct')) {
    $chart_engine->{liq_overlay}->set_density_pct(100);
}
if ($chart_engine->{zigzag_overlay} && $chart_engine->{zigzag_overlay}->can('set_density_pct')) {
    $chart_engine->{zigzag_overlay}->set_density_pct(100);
}
my %vis_zzelem = ( INTERNAL => 1, EXTERNAL => 1, CHANNEL => 0 );
my $zigzag_resolution = 30;

# Callbacks (factorías testeadas headless). F1: SIEMPRE pasamos el valor de la
# -variable explícito al callback (Tk no lo pasa solo en -command).
my $cb_smc_pro = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'smc_pro');
my $cb_smc_fvg = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'smc_fvg');
my $cb_liq = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'liq');
my $cb_strategy = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'strategy');
my $cb_vwap = Market::UI::Callbacks->make_vwap_toggle($chart_engine);
my $cb_vwap_reanchor = Market::UI::Callbacks->make_vwap_reanchor($chart_engine);
my $cb_vwap_band = Market::UI::Callbacks->make_vwap_band_setter($chart_engine);
# Defaults TradingView Anchored VWAP (captura profe): #1 on mult=1, #2/#3 off.
my %vwap_band_on   = (1 => 1, 2 => 0, 3 => 0);
my %vwap_band_mult = (1 => '1', 2 => '2', 3 => '3');
my $cb_vp = Market::UI::Callbacks->make_vp_toggle($chart_engine);
my $cb_vp_reanchor = Market::UI::Callbacks->make_vp_reanchor($chart_engine);
my $cb_vp_settings = Market::UI::Callbacks->make_vp_settings_setter($chart_engine);
# Defaults TV AVP: Number of Rows=24, Value Area=70, Volume=Total (azul).
my $vp_row_size = '24';
my $vp_va_pct   = '70';
my $cb_zigzag = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'zigzag');
my %cb_elem = map { $_ => Market::UI::Callbacks->make_liq_element_toggle($chart_engine, $_) }
              qw(BSL SSL EQH EQL SWEEP GRAB RUN);
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
    smc_pro => \$vis_smc_pro, smc_fvg => \$vis_smc_fvg,
    liq => \$vis_liq, strategy => \$vis_strategy,
    vp => \$vis_vp, vwap => \$vis_vwap, zigzag => \$vis_zigzag,
);
my %overlay_cb = (
    smc_pro => $cb_smc_pro, smc_fvg => $cb_smc_fvg,
    liq => $cb_liq, strategy => $cb_strategy,
    vp => $cb_vp, vwap => $cb_vwap, zigzag => $cb_zigzag,
);
# cb_vp ya es make_vp_toggle (ancla), no make_overlay_toggle genérico.
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
$panel{$_} = $panel_row->Frame() for qw(Capas SMC Liq ZigZag Estrategia Escala Replay);

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
    ZigZag    => 'ZigZag',
    Estrategia=> 'Estrategia',
    Escala    => 'Escala',
    Replay    => 'Replay',
);
my $tabs_box = $tab_row->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 5);
for my $name (qw(Capas SMC Liq ZigZag Estrategia Escala Replay)) {
    $tabs_box->Radiobutton(
        -text => $tab_label{$name}, -value => $name, -variable => \$active_tab,
        -indicatoron => 0, -padx => 8, -pady => 1,
        -command => sub {
            $show_panel->($name);
            $cb_replay_activate->() if $name eq 'Replay';
        },
    )->pack(-side => 'left', -padx => 1);
}

# Recargar app: reinicio TOTAL del proceso (código nuevo 100%).
# En Windows+Tk, exec() a menudo NO reemplaza el proceso GUI y parece que
# "no cargan los cambios". Flujo fiable: destroy UI → spawn proceso nuevo → exit.
# (Panel Densidad eliminado de la UI — a borrar por completo más adelante.)
my $reload_app = sub {
    require Cwd;
    require File::Spec;
    require File::Basename;

    my $script = $0;
    if ($script !~ m{^/} && $script !~ m{^[A-Za-z]:}) {
        $script = Cwd::abs_path($script) // $script;
    }
    $script = File::Spec->rel2abs($script);

    my $dir = File::Basename::dirname($script);
    chdir $dir if length $dir && -d $dir;

    my $perl = $^X;
    if ($perl !~ m{^/} && $perl !~ m{^[A-Za-z]:}) {
        $perl = Cwd::abs_path($perl) // $perl;
    }
    $perl = File::Spec->rel2abs($perl);

    my $lib_flag = '-I' . $dir;
    print "[*] RELOAD: perl=$perl\n";
    print "[*] RELOAD: script=$script\n";
    print "[*] RELOAD: lib=$dir\n";
    print "[*] RELOAD: destroying UI and spawning fresh process...\n";
    STDOUT->flush if STDOUT->can('flush');
    STDERR->flush if STDERR->can('flush');

    # Soltar display Tk antes de spawn (crítico en Windows).
    eval {
        $mw->withdraw if $mw && $mw->can('withdraw');
        $mw->update  if $mw && $mw->can('update');
        $mw->destroy if $mw && $mw->can('destroy');
        1;
    };

    local $ENV{MARKET_RELOAD} = 1;
    my @cmd = ($perl, $lib_flag, $script);

    # Windows: system(1, LIST) = create process sin wait; luego exit del padre.
    if ($^O =~ /MSWin32|msys|cygwin/i) {
        my $pid = eval { system(1, @cmd) };
        if (!defined $pid || $pid == 0 || $pid == -1) {
            # Fallback: intentar exec; si falla, system bloqueante no sirve.
            exec { $cmd[0] } @cmd;
            warn "[!] RELOAD falló: $! (@cmd)\n";
            exit 1;
        }
        print "[*] RELOAD: spawned pid=$pid — exiting old process\n";
        exit 0;
    }

    # Unix/WSL: reemplazo in-place; si falla, spawn + exit.
    exec { $cmd[0] } @cmd;
    warn "[!] exec falló ($!), intentando system...\n";
    my $rc = system { $cmd[0] } @cmd;
    exit($rc == 0 ? 0 : 1);
};
$tab_row->Button(
    -text    => 'Recargar',
    -padx    => 4,
    -pady    => 0,
    -relief  => 'groove',
    -command => $reload_app,
)->pack(-side => 'right', -padx => 3);

if ($ENV{MARKET_RELOAD}) {
    print "[*] RELOAD: fresh process started (MARKET_RELOAD=1)\n";
}

# ---- Panel "Capas": overlays principales + HTF ----
{
    my $p = $panel{Capas};
    $p->Label(-text => 'Capas:')->pack(-side => 'left', -padx => 3);
    $p->Checkbutton(-text => 'SMC Pro', -variable => \$vis_smc_pro,
        -command => sub { $set_overlay_visible->('smc_pro', $vis_smc_pro ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'FVG (Structures)', -variable => \$vis_smc_fvg,
        -command => sub { $set_overlay_visible->('smc_fvg', $vis_smc_fvg ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'Liquidez', -variable => \$vis_liq,
        -command => sub { $set_overlay_visible->('liq', $vis_liq ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'Estrategia', -variable => \$vis_strategy,
        -command => sub { $set_overlay_visible->('strategy', $vis_strategy ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'Perfil Vol', -variable => \$vis_vp,
        -command => sub { $set_overlay_visible->('vp', $vis_vp ? 1 : 0); })->pack(-side => 'left');
    my $vp_hint;
    my $set_vp_hint = sub {
        my ($on) = @_;
        return unless $vp_hint;
        if ($on) {
            $vp_hint->configure(-text => 'Clic vela AVP… (Esc)', -fg => '#01579B');
        } else {
            $vp_hint->configure(-text => '', -fg => '#666666');
        }
    };
    $chart_engine->{vp_select_mode_callback} = sub { $set_vp_hint->($_[0] ? 1 : 0); };
    $chart_engine->{vp_anchor_callback} = sub { $set_vp_hint->(0); };
    $chart_engine->{vp_select_cancel_callback} = sub { $set_vp_hint->(0); };
    $p->Button(
        -text => 'Anclar VP',
        -command => sub {
            $vis_vp = 1;
            $cb_vp_reanchor->();
            $refresh_overlay_button->('vp') if $overlay_button{vp};
            $set_vp_hint->(1);
        },
    )->pack(-side => 'left', -padx => 2);
    $vp_hint = $p->Label(-text => '', -fg => '#01579B', -font => ['Helvetica', 9, 'bold'])
        ->pack(-side => 'left', -padx => 2);
    # AVP Inputs (TV): Row Size + Value Area %
    my $vp_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 3);
    $vp_box->Label(-text => 'Rows:')->pack(-side => 'left', -padx => 1);
    my $vp_rows_ent = $vp_box->Entry(-textvariable => \$vp_row_size, -width => 5, -justify => 'right');
    $vp_rows_ent->pack(-side => 'left', -padx => 1);
    $vp_box->Label(-text => 'VA%:')->pack(-side => 'left', -padx => 1);
    my $vp_va_ent = $vp_box->Entry(-textvariable => \$vp_va_pct, -width => 3, -justify => 'right');
    $vp_va_ent->pack(-side => 'left', -padx => 1);
    my $apply_vp_settings = sub {
        my $rs = $vp_row_size;
        $rs = '24' if !defined $rs || $rs eq '';
        $rs =~ s/,/./g;
        $rs = 24 unless $rs =~ /^\d+$/;
        $rs = 1 if $rs < 1;
        $rs = 5000 if $rs > 5000;
        $vp_row_size = $rs;
        my $va = $vp_va_pct;
        $va = '70' if !defined $va || $va eq '';
        $va =~ s/,/./g;
        $va = 70 unless $va =~ /^\d+\.?\d*$/;
        $va = 1 if $va < 1;
        $va = 100 if $va > 100;
        $vp_va_pct = $va;
        $cb_vp_settings->(row_size => $rs, value_area_pct => $va);
    };
    $vp_rows_ent->Tk::bind('<Return>', $apply_vp_settings);
    $vp_rows_ent->Tk::bind('<FocusOut>', $apply_vp_settings);
    $vp_va_ent->Tk::bind('<Return>', $apply_vp_settings);
    $vp_va_ent->Tk::bind('<FocusOut>', $apply_vp_settings);
    # Aplicar defaults al arranque
    $apply_vp_settings->();

    $p->Checkbutton(-text => 'VWAP', -variable => \$vis_vwap,
        -command => sub { $set_overlay_visible->('vwap', $vis_vwap ? 1 : 0); })->pack(-side => 'left');
    my $vwap_hint;
    my $set_vwap_hint = sub {
        my ($on) = @_;
        return unless $vwap_hint;
        if ($on) {
            $vwap_hint->configure(
                -text => 'Clic en una vela… (Esc cancela)',
                -fg   => '#0D47A1',
            );
        }
        else {
            $vwap_hint->configure(-text => '', -fg => '#666666');
        }
    };
    $chart_engine->{vwap_select_mode_callback} = sub {
        my ($on) = @_;
        $set_vwap_hint->($on ? 1 : 0);
    };
    $chart_engine->{vwap_anchor_callback} = sub {
        $set_vwap_hint->(0);
    };
    $chart_engine->{vwap_select_cancel_callback} = sub {
        $set_vwap_hint->(0);
    };

    $p->Button(
        -text => 'Anclar VWAP',
        -command => sub {
            $vis_vwap = 1;
            $cb_vwap_reanchor->();
            $refresh_overlay_button->('vwap') if $overlay_button{vwap};
            $set_vwap_hint->(1);
        },
    )->pack(-side => 'left', -padx => 2);
    $vwap_hint = $p->Label(
        -text   => '',
        -fg     => '#0D47A1',
        -font   => ['Helvetica', 9, 'bold'],
    )->pack(-side => 'left', -padx => 4);

    # Anchored VWAP — Bands Settings (como Inputs de TradingView)
    my $vwap_bands = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $vwap_bands->Label(-text => 'Bands:')->pack(-side => 'left', -padx => 2);
    for my $n (1, 2, 3) {
        my $row = $vwap_bands->Frame()->pack(-side => 'left', -padx => 2);
        $row->Checkbutton(
            -text     => "#$n",
            -variable => \$vwap_band_on{$n},
            -command  => sub {
                $cb_vwap_band->($n,
                    on   => $vwap_band_on{$n} ? 1 : 0,
                    mult => $vwap_band_mult{$n},
                );
            },
        )->pack(-side => 'left');
        my $ent = $row->Entry(
            -textvariable => \$vwap_band_mult{$n},
            -width        => 3,
            -justify      => 'right',
        );
        $ent->pack(-side => 'left', -padx => 1);
        # Aplicar mult al salir del campo o Enter (sin Optionmenu: WSLg-safe).
        my $apply_mult = sub {
            my $raw = $vwap_band_mult{$n};
            $raw = '1' if !defined $raw || $raw eq '';
            $raw =~ s/,/./g;
            unless ($raw =~ /^-?\d*\.?\d+$/) {
                $vwap_band_mult{$n} = $n;  # reset default TV
                $raw = $n;
            }
            my $m = 0 + $raw;
            $m = 0.01 if $m < 0.01;
            $vwap_band_mult{$n} = $m;
            $cb_vwap_band->($n, on => $vwap_band_on{$n} ? 1 : 0, mult => $m);
        };
        $ent->Tk::bind('<Return>', $apply_mult);
        $ent->Tk::bind('<FocusOut>', $apply_mult);
    }

    $p->Checkbutton(-text => 'ZigZag', -variable => \$vis_zigzag,
        -command => sub { $set_overlay_visible->('zigzag', $vis_zigzag ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'HTF sobre LTF', -variable => \$htf_enabled,
        -command => sub { $cb_htf->($htf_enabled ? 1 : 0); })->pack(-side => 'left', -padx => 6);
}

# ---- Panel "SMC": solo las 2 capas TV (Neon + Structures/FVG), config capturas ----
{
    my $p = $panel{SMC};
    my $main_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $main_box->Label(-text => 'SMC TV:')->pack(-side => 'left', -padx => 3);
    $overlay_button{smc_pro} = $main_box->Button(
        -text => $overlay_button_text->($vis_smc_pro),
        -command => sub { $toggle_overlay_visible->('smc_pro'); },
    )->pack(-side => 'left', -padx => 2);
    $main_box->Label(-text => 'SMC Pro')->pack(-side => 'left');
    $overlay_button{smc_fvg} = $main_box->Button(
        -text => $overlay_button_text->($vis_smc_fvg),
        -command => sub { $toggle_overlay_visible->('smc_fvg'); },
    )->pack(-side => 'left', -padx => 2);
    $main_box->Label(-text => 'FVG Structures')->pack(-side => 'left');
    my $info_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $info_box->Label(
        -text => 'Config = capturas profe (Neon + LudoGH). Sin Mxwll. Sin density filter.',
        -font => ['Helvetica', 8],
    )->pack(-side => 'left', -padx => 3);
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
