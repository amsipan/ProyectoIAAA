use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;

# ===========================================================================
# Test 0001: Temporalidades extendidas en MarketData.
# Inicio de semana = LUNES (ISO 8601, Time::Moment->day_of_week 1=Lun .. 7=Dom).
# ===========================================================================

# --- Helper: construir velas 1m sintéticas con OHLCV conocido ---
# 2 horas completas (120 velas 1m) del 2026-04-06 (lunes) + 1 hora del día siguiente.
# Cada vela 1m: open=i*10+100, high=i*10+105, low=i*10+95, close=i*10+102, vol=i+1.
sub build_synthetic_1m {
    my @candles;
    # Hora 0: 00:00 - 00:59 (60 velas)
    for my $i (0 .. 59) {
        push @candles, [
            sprintf('2026-04-06T00:%02d:00-05:00', $i),
            $i * 10 + 100,  # open
            $i * 10 + 105,  # high
            $i * 10 + 95,   # low
            $i * 10 + 102,  # close
            $i + 1,         # vol
        ];
    }
    # Hora 1: 01:00 - 01:59 (60 velas)
    for my $i (0 .. 59) {
        push @candles, [
            sprintf('2026-04-06T01:%02d:00-05:00', $i),
            ($i + 60) * 10 + 100,
            ($i + 60) * 10 + 105,
            ($i + 60) * 10 + 95,
            ($i + 60) * 10 + 102,
            $i + 61,
        ];
    }
    # Hora 2 del día siguiente: 2026-04-07 00:00 - 00:59 (60 velas)
    for my $i (0 .. 59) {
        push @candles, [
            sprintf('2026-04-07T00:%02d:00-05:00', $i),
            ($i + 120) * 10 + 100,
            ($i + 120) * 10 + 105,
            ($i + 120) * 10 + 95,
            ($i + 120) * 10 + 102,
            $i + 121,
        ];
    }
    return @candles;
}

# ===========================================================================
# Test 1: vela 1h tiene OHLCV exacto de sus 60 sub-velas 1m.
# ===========================================================================
my $md = Market::MarketData->new();
my @candles = build_synthetic_1m();
$md->add_candle($_) for @candles;
$md->build_timeframes();

# Verificar tamaño 1m
is($md->{data}->{'1m'}->@*, 180, '1m size = 180 velas');

# Cambiar a 1h y verificar
$md->set_timeframe('1h');
my $h1_size = $md->size();
is($h1_size, 3, '1h size = 3 velas (2 horas del 06 + 1 hora del 07)');

# La primera vela 1h (00:00-00:59 del 06) debe tener:
# Open = primera sub-vela open = 100
# High = max de todas las sub-velas = 59*10+105 = 695
# Low = min de todas las sub-velas = 95
# Close = última sub-vela close = 59*10+102 = 692
# Vol = suma(1..60) = 1830
my $h1_candle = $md->get_candle(0);
is($h1_candle->[0], '2026-04-06T00:00:00-05:00', '1h bucket timestamp = 00:00');
is($h1_candle->[1], 100,  '1h[0] Open = primera sub-vela open (100)');
is($h1_candle->[2], 695,  '1h[0] High = max de sub-velas (695)');
is($h1_candle->[3], 95,   '1h[0] Low = min de sub-velas (95)');
is($h1_candle->[4], 692,  '1h[0] Close = última sub-vela close (692)');
is($h1_candle->[5], 1830, '1h[0] Vol = suma de sub-velas (1830)');

# Segunda vela 1h (01:00-01:59 del 06)
my $h1_candle2 = $md->get_candle(1);
is($h1_candle2->[0], '2026-04-06T01:00:00-05:00', '1h[1] bucket = 01:00');
is($h1_candle2->[1], 700,  '1h[1] Open = 700');
is($h1_candle2->[5], 5430, '1h[1] Vol = suma(61..120) = 7260-1830 = 5430');

# ===========================================================================
# Test 2: size('D') ~= días de trading con datos, size('W') ~= semanas.
# ===========================================================================
$md->set_timeframe('D');
my $d_size = $md->size();
is($d_size, 2, 'D size = 2 (días de trading 06 y 07 de abril)');

my $d0 = $md->get_candle(0);
is($d0->[0], '2026-04-06T00:00:00-05:00', 'D[0] bucket = trading day 2026-04-06');
# Open del día de trading = primera vela 1m disponible de esa sesión = 100
is($d0->[1], 100, 'D[0] Open = 100');
# Close del día de trading = última vela 1m antes de 17:00 = (59+60)*10+102 = 1292
is($d0->[4], 1292, 'D[0] Close = 1292');
# Vol = suma(1..120) = 120*121/2 = 7260
is($d0->[5], 7260, 'D[0] Vol = suma de 120 sub-velas = 7260');

# Semanal: ambas velas 06 y 07 caen en la misma semana (lunes 06 de abril).
# Inicio de semana = LUNES (ISO 8601, day_of_week=1). 2026-04-06 es lunes.
$md->set_timeframe('W');
my $w_size = $md->size();
is($w_size, 1, 'W size = 1 (ambos días en la misma semana del lunes 06)');

my $w0 = $md->get_candle(0);
is($w0->[0], '2026-04-06T00:00:00-05:00', 'W[0] bucket = lunes 2026-04-06');
is($w0->[1], 100,  'W[0] Open = 100');
# Vol = suma(1..180) = 180*181/2 = 16290
is($w0->[5], 16290, 'W[0] Vol = suma(1..180) = 16290');

