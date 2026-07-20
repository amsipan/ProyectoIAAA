package Market::Overlays::Liquidity;
use strict;
use warnings;

# Overlay Liquidity v2 — estilos PDF tabla 2 (BSL rojo, SSL verde, …).
# Labels ASCII (Tk-safe). HISTORY = dibujar niveles resolved (demo profe).
# Elementos: BSL SSL EQH EQL SWEEP GRAB RUN HISTORY

use constant {
    MAX_EVENT_MARKERS => 40,
    DEDUPE_IDX_WINDOW => 2,
    MAX_LEVEL_LABELS  => 24,
};

sub new {
    my ( $class, %args ) = @_;
    die "Overlays::Liquidity: requiere 'indicator'" unless $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ( $args{visible} ? 1 : 0 ) : 0,
        elements  => {
            BSL     => 1,
            SSL     => 1,
            EQH     => 1,
            EQL     => 1,
            SWEEP   => 1,
            GRAB    => 1,
            RUN     => 1,
            HISTORY => 0,    # off: solo vivos; on: también resolved
            %{ $args{elements} || {} },
        },
        _result   => undef,
        _range    => [ 0, 0 ],
        _md       => undef,
        _feed_end => undef,
    };
    bless $self, $class;
    return $self;
}

sub tag { 'ov_liq' }

sub set_visible {
    my ( $self, $bool ) = @_;
    $self->{visible} = $bool ? 1 : 0;
    return $self;
}

sub is_visible { $_[0]->{visible} }

