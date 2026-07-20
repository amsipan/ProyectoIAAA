use strict;
use warnings;
use Test::More;

use lib '.';
use Market::OverlayManager;
use Market::Overlays::Base;
use Market::Overlays::SMC_Pro;
use Market::Overlays::SMC_Structures_FVG;
use Market::Panels::Scales;

# =============================================================================
# Spec 0013: overlays SMC Pro + Structures/FVG (reemplaza ov_smc híbrido).
# =============================================================================

{
    package TestCanvas;
    sub new { bless { w => 900, h => 600, ops => [] }, shift }
    sub delete {
        my ($self, @args) = @_;
        push @{ $self->{ops} }, [ delete => @args ];
        return;
    }
    sub createLine {
        my ($self, @args) = @_;
        push @{ $self->{ops} }, [ createLine => @args ];
        return scalar @{ $self->{ops} };
    }
    sub createRectangle {
        my ($self, @args) = @_;
        push @{ $self->{ops} }, [ createRectangle => @args ];
        return scalar @{ $self->{ops} };
    }
    sub createText {
        my ($self, @args) = @_;
        push @{ $self->{ops} }, [ createText => @args ];
        return scalar @{ $self->{ops} };
    }
}

{
    package TestSMCProInd;
    sub new {
        my ($class, %items) = @_;
        return bless { %items }, $class;
    }
    sub get_pivots       { shift->{pivots} || [] }
    sub get_events       { shift->{events} || [] }
    sub get_eqhl         { shift->{eqhl} || [] }
    sub get_order_blocks { shift->{obs} || [] }
    sub get_strong_weak  { shift->{sw} || [] }
    sub get_mtf_levels   { shift->{mtf} || [] }
    sub get_fvg          { [] }
    sub get_fibonacci    { [] }
    sub get_major        { [] }
}

{
    package TestFVGInd;
    sub new {
        my ($class, %items) = @_;
        return bless { %items }, $class;
    }
    sub get_events { shift->{events} || [] }
    sub get_fvg    { shift->{fvgs} || [] }
}

sub make_scales {
    my ($min_p, $max_p, $bars) = @_;
    $min_p //= 5;
    $max_p //= 25;
    $bars  //= 12;
    my $s = Market::Panels::Scales->new(
        min_y => $min_p, max_y => $max_p, bars => $bars, right_margin => 0
    );
    $s->{width}  = 900;
    $s->{height} = 600;
    return $s;
}

