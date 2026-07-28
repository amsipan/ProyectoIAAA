package Market::ML::ExtractFantasmaDataset;
use strict;
use warnings;
use Time::Moment;

# Extractor headless de features + labels para el LSTM del fantasmita.
# Contrato Opción A (PivotPointsHL actual / comentario Josafa):
#   - disparo = aparición o reubicación de la punta provisional
#   - rastro "1" solo si la punta se mueve (trail en punta previa)
#   - labels y3/y5/y10/y15 = conteo de trails creados en ventanas futuras
# Sin Tk. Causal: features solo con estructura <= event_bar.

use Market::MarketData;
use Market::Indicators::PivotPointsHL;
use Market::Indicators::ATR;
use Market::Indicators::SMC_Pro;
use Market::Indicators::SMC_Structures_FVG;
use Market::Indicators::ZigZag;
use Market::Indicators::DIY;
use Market::Indicators::AnchoredVWAP;
use Market::Indicators::VolumeProfile2;
use Market::Indicators::HLD;
use Market::Indicators::AutoTrendChannel;
use Market::Indicators::Liquidity;
use Market::Drawing::FibRetracement;

use constant PIP_SIZE => 0.25;    # 1 PIP NQ = 1 tick
use constant PPH_LEN  => 50;
use constant ATR_LEN  => 14;
use constant VOL_EMA  => 9;

my @LABEL_HORIZONS = ( 3, 5, 10, 15 );
my @FEATURE_TFS    = qw(1m 10m 1h);

sub pip_size { return PIP_SIZE }

sub load_csv {
    my ( $class, $path, %opts ) = @_;
    die "CSV no encontrado: $path\n" unless defined $path && -f $path;

    my $md = Market::MarketData->new();
    $md->set_base_timeframe('1m');

    open my $fh, '<', $path or die "No se pudo abrir $path: $!";
    my $header = <$fh>;
    my $n      = 0;
    my $max_bars   = $opts{max_bars};
    my $start_ts   = $opts{start_ts};
    my $end_ts     = $opts{end_ts};

    while ( my $linea = <$fh> ) {
        chomp $linea;
        $linea =~ s/\r//g;
        my @c = split /,/, $linea;
        next if @c < 5;
        my $ts = $c[0];
        next if defined $start_ts && $ts lt $start_ts;
        last if defined $end_ts   && $ts gt $end_ts;

        my $vol = 0;
        if ( defined $c[5] && $c[5] =~ /^-?\d+(?:\.\d+)?$/ ) {
            $vol = 0 + $c[5];
        }
        $md->add_candle( [ @c[ 0 .. 4 ], $vol ] );
        $n++;
        last if defined $max_bars && $n >= $max_bars;
    }
    close $fh;

    $md->build_timeframes();
    $md->set_timeframe('1m');
    return $md;
}

