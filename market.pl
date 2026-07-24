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
# Producto oficial: ATR al arranque; capas SMC/ZZ/HLD/Liquidity v2 bajo demanda
# (docs/PRODUCTO_OFICIAL.md). Legacy Mxwll/VP/VWAP no se cargan.
my $market_data = Market::MarketData->new();
my $indicator_manager = Market::IndicatorManager->new();
$indicator_manager->register('ATR', Market::Indicators::ATR->new(14));

# Dataset por defecto: Data/2026_07_20.csv (NQ1! 1m, ISO UTC-5, volumen real).
# Base nativa = 1m; 5m/15m/1h/2h/4h/D/W se agregan desde 1m.
# El export 15m y los CSV antiguos quedan como opción/fallback dentro de Data/.
# Copia portable en Data/; fallback a Downloads si falta la copia.
my $tv_src = 'C:/Users/bryan/Downloads/CME_MINI_DL_NQ1!, 1.csv';
my $tv_dst = 'Data/tv_nq1_1m.csv';
if (-f $tv_src && !-f $tv_dst) {
    require File::Copy;
    File::Copy::copy($tv_src, $tv_dst)
        or warn "[!] No se pudo copiar $tv_src → $tv_dst: $!\n";
    print "[*] CSV TV 1m copiado a $tv_dst\n" if -f $tv_dst;
}

my @csv_candidates = (
    'Data/2026_07_20.csv',      # default: 1–20 julio 2026, 1m y volumen real
    $tv_dst,                    # fallback: export TV 1m anterior
    $tv_src,
    'Data/tv_nq1_15m.csv',      # opción: export TV 15m
    # Fallbacks legacy (solo si no hay export TV)
    'Data/2026_06.csv',
    'C:/Users/bryan/Downloads/Proyecto/2026_06.csv',
);
my $archivo_csv;
for my $cand (@csv_candidates) {
    if (-f $cand) { $archivo_csv = $cand; last; }
}
die "CRÍTICO: no se encontró dataset (2026_07_20.csv, tv_nq1_1m.csv, tv_nq1_15m.csv ni 2026_06.csv)\n"
    unless defined $archivo_csv;

# Detectar base por nombre: *15m* → base 15m; si no (1m u otros) → 1m.
my $base_tf = '1m';
if ($archivo_csv =~ /15m|_15\.csv|, 15\.csv/i) {
    $base_tf = '15m';
}
$market_data->set_base_timeframe($base_tf);

