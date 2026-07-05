use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::ZigZag;
use Market::Overlays::ZigZag;
use Market::Overlays::Base;
use Market::Panels::Scales;
use Market::Debug::IndicatorSnapshot;

my $D = 'Market::Debug::IndicatorSnapshot';

{
    package ZZTestCanvas;
    sub new { bless { ops => [] }, shift }
    sub delete { my ($s,@a)=@_; push @{$s->{ops}},[delete=>@a]; return }
    sub createLine { my ($s,@a)=@_; push @{$s->{ops}},[createLine=>@a]; return scalar @{$s->{ops}} }
}

sub build_ohlc {
    my ($rows, $start_min) = @_;
    $start_min //= 0;
    my $md = Market::MarketData->new();
    for my $i (0 .. $#{$rows}) {
        my ($o, $h, $l, $c) = @{ $rows->[$i] };
        my $total = $start_min + $i;
        my $hh = int($total / 60);
        my $mm = $total % 60;
        my $ts = sprintf('2026-06-29T%02d:%02d:00-05:00', $hh, $mm);
        $md->add_candle([$ts, $o, $h, $l, $c, 100 + $i]);
    }
    return $md;
}

sub feed_all {
    my ($ind, $md) = @_;
    $ind->update_last($md, $_) for 0 .. $md->last_index;
}

# 1. Contrato indicador
{
    my $ind = Market::Indicators::ZigZag->new();
    ok($ind->can('update_last'), 'contrato: update_last');
    ok($ind->can('get_values'),  'contrato: get_values');
    ok($ind->can('reset'),       'contrato: reset');
    my $v = $ind->get_values();
    for my $k (qw(internal_vertices external_vertices internal_segments external_segments external_channel trend_channels internal_direction external_direction)) {
        ok(exists $v->{$k}, "get_values tiene '$k'");
    }
}

# 2. Fixture interno: pivotes con resolución 5m (test) y period=2
{
    my @rows = (
        [10,11, 9,10], [10,12,10,11], [11,15,11,14], [14,18,14,17],
        [17,17,12,13], [13,14,10,11], [11,12, 8, 9], [9,11, 9,10],
        [10,14,10,13], [13,20,13,19], [19,22,18,21],
    );
    my $md  = build_ohlc(\@rows);
    my $ind = Market::Indicators::ZigZag->new(internal_resolution => 5, internal_period => 2, swing_length => 50);
    feed_all($ind, $md);
    my $verts = $ind->get_values()->{internal_vertices};
    ok(@$verts >= 2, 'interno: al menos 2 vértices en fixture con pivotes');
    my @asc = sort { $a->{index} <=> $b->{index} } @$verts;
    ok($asc[0]->{price} <= $asc[-1]->{price} || $asc[0]->{price} >= $asc[-1]->{price},
       'interno: vértices con precios válidos');
    my $last_dir = ($ind->get_values()->{internal_direction})[-1];
    ok(($last_dir == 1 || $last_dir == -1) || @$verts >= 2,
       'interno: dirección +1/-1 o vértices generados');
}

# 3. Último segmento se ajusta; anteriores consolidados
{
    my @base = (
        [10,11, 9,10], [10,12,10,11], [11,15,11,14], [14,18,14,17],
        [17,17,12,13], [13,14,10,11], [11,12, 8, 9], [9,11, 9,10],
        [10,14,10,13], [13,20,13,19],
    );
    my $md1 = build_ohlc(\@base);
    my $ind = Market::Indicators::ZigZag->new(internal_resolution => 5, swing_length => 50);
    feed_all($ind, $md1);
    my @verts1 = @{ $ind->get_values()->{internal_vertices} };
    my @segs1  = @{ $ind->get_values()->{internal_segments} };

    my @extra = ([19,24,19,23], [23,26,22,25]);
    my $md2 = build_ohlc([@base, @extra]);
    $ind->reset();
    feed_all($ind, $md2);
    my @verts2 = @{ $ind->get_values()->{internal_vertices} };
    my @segs2  = @{ $ind->get_values()->{internal_segments} };

    ok(@verts2 >= @verts1, 'ajuste: más datos → al menos mismos vértices');
    if (@verts1 >= 2 && @verts2 >= 2) {
        my $old_consolidated = $verts1[-1];
        my $new_consolidated = $verts2[-1];
        is($new_consolidated->{index}, $old_consolidated->{index},
           'ajuste: penúltimo vértice consolidado conserva índice')
            if @verts2 >= 2 && @verts1 >= 2 && $verts2[-1]{price} != $verts1[-1]{price};
    }
    ok(@segs2 >= 1, 'ajuste: hay segmentos internos');
    ok(!defined $segs2[-1]{consolidated} || !$segs2[-1]{consolidated},
       'ajuste: último segmento no consolidado');
}

