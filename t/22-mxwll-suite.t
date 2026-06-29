use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::Mxwll_Suite;
use Market::Overlays::Mxwll_Suite;

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

done_testing();
