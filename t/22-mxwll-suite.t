use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::Mxwll_Suite;
use Market::Overlays::Mxwll_Suite;
use Market::Panels::Scales;

# --- Mock de canvas Tk: registra las ops de dibujo sin GUI ---
{
    package TestCanvas;
    sub new { bless { w => 900, h => 600, ops => [] }, shift }
    sub delete { my ($s,@a)=@_; push @{$s->{ops}}, [delete=>@a]; return; }
    sub createLine { my ($s,@a)=@_; push @{$s->{ops}}, [createLine=>@a]; return scalar @{$s->{ops}}; }
    sub createRectangle { my ($s,@a)=@_; push @{$s->{ops}}, [createRectangle=>@a]; return scalar @{$s->{ops}}; }
    sub createText { my ($s,@a)=@_; push @{$s->{ops}}, [createText=>@a]; return scalar @{$s->{ops}}; }
}
sub mx_op_arg {
    my ($op, $key) = @_;
    my @a = @$op;
    for my $i (0 .. $#a - 1) {
        return $a[$i + 1] if defined $a[$i] && $a[$i] eq "-$key";
    }
    return undef;
}
sub mx_scales {
    my $s = Market::Panels::Scales->new(min_y => 5, max_y => 25, bars => 30, right_margin => 0);
    $s->{width} = 900; $s->{height} = 600;
    return $s;
}

# Helper: construir MarketData sintético desde lista [O,H,L,C].
sub build_ohlc {
    my ($candles) = @_;
    my $md = Market::MarketData->new();
    for my $i (0 .. $#{$candles}) {
        my ($o, $h, $l, $c) = @{ $candles->[$i] };
        my $ts = sprintf("2026-04-06T00:%02d:00-05:00", $i);
        $md->add_candle([$ts, $o, $h, $l, $c, 10]);
    }
    return $md;
}

# =============================================================================
# 1. Contrato del indicador: get_values / update_last / reset
# =============================================================================
{
    my $ind = Market::Indicators::Mxwll_Suite->new();
    ok($ind->can('update_last'), 'indicador: tiene update_last');
    ok($ind->can('get_values'),  'indicador: tiene get_values');
    ok($ind->can('reset'),       'indicador: tiene reset');

    my @c = ([10,11,9,10],[10,12,10,11],[11,14,11,13],[13,18,13,17],[16,17,12,13]);
    my $md = build_ohlc(\@c);
    $ind->update_last($md, $_) for 0 .. $md->last_index;
    my $v = $ind->get_values();
    for my $key (qw(swings structures high_blocks low_blocks fvgs)) {
        is(ref $v->{$key}, 'ARRAY', "get_values: '$key' es arrayref");
    }
}

# =============================================================================
# 2. FVG alcista: low[i] > high[i-2] → hueco (high[i-2], low[i])
# =============================================================================
{
    my @c = ([9,10,9,10],[10,11,10,11],[12,14,12,13],[13,15,13,14]);
    my $md = build_ohlc(\@c);
    my $ind = Market::Indicators::Mxwll_Suite->new();
    $ind->update_last($md, $_) for 0 .. $md->last_index;
    my @up = grep { $_->{dir} eq 'up' } @{ $ind->get_values()->{fvgs} };
    ok(scalar(@up) >= 1, 'FVG alcista detectado');
    my ($g) = grep { abs($_->{bottom} - 10) < 1e-9 && abs($_->{top} - 12) < 1e-9 } @up;
    ok($g, 'FVG alcista con hueco (10,12)');
}

# =============================================================================
# 3. FVG bajista: high[i] < low[i-2] → hueco (high[i], low[i-2])
# =============================================================================
{
    my @c = ([14,15,13,14],[12,13,11,12],[8,9,7,8],[7,8,6,7]);
    my $md = build_ohlc(\@c);
    my $ind = Market::Indicators::Mxwll_Suite->new();
    $ind->update_last($md, $_) for 0 .. $md->last_index;
    my @dn = grep { $_->{dir} eq 'down' } @{ $ind->get_values()->{fvgs} };
    ok(scalar(@dn) >= 1, 'FVG bajista detectado');
    my ($g) = grep { abs($_->{top} - 13) < 1e-9 && abs($_->{bottom} - 9) < 1e-9 } @dn;
    ok($g, 'FVG bajista con hueco (9,13)');
}

