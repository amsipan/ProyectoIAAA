#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::ChartEngine;
use Market::OverlayManager;

# Helpers de catch-up (anti-artefactos carga SMC).
{
    my $ce = bless {
        _smc_fed_up_to     => 500,
        _smc_fvg_fed_up_to => 100,
    }, 'Market::ChartEngine';

    ok( $ce->_overlay_feed_caught_up( '_smc_fed_up_to', 500 ), 'caught-up exacto' );
    ok( $ce->_overlay_feed_caught_up( '_smc_fed_up_to', 400 ), 'caught-up por encima del target' );
    ok( !$ce->_overlay_feed_caught_up( '_smc_fed_up_to', 501 ), 'no caught-up si falta 1' );
    ok( $ce->_overlay_feed_caught_up( '_smc_fed_up_to', -1 ),  'feed_to < 0 → ready' );
}

# Defer flags por capa (SMC vs FVG independientes).
{
    package MockOv;
    sub new { bless { visible => $_[1], _defer_draw => 0 }, $_[0] }
    sub is_visible { $_[0]->{visible} }

    package main;
    my $mgr = Market::OverlayManager->new();
    my $smc = MockOv->new(1);
    my $fvg = MockOv->new(1);
    $mgr->register( 'smc_pro', $smc );
    $mgr->register( 'smc_fvg', $fvg );

    my $ce = bless {
        overlay_manager    => $mgr,
        _smc_fed_up_to     => 100,
        _smc_fvg_fed_up_to => 9999,
        market_data        => bless( {}, 'MockMD' ),
    }, 'Market::ChartEngine';
    {
        package MockMD;
        sub size { 10000 }
    }
    # _causal_end sin replay → size-1; stub mínimo
    no warnings 'redefine';
    local *Market::ChartEngine::_causal_end = sub { 5000 };

    $ce->_apply_smc_defer_draw_flags(5000);
    ok( $smc->{_defer_draw}, 'SMC defer si fed < feed_to' );
    ok( !$fvg->{_defer_draw}, 'FVG no defer si ya caught-up' );

    $ce->{_smc_fed_up_to} = 5000;
    $ce->_apply_smc_defer_draw_flags(5000);
    ok( !$smc->{_defer_draw}, 'SMC sin defer cuando caught-up' );
}

# OverlayManager omite _defer_draw en compute/draw.
{
    package MockOv2;
    sub new {
        my ( $c, %a ) = @_;
        bless {
            visible     => $a{visible} // 1,
            _defer_draw => $a{defer}   // 0,
            computed    => 0,
            drawn       => 0,
        }, $c;
    }
    sub is_visible      { $_[0]->{visible} }
    sub compute_visible { $_[0]->{computed}++ }
    sub draw            { $_[0]->{drawn}++ }

    package main;
    my $mgr = Market::OverlayManager->new();
    my $a = MockOv2->new( defer => 0 );
    my $b = MockOv2->new( defer => 1 );
    $mgr->register( 'a', $a );
    $mgr->register( 'b', $b );
    $mgr->compute_all( undef, 0, 10 );
    $mgr->draw_all( undef, undef );
    is( $a->{computed}, 1, 'compute activo sin defer' );
    is( $b->{computed}, 0, 'compute omitido con defer' );
    is( $a->{drawn},    1, 'draw activo sin defer' );
    is( $b->{drawn},    0, 'draw omitido con defer' );
}

# ChartEngine: background solo request_render si done.
{
    open my $fh, '<', 'Market/ChartEngine.pm' or die $!;
    my $src = do { local $/; <$fh> };
    close $fh;
    my ($body) = $src =~ /sub _schedule_smc_background_feed \{(.*?)\nsub /s;
    ok( defined $body, '_schedule_smc_background_feed presente' );
    like(
        $body // '',
        qr/if\s*\(\s*\$done\s*\)\s*\{[^}]*request_render/s,
        'request_render solo en rama done'
    );
    unlike(
        $body // '',
        qr/Re-render para ir mostrando estructura/,
        'comentario de paint parcial eliminado'
    );
}

done_testing();