print "[*] Leyendo dataset (base=$base_tf)...\n";
open my $fh, '<', $archivo_csv or die "CRÍTICO: No se pudo abrir $archivo_csv: $!";
my $header = <$fh>;  # time,open,high,low,close,Plot|Volume
my $n_file = 0;
my ($ts_first, $ts_last);
while (my $linea = <$fh>) {
    chomp $linea;
    $linea =~ s/\r//g;
    my @columnas = split /,/, $linea;
    next if @columnas < 5;
    # TV export: 6ª col a menudo vacía (header "Plot") → volume 0
    my $vol = 0;
    if (defined $columnas[5] && $columnas[5] =~ /^-?\d+(?:\.\d+)?$/) {
        $vol = 0 + $columnas[5];
    }
    my $candle = [ @columnas[0 .. 4], $vol ];
    $ts_first = $candle->[0] if !defined $ts_first;
    $ts_last  = $candle->[0];
    $market_data->add_candle($candle);
    $n_file++;
}
close $fh;
print "[*]   archivo : $archivo_csv\n";
print "[*]   base_tf : $base_tf\n";
print "[*]   velas   : $n_file\n";
print "[*]   first   : ", ($ts_first // '?'), "\n";
print "[*]   last    : ", ($ts_last  // '?'), "\n";
$market_data->build_timeframes();  # lazy no-op; eager=>1 solo si se necesita todo
$market_data->set_timeframe($base_tf);
print "[*] Velas en memoria ($base_tf): ", $market_data->size(), " (TF altos se construyen al usarlos)\n";
print "[*] Calculando ATR $base_tf...\n";
for (my $i = 0; $i < $market_data->size(); $i++) {
    $indicator_manager->update_last($market_data, $i);   # ATR es O(1)/vela
}
print "[*] Listo — abriendo UI en $base_tf\n";

# ==========================================
# 2. VENTANA PRINCIPAL
# ==========================================
my $mw = MainWindow->new;
$mw->title("IAAA — Motor de Charting (EPN 2026A)");
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
# Esquina inferior derecha (intersección eje precio × eje tiempo): aloja el
# toggle A/M del modo de escala de precio (estilo TradingView). Se cablea más
# abajo, tras crear $chart_engine.
my $price_mode_corner = $time_frame->Frame(
    -width => $right_axis_width, -height => $time_axis_height, -background => $theme{bg},
    -relief => 'sunken', -bd => 1,
)->pack(-side => 'right', -fill => 'y');
$price_mode_corner->packPropagate(0);
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
my $active_tf = $base_tf;  # UI resalta el TF base (15m con export TV)
my $replay_on   = 0;
my $replay_select_mode = 0;
my $replay_watermark_on = 0;   # marca de agua "Replay" oculta por defecto; se activa con Mark/tecla M
my $replay_panel;
my %ui_vars = (
    active_tf => \$active_tf, replay_on => \$replay_on,
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
    replay_select_mode_callback => sub {
        $replay_select_mode = $_[0] ? 1 : 0;
        # Feedback visual: resaltar "Select bar" mientras el modo está activo.
        if ($replay_panel && ref($replay_panel) && $replay_panel->can('sync_select_bar_button')) {
            $replay_panel->sync_select_bar_button($replay_select_mode);
        }
    },
    theme             => \%theme
);

$chart_engine->{replay_watermark_on_ref} = \$replay_watermark_on;
$chart_engine->{replay_on_ref} = \$replay_on;
$chart_engine->{plot_frames} = [$price_frame, $atr_frame];
# Referencia del frame ATR para poder ocultarlo/mostrarlo (toggle UI).
$chart_engine->{atr_frame} = $atr_frame;
$chart_engine->init_plot_cursors();

# --- Toggle A/M del modo de escala de PRECIO (esquina inf. derecha, estilo TV) ---
# A = automático, M = manual. El botón activo se resalta. Estos botones y el
# modo de escala comparten los mismos callbacks para no desincronizarse.
my $PMODE_ON_BG   = '#2962ff';   # activo
my $PMODE_ON_FG   = '#ffffff';
my $PMODE_OFF_BG  = '#e9edf3';   # inactivo
my $PMODE_OFF_FG  = '#1c2431';
my ($price_mode_A, $price_mode_M);
my $refresh_price_mode_buttons = sub {
    my $auto = ($scale_mode eq 'auto');
    $price_mode_A->configure(-bg => $auto ? $PMODE_ON_BG : $PMODE_OFF_BG,
                             -fg => $auto ? $PMODE_ON_FG : $PMODE_OFF_FG) if $price_mode_A;
    $price_mode_M->configure(-bg => !$auto ? $PMODE_ON_BG : $PMODE_OFF_BG,
                             -fg => !$auto ? $PMODE_ON_FG : $PMODE_OFF_FG) if $price_mode_M;
};
my $set_price_mode = sub {
    my ($mode) = @_;
    $chart_engine->set_scale_mode($mode);   # actualiza $scale_mode vía callback
    $refresh_price_mode_buttons->();
};
$price_mode_A = $price_mode_corner->Button(
    -text => 'A', -font => [ 'Helvetica', 8, 'bold' ],
    -bd => 1, -relief => 'raised', -padx => 1, -pady => 0, -highlightthickness => 0,
    -command => sub { $set_price_mode->('auto'); },
)->pack(-side => 'left', -expand => 1, -fill => 'both');
$price_mode_M = $price_mode_corner->Button(
    -text => 'M', -font => [ 'Helvetica', 8, 'bold' ],
    -bd => 1, -relief => 'raised', -padx => 1, -pady => 0, -highlightthickness => 0,
    -command => sub { $set_price_mode->('manual'); },
)->pack(-side => 'left', -expand => 1, -fill => 'both');
$refresh_price_mode_buttons->();

$chart_engine->{replay_bar_selected_callback} = sub {
    Market::UI::Callbacks->replay_confirm_bar_selection($chart_engine, \%ui_vars);
};

$ui_vars{mw} = $mw;

$chart_engine->bind_replay_window_shortcuts($mw);

$mw->Tk::bind('<Configure>', sub { $chart_engine->request_render(); });

# Capas producto oficial (OFF por defecto). Ver docs/PRODUCTO_OFICIAL.md
my $vis_smc_pro = 0;
my $vis_smc_fvg = 0;
my $vis_hld     = 0;
my $vis_liq     = 0;
my $vis_diy     = 0;
my $vis_vp      = 0;
my $vis_zz_ext = 0;
my $vis_zz_int = 0;
my $vis_zigzag = 0;    # true si alguna capa ZZ está ON
if ($chart_engine->{zigzag_overlay} && $chart_engine->{zigzag_overlay}->can('set_density_pct')) {
    $chart_engine->{zigzag_overlay}->set_density_pct(100);
}
my %vis_zzelem = ( INTERNAL => 0, EXTERNAL => 0, CHANNEL => 0 );
my %vis_liq_el = map { $_ => 1 } qw(BSL SSL EQH EQL SWEEP GRAB RUN);
$vis_liq_el{HISTORY} = 0;    # niveles archivados (resolved) — demo profe
my $zigzag_resolution = 30;
my $fib_extend_to_last = 0;
# Pivot Points High Low & Missed (fantasmas) — LuxAlgo. Ancla del VWAP.
my $vis_pph       = 0;
my $pph_show_reg  = 1;   # pivots regulares ▼▲
my $pph_show_miss = 1;   # pivots perdidos 👻
my $pph_show_rastro = 1; # rastro "1" (Josafa)

my $cb_smc_pro = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'smc_pro');
my $cb_smc_fvg = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'smc_fvg');
my $cb_hld     = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'hld');
my $cb_liq     = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'liq');
my $cb_diy     = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'diy');
my $cb_vp      = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'volumeprofile');
my $cb_pph     = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'pivotpointshl');
my $cb_zigzag = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'zigzag');
my %cb_zzelem = map { $_ => Market::UI::Callbacks->make_zigzag_element_toggle($chart_engine, $_) }
                qw(INTERNAL EXTERNAL CHANNEL);
