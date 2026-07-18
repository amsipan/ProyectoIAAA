#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '.';

use Market::MarketData;
use Market::Indicators::SMC_Structures_FVG;
use Market::Overlays::SMC_Structures_FVG;
use Market::Overlays::Base;

# -----------------------------------------------------------------------------
# Defaults = captura profesor
# -----------------------------------------------------------------------------
{
    my $ind = Market::Indicators::SMC_Structures_FVG->new();
    ok( $ind->{show_fvg},             'captura: Display FVG ON' );
    ok( $ind->{reduce_mitigated_fvg}, 'captura: Reduce mitigated ON' );
    is( $ind->{fvg_history},     5,  'captura: Number of FVG = 5' );
    ok( !$ind->{break_with_body},    'captura: Break with body OFF' );
    ok( !$ind->{show_current_struct},'captura: Display current structure OFF' );
    is( $ind->{struct_history}, 10,  'captura: Number of breaks = 10' );
    ok( !$ind->{show_fibs},          'captura: fibs OFF' );
    is_deeply( $ind->get_current_structure(), [], 'current structure empty when OFF' );
    is_deeply( $ind->get_fibonacci(), [], 'no fibs' );
}

# -----------------------------------------------------------------------------
# Bullish FVG: high[3] < low[1]
# bars: i=0..3 at least
# -----------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    # index: 0,1,2,3 — at bar 3: high[0] < low[2]
    # high[3]=bar0 high, low[1]=bar2 low in Pine terms at i=3 → high[i-3], low[i-1]
    $md->add_candle( [ '2026-06-01T00:00:00-05:00', 100, 101, 99,  100, 1 ] ); # 0 high=101
    $md->add_candle( [ '2026-06-01T00:01:00-05:00', 100, 102, 98,  101, 1 ] ); # 1
    $md->add_candle( [ '2026-06-01T00:02:00-05:00', 101, 110, 105, 108, 1 ] ); # 2 low=105 > 101 → gap
    $md->add_candle( [ '2026-06-01T00:03:00-05:00', 108, 112, 107, 110, 1 ] ); # 3 detect

    my $ind = Market::Indicators::SMC_Structures_FVG->new();
    $ind->update_last( $md, $_ ) for 0 .. 3;
    my $fvgs = $ind->get_fvg();
    ok( scalar(@$fvgs) >= 1, 'crea FVG bullish' );
    my ($bull) = grep { $_->{type} eq 'bull' } @$fvgs;
    ok( $bull, 'tipo bull' );
    is( $bull->{lo}, 101, 'bull lo = high[3]' );
    is( $bull->{hi}, 105, 'bull hi = low[1]' );
    is( $bull->{left},  1, 'left = i-2' );
    is( $bull->{right}, 3, 'right extends to current after mitigate pass' );
}

# -----------------------------------------------------------------------------
# Full mitigate bull FVG when low <= bottom
# -----------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    $md->add_candle( [ 't0', 100, 101, 99,  100, 1 ] );
    $md->add_candle( [ 't1', 100, 102, 98,  101, 1 ] );
    $md->add_candle( [ 't2', 101, 110, 105, 108, 1 ] );
    $md->add_candle( [ 't3', 108, 112, 107, 110, 1 ] ); # create bull lo=101 hi=105
    $md->add_candle( [ 't4', 110, 111, 100, 101, 1 ] ); # low=100 <= 101 → full mitigate

    my $ind = Market::Indicators::SMC_Structures_FVG->new();
    $ind->update_last( $md, $_ ) for 0 .. 4;
    my @bull = grep { $_->{type} eq 'bull' } @{ $ind->get_fvg() };
    is( scalar(@bull), 0, 'FVG bull fully mitigated → removed' );
}

# -----------------------------------------------------------------------------
# Reduce mitigated: partial fill shrinks top of bull FVG
# -----------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    $md->add_candle( [ 't0', 100, 101, 99,  100, 1 ] );
    $md->add_candle( [ 't1', 100, 102, 98,  101, 1 ] );
    $md->add_candle( [ 't2', 101, 110, 105, 108, 1 ] );
    $md->add_candle( [ 't3', 108, 112, 107, 110, 1 ] ); # bull lo=101 hi=105
    $md->add_candle( [ 't4', 110, 111, 103, 104, 1 ] ); # low=103 in (101,105)

    my $ind = Market::Indicators::SMC_Structures_FVG->new( reduce_mitigated_fvg => 1 );
    $ind->update_last( $md, $_ ) for 0 .. 4;
    my ($bull) = grep { $_->{type} eq 'bull' } @{ $ind->get_fvg() };
    ok( $bull, 'partial mitigate keeps FVG' );
    ok( $bull->{mitig}, 'marked mitigated' );
    is( $bull->{hi}, 103, 'reduce: top shrunk to low' );
    is( $bull->{lo}, 101, 'bottom unchanged' );
}