# extract(%opts) → { rows => [...], columns => [...], stats => {...} }
# opts: csv | market_data, max_bars, max_samples, start_ts, end_ts,
#       feature_pack => 'core'|'full' (default full), length => PPH length
sub extract {
    my ( $class, %opts ) = @_;
    my $md = $opts{market_data};
    if ( !$md ) {
        die "extract requiere csv o market_data\n" unless $opts{csv};
        $md = $class->load_csv(
            $opts{csv},
            max_bars => $opts{max_bars},
            start_ts => $opts{start_ts},
            end_ts   => $opts{end_ts},
        );
    }
    $md->set_timeframe('1m');

    my $pack   = $opts{feature_pack} // 'full';
    my $pph_len = $opts{length} // PPH_LEN;
    my $max_samples = $opts{max_samples};

    my $n = $md->size();
    die "dataset vacío\n" if $n < 1;

    my $ctx1 = $class->_new_tf_context( $md, '1m', $pph_len, $pack );

    # Series HTF como MarketData base propia (velas ya agregadas).
    my %htf_md;
    my %htf_ctx;
    my %htf_fed;
    for my $tf (qw(10m 1h)) {
        $htf_md{$tf}  = $class->_md_from_tf_series( $md, $tf );
        $htf_ctx{$tf} = $class->_new_tf_context( $htf_md{$tf}, $tf, $pph_len, $pack )
          if $pack eq 'full';
        $htf_fed{$tf} = -1;
    }

    my $hld = Market::Indicators::HLD->new();

    my @trail_created;    # índices 1m donde se creó un rastro Opción A
    my @raw_samples;
    my $prev_trail_n = 0;
    my $prev_prov_key;
    # Tras max_samples seguir alimentando hasta event+horizonte máx. (labels).
    my $feed_until;
    my $max_h = $LABEL_HORIZONS[-1];
    my $t_loop = time();
    my $prog_every = $opts{progress_every} // 1000;
    {
        my $prev = select(STDERR);
        $| = 1;
        select($prev);
    }
    printf STDERR "[extract] start loop bars=%d pack=%s progress_every=%d\n",
      $n, $pack, $prog_every;

    for my $i ( 0 .. $n - 1 ) {
        if ( $prog_every > 0 && $i > 0 && ( $i % $prog_every ) == 0 ) {
            my $elapsed = time() - $t_loop;
            my $pct     = 100 * $i / $n;
            my $eta     = $elapsed > 0 ? int( ( $n - $i ) * $elapsed / $i ) : -1;
            printf STDERR "[extract] bar=%d/%d (%.1f%%) samples=%d trails=%d elapsed=%ds eta~%ds\n",
              $i, $n, $pct, scalar(@raw_samples), scalar(@trail_created), $elapsed, $eta;
            STDERR->flush() if STDERR->can('flush');
        }
        $class->_feed_context( $ctx1, $md, $i );

        # Avanzar HTF solo sobre velas cerradas.
        for my $tf (qw(10m 1h)) {
            next unless $pack eq 'full' && $htf_ctx{$tf};
            my $closed = $class->_last_closed_tf_index( $md, $tf, $i );
            while ( $htf_fed{$tf} < $closed ) {
                $htf_fed{$tf}++;
                $class->_feed_context( $htf_ctx{$tf}, $htf_md{$tf}, $htf_fed{$tf} );
            }
        }

        my $pph_v   = $ctx1->{pph}->get_values();
        my $prov    = $pph_v->{provisional};
        my $trails  = $pph_v->{trails} || [];
        my $trail_n = scalar @$trails;

        while ( $prev_trail_n < $trail_n ) {
            push @trail_created, $i;
            $prev_trail_n++;
        }

        my $key = $class->_prov_key($prov);
        if ( defined $key && ( !defined $prev_prov_key || $key ne $prev_prov_key ) ) {
            if ( !defined $max_samples || @raw_samples < $max_samples ) {
                my $feats = $class->_snapshot_features(
                    md       => $md,
                    i        => $i,
                    pack     => $pack,
                    ctx1     => $ctx1,
                    htf_md   => \%htf_md,
                    htf_ctx  => \%htf_ctx,
                    htf_fed  => \%htf_fed,
                    hld      => $hld,
                    prov     => $prov,
                );
                push @raw_samples, {
                    event_bar  => $i,
                    tip_index  => $prov->{index},
                    tip_price  => $prov->{price},
                    tip_dir    => $prov->{dir} // '',
                    features   => $feats,
                };
                if ( defined $max_samples && @raw_samples >= $max_samples ) {
                    $feed_until = $i + $max_h;
                }
            }
        }
        $prev_prov_key = $key;
        last if defined $feed_until && $i >= $feed_until;
    }

    my @rows;
    for my $s (@raw_samples) {
        my $eb = $s->{event_bar};
        my $fb = $eb + 1;
        next if $fb >= $n;            # hace falta la vela siguiente
        next if $eb + $max_h >= $n;   # ventana y15 incompleta al final de serie

        my %lab;
        for my $h (@LABEL_HORIZONS) {
            $lab{"y$h"} = $class->_count_trails_in_window( \@trail_created, $eb, $h );
        }

        my $c_feat = $md->get_candle($fb);
        my $ts     = $c_feat ? $c_feat->[0] : '';
        my ( $date, $hour, $minute ) = $class->_split_ts($ts);

        my %row = (
            meta_event_bar   => $eb,
            meta_feature_bar => $fb,
            meta_time        => $ts,
            meta_date        => $date,
            meta_hour        => $hour,
            meta_minute      => $minute,
            meta_tip_index   => $s->{tip_index},
            meta_tip_price   => $s->{tip_price},
            meta_tip_dir     => $s->{tip_dir},
            meta_contract    => 'A',
            %lab,
            %{ $s->{features} },
        );
        push @rows, \%row;
    }

    my @columns = $class->_column_order( $pack, \@rows );
    my %stats   = (
        bars          => $n,
        triggers      => scalar(@raw_samples),
        samples       => scalar(@rows),
        trails_total  => scalar(@trail_created),
        pip_size      => PIP_SIZE,
        feature_pack  => $pack,
        label_note    => 'yH = trails creados en (event_bar, event_bar+H] Opción A',
    );

    return { rows => \@rows, columns => \@columns, stats => \%stats };
}