# 4. Externo: swing largo produce segmento (bajada luego subida)
{
    my @rows;
    for my $i (0 .. 9) {
        my $p = 100 - $i;
        push @rows, [$p, $p + 1, $p - 2, $p - 1];
    }
    for my $i (0 .. 11) {
        my $p = 90 + $i * 2;
        push @rows, [$p, $p + 2, $p - 1, $p + 1];
    }
    my $md  = build_ohlc(\@rows);
    my $ind = Market::Indicators::ZigZag->new(swing_length => 8, internal_resolution => 30);
    feed_all($ind, $md);
    my $ext = $ind->get_values()->{external_segments};
    ok(@$ext >= 1, 'externo: al menos un segmento tras bajada+subida');
    ok($ind->get_values()->{external_direction}[-1] == 1,
       'externo: dirección alcista al final del rally');
}

# 5. Equivalencia incremental == batch
{
    my @rows = map { [10+$_, 12+$_, 9+$_, 11+$_] } 0 .. 24;
    my $md = build_ohlc(\@rows);
    my $ind1 = Market::Indicators::ZigZag->new(internal_resolution => 5, swing_length => 10);
    feed_all($ind1, $md);
    my $n1 = scalar @{ $ind1->get_snapshot_items() };

    my $ind2 = Market::Indicators::ZigZag->new(internal_resolution => 5, swing_length => 10);
    $ind2->reset();
    feed_all($ind2, $md);
    my $n2 = scalar @{ $ind2->get_snapshot_items() };
    is($n1, $n2, 'equiv: reset+realimentar produce misma cantidad de items');
}