my %cb_liq_el = map {
    $_ => Market::UI::Callbacks->make_liq_element_toggle($chart_engine, $_)
} qw(BSL SSL EQH EQL SWEEP GRAB RUN HISTORY);
my %overlay_state_ref = (
    smc_pro => \$vis_smc_pro, smc_fvg => \$vis_smc_fvg, hld => \$vis_hld,
    liq => \$vis_liq, diy => \$vis_diy, volumeprofile => \$vis_vp, zigzag => \$vis_zigzag,
);
my %overlay_cb = (
    smc_pro => $cb_smc_pro, smc_fvg => $cb_smc_fvg, hld => $cb_hld,
    liq => $cb_liq, diy => $cb_diy, volumeprofile => $cb_vp, zigzag => $cb_zigzag,
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
               qw(15 30 60 120);
# Toggle por capa ZZ (INTERNAL / EXTERNAL) con re-feed on-demand
my $set_zz_layer = sub {
    my ( $elem, $on ) = @_;
    $elem = uc( $elem // '' );
    return unless $elem eq 'INTERNAL' || $elem eq 'EXTERNAL';
    $on = $on ? 1 : 0;
    if ( $elem eq 'INTERNAL' ) {
        $vis_zz_int = $on;
        $vis_zzelem{INTERNAL} = $on;
    }
    else {
        $vis_zz_ext = $on;
        $vis_zzelem{EXTERNAL} = $on;
    }
    $vis_zigzag = ( $vis_zz_int || $vis_zz_ext ) ? 1 : 0;
    if ( $chart_engine->can('set_zigzag_layer') ) {
        $chart_engine->set_zigzag_layer( $elem, $on );
    }
    elsif ( $cb_zzelem{$elem} ) {
        $cb_zzelem{$elem}->($on);
    }
};
# Fib "Fib ZZ ext" activa el overlay externo → marcar checkbox en la UI
$chart_engine->{zz_external_ui_sync} = sub {
    my ($on) = @_;
    $on = $on ? 1 : 0;
    $vis_zz_ext = $on;
    $vis_zzelem{EXTERNAL} = $on;
    $vis_zigzag = ( $vis_zz_int || $vis_zz_ext ) ? 1 : 0;
};
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
# la pantalla (TF + capas + liq + mxwll no cabían). Ahora:
#   - FILA SUPERIOR (siempre visible): selector TF + botones de PESTAÑA.
#   - FILA INFERIOR (área de panel): muestra SOLO el panel de la pestaña activa.
# Se emula un "notebook" con Frames + pack/packForget (NO se usa menubar nativo,
# Optionmenu ni Tk::NoteBook: bajo WSLg abren ventanas X aparte y fallan).
my $tab_row   = $frame_controles->Frame()->pack(-side => 'top', -fill => 'x', -pady => 1);
my $panel_row = $frame_controles->Frame()->pack(-side => 'top', -fill => 'x', -pady => 1);

# Reset Vista: siempre visible (cualquier pestaña), abajo-derecha bajo el ↻.
$panel_row->Button(
    -text    => 'Reset Vista',
    -padx    => 5,
    -pady    => 0,
    -relief  => 'groove',
    -command => sub { $chart_engine->reset_view() },
)->pack( -side => 'right', -padx => 3 );

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

# Opción A: TF siempre visible y pestañas compactas por dominio.
# Replay es pestaña propia (no mezclada con Vista): un clic → Select bar listo.
my %panel;
$panel{$_} = $panel_row->Frame()
  for qw(Estructura Liquidez ZigZag Dibujo Auto Volumen Vista Replay);

my $active_tab = 'Estructura';
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
    $active_tab = 'Estructura';
    $show_panel->('Estructura');
};

my %tab_label = (
    Estructura => 'Estructura',
    Liquidez   => 'Liquidez',
    ZigZag     => 'ZigZag',
    Dibujo     => 'Dibujo',
    Auto       => 'Auto',
    Volumen    => 'Volumen',
    Vista      => 'Vista',
    Replay     => 'Replay',
);
my $tabs_box = $tab_row->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 5);
for my $name (qw(Estructura Liquidez ZigZag Dibujo Auto Volumen Vista Replay)) {
    $tabs_box->Radiobutton(
        -text => $tab_label{$name}, -value => $name, -variable => \$active_tab,
        -indicatoron => 0, -padx => 8, -pady => 1,
        -command => sub {
            # Replay: mostrar controles + preseleccionar Select bar (1 clic desde cualquier pestaña).
            if ( $name eq 'Replay' ) {
                $cb_replay_activate->();
            }
            else {
                $show_panel->($name);
            }
        },
    )->pack(-side => 'left', -padx => 1);
}