# --- SMC Pro ---
{
    my $ind = TestSMCProInd->new(
        pivots => [ { index => 1, type => 'HH', price => 20 } ],
        events => [
            { index => 3, type => 'BOS', dir => 'up', price => 18, start_index => 1, scope => 'swing' },
        ],
        obs => [
            { index => 2, hi => 19, lo => 17, bias => 'bull', active => 1, scope => 'swing' },
        ],
        # prev_price != price → línea diagonal (paridad Pine EQ)
        eqhl => [
            {
                index => 4, type => 'EQL', price => 10,
                prev_index => 1, prev_price => 12,
            },
        ],
        sw => [
            { index => 1, price => 20, type => 'Strong High', side => 'high' },
        ],
        mtf => [
            { index => 0, price => 15, label => 'PDH', tf => 'D', side => 'H' },
        ],
    );
    my $ov = Market::Overlays::SMC_Pro->new(indicator => $ind, theme => {}, visible => 1);
    ok(Market::Overlays::Base->validate($ov), 'SMC_Pro pasa contrato overlay');
    is($ov->tag(), 'ov_smc_pro', 'tag ov_smc_pro');

    my $mgr = Market::OverlayManager->new();
    $mgr->register('smc_pro', $ov);
    my @active = $mgr->each_active();
    ok(scalar(@active) >= 1, 'registrado smc_pro');

    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 12);  # width=900 → bar_w=75
    $ov->compute_visible(undef, $ind, 0, 10);
    $ov->draw($canvas, $scales);
    ok(scalar(@{ $canvas->{ops} }) > 0, 'SMC_Pro draw produce ops');

    # BOS: X en centro de vela (index 1 y 3), no en borde izquierdo
    my $bar_w = 900 / 12;
    my $center_1 = 1 * $bar_w + $bar_w / 2;
    my $center_3 = 3 * $bar_w + $bar_w / 2;
    my $left_1   = 1 * $bar_w;
    my ($bos_line) = grep {
        $_->[0] eq 'createLine'
        && defined $_->[1] && defined $_->[3]
        && abs(($_->[1] // 0) - $center_1) < 0.5
        && abs(($_->[3] // 0) - $center_3) < 0.5
    } @{ $canvas->{ops} };
    ok($bos_line, 'BOS anclado a centro de vela (no borde izquierdo)');
    ok(!$bos_line || abs(($bos_line->[1] // 0) - $left_1) > 1,
       'BOS no usa index_to_x (borde izquierdo)');

    # EQL diagonal: dos Y distintos (prev_price=12, price=10)
    my ($eq_line) = grep {
        $_->[0] eq 'createLine'
        && defined $_->[2] && defined $_->[4]
        && abs(($_->[2] // 0) - ($_->[4] // 0)) > 1
    } @{ $canvas->{ops} };
    ok($eq_line, 'EQL/EQH dibuja segmento diagonal (Y distinto en extremos)');

    # BOS no se estira hasta el fin de ventana: x2 = centro del break (index=3),
    # no del end=10.
    my $center_10 = 10 * $bar_w + $bar_w / 2;
    ok($bos_line && abs(($bos_line->[3] // 0) - $center_3) < 0.5,
       'BOS termina en vela de rotura, no en fin de ventana');
    ok(!$bos_line || abs(($bos_line->[3] // 0) - $center_10) > 1,
       'BOS no usa end de ventana como extremo derecho');

    # OB: borde izquierdo de la caja = centro de vela del bloque (paridad TV),
    # no borde izquierdo de la barra (media vela antes).
    my $center_2 = 2 * $bar_w + $bar_w / 2;
    my $left_2   = 2 * $bar_w;
    my ($ob_rect) = grep {
        $_->[0] eq 'createRectangle'
        && defined $_->[1]
        && abs(($_->[1] // 0) - $center_2) < 0.5
    } @{ $canvas->{ops} };
    ok($ob_rect, 'OB anclado al centro de vela (x1 = index_to_center_x)');
    ok(!$ob_rect || abs(($ob_rect->[1] // 0) - $left_2) > 1,
       'OB no usa borde izquierdo de barra (index_to_x)');

    $ov->clear($canvas);
    my $has_del = grep { $_->[0] eq 'delete' } @{ $canvas->{ops} };
    ok($has_del, 'clear emite delete');
}

# Strong/Weak y MTF no cruzan más allá de la última vela de datos
{
    package MockMD;
    sub new { bless { li => $_[1] }, $_[0] }
    sub last_index { $_[0]{li} }
    sub size { $_[0]{li} + 1 }
}

{
    my $ind = TestSMCProInd->new(
        events => [],
        sw => [
            { index => 1, price => 20, type => 'Weak High', side => 'high' },
        ],
        mtf => [
            { index => 0, price => 15, label => 'PDH', tf => 'D', side => 'H' },
        ],
    );
    my $ov = Market::Overlays::SMC_Pro->new(indicator => $ind, theme => {}, visible => 1);
    my $md = MockMD->new(5);          # datos solo hasta índice 5
    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 12);  # ventana local 0..11
    $ov->compute_visible($md, $ind, 0, 11);
    $ov->draw($canvas, $scales);

    my $bar_w = 900 / 12;
    # borde derecho de vela 5 = index_to_x(6) = 6*bar_w
    my $max_x = 6 * $bar_w + 1;  # tolerancia
    my @ext_lines = grep {
        $_->[0] eq 'createLine'
        && defined $_->[3]
        && ($_->[3] // 0) > $max_x
    } @{ $canvas->{ops} };
    ok(scalar(@ext_lines) == 0,
       'Strong/Weak y MTF no se extienden más allá de last_index de datos');
}

# Zoom independiente: BOS largo con extremos fuera del viewport SÍ se dibuja
{
    package MockMD2;
    sub new { bless { li => $_[1] }, $_[0] }
    sub last_index { $_[0]{li} }
    sub size { $_[0]{li} + 1 }
}

{
    my $ind = TestSMCProInd->new(
        events => [
            {
                # pivote y rotura FUERA del zoom [40,60]; el tramo lo cruza
                index => 100, start_index => 0, type => 'BOS', dir => 'up',
                price => 18, scope => 'swing',
            },
            {
                # totalmente a la izquierda del zoom → no
                index => 10, start_index => 0, type => 'BOS', dir => 'up',
                price => 12, scope => 'swing',
            },
            {
                # totalmente a la derecha → no
                index => 200, start_index => 150, type => 'CHoCH', dir => 'down',
                price => 22, scope => 'internal',
            },
        ],
    );
    my $ov = Market::Overlays::SMC_Pro->new(indicator => $ind, theme => {}, visible => 1);
    my $md = MockMD2->new(200);
    $ov->compute_visible($md, $ind, 40, 60);
    my $kept = $ov->{_events} || [];
    is(scalar(@$kept), 1, 'viewport: solo el BOS que cruza el zoom (extremos fuera OK)');
    is($kept->[0]{start_index}, 0, 'conserva start_index real (no recorta al zoom)');
    is($kept->[0]{index}, 100, 'conserva end de rotura real');

    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 21);  # 21 bars = 40..60
    $ov->draw($canvas, $scales);
    my $n_lines = scalar grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    ok($n_lines >= 1, 'draw emite línea aunque velas ancla no estén en pantalla');
}

# PDH al mismo precio que BOS no alarga el trazo de estructura:
# BOS (tag smc_evt) termina en break; MTF puede llegar a data_end con dash.
{
    my $ind = TestSMCProInd->new(
        events => [
            {
                index => 3, start_index => 1, type => 'BOS', dir => 'up',
                price => 18, scope => 'swing',
            },
        ],
        mtf => [
            { index => 1, price => 18, label => 'PDH', tf => 'D', side => 'H' },
        ],
    );
    my $ov = Market::Overlays::SMC_Pro->new(indicator => $ind, theme => {}, visible => 1);
    my $md = MockMD->new(10);
    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 12);
    $ov->compute_visible($md, $ind, 0, 10);
    $ov->draw($canvas, $scales);

    my $bar_w = 900 / 12;
    my $center_3 = 3 * $bar_w + $bar_w / 2;

    # Líneas de estructura (width 2, tag smc_evt) — fin en break bar 3
    my @evt_lines = grep {
        $_->[0] eq 'createLine'
        && ref($_->[-1]) eq 'ARRAY'
        && grep { $_ eq 'smc_evt' } @{ $_->[-1] }
    } @{ $canvas->{ops} };

    # Fallback: createLine args may pack -tags as hash-style
    if (!@evt_lines) {
        @evt_lines = grep {
            $_->[0] eq 'createLine'
            && join(',', @$_) =~ /smc_evt/
        } @{ $canvas->{ops} };
    }

    my $bos_ok = 0;
    for my $op (@evt_lines) {
        # coords: createLine x1,y1,x2,y2, -fill, ..., -tags
        my $x2 = $op->[3];
        $bos_ok = 1 if defined $x2 && abs($x2 - $center_3) < 1;
    }
    # Also accept any createLine whose x2 is center_3 (BOS) even if tag parse fails
    if (!$bos_ok) {
        for my $op (@{ $canvas->{ops} }) {
            next unless $op->[0] eq 'createLine';
            $bos_ok = 1 if abs(($op->[3] // -1) - $center_3) < 1
                        && abs(($op->[1] // -1) - (1 * $bar_w + $bar_w / 2)) < 1;
        }
    }
    ok($bos_ok, 'BOS (mismo precio que PDH) termina en vela de rotura, no en data_end');
}

# --- Structures FVG ---
{
    my $ind = TestFVGInd->new(
        fvgs => [
            { index => 5, left => 3, right => 5, hi => 12, lo => 10, type => 'bull', mitig => 0, active => 1 },
        ],
        events => [
            { index => 6, type => 'CHoCH', dir => 'up', price => 12, start_index => 2, color_role => 'choch_bull' },
        ],
    );
    my $ov = Market::Overlays::SMC_Structures_FVG->new(indicator => $ind, theme => {}, visible => 1);
    ok(Market::Overlays::Base->validate($ov), 'SMC_Structures_FVG pasa contrato');
    is($ov->tag(), 'ov_smc_fvg', 'tag ov_smc_fvg');

    my $canvas = TestCanvas->new();
    my $scales = make_scales();
    $ov->compute_visible(undef, $ind, 0, 10);
    $ov->draw($canvas, $scales);
    ok(scalar(@{ $canvas->{ops} }) > 0, 'FVG overlay draw produce ops');
}

done_testing();