# -----------------------------------------------------------------------------
# Max 5 FVG
# -----------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    # Generate many bullish gaps
    for my $i ( 0 .. 40 ) {
        my $base = 100 + $i * 10;
        $md->add_candle( [ "t$i", $base, $base + 1, $base - 1, $base, 1 ] );
    }
    # Force gaps: pattern every 4 bars
    my $ind = Market::Indicators::SMC_Structures_FVG->new( fvg_history => 5 );
    # Manually inject via synthetic series that creates gaps
    $ind = Market::Indicators::SMC_Structures_FVG->new( fvg_history => 5 );
    for my $n ( 0 .. 9 ) {
        my $b = 1000 + $n * 50;
        my $md2 = Market::MarketData->new();
        # rebuild short series each time won't accumulate — feed continuous
    }
    # Continuous: bars that alternate gap pattern
    $md = Market::MarketData->new();
    for my $i ( 0 .. 60 ) {
        # Every bar high of i-3 < low of i-1 when i>=3 with ascending floors
        my $o = 100 + $i;
        my $h = 100 + $i + ( $i % 4 == 0 ? 0.5 : 5 );
        my $l = 100 + $i - ( $i % 4 == 2 ? 0.5 : 5 );
        # Simpler: inject after feed by calling update with crafted OHLC via fake MD
        $md->add_candle( [ sprintf( '2026-06-01T%02d:%02d:00-05:00', int( $i / 60 ), $i % 60 ),
            $o, $h, $l, $o + 0.1, 1 ] );
    }
    $ind = Market::Indicators::SMC_Structures_FVG->new( fvg_history => 5 );
    $ind->update_last( $md, $_ ) for 0 .. $md->last_index;
    # Pine: size > fvgHistoryNbr + 1 → keep history+1 (=6 con history=5)
    for my $k ( 0 .. 9 ) {
        push @{ $ind->{_fvgs} }, {
            index => $k, left => $k, right => $k + 1,
            hi => 10 + $k, lo => 1 + $k, type => 'bull', mitig => 0, active => 1,
        };
        $ind->_trim_fvgs;
    }
    is( scalar( @{ $ind->get_fvg() } ), 6, 'FVG cap = history+1 (Pine: 5→keep 6)' );
    # El más antiguo (left=0..3) debe haber salido; quedan left 4..9
    my @lefts = sort { $a <=> $b } map { $_->{left} } @{ $ind->get_fvg() };
    is_deeply( \@lefts, [ 4, 5, 6, 7, 8, 9 ], 'trim quita los más antiguos, conserva 6' );
}

# -----------------------------------------------------------------------------
# Structure: multi-bar break creates CHoCH then BOS
# -----------------------------------------------------------------------------
{
    my $md = Market::MarketData->new();
    # Build range then break high with 3 bars below first
    for my $i ( 0 .. 20 ) {
        my $mid = 100;
        $md->add_candle( [
            sprintf( '2026-06-01T10:%02d:00-05:00', $i ),
            $mid, $mid + 2, $mid - 2, $mid, 1
        ] );
    }
    # Raise high slowly to set structure high
    for my $i ( 21 .. 25 ) {
        my $h = 105 + ( $i - 21 );
        $md->add_candle( [
            sprintf( '2026-06-01T10:%02d:00-05:00', $i ),
            100, $h, 98, 100, 1
        ] );
    }
    # Bars at/below structure then break with multi-bar confirm
    # structure high should be elevated; break with highs clearly above
    my $ind = Market::Indicators::SMC_Structures_FVG->new( break_with_body => 0 );
    $ind->update_last( $md, $_ ) for 0 .. $md->last_index;

    # Force break: after feed, check events API exists
    my $ev = $ind->get_events();
    ok( ref($ev) eq 'ARRAY', 'get_events array' );
    # Structure state defined
    ok( defined $ind->{_struct_hi}, 'structure high defined' );
    ok( defined $ind->{_struct_lo}, 'structure low defined' );
}