# ===========================================================================
# Test 3: 1m/5m/15m no cambian respecto a antes.
# ===========================================================================
# 5m: 180 velas 1m / 5 = 36 velas 5m
$md->set_timeframe('5m');
is($md->size(), 36, '5m size = 36 (180/5)');

# 15m: 180 velas 1m / 15 = 12 velas 15m
$md->set_timeframe('15m');
is($md->size(), 12, '15m size = 12 (180/15)');

# 15m primera vela: bucket 00:00, open=100, close de la vela 1m #14 = 14*10+102 = 242
my $m15_0 = $md->get_candle(0);
is($m15_0->[0], '2026-04-06T00:00:00-05:00', '15m[0] bucket = 00:00');
is($m15_0->[1], 100, '15m[0] Open = 100');
is($m15_0->[4], 242, '15m[0] Close = última sub-vela del bucket (242)');

# 5m primera vela: bucket 00:00, open=100, close de la vela 1m #4 = 4*10+102 = 142
$md->set_timeframe('5m');
my $m5_0 = $md->get_candle(0);
is($m5_0->[0], '2026-04-06T00:00:00-05:00', '5m[0] bucket = 00:00');
is($m5_0->[1], 100, '5m[0] Open = 100');
is($m5_0->[4], 142, '5m[0] Close = última sub-vela del bucket (142)');

# ===========================================================================
# Test 4: 2h y 4h agregan con anclaje de sesión CME/TradingView (17:00).
# ===========================================================================
$md->set_timeframe('2h');
# 2h anclado a 17:00 produce buckets impares: ...23:00,01:00,03:00...
# En este set: 00:00-00:59 => bucket 23:00 día anterior; 01:00-01:59 => 01:00.
is($md->size(), 3, '2h size = 3 con buckets de sesión (23:00, 01:00, 23:00)');
my $h2_0 = $md->get_candle(0);
is($h2_0->[0], '2026-04-05T23:00:00-05:00', '2h[0] bucket = 23:00 día previo (sesión CME)');
is($h2_0->[1], 100, '2h[0] Open = 100');
is($h2_0->[4], 692, '2h[0] Close = 692');
my $h2_1 = $md->get_candle(1);
is($h2_1->[0], '2026-04-06T01:00:00-05:00', '2h[1] bucket = 01:00');
is($h2_1->[1], 700, '2h[1] Open = 700');
is($h2_1->[4], 1292, '2h[1] Close = 1292');

$md->set_timeframe('4h');
# 4h anclado a 17:00 produce ...21:00,01:00,05:00...
is($md->size(), 3, '4h size = 3 con buckets de sesión (21:00, 01:00, 21:00)');
my $h4_0 = $md->get_candle(0);
is($h4_0->[0], '2026-04-05T21:00:00-05:00', '4h[0] bucket = 21:00 día previo');
my $h4_1 = $md->get_candle(1);
is($h4_1->[0], '2026-04-06T01:00:00-05:00', '4h[1] bucket = 01:00');

# ===========================================================================
# Test 5: _bucket_timestamp semanal — verify lunes como inicio de semana.
# 2026-04-07 es martes (dow=2). Su bucket semanal debe ser 2026-04-06 (lunes).
# ===========================================================================
my $test_md = Market::MarketData->new();
is($test_md->_bucket_timestamp('2026-04-07T12:30:00-05:00', 'W'),
   '2026-04-06T00:00:00-05:00',
   'W bucket for martes 07 = lunes 06');

is($test_md->_bucket_timestamp('2026-04-06T12:30:00-05:00', 'W'),
   '2026-04-06T00:00:00-05:00',
   'W bucket for lunes 06 = mismo lunes 06');

# Domingo (dow=7): debe ir al lunes anterior (2026-04-06 - 6 dias = 2026-03-31)
is($test_md->_bucket_timestamp('2026-04-12T12:30:00-05:00', 'W'),
   '2026-04-06T00:00:00-05:00',
   'W bucket for domingo 12 = lunes 06');

# ===========================================================================
# Test 6: compat retro — _bucket_timestamp con entero de minutos.
# ===========================================================================
is($test_md->_bucket_timestamp('2026-04-06T00:07:30-05:00', 5),
   '2026-04-06T00:05:00-05:00',
   'compat: entero 5 sigue funcionando como antes');

is($test_md->_bucket_timestamp('2026-04-06T00:07:30-05:00', 15),
   '2026-04-06T00:00:00-05:00',
   'compat: entero 15 sigue funcionando como antes');

# ===========================================================================
# Test 7: Criterios de aceptación de la Task 0020 (Anclaje de sesión CME).
# ===========================================================================
is($test_md->_bucket_timestamp('2026-04-06T01:30:00-05:00', '2h'),
   '2026-04-06T01:00:00-05:00',
   'Acceptance: 2h bucket for 2026-04-06T01:30 = 01:00');

is($test_md->_bucket_timestamp('2026-04-06T02:30:00-05:00', 180),
   '2026-04-06T02:00:00-05:00',
   'Acceptance: 180m (3h) bucket for 2026-04-06T02:30 = 02:00');

is($test_md->_bucket_timestamp('2026-04-06T01:30:00-05:00', '4h'),
   '2026-04-06T01:00:00-05:00',
   'Acceptance: 4h bucket for 2026-04-06T01:30 = 01:00');

is($test_md->_bucket_timestamp('2026-04-06T17:30:00-05:00', 'D'),
   '2026-04-07T00:00:00-05:00',
   'Acceptance: D bucket for 2026-04-06T17:30 = 2026-04-07');

done_testing();
