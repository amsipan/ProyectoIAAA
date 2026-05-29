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

print "========== LAUNCHING FINANCIAL CHARTING ENGINE (Tk) ==========\n";
print "[*] Build visual: WSLg geometry sync fix v2\n";

# ==========================================
# 1. INICIALIZAR GESTOR DE DATOS E INDICADORES
# ==========================================
my $market_data = Market::MarketData->new();
my $indicator_manager = Market::IndicatorManager->new();
my $atr_indicator = Market::Indicators::ATR->new(14); # ATR de 14 periodos clásico

$indicator_manager->register('ATR', $atr_indicator);

# ==========================================
# 2. CARGAR HISTÓRICO Y SIMULAR STREAMING PARA ATR
# ==========================================
my $archivo_csv = 'Data/2026_03.csv';
print "[*] Leyendo base de datos histórica y calculando indicadores...\n";
open my $fh, '<', $archivo_csv or die "CRÍTICO: No se pudo abrir $archivo_csv: $!";
my $header = <$fh>;

while (my $linea = <$fh>) {
    chomp $linea;
    my @columnas = split /,/, $linea;
    
    # Añadimos la vela al gestor de datos
    $market_data->add_candle(\@columnas);
    
}
close $fh;

print "[*] Construyendo temporalidades de 5m y 15m...\n";
$market_data->build_timeframes();
$market_data->set_timeframe('1m');
for (my $i = 0; $i < $market_data->size(); $i++) {
    $indicator_manager->update_last($market_data, $i);
}

# ==========================================
# 3. CONSTRUCCIÓN DE LA INTERFAZ GRÁFICA (PERL-TK)
# ==========================================
my $mw = MainWindow->new;
$mw->title("Plataforma de Gráficos Financieros - Motor de Charting Tk");

# Tamaño mínimo de la ventana principal.
$mw->minsize(800, 600);

# Maximizar ventana al iniciar (tema claro, paridad con TradingView).
# En WSLg/Tk a veces `state('zoomed')` deja la ventana invisible o reporta una
# pantalla absurda (p.ej. 131072x1). Por eso validamos dimensiones antes de usar
# maximizado y siempre dejamos una geometría segura visible como fallback.
my $sw = eval { $mw->screenwidth }  || 1280;
my $sh = eval { $mw->screenheight } || 800;
my $screen_ok = ($sw >= 800 && $sw <= 10000 && $sh >= 600 && $sh <= 10000);

if ($screen_ok) {
    my $maximized = eval { $mw->state('zoomed'); 1 };
    if (!$maximized) {
        $mw->geometry("${sw}x${sh}+0+0");
    }
} else {
    warn "[!] Tk reportó pantalla inválida (${sw}x${sh}); usando geometría segura.\n";
    $mw->geometry('1280x800+50+50');
}

$mw->deiconify;
$mw->raise;
$mw->focusForce;

# ==========================================
# PALETA DE TEMA CLARO (hash léxico, NO global de paquete)
# Inyectada a ChartEngine y transportada a los paneles/escalas.
# ==========================================
my %theme = (
    bg             => '#ffffff',
    grid           => '#e0e0e0',
    axis_text      => '#363a45',
    bull           => '#26a69a',
    bear           => '#ef5350',
    atr_line       => '#2962ff',
    crosshair_line => '#9598a1',
    label_bg       => '#363a45',
    label_fg       => '#ffffff',
    last_price_bg  => '#363a45',
    last_price_fg  => '#ffffff',
);

# ORDEN CORRECTO: De abajo hacia arriba.

# 1. Controles (Se anclan al fondo)
my $frame_controles = $mw->Frame()->pack(-side => 'bottom', -fill => 'x', -pady => 5);
$frame_controles->Label(-text => "Temporalidades: ")->pack(-side => 'left', -padx => 10);

# 2. Panel inferior ATR (Se ancla justo encima de los controles)
my $atr_canvas = $mw->Canvas(
    -height     => 150,
    -background => $theme{bg},
    -relief     => 'sunken',
    -bd         => 1
)->pack(-side => 'bottom', -fill => 'x');

# 3. Panel superior de Velas (Toma todo el espacio que sobra arriba)
my $price_canvas = $mw->Canvas(
    -background => $theme{bg},
    -relief     => 'sunken',
    -bd         => 1
)->pack(-side => 'top', -expand => 1, -fill => 'both');

# ==========================================
# 4. INSTANCIAR EL MOTOR ORQUESTADOR (CHART ENGINE)
# ==========================================
my $chart_engine = Market::ChartEngine->new(
    market_data       => $market_data,
    indicator_manager => $indicator_manager,
    price_canvas      => $price_canvas,
    atr_canvas        => $atr_canvas,
    theme             => \%theme
);

$mw->Tk::bind('<Configure>', sub { $chart_engine->request_render(); });

# Conectar botones al motor usando los sufijos 'm' para coincidir con MarketData.pm
$frame_controles->Button(-text => "1 Minuto",   -command => sub { $chart_engine->set_timeframe('1m') })->pack(-side => 'left', -padx => 2);
$frame_controles->Button(-text => "5 Minutos",  -command => sub { $chart_engine->set_timeframe('5m') })->pack(-side => 'left', -padx => 2);
$frame_controles->Button(-text => "15 Minutos", -command => sub { $chart_engine->set_timeframe('15m') })->pack(-side => 'left', -padx => 2);

my $scale_mode = 'auto';
$frame_controles->Label(-text => "  Escala: ")->pack(-side => 'left', -padx => 6);
$frame_controles->Radiobutton(
    -text     => 'Auto',
    -value    => 'auto',
    -variable => \$scale_mode,
    -command  => sub { $chart_engine->set_scale_mode('auto') },
)->pack(-side => 'left', -padx => 2);
$frame_controles->Radiobutton(
    -text     => 'Manual',
    -value    => 'manual',
    -variable => \$scale_mode,
    -command  => sub { $chart_engine->set_scale_mode('manual') },
)->pack(-side => 'left', -padx => 2);

$frame_controles->Button(-text => "Reset Vista",-command => sub { $chart_engine->reset_view() })->pack(-side => 'right', -padx => 20);

# ==========================================
# 5. DISPARAR RENDER Y LOOP GRÁFICO (CON ESTABILIDAD PARA WAYLAND)
# ==========================================
print "[*] Abriendo ventana nativa y delegando control a Tk...\n";

# Le damos a Tk tiempo para mapear la ventana y calcular geometrías reales antes
# del primer render. En WSLg, renderizar demasiado pronto puede dejar escalas viejas.
$mw->update;
$mw->after(300, sub {
    print "[*] Ejecutando renderizado inicial en los Canvas...\n";
    $chart_engine->render();
    $mw->after(200, sub { $chart_engine->request_render(); });
    $mw->after(800, sub { $chart_engine->request_render(); });
    $mw->after(1500, sub { $chart_engine->request_render(); });
});

# Entregamos el control absoluto sin forzar updates previos
MainLoop;
