#!/usr/bin/perl
use strict;
use warnings;
use Tk;

use lib '.';
use Market::MarketData;
use Market::IndicatorManager;
use Market::Indicators::ATR;
use Market::ChartEngine;

print "========== LAUNCHING FINANCIAL CHARTING ENGINE (Tk) ==========\n";

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
$mw->geometry("1024x768"); # Forzamos una resolución inicial fija

# ORDEN CORRECTO: De abajo hacia arriba.

# 1. Controles (Se anclan al fondo)
my $frame_controles = $mw->Frame()->pack(-side => 'bottom', -fill => 'x', -pady => 5);
$frame_controles->Label(-text => "Temporalidades: ")->pack(-side => 'left', -padx => 10);

# 2. Panel inferior ATR (Se ancla justo encima de los controles)
my $atr_canvas = $mw->Canvas(
    -height     => 150,
    -background => '#131722',
    -relief     => 'sunken',
    -bd         => 1
)->pack(-side => 'bottom', -fill => 'x');

# 3. Panel superior de Velas (Toma todo el espacio que sobra arriba)
my $price_canvas = $mw->Canvas(
    -background => '#131722', 
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
    atr_canvas        => $atr_canvas
);

# Conectar botones al motor usando los sufijos 'm' para coincidir con MarketData.pm
$frame_controles->Button(-text => "1 Minuto",   -command => sub { $chart_engine->set_timeframe('1m') })->pack(-side => 'left', -padx => 2);
$frame_controles->Button(-text => "5 Minutos",  -command => sub { $chart_engine->set_timeframe('5m') })->pack(-side => 'left', -padx => 2);
$frame_controles->Button(-text => "15 Minutos", -command => sub { $chart_engine->set_timeframe('15m') })->pack(-side => 'left', -padx => 2);
$frame_controles->Button(-text => "Reset Vista",-command => sub { $chart_engine->reset_view() })->pack(-side => 'right', -padx => 20);

# ==========================================
# 5. DISPARAR RENDER Y LOOP GRÁFICO (CON ESTABILIDAD PARA WAYLAND)
# ==========================================
print "[*] Abriendo ventana nativa y delegando control a Tk...\n";

# Le decimos a Tk: "Abre la ventana ya mismo, y 100 milisegundos 
# después de que estés listo, ejecuta el renderizado".
$mw->after(100, sub {
    print "[*] Ejecutando renderizado inicial en los Canvas...\n";
    $chart_engine->render();
});

# Entregamos el control absoluto sin forzar updates previos
MainLoop;