# Indicador sutil de sesión Replay (fuera del gráfico: no tapa velas).
# Visible con Select bar o replay truncado; distinto del watermark grande (Mark).
my $replay_badge = $tab_row->Label(
    -text   => '',
    -font   => [ 'Helvetica', 7 ],
    -fg     => '#8a93a0',
    -padx   => 6,
)->pack( -side => 'left', -padx => 2 );
my $replay_badge_was_on;
$chart_engine->{replay_session_badge_sync} = sub {
    my ($on) = @_;
    $on = $on ? 1 : 0;
    return if defined $replay_badge_was_on && $replay_badge_was_on == $on;
    $replay_badge_was_on = $on;
    $replay_badge->configure( -text => $on ? 'Replay' : '' );
};

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
    -text    => '↻',
    -padx    => 7,
    -pady    => 0,
    -relief  => 'groove',
    -command => $reload_app,
)->pack(-side => 'right', -padx => 3);

if ($ENV{MARKET_RELOAD}) {
    print "[*] RELOAD: fresh process started (MARKET_RELOAD=1)\n";
}

# ============================================================================
# OPCIÓN A: cinco pestañas por dominio (compactas para 14"). Cada control y
# callback se conserva; solo se reorganizan por grupo temático.
# ============================================================================

# ---- Pestaña "Estructura": SMC Pro / Structures+FVG / HLD ----
{
    my $p = $panel{Estructura};
    my $box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $box->Label(-text => 'SMC:')->pack(-side => 'left', -padx => 3);
    $box->Checkbutton(-text => 'SMC Pro', -variable => \$vis_smc_pro,
        -command => sub { $set_overlay_visible->('smc_pro', $vis_smc_pro ? 1 : 0); })->pack(-side => 'left');
    $box->Checkbutton(-text => 'SMC Structures+FVG', -variable => \$vis_smc_fvg,
        -command => sub { $set_overlay_visible->('smc_fvg', $vis_smc_fvg ? 1 : 0); })->pack(-side => 'left');
    $box->Checkbutton(-text => 'HLD (4h/D)', -variable => \$vis_hld,
        -command => sub { $set_overlay_visible->('hld', $vis_hld ? 1 : 0); })->pack(-side => 'left');

    # Order Blocks: interno / externo (swing). Defaults ambos ON (demo profe).
    # Neon: Int ON / Swing OFF — volver vía args del indicador.
    # Toggle exige reset+refeed porque _store_order_block filtra al crear.
    my $smc_ob_int = 1;
    my $smc_ob_ext = 1;
    my $apply_smc_ob = sub {
        my $ind = $chart_engine->{smc_pro_indicator} // $chart_engine->{smc_indicator};
        return unless $ind;
        $ind->{show_internal_ob} = $smc_ob_int ? 1 : 0;
        $ind->{show_swing_ob}    = $smc_ob_ext ? 1 : 0;
        $ind->reset() if $ind->can('reset');
        $chart_engine->{_smc_fed_up_to}     = -1;
        $chart_engine->{_smc_pro_fed_up_to} = -1;
        $chart_engine->request_render();
    };
    my $ob_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $ob_box->Label(-text => 'OB:', -fg => '#555')->pack(-side => 'left', -padx => 2);
    $ob_box->Checkbutton(
        -text     => 'OB int',
        -variable => \$smc_ob_int,
        -command  => $apply_smc_ob,
    )->pack(-side => 'left');
    $ob_box->Checkbutton(
        -text     => 'OB ext',
        -variable => \$smc_ob_ext,
        -command  => $apply_smc_ob,
    )->pack(-side => 'left');

    my $info_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $info_box->Label(
        -text => 'HLD solo en TF 4h o D. R/S de vela HTF más cercana al precio.',
        -font => ['Helvetica', 8],
    )->pack(-side => 'left', -padx => 3);
}

# ---- Pestaña "Liquidez": capa Liquidity + Niveles + Eventos ----
{
    my $p = $panel{Liquidez};
    $p->Checkbutton(
        -text     => 'Liquidity',
        -variable => \$vis_liq,
        -command  => sub { $set_overlay_visible->( 'liq', $vis_liq ? 1 : 0 ); },
    )->pack( -side => 'left', -padx => 3 );

    my $niveles_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $niveles_box->Label(-text => 'Niveles:', -fg => '#555')->pack(-side => 'left', -padx => 2);
    for my $el (qw(BSL SSL EQH EQL)) {
        $niveles_box->Checkbutton(
            -text     => $el,
            -variable => \$vis_liq_el{$el},
            -command  => sub {
                $cb_liq_el{$el}->( $vis_liq_el{$el} ? 1 : 0 ) if $cb_liq_el{$el};
                $chart_engine->request_render();
            },
        )->pack( -side => 'left' );
    }

    my $eventos_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $eventos_box->Label(-text => 'Eventos:', -fg => '#555')->pack(-side => 'left', -padx => 2);
    for my $el (qw(SWEEP GRAB RUN HISTORY)) {
        my $txt = $el eq 'HISTORY' ? 'Historial' : $el;
        $eventos_box->Checkbutton(
            -text     => $txt,
            -variable => \$vis_liq_el{$el},
            -command  => sub {
                $cb_liq_el{$el}->( $vis_liq_el{$el} ? 1 : 0 ) if $cb_liq_el{$el};
                $chart_engine->request_render();
            },
        )->pack( -side => 'left' );
    }
}