# =============================================================================
# 4. Mitigación de FVG alcista: si el precio rellena el hueco, se desactiva
# =============================================================================
{
    # FVG alcista (10,12) en idx 1-2, luego vela 4 baja a low=9 < 10 → mitigado.
    my @c = ([9,10,9,10],[10,11,10,11],[12,14,12,13],[13,15,13,14],[11,12,9,10]);
    my $md = build_ohlc(\@c);
    my $ind = Market::Indicators::Mxwll_Suite->new();
    $ind->update_last($md, $_) for 0 .. $md->last_index;
    my @up = grep { $_->{dir} eq 'up' && abs($_->{bottom} - 10) < 1e-9 } @{ $ind->get_values()->{fvgs} };
    is(scalar(@up), 0, 'FVG alcista (10,12) mitigado tras rellenar el hueco');
}

# =============================================================================
# 5. reset() limpia todo el estado
# =============================================================================
{
    my @c = ([9,10,9,10],[10,11,10,11],[12,14,12,13],[13,15,13,14]);
    my $md = build_ohlc(\@c);
    my $ind = Market::Indicators::Mxwll_Suite->new();
    $ind->update_last($md, $_) for 0 .. $md->last_index;
    ok(scalar(@{ $ind->get_values()->{fvgs} }) > 0, 'reset: hay FVG antes del reset');
    $ind->reset();
    my $v = $ind->get_values();
    is(scalar(@{ $v->{fvgs} }), 0, 'reset: fvgs vacío');
    is(scalar(@{ $v->{structures} }), 0, 'reset: structures vacío');
    is(scalar(@{ $v->{swings} }), 0, 'reset: swings vacío');
}

# =============================================================================
# 6. Equivalencia incremental == batch (cero estado residual)
# =============================================================================
{
    my @c = ([10,11,9,10],[10,12,10,11],[11,14,11,13],[13,18,13,17],
             [16,17,12,13],[13,14,10,11],[11,12,8,9],[9,11,9,10],
             [10,13,10,12],[12,20,12,19]);
    my $md = build_ohlc(\@c);
    my $ind = Market::Indicators::Mxwll_Suite->new(int_sens=>3, ext_sens=>3);
    $ind->update_last($md, $_) for 0 .. $md->last_index;
    my $n1 = scalar @{ $ind->get_values()->{structures} };

    $ind->reset();
    $ind->update_last($md, $_) for 0 .. $md->last_index;
    my $n2 = scalar @{ $ind->get_values()->{structures} };
    is($n1, $n2, 'equiv: mismas estructuras tras reset+recálculo');
}

# =============================================================================
# 7. Datos reales (CSV) en 2h: estructura + FVG + AOE no vacíos
# =============================================================================
SKIP: {
    skip "Data/2026_03.csv no disponible", 4 unless -e 'Data/2026_03.csv';
    my $md = Market::MarketData->new();
    open my $fh, '<', 'Data/2026_03.csv' or skip "no se pudo abrir CSV", 4;
    my $hdr = <$fh>;
    while (my $l = <$fh>) {
        chomp $l; next unless length $l;
        my @f = split /,/, $l; next unless @f >= 6;
        $md->add_candle([$f[0], $f[1]+0, $f[2]+0, $f[3]+0, $f[4]+0, $f[5]+0]);
    }
    close $fh;
    $md->build_timeframes();
    $md->set_timeframe('2h');
    my $ind = Market::Indicators::Mxwll_Suite->new;
    $ind->update_last($md, $_) for 0 .. $md->last_index;
    my $v = $ind->get_values();

    ok(scalar(@{ $v->{structures} }) > 0, 'real 2h: hay estructuras BOS/CHoCH');
    ok(scalar(@{ $v->{fvgs} }) >= 0,       'real 2h: fvgs es lista válida');
    ok(defined $v->{aoe},                  'real 2h: AOE calculado');
    # Las estructuras deben tener etiquetas válidas del Mxwll.
    my %valid = map { $_ => 1 } qw(BoS CHoCH I-BoS I-CHoCH);
    my $all_valid = 1;
    for my $s (@{ $v->{structures} }) { $all_valid = 0 unless $valid{$s->{label}}; }
    ok($all_valid, 'real 2h: todas las estructuras tienen etiqueta válida');
}

