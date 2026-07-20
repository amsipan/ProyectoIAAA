use strict;
use warnings;
use Test::More tests => 24;
use lib '.';

use_ok('Market::Indicators::AnchoredVWAP');
use_ok('Market::Overlays::AnchoredVWAP');

# 1. Instanciación
my $ind = Market::Indicators::AnchoredVWAP->new(
    source     => 'hlc3',
    band1_on   => 1, band1_mult => 1.0,
    band2_on   => 1, band2_mult => 2.0,
    band3_on   => 0, band3_mult => 3.0,
);
ok($ind, 'Instanciación de AnchoredVWAP indicador ok');

my $ov = Market::Overlays::AnchoredVWAP->new(
    indicator => $ind,
    visible   => 0,
);
ok($ov, 'Instanciación de AnchoredVWAP overlay ok');
is($ov->tag(), 'ov_avwap', 'Tag correcto para AnchoredVWAP overlay');
is($ov->is_visible(), 0, 'Oculto por defecto');

# 2. Mock dataset
package MockMarketData;
sub new { bless { candles => $_[1] }, $_[0] }
sub get_candle { $_[0]->{candles}->[$_[1]] }
sub last_candle { $_[0]->{candles}->[-1] }
package main;

# [ts, open, high, low, close, volume]
my @candles = (
    ['2026-06-25 10:00', 100, 105, 95, 102, 1000],
    ['2026-06-25 10:15', 102, 110, 100, 108, 1500],
    ['2026-06-25 10:30', 108, 112, 104, 106, 1200],
    ['2026-06-25 10:45', 106, 115, 105, 114, 2000],
    ['2026-06-25 11:00', 114, 120, 110, 118, 2500],
);

my $mdata = MockMarketData->new(\@candles);

# Al alimentar sin ancla no genera serie
for my $i (0 .. $#candles) {
    $ind->update_last($mdata, $i);
}
ok(!$ind->has_anchor(), 'Sin ancla definida inicialmente');

# Fijo ancla en la vela 1 (10:15)
$ind->set_anchor(1);
ok($ind->has_anchor(), 'Ancla establecida en vela 1');
is($ind->anchor_index(), 1, 'Índice de ancla es 1');

my $series = $ind->get_values();
ok($series && @$series, 'Serie de valores generada');

# Puntos antes de la ancla deben ser undef
is($series->[0], undef, 'Punto previo a la ancla es undef');

# Punto en la ancla (índice 1)
my $pt1 = $series->[1];
ok($pt1 && defined $pt1->{value}, 'VWAP en la ancla definido');
# hlc3 vela 1: (110 + 100 + 108)/3 = 318/3 = 106.0
is(sprintf("%.2f", $pt1->{value}), '106.00', 'Valor VWAP en la ancla coincide con HLC3 de la vela');

# Puntos posteriores
my $pt4 = $series->[4];
ok($pt4 && defined $pt4->{value}, 'VWAP acumulado en vela 4 definido');
ok(defined $pt4->{upper1} && defined $pt4->{lower1}, 'Banda 1 (+-1σ) definida');
ok(defined $pt4->{upper2} && defined $pt4->{lower2}, 'Banda 2 (+-2σ) definida');
is($pt4->{upper3}, undef, 'Banda 3 (+-3σ) es undef por estar desactivada');

ok($pt4->{upper1} > $pt4->{value}, 'Upper1 > VWAP central');
ok($pt4->{lower1} < $pt4->{value}, 'Lower1 < VWAP central');
ok($pt4->{upper2} > $pt4->{upper1}, 'Upper2 > Upper1');
ok($pt4->{lower2} < $pt4->{lower1}, 'Lower2 < Lower1');

# Re-anclar a la vela 2
$ind->set_anchor(2);
is($ind->anchor_index(), 2, 'Re-anclado a la vela 2');
my $series2 = $ind->get_values();
is($series2->[1], undef, 'Punto 1 ahora es undef tras re-anclar a 2');
ok(defined $series2->[2]->{value}, 'Punto 2 definido como nueva ancla');
