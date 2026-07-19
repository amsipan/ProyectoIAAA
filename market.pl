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
# Producto oficial: ATR al arranque; capas SMC/ZZ/HLD bajo demanda
# (docs/PRODUCTO_OFICIAL.md). Legacy Liquidity/Mxwll/VP/VWAP no se cargan.
my $market_data = Market::MarketData->new();
my $indicator_manager = Market::IndicatorManager->new();
$indicator_manager->register('ATR', Market::Indicators::ATR->new(14));

# Dataset canónico: export TradingView NQ1! 15m (ISO UTC-5, ETH).
# Base nativa = 15m; 1h/2h/4h/D/W se agregan desde 15m. 1m/5m quedan vacíos
# (botones UI se mantienen; no hay data más fina que la base).
# Copia portable en Data/; fallback a Downloads si falta la copia.
my $tv_src = 'C:/Users/bryan/Downloads/CME_MINI_DL_NQ1!, 15.csv';
my $tv_dst = 'Data/tv_nq1_15m.csv';
if (-f $tv_src && !-f $tv_dst) {
    require File::Copy;
    File::Copy::copy($tv_src, $tv_dst)
        or warn "[!] No se pudo copiar $tv_src → $tv_dst: $!\n";
    print "[*] CSV TV 15m copiado a $tv_dst\n" if -f $tv_dst;
}

my @csv_candidates = (
    $tv_dst,
    $tv_src,
    # Fallbacks legacy 1m (solo si no hay export 15m)
    'Data/2026_06.csv',
    'C:/Users/bryan/Downloads/Proyecto/2026_06.csv',
);
my $archivo_csv;
for my $cand (@csv_candidates) {
    if (-f $cand) { $archivo_csv = $cand; last; }
}
die "CRÍTICO: no se encontró dataset (tv_nq1_15m.csv ni export TV ni 2026_06.csv)\n"
    unless defined $archivo_csv;

# Detectar base: export 15m de TV o nombre *15m* → base 15m; si no, 1m.
my $base_tf = '1m';
if ($archivo_csv =~ /15m|15\.csv|_15\.csv|, 15\.csv/i) {
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
my $active_tf = $base_tf;  # UI resalta el TF base (15m con export TV)
my $replay_on   = 0;
my $replay_select_mode = 0;
my $replay_watermark_on = 1;
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

# Capas producto oficial (OFF por defecto). Ver docs/PRODUCTO_OFICIAL.md
my $vis_smc_pro = 0;
my $vis_smc_fvg = 0;
my $vis_hld     = 0;
my $vis_zz_ext = 0;
my $vis_zz_int = 0;
my $vis_zigzag = 0;    # true si alguna capa ZZ está ON
if ($chart_engine->{zigzag_overlay} && $chart_engine->{zigzag_overlay}->can('set_density_pct')) {
    $chart_engine->{zigzag_overlay}->set_density_pct(100);
}
my %vis_zzelem = ( INTERNAL => 0, EXTERNAL => 0, CHANNEL => 0 );
my $zigzag_resolution = 30;
my $fib_extend_to_last = 0;

my $cb_smc_pro = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'smc_pro');
my $cb_smc_fvg = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'smc_fvg');
my $cb_hld     = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'hld');
my $cb_zigzag = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'zigzag');
my %cb_zzelem = map { $_ => Market::UI::Callbacks->make_zigzag_element_toggle($chart_engine, $_) }
                qw(INTERNAL EXTERNAL CHANNEL);