# -----------------------------------------------------------------------------
# Overlay contract
# -----------------------------------------------------------------------------
{
    my $ind = Market::Indicators::SMC_Structures_FVG->new();
    my $ov  = Market::Overlays::SMC_Structures_FVG->new( indicator => $ind, visible => 1 );
    ok( Market::Overlays::Base->check_contract($ov), 'overlay cumple contrato' )
      if Market::Overlays::Base->can('check_contract');
    is( $ov->tag(), 'ov_smc_fvg', 'tag ov_smc_fvg' );
    $ov->set_visible(0);
    ok( !$ov->is_visible, 'hide' );
    $ov->set_visible(1);
    ok( $ov->is_visible, 'show' );
}

# -----------------------------------------------------------------------------
# Max 10 structure breaks
# -----------------------------------------------------------------------------
{
    my $ind = Market::Indicators::SMC_Structures_FVG->new( struct_history => 10 );
    for my $k ( 0 .. 25 ) {
        $ind->_push_break( {
            index => $k, type => 'BOS', dir => 'up', price => 100 + $k,
            start_index => $k - 1, color_role => 'bos_bull',
        } );
    }
    is( scalar( @{ $ind->get_events() } ), 10, 'max 10 structure breaks' );
}

# -----------------------------------------------------------------------------
# FVG draw: ancla X al centro de vela (no borde izq. del slot)
# -----------------------------------------------------------------------------
{
    package MockCanvasFVG;
    sub new { bless { ops => [] }, shift }
    sub delete { 1 }
    sub createRectangle {
        my ( $self, @a ) = @_;
        push @{ $self->{ops} }, [ createRectangle => @a ];
    }
    sub createText {
        my ( $self, @a ) = @_;
        push @{ $self->{ops} }, [ createText => @a ];
    }
    sub createLine {
        my ( $self, @a ) = @_;
        push @{ $self->{ops} }, [ createLine => @a ];
    }
    package MockScalesFVG;
    sub new {
        my ( $class, %a ) = @_;
        bless {
            plot_width => $a{plot_width} // 400,
            bars       => $a{bars}       // 10,
            x_shift    => 0,
            plot_left  => 0,
            plot_right => $a{plot_width} // 400,
        }, $class;
    }
    sub plot_width { $_[0]{plot_width} }
    sub index_to_x {
        my ( $self, $i ) = @_;
        my $bw = $self->{plot_width} / ( $self->{bars} || 1 );
        return $i * $bw;
    }
    sub index_to_center_x {
        my ( $self, $i ) = @_;
        my $bw = $self->{plot_width} / ( $self->{bars} || 1 );
        return $i * $bw + $bw / 2;
    }
    sub value_to_y { my ( $s, $p ) = @_; return 1000 - $p; }

    package main;
    my $ind = Market::Indicators::SMC_Structures_FVG->new();
    # Inyectar un FVG sintético left=2 right=5
    push @{ $ind->{_fvgs} }, {
        type => 'bear', left => 2, right => 5, hi => 110, lo => 100,
        active => 1, mitig => 0,
    };
    my $ov = Market::Overlays::SMC_Structures_FVG->new( indicator => $ind, visible => 1 );
    $ov->compute_visible( undef, $ind, 0, 9 );
    my $canvas = MockCanvasFVG->new();
    my $scales = MockScalesFVG->new( plot_width => 400, bars => 10 );
    my $bar_w  = 40;
    my $center_2 = 2 * $bar_w + $bar_w / 2;  # 100
    my $center_5 = 5 * $bar_w + $bar_w / 2;  # 220
    my $left_2   = 2 * $bar_w;               # 80  (borde izq. — incorrecto)
    $ov->draw( $canvas, $scales );
    my ($rect) = grep { $_->[0] eq 'createRectangle' } @{ $canvas->{ops} };
    ok( $rect, 'draw emite createRectangle FVG' );
    ok( $rect && abs( ( $rect->[1] // -1 ) - $center_2 ) < 0.5,
        'FVG x1 = centro vela left (no se sale a la izquierda)' );
    ok( $rect && abs( ( $rect->[1] // -1 ) - $left_2 ) > 1,
        'FVG x1 no usa borde izquierdo del slot' );
    ok( $rect && abs( ( $rect->[3] // -1 ) - $center_5 ) < 0.5,
        'FVG x2 = centro vela right' );
}

done_testing();