# ---- Pestaña "ZigZag": solo ZZ interno/externo (Canal/Trend/Fib → "Dibujo") ----
{
    my $p = $panel{ZigZag};
    # ZigZag interno ZZMTF (Show ZZ ON; fib OFF; verde/rojo; res 15/30/60)
    $p->Checkbutton(
        -text     => 'ZigZag interno',
        -variable => \$vis_zz_int,
        -command  => sub { $set_zz_layer->( 'INTERNAL', $vis_zz_int ? 1 : 0 ); },
    )->pack( -side => 'left' );
    # Resolución MTF del ZZMTF (profe: 15, 30 o 60; default 30; 120=2h opcional)
    my $zz_res_box = $p->Frame()->pack( -side => 'left', -padx => 4 );
    $zz_res_box->Label( -text => 'res:', -fg => '#555' )->pack( -side => 'left' );
    for my $mins (qw(15 30 60)) {
        $zz_res_box->Radiobutton(
            -text     => "${mins}m",
            -value    => $mins,
            -variable => \$zigzag_resolution,
            -command  => sub {
                $zigzag_resolution = $mins;
                $cb_zzres{$mins}->() if $cb_zzres{$mins};
            },
        )->pack( -side => 'left' );
    }
    # ZigZag externo ChartPrime (Length 150; VP/Channel/PoC OFF → solo azul)
    $p->Checkbutton(
        -text     => 'ZigZag externo',
        -variable => \$vis_zz_ext,
        -command  => sub { $set_zz_layer->( 'EXTERNAL', $vis_zz_ext ? 1 : 0 ); },
    )->pack( -side => 'left' );
}