# =============================================================================
# 8. Contrato del overlay: tag, visibilidad, toggles, draw sin canvas no muere
# =============================================================================
{
    my $ind = Market::Indicators::Mxwll_Suite->new;
    my $ov = Market::Overlays::Mxwll_Suite->new(indicator => $ind, visible => 0);
    is($ov->tag(), 'ov_mxwll', 'overlay: tag ov_mxwll');
    is($ov->is_visible(), 0, 'overlay: oculto por defecto');
    $ov->set_visible(1);
    is($ov->is_visible(), 1, 'overlay: set_visible(1)');

    for my $el (qw(STRUCTURE SWINGS OB FVG AOE FIBS)) {
        is($ov->is_element_visible($el), 1, "overlay: elemento $el visible por defecto");
        $ov->set_element_visible($el, 0);
        is($ov->is_element_visible($el), 0, "overlay: elemento $el desactivable");
    }
    # compute_visible guarda la ventana sin requerir Tk.
    $ov->compute_visible(undef, undef, 5, 20);
    is($ov->{_start}, 5, 'overlay: compute_visible guarda start');
    is($ov->{_end}, 20, 'overlay: compute_visible guarda end');
    # draw sin canvas retorna sin morir.
    ok(eval { $ov->draw(undef, undef); 1 }, 'overlay: draw sin canvas no muere');
}