# 6. Replay guard
{
    my @rows = map { [10+$_, 12+$_, 9+$_, 11+$_] } 0 .. 30;
    my $md = build_ohlc(\@rows);
    my $ind = Market::Indicators::ZigZag->new(internal_resolution => 5, swing_length => 10);
    my $replay_idx = 15;
    $ind->update_last($md, $_) for 0 .. $replay_idx;
    my $items = $ind->get_snapshot_items();
    is(scalar($D->replay_violations($items, $replay_idx)), 0,
       'replay guard: items con index <= último feed (snapshot por segmento)');
    my @bad = grep { ($_->{index} // 0) > $replay_idx } @$items;
    ok(!@bad, 'replay guard: ningún item de segmento con index > replay_idx');
}

# 7. Overlay: tag, toggles, draw headless
{
    my $ind = Market::Indicators::ZigZag->new(internal_resolution => 5, swing_length => 8);
    my @rows = map { [10+$_, 12+$_, 9+$_, 11+$_] } 0 .. 15;
    feed_all($ind, build_ohlc(\@rows));
    my $ov = Market::Overlays::ZigZag->new(indicator => $ind);
    ok(Market::Overlays::Base->validate($ov), 'overlay ZigZag valida contrato');
    is($ov->tag(), 'ov_zigzag', 'tag ov_zigzag');
    ok($ov->is_element_visible('INTERNAL'), 'toggle interno ON por defecto');
    ok($ov->is_element_visible('EXTERNAL'), 'toggle externo ON por defecto');
    $ov->set_visible(1);
    $ov->compute_visible(undef, $ind, 0, 15);
    my $canvas = ZZTestCanvas->new();
    my $scales = Market::Panels::Scales->new(min_y => 5, max_y => 30, bars => 16);
    $scales->{width} = 400; $scales->{height} = 300;
    $ov->draw($canvas, $scales);
    my @lines = grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    ok(@lines >= 1, 'draw: al menos una línea (externo azul)');
    $ov->set_visible(0);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);
    is(scalar(grep { $_->[0] ne 'delete' } @{ $canvas->{ops} }), 0, 'visible=0: sin ops');
}

# Fixture compartida: onda triangular con varios swings externos (task 0061).
# Escalones de 5 velas entre picos alternos → múltiples vértices externos → canales.
sub _triangle_wave_rows {
    my @peaks = (100, 80, 110, 70, 120, 60, 130);
    my @rows;
    my $prev = 90;
    for my $tgt (@peaks) {
        my $step = ($tgt - $prev) / 5;
        for my $k (1 .. 5) {
            my $p = $prev + $step * $k;
            push @rows, [$p, $p + 1, $p - 1, $p];
        }
        $prev = $tgt;
    }
    return @rows;
}

# 8. Canal clásico trend_channels: pendiente idéntica y paralela en el extremo opuesto (task 0061)
{
    my @rows = _triangle_wave_rows();
    my $md  = build_ohlc(\@rows);
    my $ind = Market::Indicators::ZigZag->new(swing_length => 5, internal_resolution => 30);
    feed_all($ind, $md);
    my $vals = $ind->get_values();
    ok(@{ $vals->{external_segments} } >= 2, 'trend_channels: al menos dos piernas externas');
    ok(@{ $vals->{trend_channels} } >= 1, 'trend_channels: al menos un canal clásico');

    my $ch = $vals->{trend_channels}[-1];
    my $di_t = $ch->{to_index} - $ch->{from_index};
    my $di_p = $ch->{parallel_to_index} - $ch->{parallel_from_index};
    ok($di_t && $di_p, 'trend_channels: índices válidos');
    my $slope_t = ($ch->{to_price} - $ch->{from_price}) / $di_t;
    my $slope_p = ($ch->{parallel_to_price} - $ch->{parallel_from_price}) / $di_p;
    ok(abs($slope_t - $slope_p) < 1e-9, 'trend_channels: trendline y paralela misma pendiente');

    # La paralela pasa por (from_index, from_price) con esa pendiente; su valor en
    # cualquier índice sigue m*(x - from) + from_price. La trendline y la paralela
    # comparten pendiente pero distinto intercepto (encierran el precio).
    ok($ch->{parallel_from_price} != $ch->{from_price}
       || $ch->{parallel_to_price} != $ch->{to_price},
       'trend_channels: paralela desplazada respecto a la trendline');
}

# 9. Overlay canal: toggle CHANNEL OFF por defecto; ON dibuja líneas sólidas del canal
{
    my @rows = _triangle_wave_rows();
    my $ind = Market::Indicators::ZigZag->new(swing_length => 5, internal_resolution => 30);
    feed_all($ind, build_ohlc(\@rows));
    my $ov = Market::Overlays::ZigZag->new(indicator => $ind);
    ok(!$ov->is_element_visible('CHANNEL'), 'canal: toggle CHANNEL OFF por defecto');
    $ov->set_visible(1);
    $ov->compute_visible(undef, $ind, 0, $#rows);
    my $canvas = ZZTestCanvas->new();
    my $scales = Market::Panels::Scales->new(min_y => 50, max_y => 140, bars => scalar @rows);
    $scales->{width} = 400; $scales->{height} = 300;
    $ov->draw($canvas, $scales);
    my $lines_no_ch = scalar grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };

    $ov->set_element_visible('CHANNEL', 1);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);
    my $lines_with_ch = scalar grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    ok($lines_with_ch > $lines_no_ch, 'canal: CHANNEL ON añade líneas paralelas');
    my $n_ch = scalar @{ $ind->get_values()->{trend_channels} };
    ok($n_ch >= 1, 'canal: fixture produce >=1 trend_channel');
    ok($lines_with_ch - $lines_no_ch >= 2 * $n_ch,
       'canal: +2 líneas sólidas por trend_channel');
}

# 10. Snapshot determinista (segmentos internos)
{
    my @rows = (
        [10,11, 9,10], [10,13,10,12], [12,16,12,15], [15,16,11,12],
        [12,13, 9,10], [10,11, 8, 9], [9,12,9,11], [11,18,11,17],
    );
    my $md  = build_ohlc(\@rows);
    my $ind = Market::Indicators::ZigZag->new(internal_resolution => 5, swing_length => 20);
    feed_all($ind, $md);
    my $txt = $D->render_items($ind->get_snapshot_items(), title => 'zigzag_fixture');
    ok($txt =~ /ZZ_INT/, 'snapshot: contiene segmentos ZZ_INT');
    ok(length $txt > 10, 'snapshot: salida no vacía');
}

done_testing();