# ---- Pestaña "Dibujo": herramientas de trazado (Canal + Trend + Fib) ----
# Separadas de ZigZag para respetar el ancho máximo en laptop 14" (~1050 px).
# Ver docs/UI_FASE_ACTUAL.md (restricción de ancho).
{
    my $p = $panel{Dibujo};

    # Parallel Channel (herramienta TV del video del profe)
    my $pchan_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 6);
    $pchan_box->Label(-text => 'Canal:')->pack(-side => 'left', -padx => 2);
    my $pchan_hint = $pchan_box->Label(
        -text => '',
        -fg   => '#0D47A1',
        -font => [ 'Helvetica', 9, 'bold' ],
    );
    $chart_engine->{pchan_mode_callback} = sub {
        my ( $active, $n ) = @_;
        if ($active) {
            my $step = ( $n // 0 ) + 1;
            $step = 3 if $step > 3;
            $pchan_hint->configure(
                -text => "Clic $step/3… (Esc cancela)",
                -fg   => '#0D47A1',
            );
        }
        else {
            $pchan_hint->configure( -text => '', -fg => '#666666' );
        }
    };
    $pchan_box->Button(
        -text    => 'Parallel Channel',
        -command => sub { $chart_engine->start_parallel_channel_tool(); },
    )->pack( -side => 'left', -padx => 2 );
    $pchan_box->Button(
        -text    => 'Cancelar',
        -command => sub { $chart_engine->cancel_parallel_channel_tool(); },
    )->pack( -side => 'left', -padx => 2 );
    $pchan_box->Button(
        -text    => 'Borrar canal',
        -command => sub { $chart_engine->clear_parallel_channel(); },
    )->pack( -side => 'left', -padx => 2 );
    $pchan_hint->pack( -side => 'left', -padx => 4 );

    # TrendLine (varias líneas de 2 puntos, extremos arrastrables)
    my $trend_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 6);
    $trend_box->Label(-text => 'Trend:')->pack(-side => 'left', -padx => 2);
    my $trend_hint = $trend_box->Label(
        -text => '',
        -fg   => '#E65100',
        -font => [ 'Helvetica', 9, 'bold' ],
    );
    $chart_engine->{trend_mode_callback} = sub {
        my ( $active, $n ) = @_;
        if ($active) {
            my $step = ( $n // 0 ) + 1;
            $step = 2 if $step > 2;
            $trend_hint->configure(
                -text => "Clic $step/2… (Esc cancela)",
                -fg   => '#E65100',
            );
        }
        else {
            $trend_hint->configure( -text => '', -fg => '#666666' );
        }
    };
    $trend_box->Button(
        -text    => 'Trendline',
        -command => sub { $chart_engine->start_trendline_tool(); },
    )->pack( -side => 'left', -padx => 2 );
    $trend_box->Button(
        -text    => 'Cancelar',
        -command => sub { $chart_engine->cancel_trendline_tool(); },
    )->pack( -side => 'left', -padx => 2 );
    $trend_box->Button(
        -text    => 'Borrar última',
        -command => sub { $chart_engine->clear_last_trendline(); },
    )->pack( -side => 'left', -padx => 2 );
    $trend_box->Button(
        -text    => 'Borrar todas',
        -command => sub { $chart_engine->clear_trendlines(); },
    )->pack( -side => 'left', -padx => 2 );
    $trend_hint->pack( -side => 'left', -padx => 4 );

    # Fib Retracement (clone TV: 2 clics / último impulso ZZ ext / hasta última vela)
    my $fib_box = $p->Frame( -relief => 'groove', -bd => 2 )->pack( -side => 'left', -padx => 6 );
    $fib_box->Label( -text => 'Fib:' )->pack( -side => 'left', -padx => 2 );
    my $fib_hint = $fib_box->Label(
        -text => '',
        -fg   => '#0D47A1',
        -font => [ 'Helvetica', 9, 'bold' ],
    );
    $chart_engine->{fib_mode_callback} = sub {
        my ( $active, $n ) = @_;
        if ( defined $active && $active == 3 && defined $n && $n == -1 ) {
            $fib_hint->configure(
                -text => 'Sin impulso ZZ ext consolidado aún',
                -fg   => '#c62828',
            );
        }
        elsif ($active) {
            my $step = ( $n // 0 ) + 1;
            $step = 2 if $step > 2;
            $fib_hint->configure(
                -text => "Clic $step/2… (Esc cancela)",
                -fg   => '#0D47A1',
            );
        }
        else {
            $fib_hint->configure( -text => '', -fg => '#666666' );
        }
    };
    $fib_box->Button(
        -text    => 'Fib Retracement',
        -command => sub { $chart_engine->start_fib_retracement_tool(); },
    )->pack( -side => 'left', -padx => 2 );
    $fib_box->Button(
        -text    => 'Fib ZZ ext',
        -command => sub {
            $fib_extend_to_last = 1;
            $chart_engine->apply_fib_last_zz_impulse();
        },
    )->pack( -side => 'left', -padx => 2 );
    $fib_box->Button(
        -text    => 'Borrar Fib',
        -command => sub { $chart_engine->clear_fib_retracement(); },
    )->pack( -side => 'left', -padx => 2 );
    $fib_box->Checkbutton(
        -text     => 'Hasta última vela',
        -variable => \$fib_extend_to_last,
        -command  => sub {
            $chart_engine->set_fib_extend_to_last( $fib_extend_to_last ? 1 : 0 );
        },
    )->pack( -side => 'left', -padx => 2 );
    $fib_hint->pack( -side => 'left', -padx => 4 );
}

# ---- Pestaña "Auto": Trendline auto + Canal auto (ciclo nacer/vivir/morir) ----
# Separada de Dibujo por ancho en laptop 14" (manuales quedan en Dibujo).
{
    my $p = $panel{Auto};

    # Canal auto: ≥3 toques / ≥60 min. Trendline auto: ≥3 toques / ≥120 min.
    my $vis_auto_tl = 0;
    my $vis_auto_ch = 0;
    my $apply_auto_tc = sub {
        $chart_engine->set_auto_tc_layers(
            trendline => $vis_auto_tl ? 1 : 0,
            channel   => $vis_auto_ch ? 1 : 0,
        );
    };
    my $auto_box = $p->Frame( -relief => 'groove', -bd => 2 )
      ->pack( -side => 'left', -padx => 6 );
    $auto_box->Label( -text => 'Auto:', -fg => '#555' )->pack( -side => 'left', -padx => 2 );
    $auto_box->Checkbutton(
        -text     => 'Trendline auto',
        -variable => \$vis_auto_tl,
        -command  => $apply_auto_tc,
    )->pack( -side => 'left' );
    $auto_box->Checkbutton(
        -text     => 'Canal auto',
        -variable => \$vis_auto_ch,
        -command  => $apply_auto_tc,
    )->pack( -side => 'left' );
}

# ---- Pestaña "Volumen": AVP / AVWAP / Pivots-Fantasmas / DIY ----
{
    my $p = $panel{Volumen};
    # Anchored Volume Profile (AVP): Off | Manual | Auto (ZZ ext)
    my $vp_mode_ui = 'off';    # off | manual | auto
    my $vp_box = $p->Frame( -relief => 'groove', -bd => 2 )
      ->pack( -side => 'left', -padx => 4 );
    $vp_box->Label( -text => 'AVP' )->pack( -side => 'left' );

    my $apply_vp_mode = sub {
        my ($mode) = @_;
        $vp_mode_ui = $mode;
        $vis_vp = ( $mode eq 'off' ) ? 0 : 1;
        $chart_engine->set_vp_mode($mode);
    };
    $vp_box->Radiobutton(
        -text     => 'Off',
        -value    => 'off',
        -variable => \$vp_mode_ui,
        -command  => sub { $apply_vp_mode->('off'); },
    )->pack( -side => 'left' );
    $vp_box->Radiobutton(
        -text     => 'Manual',
        -value    => 'manual',
        -variable => \$vp_mode_ui,
        -command  => sub { $apply_vp_mode->('manual'); },
    )->pack( -side => 'left' );
    $vp_box->Radiobutton(
        -text     => 'Auto (ZZ ext)',
        -value    => 'auto',
        -variable => \$vp_mode_ui,
        -command  => sub { $apply_vp_mode->('auto'); },
    )->pack( -side => 'left' );
    $vp_box->Button(
        -text    => 'Eliminar',
        -padx    => 3,
        -command => sub {
            $vp_mode_ui = 'off';
            $vis_vp     = 0;
            $chart_engine->remove_vp_overlay();
        },
    )->pack( -side => 'left', -padx => 2 );

    # Anchored VWAP (AVWAP): Manual | Auto | Manual+Auto
    # Auto ≤2 (pivot consolidado + fantasma); manual opcional adicional (hasta 3).
    my $avwap_mode_ui = 'off';    # off | manual | auto | both
    my %vis_avwap_sub = ( band1 => 1, band2 => 1, band3 => 0, fill => 1 );
    my $avwap_box = $p->Frame( -relief => 'groove', -bd => 2 )
      ->pack( -side => 'left', -padx => 4 );
    $avwap_box->Label( -text => 'AVWAP' )->pack( -side => 'left' );

    my $apply_avwap_mode = sub {
        my ($mode) = @_;
        $avwap_mode_ui = $mode;
        $chart_engine->set_avwap_mode($mode);
        $chart_engine->set_avwap_bands_all(
            band1 => $vis_avwap_sub{band1},
            band2 => $vis_avwap_sub{band2},
            band3 => $vis_avwap_sub{band3},
            fill  => $vis_avwap_sub{fill},
        );
    };
    $avwap_box->Radiobutton(
        -text     => 'Off',
        -value    => 'off',
        -variable => \$avwap_mode_ui,
        -command  => sub { $apply_avwap_mode->('off'); },
    )->pack( -side => 'left' );
    $avwap_box->Radiobutton(
        -text     => 'Manual',
        -value    => 'manual',
        -variable => \$avwap_mode_ui,
        -command  => sub { $apply_avwap_mode->('manual'); },
    )->pack( -side => 'left' );
    $avwap_box->Radiobutton(
        -text     => 'Auto',
        -value    => 'auto',
        -variable => \$avwap_mode_ui,
        -command  => sub { $apply_avwap_mode->('auto'); },
    )->pack( -side => 'left' );
    $avwap_box->Radiobutton(
        -text     => 'Manual+Auto',
        -value    => 'both',
        -variable => \$avwap_mode_ui,
        -command  => sub { $apply_avwap_mode->('both'); },
    )->pack( -side => 'left' );

    my $avwap_sub_frame = $avwap_box->Frame()->pack( -side => 'left', -padx => 2 );
    my $apply_bands = sub {
        $chart_engine->set_avwap_bands_all(
            band1 => $vis_avwap_sub{band1},
            band2 => $vis_avwap_sub{band2},
            band3 => $vis_avwap_sub{band3},
            fill  => $vis_avwap_sub{fill},
        );
    };
    $avwap_sub_frame->Checkbutton(
        -text     => 'σ1',
        -variable => \$vis_avwap_sub{band1},
        -command  => $apply_bands,
    )->pack( -side => 'left' );
    $avwap_sub_frame->Checkbutton(
        -text     => 'σ2',
        -variable => \$vis_avwap_sub{band2},
        -command  => $apply_bands,
    )->pack( -side => 'left' );
    $avwap_sub_frame->Checkbutton(
        -text     => 'σ3',
        -variable => \$vis_avwap_sub{band3},
        -command  => $apply_bands,
    )->pack( -side => 'left' );
    $avwap_sub_frame->Checkbutton(
        -text     => 'Relleno',
        -variable => \$vis_avwap_sub{fill},
        -command  => $apply_bands,
    )->pack( -side => 'left' );
    $avwap_box->Button(
        -text    => 'Eliminar manual',
        -padx    => 3,
        -command => sub {
            $chart_engine->remove_vwap_overlay();
            my $m = $chart_engine->{avwap_mode} // 'off';
            $avwap_mode_ui = $m;
        },
    )->pack( -side => 'left', -padx => 2 );

    # Pivot Points High Low & Missed (fantasmas) — LuxAlgo. Ancla del VWAP.
    my $pph_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 6);
    my $apply_pph = sub {
        my $ind = $chart_engine->{pph_indicator} or return;
        $ind->{show_reg}  = $pph_show_reg  ? 1 : 0;
        $ind->{show_miss} = $pph_show_miss ? 1 : 0;
        $ind->reset() if $ind->can('reset');
        $chart_engine->{_pph_fed_up_to} = -1;   # forzar re-feed causal (Replay-safe)
        $chart_engine->set_pph_show_rastro($pph_show_rastro);
        $chart_engine->request_render();
    };
    $pph_box->Checkbutton(
        -text     => 'Pivots & Fantasmas',
        -variable => \$vis_pph,
        -command  => sub { $cb_pph->( $vis_pph ? 1 : 0 ); },
    )->pack( -side => 'left' );
    $pph_box->Checkbutton(
        -text     => 'Regular',
        -variable => \$pph_show_reg,
        -command  => $apply_pph,
    )->pack( -side => 'left' );
    $pph_box->Checkbutton(
        -text     => 'Missed',
        -variable => \$pph_show_miss,
        -command  => $apply_pph,
    )->pack( -side => 'left' );
    $pph_box->Checkbutton(
        -text     => 'Rastro',
        -variable => \$pph_show_rastro,
        -command  => sub {
            $chart_engine->set_pph_show_rastro($pph_show_rastro);
        },
    )->pack( -side => 'left' );

    # DIY Custom Strategy Builder (Supply/Demand Zones)
    $p->Checkbutton(
        -text     => 'DIY (S/D Zones)',
        -variable => \$vis_diy,
        -command  => sub { $set_overlay_visible->( 'diy', $vis_diy ? 1 : 0 ); },
    )->pack( -side => 'left' );
}