my %overlay_state_ref = (
    smc_pro => \$vis_smc_pro, smc_fvg => \$vis_smc_fvg, hld => \$vis_hld,
    zigzag => \$vis_zigzag,
);
my %overlay_cb = (
    smc_pro => $cb_smc_pro, smc_fvg => $cb_smc_fvg, hld => $cb_hld,
    zigzag => $cb_zigzag,
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
# Fib "Desde ZZ ext" activa el overlay externo → marcar checkbox en la UI
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
# --- FASE ACTUAL: SMC + HLD + PChan + ZZ ext/int + Fib Retracement tool ---
# PASO A PASO: Liq / Strategy / VWAP / VP desactivados.
my %panel;
$panel{$_} = $panel_row->Frame() for qw(Capas SMC Escala Replay);

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

my %tab_label = (
    Capas  => 'Capas',
    SMC    => 'SMC',
    Escala => 'Escala',
    Replay => 'Replay',
    # Desactivadas (fase futura): Liq, ZigZag, Estrategia
);
my $tabs_box = $tab_row->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 5);
for my $name (qw(Capas SMC Escala Replay)) {
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

# ---- Panel "Capas": fase actual (sin Liq/VWAP/VP/Strategy) ----
{
    my $p = $panel{Capas};
    $p->Label(-text => 'Capas:')->pack(-side => 'left', -padx => 3);
    $p->Checkbutton(-text => 'SMC Pro', -variable => \$vis_smc_pro,
        -command => sub { $set_overlay_visible->('smc_pro', $vis_smc_pro ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'SMC Structures+FVG', -variable => \$vis_smc_fvg,
        -command => sub { $set_overlay_visible->('smc_fvg', $vis_smc_fvg ? 1 : 0); })->pack(-side => 'left');
    $p->Checkbutton(-text => 'HLD (4h/D)', -variable => \$vis_hld,
        -command => sub { $set_overlay_visible->('hld', $vis_hld ? 1 : 0); })->pack(-side => 'left');
    # ZigZag externo ChartPrime (Length 150; VP/Channel/PoC OFF → solo azul)
    $p->Checkbutton(
        -text     => 'ZigZag externo',
        -variable => \$vis_zz_ext,
        -command  => sub { $set_zz_layer->( 'EXTERNAL', $vis_zz_ext ? 1 : 0 ); },
    )->pack( -side => 'left' );
    # ZigZag interno ZZMTF (Show ZZ ON; fib OFF; verde/rojo; res 15/30/60)
    $p->Checkbutton(
        -text     => 'ZigZag interno',
        -variable => \$vis_zz_int,
        -command  => sub { $set_zz_layer->( 'INTERNAL', $vis_zz_int ? 1 : 0 ); },
    )->pack( -side => 'left' );
    # Resolución MTF del ZZMTF (profe: 15, 30 o 60; default 30; 120=2h opcional)
    my $zz_res_box = $p->Frame()->pack( -side => 'left', -padx => 4 );
    $zz_res_box->Label( -text => 'ZZ int:', -fg => '#555' )->pack( -side => 'left' );
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

    # Fib Retracement (clone TV: 2 clics / pick pierna ZZ / hasta última vela)
    my $fib_box = $p->Frame( -relief => 'groove', -bd => 2 )->pack( -side => 'left', -padx => 6 );
    $fib_box->Label( -text => 'Fib:' )->pack( -side => 'left', -padx => 2 );
    my $fib_hint = $fib_box->Label(
        -text => '',
        -fg   => '#0D47A1',
        -font => [ 'Helvetica', 9, 'bold' ],
    );
    $chart_engine->{fib_mode_callback} = sub {
        my ( $active, $n ) = @_;
        if ( defined $active && $active == 2 ) {
            # Modo elegir pierna azul del ZZ externo
            if ( defined $n && $n == -1 ) {
                $fib_hint->configure(
                    -text => 'Clic más cerca de una línea azul…',
                    -fg   => '#c62828',
                );
            }
            else {
                $fib_hint->configure(
                    -text => 'Clic en la pierna azul del ZZ… (Esc cancela)',
                    -fg   => '#0D47A1',
                );
            }
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
        -text    => 'Desde ZZ ext',
        -command => sub { $chart_engine->start_fib_pick_zz(); },
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
    $main_box->Label(-text => 'SMC Structures+FVG')->pack(-side => 'left');
    $overlay_button{hld} = $main_box->Button(
        -text => $overlay_button_text->($vis_hld),
        -command => sub { $toggle_overlay_visible->('hld'); },
    )->pack(-side => 'left', -padx => 2);
    $main_box->Label(-text => 'HLD')->pack(-side => 'left');
    my $info_box = $p->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
    $info_box->Label(
        -text => 'HLD solo en TF 4h o D. R/S de vela HTF más cercana al precio (video ~40min).',
        -font => ['Helvetica', 8],
    )->pack(-side => 'left', -padx => 3);
}

# ---- Paneles Liq / ZigZag / Estrategia: DESACTIVADOS (fase futura) ----
# El código de UI de esas pestañas se eliminó del árbol de pestañas activas.
# Módulos Market/Indicators|Overlays se conservan en el repo.
# Reactivar: añadir pestaña en %panel + botones de pestaña + re-registrar en ChartEngine.

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
    print "[*] Render inicial (producto oficial: velas + ATR; capas bajo demanda)...\n";
    $chart_engine->render();
    $mw->after(200,  sub { $chart_engine->request_render(); });
    $mw->after(800,  sub { $chart_engine->request_render(); });
});

MainLoop;