sub write_csv {
    my ( $class, $result, $path ) = @_;
    die "write_csv: resultado vacío\n" unless $result && $result->{columns};
    my @cols = @{ $result->{columns} };
    open my $fh, '>', $path or die "No se pudo escribir $path: $!";
    print {$fh} join( ',', @cols ), "\n";
    for my $r ( @{ $result->{rows} || [] } ) {
        my @vals = map { $class->_csv_escape( $r->{$_} ) } @cols;
        print {$fh} join( ',', @vals ), "\n";
    }
    close $fh;
    return $path;
}

# --- internos ---

sub _new_tf_context {
    my ( $class, $md, $tf, $pph_len, $pack ) = @_;
    # length PPH: en HTF hay menos velas; acortar para tener fantasma/pivotes.
    my %pph_by_tf = ( '1m' => $pph_len, '10m' => 20, '1h' => 10 );
    my $len = $pph_by_tf{$tf} // $pph_len;
    my $ctx = {
        tf   => $tf,
        pph  => Market::Indicators::PivotPointsHL->new( length => $len ),
        atr  => Market::Indicators::ATR->new(ATR_LEN),
        vol_ema_prev => undef,
        vol_ema      => undef,
    };
    return $ctx if $pack eq 'core';

    $ctx->{smc} = Market::Indicators::SMC_Pro->new();
    $ctx->{fvg} = Market::Indicators::SMC_Structures_FVG->new();
    # ZZ externo: swing_length del producto (150) es para chart 1m/15m.
    # En HTF hay menos velas → acortar para que existan impulsos consolidables.
    my %zz_swing = ( '1m' => 150, '10m' => 40, '1h' => 20 );
    $ctx->{zz} = Market::Indicators::ZigZag->new(
        compute_internal => 0,
        compute_external => 1,
        swing_length     => ( $zz_swing{$tf} // 150 ),
    );
    $ctx->{diy} = Market::Indicators::DIY->new();
    $ctx->{avwap_ghost} = Market::Indicators::AnchoredVWAP->new();
    $ctx->{avwap_pivot} = Market::Indicators::AnchoredVWAP->new();
    $ctx->{vp} = Market::Indicators::VolumeProfile2->new(
        row_size  => 200,    # más ligero que 1000 para batch
        tick_size => PIP_SIZE,
    );
    my %bar_min = ( '1m' => 1, '10m' => 10, '1h' => 60 );
    $ctx->{channel} = Market::Indicators::AutoTrendChannel->new(
        bar_minutes => ( $bar_min{$tf} // 1 ),
    );
    $ctx->{liq}     = Market::Indicators::Liquidity->new();
    return $ctx;
}

sub _feed_context {
    my ( $class, $ctx, $md, $i ) = @_;
    $ctx->{pph}->update_last( $md, $i );
    $ctx->{atr}->update_last( $md, $i );

    my $c = $md->get_candle($i);
    my $vol = $c ? ( $c->[5] // 0 ) : 0;
    my $alpha = 2 / ( VOL_EMA + 1 );
    if ( !defined $ctx->{vol_ema} ) {
        $ctx->{vol_ema} = $vol;
    }
    else {
        $ctx->{vol_ema} = $alpha * $vol + ( 1 - $alpha ) * $ctx->{vol_ema};
    }

    return if !$ctx->{smc};

    $ctx->{smc}->update_last( $md, $i );
    $ctx->{fvg}->update_last( $md, $i );
    $ctx->{zz}->update_last( $md, $i );
    $ctx->{diy}->update_last( $md, $i );
    $ctx->{vp}->update_last( $md, $i );
    $ctx->{channel}->update_last( $md, $i ) if $ctx->{channel};

    # Liquidez: absorber pivotes ZZ externos y alimentar.
    if ( $ctx->{liq} && $ctx->{zz} ) {
        my $zzv = $ctx->{zz}->get_values();
        my $pivs = $class->_zz_ext_as_liq_pivots($zzv);
        $ctx->{liq}->absorb_pivots($pivs) if $pivs && $ctx->{liq}->can('absorb_pivots');
        $ctx->{liq}->update_last( $md, $i );
    }

    # AVWAP fantasmita: anclar a punta provisional actual.
    my $prov = $ctx->{pph}->get_values()->{provisional};
    if ( $prov && defined $prov->{index} ) {
        my $ai = $prov->{index};
        my $cur = $ctx->{avwap_ghost}->anchor_index();
        if ( !defined $cur || $cur != $ai ) {
            $ctx->{avwap_ghost}->set_anchor($ai);
        }
        $ctx->{avwap_ghost}->update_last( $md, $i );
    }

    # AVWAP penúltimo / último pivot regular.
    my $reg = $ctx->{pph}->get_values()->{last_regular};
    if ( $reg && defined $reg->{index} ) {
        my $ai = $reg->{index};
        my $cur = $ctx->{avwap_pivot}->anchor_index();
        if ( !defined $cur || $cur != $ai ) {
            $ctx->{avwap_pivot}->set_anchor($ai);
        }
        $ctx->{avwap_pivot}->update_last( $md, $i );
    }
    return;
}

sub _snapshot_features {
    my ( $class, %a ) = @_;
    my $md   = $a{md};
    my $i    = $a{i};
    my $pack = $a{pack};
    my $ctx1 = $a{ctx1};
    my $prov = $a{prov};

    my $tip_i = $prov->{index};
    my $c_tip = $md->get_candle($tip_i);
    # Promedio de la vela donde está el fantasma (DOCX).
    my $ref = undef;
    if ($c_tip) {
        $ref = ( ( $c_tip->[2] // 0 ) + ( $c_tip->[3] // 0 ) ) / 2;
    }

    my %f;
    my $atr_vals = $ctx1->{atr}->get_values() || [];
    $f{atr_1m}       = $atr_vals->[$i];
    my $c_i = $md->get_candle($i);
    $f{vol_1m}       = $c_i ? ( $c_i->[5] // 0 ) : undef;
    $f{vol_ema9_1m}  = $ctx1->{vol_ema};
    $f{ref_mid_pips} = defined $ref ? $ref / PIP_SIZE : undef;  # metadata escala; no es time

    return \%f if $pack eq 'core';

    $class->_add_level_features( \%f, $ref, $ctx1, '1m', $md, $i, $a{hld} );

    for my $tf (qw(10m 1h)) {
        my $ctx = $a{htf_ctx}{$tf};
        next unless $ctx;
        my $fed = $a{htf_fed}{$tf} // -1;
        next if $fed < 0;
        $class->_add_level_features( \%f, $ref, $ctx, $tf, $a{htf_md}{$tf}, $fed, $a{hld} );
    }

    # HLD 4h / D y S/R semanal desde series del md 1m (sin reabrir GUI).
    $class->_add_hld_sr_features( \%f, $ref, $md, $i, $a{hld} );

    return \%f;
}

sub _add_level_features {
    my ( $class, $f, $ref, $ctx, $tf, $md, $i, $hld ) = @_;
    return unless $ctx && $ctx->{smc};

    # OB: nivel medio + espesor
    my $obs = $ctx->{smc}->get_order_blocks() || [];
    my ( $ob_mid, $ob_thick ) = $class->_nearest_ob( $ref, $obs );
    $f->{"pip_ob_$tf"}       = $class->_pips( $ref, $ob_mid );
    $f->{"pip_ob_thick_$tf"} = defined $ob_thick ? $ob_thick / PIP_SIZE : undef;

    # FVG
    my $fvgs = $ctx->{fvg}->can('get_fvg') ? $ctx->{fvg}->get_fvg() : [];
    my ( $fvg_mid, $fvg_rng ) = $class->_nearest_fvg( $ref, $fvgs );
    $f->{"pip_fvg_$tf"}       = $class->_pips( $ref, $fvg_mid );
    $f->{"pip_fvg_range_$tf"} = defined $fvg_rng ? $fvg_rng / PIP_SIZE : undef;

    # Fib ZZ externo consolidado (ratios TV default; reporta nearest + 0.5/0.618)
    my $zzv = $ctx->{zz}->get_values();
    my $leg = Market::Drawing::FibRetracement->last_impulse_zz_segment_for_fib(
        $zzv->{external_segments} || []
    );
    $leg ||= Market::Drawing::FibRetracement->last_consolidated_zz_segment(
        $zzv->{external_segments} || []
    );
    my @fib_prices;
    if ($leg) {
        my $p1 = { index => $leg->{from_index}, price => $leg->{from_price} };
        my $p2 = { index => $leg->{to_index},   price => $leg->{to_price} };
        for my $r ( 0.236, 0.382, 0.5, 0.618, 0.786 ) {
            my $px = Market::Drawing::FibRetracement->price_at_level( $p1, $p2, $r );
            push @fib_prices, $px if defined $px;
            $f->{ sprintf( 'pip_fib_%.3f_%s', $r, $tf ) } = $class->_pips( $ref, $px );
        }
    }
    else {
        for my $r ( 0.236, 0.382, 0.5, 0.618, 0.786 ) {
            $f->{ sprintf( 'pip_fib_%.3f_%s', $r, $tf ) } = undef;
        }
    }
    $f->{"pip_fib_nearest_$tf"} = $class->_nearest_pips( $ref, \@fib_prices );

    # AVWAP ghost + pivot
    my $g_pt = $ctx->{avwap_ghost}->get_point($i);
    $f->{"pip_avwap_ghost_$tf"} =
      $g_pt ? $class->_pips( $ref, $g_pt->{value} ) : undef;
    $f->{"pip_avwap_ghost_b1u_$tf"} =
      $g_pt && defined $g_pt->{upper1} ? $class->_pips( $ref, $g_pt->{upper1} ) : undef;
    $f->{"pip_avwap_ghost_b1l_$tf"} =
      $g_pt && defined $g_pt->{lower1} ? $class->_pips( $ref, $g_pt->{lower1} ) : undef;

    my $p_pt = $ctx->{avwap_pivot}->get_point($i);
    $f->{"pip_avwap_pivot_$tf"} =
      $p_pt ? $class->_pips( $ref, $p_pt->{value} ) : undef;

    # AVP POC/VAH/VAL anclado a último pivot ZZ ext consolidado (o tip PPH)
    my $anchor_zz = undef;
    if ( $leg && defined $leg->{to_index} ) {
        $anchor_zz = $leg->{to_index};
    }
    elsif ( my $last = Market::Drawing::FibRetracement->last_consolidated_zz_segment(
        $zzv->{external_segments} || [] ) )
    {
        $anchor_zz = $last->{to_index};
    }
    if ( !defined $anchor_zz ) {
        my $reg = $ctx->{pph}->get_values()->{last_regular};
        $anchor_zz = $reg->{index} if $reg && defined $reg->{index};
    }
    if ( !defined $anchor_zz ) {
        my $prov = $ctx->{pph}->get_values()->{provisional};
        $anchor_zz = $prov->{index} if $prov && defined $prov->{index};
    }
    if ( defined $anchor_zz && $ctx->{vp} ) {
        $ctx->{vp}->set_anchor($anchor_zz);
        my $prof = $ctx->{vp}->get_values();
        if ( $prof && ref($prof) eq 'HASH' ) {
            $f->{"pip_poc_$tf"} = $class->_pips( $ref, $prof->{poc} );
            $f->{"pip_vah_$tf"} = $class->_pips( $ref, $prof->{vah} );
            $f->{"pip_val_$tf"} = $class->_pips( $ref, $prof->{val} );
        }
        else {
            $f->{"pip_poc_$tf"} = $f->{"pip_vah_$tf"} = $f->{"pip_val_$tf"} = undef;
        }
    }
    else {
        $f->{"pip_poc_$tf"} = $f->{"pip_vah_$tf"} = $f->{"pip_val_$tf"} = undef;
    }

    # BOS / CHoCH
    my ( $bos_px, $choch_px ) = $class->_nearest_bos_choch( $ref, $ctx->{smc}->get_events() );
    $f->{"pip_bos_$tf"}   = $class->_pips( $ref, $bos_px );
    $f->{"pip_choch_$tf"} = $class->_pips( $ref, $choch_px );

    # EQH / EQL
    my ( $eqh_px, $eql_px ) = $class->_nearest_eqhl( $ref, $ctx->{smc}->get_eqhl() );
    $f->{"pip_eqh_$tf"} = $class->_pips( $ref, $eqh_px );
    $f->{"pip_eql_$tf"} = $class->_pips( $ref, $eql_px );

    # Sweep/Grab/Run (condicional; nivel del último evento resuelto)
    my ( $sgr_px, $sgr_kind ) = $class->_nearest_sgr( $ref, $ctx->{liq} );
    $f->{"pip_sgr_$tf"}  = $class->_pips( $ref, $sgr_px );
    $f->{"sgr_kind_$tf"} = $sgr_kind;    # metadata / feature categórica ligera

    # DIY S/D
    my $diy = $ctx->{diy}->get_values();
    my ( $diy_mid, $diy_rng ) = $class->_nearest_diy( $ref, $diy );
    $f->{"pip_diy_$tf"}       = $class->_pips( $ref, $diy_mid );
    $f->{"pip_diy_range_$tf"} = defined $diy_rng ? $diy_rng / PIP_SIZE : undef;

    # Canal auto (solo si hay canal activo)
    my ( $ch_mid, $ch_rng ) = $class->_nearest_channel( $ref, $ctx->{channel}, $i );
    $f->{"pip_channel_$tf"}       = $class->_pips( $ref, $ch_mid );
    $f->{"pip_channel_range_$tf"} = defined $ch_rng ? $ch_rng / PIP_SIZE : undef;

    return;
}

sub _add_hld_sr_features {
    my ( $class, $f, $ref, $md, $i, $hld ) = @_;
    my $c = $md->get_candle($i);
    my $P = $c ? $c->[4] : $ref;

    for my $src (qw(4h D)) {
        $hld->compute(
            $md,
            source_tf       => $src,
            chart_tf        => '1m',
            chart_end_index => $i,
            price           => $P,
        );
        my $res = $hld->get_result();
        my $lvl;
        if ( $res && ( !exists $res->{ok} || $res->{ok} ) && !$res->{reason} ) {
            my $hi = $res->{resistance} // $res->{high};
            my $lo = $res->{support}    // $res->{low};
            if ( defined $hi && defined $lo && defined $ref ) {
                $lvl = ( abs( $ref - $hi ) <= abs( $ref - $lo ) ) ? $hi : $lo;
            }
            else {
                $lvl = $hi // $lo;
            }
        }
        # Fallback causal: mid de la última vela HTF cerrada.
        if ( !defined $lvl ) {
            my $closed = $class->_last_closed_tf_index( $md, $src, $i );
            my $arr    = $md->{data}{$src} || [];
            if ( $closed >= 0 && $arr->[$closed] ) {
                my $hc = $arr->[$closed];
                my $hi = $hc->[2];
                my $lo = $hc->[3];
                if ( defined $hi && defined $lo && defined $ref ) {
                    $lvl = ( abs( $ref - $hi ) <= abs( $ref - $lo ) ) ? $hi : $lo;
                }
            }
        }
        my $suf = $src eq '4h' ? '4h' : 'd';
        $f->{"pip_hld_$suf"} = $class->_pips( $ref, $lvl );
    }

    # Semanal: OHLC de la última vela W cerrada
    my $w_arr = $md->{data}{W} || [];
    my $w_closed = $class->_last_closed_tf_index( $md, 'W', $i );
    if ( $w_closed >= 0 && $w_arr->[$w_closed] ) {
        my $w = $w_arr->[$w_closed];
        my $mid = ( ( $w->[2] // 0 ) + ( $w->[3] // 0 ) ) / 2;
        $f->{pip_sr_w_mid} = $class->_pips( $ref, $mid );
        $f->{pip_sr_w_hi}  = $class->_pips( $ref, $w->[2] );
        $f->{pip_sr_w_lo}  = $class->_pips( $ref, $w->[3] );
    }
    else {
        $f->{pip_sr_w_mid} = $f->{pip_sr_w_hi} = $f->{pip_sr_w_lo} = undef;
    }
    return;
}

sub _md_from_tf_series {
    my ( $class, $src, $tf ) = @_;
    my $md = Market::MarketData->new();
    # Usar 1m como “base” contenedora: empujamos velas ya agregadas.
    $md->set_base_timeframe('1m');
    my $arr = $src->{data}{$tf} || [];
    for my $c (@$arr) {
        next unless $c && ref($c) eq 'ARRAY';
        $md->add_candle( [ @{$c}[ 0 .. 5 ] ] );
    }
    $md->set_timeframe('1m');
    return $md;
}

sub _last_closed_tf_index {
    my ( $class, $md, $tf, $base_i ) = @_;
    my $arr = $md->{data}{$tf} || [];
    return -1 unless @$arr;
    my $c = $md->get_candle($base_i);
    return -1 unless $c;
    my $bucket = $md->_bucket_timestamp( $c->[0], $tf );
    my $last   = $#$arr;
    if ( defined $bucket && ( $arr->[$last][0] // '' ) eq $bucket ) {
        return $last - 1;
    }
    return $last;
}

sub _prov_key {
    my ( $class, $prov ) = @_;
    return undef unless $prov && defined $prov->{index} && defined $prov->{price};
    return sprintf( '%d:%.10g', $prov->{index}, $prov->{price} );
}

sub _count_trails_in_window {
    my ( $class, $created, $event_bar, $h ) = @_;
    my $lo = $event_bar;         # exclusivo
    my $hi = $event_bar + $h;    # inclusivo
    my $n  = 0;
    for my $t (@$created) {
        $n++ if $t > $lo && $t <= $hi;
    }
    return $n;
}

sub _pips {
    my ( $class, $ref, $level ) = @_;
    return undef unless defined $ref && defined $level;
    return abs( $ref - $level ) / PIP_SIZE;
}

sub _nearest_pips {
    my ( $class, $ref, $prices ) = @_;
    return undef unless defined $ref && $prices && @$prices;
    my $best;
    for my $p (@$prices) {
        next unless defined $p;
        my $d = abs( $ref - $p );
        $best = $d if !defined $best || $d < $best;
    }
    return defined $best ? $best / PIP_SIZE : undef;
}

sub _nearest_ob {
    my ( $class, $ref, $obs ) = @_;
    return ( undef, undef ) unless defined $ref && $obs;
    my ( $best_mid, $best_thick, $best_d );
    for my $ob (@$obs) {
        next unless $ob && defined $ob->{hi} && defined $ob->{lo};
        my $mid = ( $ob->{hi} + $ob->{lo} ) / 2;
        my $d   = abs( $ref - $mid );
        if ( !defined $best_d || $d < $best_d ) {
            $best_d     = $d;
            $best_mid   = $mid;
            $best_thick = abs( $ob->{hi} - $ob->{lo} );
        }
    }
    return ( $best_mid, $best_thick );
}

sub _nearest_fvg {
    my ( $class, $ref, $fvgs ) = @_;
    return ( undef, undef ) unless defined $ref && $fvgs;
    my ( $best_mid, $best_rng, $best_d );
    for my $g (@$fvgs) {
        next unless $g && defined $g->{hi} && defined $g->{lo};
        my $mid = ( $g->{hi} + $g->{lo} ) / 2;
        my $d   = abs( $ref - $mid );
        if ( !defined $best_d || $d < $best_d ) {
            $best_d   = $d;
            $best_mid = $mid;
            $best_rng = abs( $g->{hi} - $g->{lo} );
        }
    }
    return ( $best_mid, $best_rng );
}

sub _nearest_bos_choch {
    my ( $class, $ref, $events ) = @_;
    return ( undef, undef ) unless defined $ref && $events;
    my ( $bos, $choch, $db, $dc );
    for my $ev (@$events) {
        next unless $ev;
        my $t = lc( $ev->{type} // $ev->{label} // $ev->{kind} // '' );
        my $px = $ev->{price} // $ev->{level};
        next unless defined $px;
        my $d = abs( $ref - $px );
        if ( $t =~ /choch|choch/i || ( $ev->{choch} ) ) {
            if ( !defined $dc || $d < $dc ) { $dc = $d; $choch = $px; }
        }
        elsif ( $t =~ /bos/i || ( $ev->{bos} ) ) {
            if ( !defined $db || $d < $db ) { $db = $d; $bos = $px; }
        }
        else {
            # Heurística: muchos eventos SMC usan 'BOS'/'CHoCH' en name
            my $name = $ev->{name} // $ev->{text} // '';
            if ( $name =~ /CHoCH|CHOCH/i ) {
                if ( !defined $dc || $d < $dc ) { $dc = $d; $choch = $px; }
            }
            elsif ( $name =~ /BOS/i ) {
                if ( !defined $db || $d < $db ) { $db = $d; $bos = $px; }
            }
        }
    }
    return ( $bos, $choch );
}

sub _nearest_eqhl {
    my ( $class, $ref, $eqs ) = @_;
    return ( undef, undef ) unless defined $ref && $eqs;
    my ( $eqh, $eql, $dh, $dl );
    for my $e (@$eqs) {
        next unless $e;
        my $px = $e->{price} // $e->{level};
        next unless defined $px;
        my $d = abs( $ref - $px );
        my $side = lc( $e->{side} // $e->{type} // $e->{kind} // '' );
        if ( $side =~ /eqh|high/ ) {
            if ( !defined $dh || $d < $dh ) { $dh = $d; $eqh = $px; }
        }
        elsif ( $side =~ /eql|low/ ) {
            if ( !defined $dl || $d < $dl ) { $dl = $d; $eql = $px; }
        }
        else {
            if ( !defined $dh || $d < $dh ) { $dh = $d; $eqh = $px; }
        }
    }
    return ( $eqh, $eql );
}

sub _nearest_sgr {
    my ( $class, $ref, $liq ) = @_;
    return ( undef, undef ) unless $liq && defined $ref;
    my $events = $liq->can('get_events') ? ( $liq->get_events() || [] ) : [];
    my ( $best_px, $best_kind, $best_d );
    for my $ev (@$events) {
        next unless $ev;
        my $kind = $ev->{resolution} // $ev->{event} // '';
        next unless $kind =~ /^(?:sweep|grab|run)$/i;
        my $px = $ev->{price} // $ev->{level_price} // $ev->{level};
        next unless defined $px;
        my $d = abs( $ref - $px );
        if ( !defined $best_d || $d < $best_d ) {
            $best_d    = $d;
            $best_px   = $px;
            $best_kind = lc($kind);
        }
    }
    return ( $best_px, $best_kind );
}

sub _nearest_diy {
    my ( $class, $ref, $diy ) = @_;
    return ( undef, undef ) unless defined $ref && $diy;
    my @zones;
    push @zones, @{ $diy->{active_supply} || [] };
    push @zones, @{ $diy->{active_demand} || [] };
    my ( $best_mid, $best_rng, $best_d );
    for my $z (@zones) {
        my $top = $z->{top} // $z->{hi};
        my $bot = $z->{bottom} // $z->{lo};
        next unless defined $top && defined $bot;
        my $mid = ( $top + $bot ) / 2;
        my $d   = abs( $ref - $mid );
        if ( !defined $best_d || $d < $best_d ) {
            $best_d   = $d;
            $best_mid = $mid;
            $best_rng = abs( $top - $bot );
        }
    }
    return ( $best_mid, $best_rng );
}

sub _nearest_channel {
    my ( $class, $ref, $ch_ind, $i ) = @_;
    return ( undef, undef ) unless $ch_ind && defined $ref;
    my $v = $ch_ind->get_values();
    my $chs = $v->{channels} || [];
    return ( undef, undef ) unless @$chs;
    my $ch = $chs->[-1];
    my $slope = $ch->{slope};
    my $base_int = $ch->{base_int};
    my $par_int  = $ch->{par_int};
    return ( undef, undef )
      unless defined $slope && defined $base_int && defined $par_int;
    my $base_now = $base_int + $slope * $i;
    my $par_now  = $par_int + $slope * $i;
    my ( $lower, $upper ) =
      $base_now < $par_now ? ( $base_now, $par_now ) : ( $par_now, $base_now );
    my $mid = ( $upper + $lower ) / 2;
    return ( $mid, abs( $upper - $lower ) );
}

sub _zz_ext_as_liq_pivots {
    my ( $class, $zzv ) = @_;
    return [] unless $zzv;
    my @out;
    my $log = $zzv->{external_pivot_log} || [];
    for my $p (@$log) {
        next unless $p && defined $p->{index} && defined $p->{price};
        my $side = $p->{side};
        if ( !defined $side ) {
            my $g = $p->{type} // $p->{dir} // '';
            $side = ( $g =~ /high|ph|down/i ) ? 'high' : 'low';
        }
        push @out, { index => $p->{index}, price => $p->{price}, side => $side };
    }
    if ( !@out ) {
        my $verts = $zzv->{external_vertices} || [];
        for my $v (@$verts) {
            next unless $v && defined $v->{index} && defined $v->{price};
            push @out, {
                index => $v->{index},
                price => $v->{price},
                side  => ( $v->{side} // 'high' ),
            };
        }
    }
    return \@out;
}

sub _split_ts {
    my ( $class, $ts ) = @_;
    return ( '', '', '' ) unless defined $ts && length $ts;
    if ( $ts =~ /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})/ ) {
        return ( $1, $2, $3 );
    }
    return ( $ts, '', '' );
}

sub _csv_escape {
    my ( $class, $v ) = @_;
    return '' unless defined $v;
    return $v if $v =~ /^-?\d+(?:\.\d+)?$/;
    $v =~ s/"/""/g;
    return qq{"$v"} if $v =~ /[,"\n]/;
    return $v;
}

sub _column_order {
    my ( $class, $pack, $rows ) = @_;
    my @meta = qw(
        meta_contract meta_event_bar meta_feature_bar meta_time
        meta_date meta_hour meta_minute
        meta_tip_index meta_tip_price meta_tip_dir
        y3 y5 y10 y15
    );
    my @core = qw( atr_1m vol_1m vol_ema9_1m ref_mid_pips );
    my %seen = map { $_ => 1 } ( @meta, @core );
    my @rest;
    if ( $rows && @$rows ) {
        for my $k ( sort keys %{ $rows->[0] } ) {
            next if $seen{$k};
            push @rest, $k;
            $seen{$k} = 1;
        }
    }
    return ( @meta, @core, @rest );
}

1;