# ---- Pestaña "Vista": Escala ATR + Grid + Linea precio + Panel ATR ----
{
    my $p = $panel{Vista};
    # Modo de escala de PRECIO: se controla con los botones A/M de la esquina
    # inferior derecha del gráfico (estilo TradingView). Aquí ya no va.
    # Reset Vista vive siempre visible abajo-derecha (bajo ↻), fuera de esta pestaña.

    my $atr_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $atr_box->Label(-text => 'ATR:')->pack(-side => 'left', -padx => 3);
    $atr_box->Radiobutton(-text => 'Auto', -value => 'auto', -variable => \$atr_scale_mode,
        -indicatoron => 0, -padx => 5, -command => sub { $chart_engine->set_atr_scale_mode('auto') })->pack(-side => 'left', -padx => 1);
    $atr_box->Radiobutton(-text => 'Manual', -value => 'manual', -variable => \$atr_scale_mode,
        -indicatoron => 0, -padx => 5, -command => sub { $chart_engine->set_atr_scale_mode('manual') })->pack(-side => 'left', -padx => 1);

    my $grid_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $grid_box->Label(-text => 'Grid:')->pack(-side => 'left', -padx => 3);
    my $grid_btn;
    $grid_btn = $grid_box->Button(
        -text        => 'Mostrar',
        -padx        => 5,
        -command     => sub {
            my $on = $chart_engine->toggle_grid();
            $grid_btn->configure(-text => $on ? 'Ocultar' : 'Mostrar');
        },
    )->pack(-side => 'left', -padx => 1);

    # Línea entrecortada del precio actual (off por defecto).
    my $show_last_price_line = 0;
    $p->Checkbutton(
        -text     => 'Linea precio',
        -variable => \$show_last_price_line,
        -command  => sub {
            $chart_engine->set_show_last_price_line($show_last_price_line);
        },
    )->pack( -side => 'left', -padx => 4 );

    # Panel ATR desplegable: ocultarlo da más espacio vertical al gráfico.
    my $atr_toggle_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $atr_toggle_box->Label(-text => 'Panel ATR:')->pack(-side => 'left', -padx => 3);
    my $atr_btn;
    $atr_btn = $atr_toggle_box->Button(
        -text    => 'Mostrar',   # ATR oculto por defecto
        -padx    => 5,
        -command => sub {
            my $shown = $chart_engine->toggle_atr_panel();
            $atr_btn->configure(-text => $shown ? 'Ocultar' : 'Mostrar');
        },
    )->pack(-side => 'left', -padx => 1);
}