# =============================================================================
# 9. ORDEN 1 (task 0021 C+A): filtro de estado por volatilidad (rango lateral)
# =============================================================================
# El filtro debe REDUCIR las etiquetas de estructura cuando state_atr_factor>0
# (suprime breaks dentro de rango lateral) y NO cambiar nada con factor=0.
SKIP: {
    my $csv = -e 'Data/2026_06_29.csv' ? 'Data/2026_06_29.csv'
            : -e 'Data/2026_03.csv'    ? 'Data/2026_03.csv'
            : undef;
    skip "no hay CSV de datos reales", 4 unless $csv;
    my $md = Market::MarketData->new();
    open my $fh, '<', $csv or skip "no se pudo abrir CSV", 4;
    my $hdr = <$fh>;
    while (my $l = <$fh>) {
        chomp $l; next unless length $l;
        my @f = split /,/, $l; next unless @f >= 6;
        $md->add_candle([$f[0], $f[1]+0, $f[2]+0, $f[3]+0, $f[4]+0, $f[5]+0]);
    }
    close $fh;
    $md->build_timeframes();
    $md->set_timeframe('1m');
    my $last = $md->last_index;

    # factor=0 → sin filtro (comportamiento previo).
    my $i0 = Market::Indicators::Mxwll_Suite->new(state_atr_factor => 0);
    $i0->update_last($md, $_) for 0 .. $last;
    my $n0 = scalar @{ $i0->get_values->{structures} };

    # factor=2.0 (default) → filtra rango lateral.
    my $i2 = Market::Indicators::Mxwll_Suite->new(state_atr_factor => 2.0);
    $i2->update_last($md, $_) for 0 .. $last;
    my $n2 = scalar @{ $i2->get_values->{structures} };

    ok($n0 > 0, "ORDEN1: con factor=0 hay estructuras ($n0)");
    ok($n2 < $n0, "ORDEN1: factor=2.0 reduce el ruido ($n2 < $n0)");

    # El default del constructor debe aplicar el filtro (no factor=0).
    my $idef = Market::Indicators::Mxwll_Suite->new;
    $idef->update_last($md, $_) for 0 .. $last;
    my $ndef = scalar @{ $idef->get_values->{structures} };
    is($ndef, $n2, 'ORDEN1: el default usa state_atr_factor=2.0');

    # Las etiquetas externas (estructura mayor) deben preservarse casi intactas:
    # el filtro ataca el ruido interno, no la estructura mayor.
    my %c0; $c0{$_->{label}}++ for @{ $i0->get_values->{structures} };
    my %c2; $c2{$_->{label}}++ for @{ $i2->get_values->{structures} };
    my $ext0 = ($c0{BoS}//0) + ($c0{CHoCH}//0);
    my $ext2 = ($c2{BoS}//0) + ($c2{CHoCH}//0);
    ok($ext2 >= $ext0 * 0.8,
       "ORDEN1: estructura externa preservada (ext0=$ext0 ext2=$ext2)");
}

# =============================================================================
# 10. ORDEN 2 (task 0021 A): filtro de volatilidad para swings (HH/HL/LH/LL)
# =============================================================================
# _swing_significant: true si |price - eje_opuesto| >= swing_atr_factor * ATR.
{
    my $i = Market::Indicators::Mxwll_Suite->new(swing_atr_factor => 1.5);
    $i->{_atr_last} = 10;   # tol = 1.5*10 = 15
    is($i->_swing_significant(120, 100), 1, 'ORDEN2: recorrido 20 (>=15) significativo');
    is($i->_swing_significant(105, 100), 0, 'ORDEN2: recorrido 5 (<15) NO significativo');
    is($i->_swing_significant(105, undef), 1, 'ORDEN2: sin eje opuesto -> significativo');
    is($i->_swing_significant(105, 100), 0, 'ORDEN2: re-chequeo determinista');

    my $j = Market::Indicators::Mxwll_Suite->new(swing_atr_factor => 0);
    $j->{_atr_last} = 10;
    is($j->_swing_significant(105, 100), 1, 'ORDEN2: factor=0 desactiva el filtro');

    # Sin ATR todavia -> no censurar.
    my $k = Market::Indicators::Mxwll_Suite->new(swing_atr_factor => 1.5);
    is($k->_swing_significant(105, 100), 1, 'ORDEN2: sin ATR aun -> significativo');
}

# =============================================================================
# 11. ORDEN 14 (task 0026): order blocks etiquetados con "OB"
# =============================================================================
{
    package MxStubOB;
    sub new { bless { v => $_[1] }, $_[0] }
    sub get_values { $_[0]->{v} }
}
{
    my $vals = {
        swings => [], structures => [], fvgs => [], aoe => undef, fibs => undef,
        high_blocks => [ { index => 2, top => 20, bottom => 19.9, active => 1 } ],
        low_blocks  => [ { index => 4, top => 10.1, bottom => 10, active => 1 } ],
    };
    my $ov = Market::Overlays::Mxwll_Suite->new(indicator => MxStubOB->new($vals), visible => 1);
    # Solo OB visible para aislar.
    $ov->set_element_visible($_, 0) for qw(STRUCTURE SWINGS FVG AOE FIBS);
    $ov->compute_visible(undef, undef, 0, 29);
    my $canvas = TestCanvas->new();
    $ov->draw($canvas, mx_scales());

    my @texts = grep { $_->[0] eq 'createText' } @{ $canvas->{ops} };
    my %seen  = map { (mx_op_arg($_, 'text') // '') => 1 } @texts;
    ok($seen{'Bear OB'}, 'ORDEN14: high_block etiquetado "Bear OB"');
    ok($seen{'Bull OB'}, 'ORDEN14: low_block etiquetado "Bull OB"');

    my @rects = grep { $_->[0] eq 'createRectangle' } @{ $canvas->{ops} };
    is(scalar(@rects), 2, 'ORDEN14: se dibujan las 2 cajas de order block');
}

done_testing();