sub set_element_visible {
    my ( $self, $elem, $bool ) = @_;
    $elem = uc( $elem // '' );
    return $self unless exists $self->{elements}{$elem};
    $self->{elements}{$elem} = $bool ? 1 : 0;
    return $self;
}

sub is_element_visible {
    my ( $self, $elem ) = @_;
    $elem = uc( $elem // '' );
    return 0 unless exists $self->{elements}{$elem};
    return $self->{elements}{$elem} ? 1 : 0;
}

sub format_event_label {
    my ( $a, $b, $c ) = @_;
    my ( $res, $lk );
    if ( defined $c ) {
        $res = $b;
        $lk  = $c;
    }
    else {
        $res = $a;
        $lk  = $b;
    }
    $res = uc( $res // '' );
    $lk  = uc( $lk  // '' );

    my $is_up = ( $lk eq 'BSL' || $lk eq 'EQH' ) ? 1 : 0;
    if ( $res eq 'SWEEP' ) {
        return $is_up ? 'SWEEP UP' : 'SWEEP DN';
    }
    if ( $res eq 'GRAB' ) {
        return $is_up ? 'LQ GRAB UP' : 'LQ GRAB DN';
    }
    if ( $res eq 'RUN' ) {
        return $is_up ? 'LQ RUN UP' : 'LQ RUN DN';
    }
    return $res;
}

sub event_is_up {
    my ( $a, $b ) = @_;
    my $lk = defined $b ? $b : $a;
    $lk = uc( $lk // '' );
    return ( $lk eq 'BSL' || $lk eq 'EQH' ) ? 1 : 0;
}

# Posición X de una etiqueta sobre la porción REALMENTE visible del segmento.
# Devuelve undef si el segmento no intersecta el plot: nunca arrastra texto desde
# fuera de pantalla al borde, que era la causa de labels "flotantes" en Replay.
sub clamp_label_x {
    my ( $class, $x1, $x2, $plot_w ) = @_;
    return undef unless defined $x1 && defined $x2;
    $plot_w = 100 if !defined $plot_w || $plot_w < 20;
    my ( $lo, $hi ) = $x1 <= $x2 ? ( $x1, $x2 ) : ( $x2, $x1 );
    my $vis_lo = $lo > 2 ? $lo : 2;
    my $vis_hi = $hi < $plot_w - 2 ? $hi : $plot_w - 2;
    return undef if $vis_hi < $vis_lo;
    return ($vis_lo + 6 <= $vis_hi) ? $vis_lo + 6 : ($vis_lo + $vis_hi) / 2;
}

sub compute_visible {
    my ( $self, $market_data, $indicator, $start, $end ) = @_;
    $self->{_range}  = [ $start // 0, $end // 0 ];
    $self->{_md}     = $market_data;
    $self->{_result} = undef;
    return $self unless $self->{visible};

    my $ind = $indicator // $self->{indicator};
    return $self unless $ind;

    $self->{_result} = $ind->can('get_values') ? $ind->get_values() : undef;
    return $self;
}

sub clear {
    my ( $self, $canvas ) = @_;
    return unless $canvas;
    eval { $canvas->delete( $self->tag() ); 1 };
    return $self;
}

sub draw {
    my ( $self, $canvas, $scales ) = @_;
    return unless $self->{visible} && $canvas && $scales;
    $self->clear($canvas);

    my $r = $self->{_result};
    return $self unless $r;

    my $tag       = $self->tag();
    my $win_start = ( $self->{_range} || [0] )->[0] // 0;
    my $win_end   = ( $self->{_range} || [ 0, 0 ] )->[1] // 0;
    my $data_end  = $self->{_feed_end};
    $data_end = $win_end if !defined $data_end;

    # Tope efectivo: no dibujar “futuro” respecto a replay / feed.
    my $eff_end = $data_end;
    $eff_end = $win_end if $win_end < $eff_end;

    my $plot_w = 0;
    eval { $plot_w = $scales->plot_width() if $scales->can('plot_width'); 1 };
    $plot_w = $scales->{width} // 800 if !$plot_w;

    my $x_of = sub {
        my ($gi) = @_;
        return $scales->index_to_center_x( ( $gi // 0 ) - $win_start );
    };
    my $y_of = sub {
        my ($p) = @_;
        return $scales->value_to_y($p);
    };

    my $th = $self->{theme} || {};
    my %col = (
        BSL      => $th->{liq_bsl}      // '#e53935',
        SSL      => $th->{liq_ssl}      // '#43a047',
        EQH      => $th->{liq_eqh}      // '#ef5350',
        EQL      => $th->{liq_eql}      // '#66bb6a',
        SWEEP_UP => $th->{liq_sweep_up} // '#e53935',
        SWEEP_DN => $th->{liq_sweep_dn} // '#43a047',
        GRAB     => $th->{liq_grab}     // '#fb8c00',
        RUN      => $th->{liq_run}      // '#1e88e5',
    );
    my $hist_on = $self->is_element_visible('HISTORY');

    # --- Niveles ---
    my @level_draw;
    for my $lv ( @{ $r->{levels} || [] } ) {
        my $kind = uc( $lv->{kind} // '' );
        next unless $kind =~ /^(BSL|SSL|EQH|EQL)$/;
        next unless $self->is_element_visible($kind);

        my $state = $lv->{state} // '';
        my $price = $lv->{price};
        next unless defined $price;

        my $piv = $lv->{pivot_index};
        next if defined $piv && $piv > $eff_end;    # futuro vs replay

        if ( $state eq 'resolved' ) {
            next unless $hist_on;
            # Solo historial si el resolve ya ocurrió a este feed_end
            my $ri = $lv->{resolve_index} // $lv->{sweep_index};
            next if defined $ri && $ri > $eff_end;
            # No dibujar supersedidos como si fueran eventos de liquidez
            next if ( $lv->{resolution} // '' ) eq 'superseded_by_eq';
        }
        elsif ( $state ne 'detected' && $state ne 'swept' ) {
            next;
        }

        push @level_draw, { %$lv, kind => $kind };
    }

    @level_draw = sort {
        my $pa = ( $a->{kind} =~ /^EQ/ ) ? 0 : 1;
        my $pb = ( $b->{kind} =~ /^EQ/ ) ? 0 : 1;
        $pa <=> $pb || ( $b->{pivot_index} // 0 ) <=> ( $a->{pivot_index} // 0 )
    } @level_draw;

    my @shown_prices;
    my $price_near = sub {
        my ( $p, $archived ) = @_;
        for my $sp (@shown_prices) {
            next if ( $sp->{arch} // 0 ) != ( $archived // 0 );
            my $tol = abs( $sp->{p} ) * 1e-4 + 1e-9;
            return 1 if abs( $p - $sp->{p} ) <= $tol || abs( $p - $sp->{p} ) < 0.5;
        }
        return 0;
    };

    my $n_lbl = 0;
    for my $lv (@level_draw) {
        my $kind     = $lv->{kind};
        my $price    = $lv->{price};
        my $archived = ( ( $lv->{state} // '' ) eq 'resolved' ) ? 1 : 0;
        next if $price_near->( $price, $archived );

        my ( $i0, $i1 );
        if ( $kind =~ /^EQ/ && defined $lv->{pair_index} ) {
            $i0 = $lv->{pair_index};
            $i1 = $lv->{pivot_index} // $i0;
            ( $i0, $i1 ) = ( $i1, $i0 ) if $i0 > $i1;
            # En historial, no extender más allá del resolve
            if ($archived) {
                my $ri = $lv->{resolve_index} // $lv->{sweep_index} // $i1;
                $i1 = $ri if $ri < $i1;
            }
        }
        else {
            $i0 = $lv->{pivot_index} // $win_start;
            if ($archived) {
                # Tramo fijo: pivot → resolve/sweep (no persigue el borde del chart)
                $i1 = $lv->{resolve_index} // $lv->{sweep_index} // $i0;
            }
            else {
                # Vivo: pivot → fin de feed (replay-safe), no más allá de eff_end
                $i1 = $eff_end;
            }
        }
        $i1 = $eff_end if $i1 > $eff_end;

        next if $i1 < $win_start - 2 || $i0 > $win_end + 2;

        my $x1 = $x_of->($i0);
        my $x2 = $x_of->($i1);
        my $y  = $y_of->($price);
        my $c  = $col{$kind} // '#888888';
        # Archivados más tenues
        if ($archived) {
            $c = $kind =~ /BSL|EQH/ ? '#ef9a9a' : '#a5d6a7';
        }

        eval {
            $canvas->createLine(
                $x1, $y, $x2, $y,
                -fill  => $c,
                -width => 1,
                -dash  => $archived ? [ 2, 4 ] : [ 4, 3 ],
                -tags  => [ $tag, "liq_$kind", $archived ? 'liq_hist' : 'liq_live' ],
            );
            1;
        };
        # El precio ya quedó representado por una línea, aunque no haya cupo para
        # texto. Así el dedupe sigue evitando geometría duplicada.
        push @shown_prices, { p => $price, arch => $archived };

        # El límite es solo de TEXTO. La geometría de todos los niveles visibles
        # se conserva, especialmente con HISTORY y zoom lejano.
        next if $n_lbl >= MAX_LEVEL_LABELS;
        my $lx = __PACKAGE__->clamp_label_x( $x1, $x2, $plot_w );
        # La linea puede cruzar el viewport aunque su ancla quede fuera; en ese
        # caso no inventamos una posicion para el texto.
        next unless defined $lx;
        my $lbl = $archived ? "$kind*" : $kind;
        eval {
            $canvas->createText(
                $lx, $y - 2,
                -text   => $lbl,
                -fill   => $c,
                -anchor => 'sw',
                -font   => [ 'TkDefaultFont', 8, 'bold' ],
                -tags   => [ $tag, 'liq_lbl' ],
            );
            1;
        };
        $n_lbl++;
    }

    # --- Eventos resueltos (marcadores) ---
    my @events =
      grep {
             defined $_->{resolve_index}
          || defined $_->{sweep_index}
      } @{ $r->{events} || [] };

    @events = sort {
        ( $b->{resolve_index} // $b->{sweep_index} // 0 )
          <=> ( $a->{resolve_index} // $a->{sweep_index} // 0 )
    } @events;

    my @draw_ev;
    for my $ev (@events) {
        my $res = uc( $ev->{resolution} // '' );
        next unless $res =~ /^(SWEEP|GRAB|RUN)$/;
        next unless $self->is_element_visible($res);

        my $idx = $ev->{resolve_index} // $ev->{sweep_index};
        next unless defined $idx;
        next if $idx > $eff_end;                         # futuro vs replay
        # Un evento fuera del dominio visible no se empuja artificialmente al borde.
        next if $idx < $win_start || $idx > $win_end;

        my $price = $ev->{price};
        next unless defined $price;

        my $dup = 0;
        for my $d (@draw_ev) {
            next if uc( $d->{resolution} // '' ) ne $res;
            my $di = $d->{resolve_index} // $d->{sweep_index} // -999;
            next if abs( $di - $idx ) > DEDUPE_IDX_WINDOW;
            my $tol = abs($price) * 1e-4 + 0.5;
            if ( abs( ( $d->{price} // 0 ) - $price ) <= $tol ) {
                $dup = 1;
                last;
            }
        }
        next if $dup;
        push @draw_ev, $ev;
        last if @draw_ev >= MAX_EVENT_MARKERS;
    }

    my @event_label_pos;
    for my $ev (@draw_ev) {
        my $res   = uc( $ev->{resolution} // '' );
        my $idx   = $ev->{resolve_index} // $ev->{sweep_index};
        my $price = $ev->{price};
        my $x     = $x_of->($idx);
        my $y     = $y_of->($price);

        my $is_up = __PACKAGE__->event_is_up( $ev->{level_kind} );
        my $c =
            $res eq 'SWEEP' ? ( $is_up ? $col{SWEEP_UP} : $col{SWEEP_DN} )
          : $res eq 'GRAB'  ? $col{GRAB}
          :                   $col{RUN};

        my $label = __PACKAGE__->format_event_label( $res, $ev->{level_kind} );
        my $lx    = $x + 6;
        $lx = 4 if $lx < 4;
        $lx = $plot_w - 50 if $lx > $plot_w - 50;

        # En zoom lejano conservar el punto exacto, pero espaciar textos. Dos
        # labels dentro de la misma celda visual se perciben como duplicados.
        my $show_label = 1;
        for my $p (@event_label_pos) {
            if ( abs( $lx - $p->{x} ) < 58 && abs( $y - $p->{y} ) < 18 ) {
                $show_label = 0;
                last;
            }
        }

        eval {
            $canvas->createOval(
                $x - 4, $y - 4, $x + 4, $y + 4,
                -outline => $c,
                -fill    => $c,
                -width   => 1,
                -tags    => [ $tag, "liq_ev_$res" ],
            );
            if ($show_label) {
                $canvas->createText(
                    $lx, $y - 8,
                    -text   => $label,
                    -fill   => $c,
                    -anchor => 'w',
                    -font   => [ 'TkDefaultFont', 8, 'bold' ],
                    -tags   => [ $tag, 'liq_ev_lbl' ],
                );
            }
            1;
        };
        push @event_label_pos, { x => $lx, y => $y } if $show_label;
    }

    return $self;
}

1;