# ---- Pestaña "Replay": controles inline; al abrir se preselecciona Select bar ----
{
    my $p = $panel{Replay};
    my $replay_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 6);
    $replay_box->Label(-text => 'Replay:', -fg => '#555')->pack(-side => 'left', -padx => 2);
    $replay_panel = Market::UI::ReplayPanel->new(
        parent      => $replay_box,
        menu_parent => $mw,
        chart       => $chart_engine,
        mw          => $mw,
        root        => $mw,
        ui_vars     => \%ui_vars,
        inline      => 1,
    );
}

# Mostrar la pestaña inicial.
$show_panel->('Estructura');

# ==========================================
# 7. RENDER INICIAL + LOOP
# ==========================================
print "[*] Abriendo ventana...\n";
$mw->update;
my $maximized = eval { $mw->state('zoomed'); 1 };
$maximized ||= eval { $mw->attributes('-zoomed', 1); 1 };
$mw->update if $maximized;
$mw->after(200, sub {
    print "[*] Render inicial (producto oficial: velas + ATR; capas bajo demanda)...\n";
    $chart_engine->render();
    # Panel ATR oculto por defecto (más espacio al gráfico); se muestra con el
    # botón "Panel ATR" en la pestaña Vista.
    $chart_engine->set_atr_panel_visible(0) if $chart_engine->can('set_atr_panel_visible');
    $mw->after(200,  sub { $chart_engine->request_render(); });
    $mw->after(800,  sub { $chart_engine->request_render(); });
});

MainLoop;
