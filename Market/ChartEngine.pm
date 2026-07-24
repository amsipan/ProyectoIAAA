package Market::ChartEngine;
use strict;
use warnings;

use Time::Moment;
use File::Spec ();
use Market::Panels::Scales;
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel;
use Market::ReplayController;
use Market::OverlayManager;
use Market::Indicators::SMC_Pro;
use Market::Overlays::SMC_Pro;
use Market::Indicators::SMC_Structures_FVG;
use Market::Overlays::SMC_Structures_FVG;
use Market::Indicators::HLD;
use Market::Overlays::HLD;
use Market::Indicators::ZigZag;
use Market::Overlays::ZigZag;
use Market::Indicators::Liquidity;
use Market::Overlays::Liquidity;
use Market::Indicators::DIY;
use Market::Overlays::DIY;
use Market::Indicators::VolumeProfile2;
use Market::Overlays::VolumeProfile;
use Market::Drawing::FibRetracement;
use Market::Indicators::AnchoredVWAP;
use Market::Overlays::AnchoredVWAP;
use Market::Indicators::PivotPointsHL;
use Market::Overlays::PivotPointsHL;
use Market::Indicators::AutoTrendChannel;
use Market::Overlays::AutoTrendChannel;
# Constantes del módulo (valores fijos del paquete, no estado global mutable).
#   RIGHT_MARGIN     => margen interno derecho del área de ploteo. Los ejes ahora
#                       son canvases separados, así que debe ser 0.
#   MIN_VISIBLE_BARS => mínimo de velas visibles en la ventana (Req. 8, 10)
#   ZOOM_STEP        => barras por paso de rueda en el zoom horizontal
#   TIME_AXIS_DRAG_PX_PER_BAR => sensibilidad del drag horizontal del eje temporal
use constant {
    RIGHT_MARGIN     => 0,
    MIN_VISIBLE_BARS => 2,
    # Tope de velas DIBUJADAS (no borra dataset). 40k en 1m tumba Tk;
    # 3000 mantiene pan/zoom usables; el histório completo sigue en MarketData.
    MAX_VISIBLE_BARS => 3000,
    ZOOM_STEP        => 5,
    CTRL_MASK        => 0x0004,
    TIME_AXIS_DRAG_PX_PER_BAR => 8,
    # TradingView Bar Replay: borde derecho de la ultima vela visible al 80% del plot;
    # hueco fijo 20% del ancho (px), independiente del zoom en barras.
    REPLAY_BAR_ANCHOR_FRAC => 0.80,
    REPLAY_RIGHT_GAP_FRAC  => 0.20,
    # task 0053: tijera Select Bar (glyph unicode; linea/velo siguen azules).
    REPLAY_SELECT_SCISSOR_FONT => 'Helvetica 22',
    REPLAY_SELECT_SCISSOR_FILL => 'black',
};

# Paleta de tema claro por defecto (local al módulo). Se usa solo si el llamador
# no inyecta un hash `theme`. Mantiene EXACTAMENTE las mismas claves del contrato
# de tema definido en el diseño, de modo que los paneles puedan consumirla sin
# recurrir a variables globales.
sub _default_theme {
    return {
        bg             => '#ffffff',
        # Grid TV: puntos un poco más gruesos (width 2 + dash [2,3]) para notarse.
        grid           => '#d4d8de',
        date_grid      => '#d4d8de',
        grid_dash      => [ 2, 3 ],
        grid_width     => 2,
        axis_text      => '#363a45',
        bull           => '#26a69a',
        bear           => '#ef5350',
        atr_line       => '#2962ff',
        # Crosshair: mismo largo de trazo [6,5] y color; width 1 (más fino que grid).
        crosshair_line  => '#8b9099',
        crosshair_dash  => [ 6, 5 ],
        crosshair_width => 1,
        label_bg       => '#363a45',
        label_fg       => '#ffffff',
        last_price_bg  => '#363a45',
        last_price_fg  => '#ffffff',
    };
}

sub new {
    my ($class, %args) = @_;

    my $self = {
        market_data      => $args{market_data},
        indicator_manager=> $args{indicator_manager},
        price_canvas     => $args{price_canvas},
        atr_canvas       => $args{atr_canvas},

        visible_bars     => 60,
        offset           => 0,
        is_auto_scale    => 1,
        manual_min_y     => undef,
        manual_max_y     => undef,
        last_auto_min_y  => undef,
        last_auto_max_y  => undef,
        scale_mode_callback => $args{scale_mode_callback},
        ctrl_zoom_x_shift => 0,
        ctrl_zoom_y_lock_min => undef,
        ctrl_zoom_y_lock_max => undef,
        is_atr_auto_scale => 1,
        atr_manual_min_y => undef,
        atr_manual_max_y => undef,
        last_auto_atr_min_y => undef,
        last_auto_atr_max_y => undef,
        atr_axis_drag_start_y => undef,
        atr_axis_drag_min_y => undef,
        atr_axis_drag_max_y => undef,
        atr_drag_start_min_y => undef,
        atr_drag_start_max_y => undef,
        render_pending   => 0,
        drag_start_x     => undef,
        drag_start_y     => undef,
        drag_start_panel => undef,
        drag_start_offset=> 0,
        axis_drag_start_y=> undef,
        axis_drag_min_y  => undef,
        axis_drag_max_y  => undef,
        vertical_drag_y  => undef,
        _replay_select_mode => 0,
        _selected_bar       => undef,
        _vwap_select_mode   => 0,
        _vp_select_mode     => 0,
        show_grid           => 0,
        show_last_price_line => 0,   # línea entrecortada del precio actual (off x defecto)

        %args,
    };
    bless $self, $class;

    # Tema claro: se usa el inyectado por el llamador (market.pl) o un default
    # local con las mismas claves. El tema viaja por la instancia, nunca como global.
    $self->{theme} = $args{theme} || _default_theme();

    $self->{price_panel} = Market::Panels::PricePanel->new(
        canvas => $self->{price_canvas},
        theme  => $self->{theme},
        show_last_price_line => $self->{show_last_price_line} ? 1 : 0,
    );
    $self->{atr_panel}   = Market::Panels::ATRPanel->new(
        canvas => $self->{atr_canvas},
        theme  => $self->{theme},
    );

    # spec 0002: ReplayController — índice-tope para Replay.
    $self->{replay_controller} = Market::ReplayController->new(
        market_data => $self->{market_data},
    );

    # spec 0003: OverlayManager — registro de overlays.
    $self->{overlay_manager} = Market::OverlayManager->new();

    # spec 0013: SMC Pro [Neon] + Structures/FVG (LudoGH) — config capturas profe.
    # Reemplaza el híbrido SMC_Structures + Mxwll como verdad de estructura.
    $self->{smc_pro_indicator} = Market::Indicators::SMC_Pro->new();
    $self->{smc_pro_overlay} = Market::Overlays::SMC_Pro->new(
        indicator => $self->{smc_pro_indicator},
        theme     => $self->{theme},
        visible   => 0,
    );
    $self->{overlay_manager}->register('smc_pro', $self->{smc_pro_overlay});
    $self->{_smc_pro_fed_up_to} = -1;

    # Alias smc → smc_pro (nombres antiguos / tests).
    $self->{smc_indicator} = $self->{smc_pro_indicator};
    $self->{smc_overlay}   = $self->{smc_pro_overlay};
    $self->{_smc_fed_up_to} = -1;

    $self->{smc_fvg_indicator} = Market::Indicators::SMC_Structures_FVG->new();
    $self->{smc_fvg_overlay} = Market::Overlays::SMC_Structures_FVG->new(
        indicator => $self->{smc_fvg_indicator},
        theme     => $self->{theme},
        visible   => 0,
    );
    $self->{overlay_manager}->register('smc_fvg', $self->{smc_fvg_overlay});
    $self->{_smc_fvg_fed_up_to} = -1;

    # --- PRODUCTO OFICIAL (docs/PRODUCTO_OFICIAL.md) ---
    # smc_pro, smc_fvg, hld, pchan, zigzag, fib, liq (Liquidity v2).
    # Legacy (Mxwll/Strategy/VP/VWAP/SMC_Structures viejo + Liquidity v1):
    #   FUERA del repo — docs/LEGACY.md

    # HLD — soporte/resistencia de vela 4h|D (algoritmo profe; sin Pine TV)
    $self->{hld_indicator} = Market::Indicators::HLD->new();
    $self->{hld_overlay}   = Market::Overlays::HLD->new(
        indicator => $self->{hld_indicator},
        theme     => $self->{theme},
        visible   => 0,
    );
    $self->{overlay_manager}->register( 'hld', $self->{hld_overlay} );

    # Parallel Channel (herramienta nativa TV del video del profe)
    require Market::Drawing::ParallelChannel;
    require Market::Overlays::ParallelChannel;
    $self->{pchan_drawing} = Market::Drawing::ParallelChannel->new(
        extend_right => 0,
        extend_left  => 0,
    );
    $self->{pchan_overlay} = Market::Overlays::ParallelChannel->new(
        drawing => $self->{pchan_drawing},
        theme   => $self->{theme},
        visible => 1,
    );
    $self->{overlay_manager}->register( 'pchan', $self->{pchan_overlay} );

    # TrendLine (drawing tool TV): varias líneas de 2 puntos, arrastrables.
    require Market::Drawing::TrendLine;
    require Market::Overlays::TrendLine;
    $self->{trend_drawing} = Market::Drawing::TrendLine->new();
    $self->{trend_overlay} = Market::Overlays::TrendLine->new(
        drawing => $self->{trend_drawing},
        theme   => $self->{theme},
        visible => 1,
    );
    $self->{overlay_manager}->register( 'trend', $self->{trend_overlay} );

    # ZigZag — externo ChartPrime + interno ZZMTF.
    # Fib Retracement = Drawing tool (ver fib_drawing abajo), no elemento ZZ.
    $self->{zigzag_indicator} = Market::Indicators::ZigZag->new(
        swing_length        => 150,
        internal_resolution => 30,
        internal_period     => 2,
        compute_internal    => 0,
        compute_external    => 0,
    );
    $self->{zigzag_overlay} = Market::Overlays::ZigZag->new(
        indicator => $self->{zigzag_indicator},
        theme     => $self->{theme},
        visible   => 0,
        elements  => { INTERNAL => 0, EXTERNAL => 0, CHANNEL => 0 },
    );
    $self->{overlay_manager}->register( 'zigzag', $self->{zigzag_overlay} );
    $self->{_zigzag_fed_up_to} = -1;

    # Fib Retracement (herramienta nativa TV — 2 clics, bandas, anclas móviles)
    require Market::Drawing::FibRetracement;
    require Market::Overlays::FibRetracement;
    $self->{fib_drawing} = Market::Drawing::FibRetracement->new(
        extend_to_last => 0,
    );
    $self->{fib_overlay} = Market::Overlays::FibRetracement->new(
        drawing => $self->{fib_drawing},
        theme   => $self->{theme},
        visible => 1,
    );
    $self->{overlay_manager}->register( 'fib', $self->{fib_overlay} );

    # Liquidity v2 — BSL/SSL/EQH/EQL + FSM Sweep/Grab/Run (desde cero)
    $self->{liq_indicator} = Market::Indicators::Liquidity->new();
    $self->{liq_overlay}   = Market::Overlays::Liquidity->new(
        indicator => $self->{liq_indicator},
        theme     => $self->{theme},
        visible   => 0,
    );
    $self->{overlay_manager}->register( 'liq', $self->{liq_overlay} );
    $self->{_liq_fed_up_to} = -1;

    # DIY Custom Strategy Builder (Supply & Demand Zones)
    $self->{diy_indicator} = Market::Indicators::DIY->new();
    $self->{diy_overlay}   = Market::Overlays::DIY->new(
        indicator => $self->{diy_indicator},
        theme     => $self->{theme},
        visible   => 0,
    );
    $self->{overlay_manager}->register( 'diy', $self->{diy_overlay} );
    $self->{_diy_fed_up_to} = -1;
    if ($self->{indicator_manager}) {
        $self->{indicator_manager}->register('DIY', $self->{diy_indicator});
    }

    # Anchored Volume Profile (AVP) — v2: algoritmo calibrado a TradingView
    # (rejilla por tick, volumen 1m real vía ltf_dir, VA 70% por pares de filas).
    $self->{vp_indicator} = Market::Indicators::VolumeProfile2->new(ltf_dir => 'Data');
    $self->{vp_overlay}   = Market::Overlays::VolumeProfile->new(
        indicator => $self->{vp_indicator},
        theme     => $self->{theme},
        visible   => 0,
    );
    $self->{overlay_manager}->register( 'volumeprofile', $self->{vp_overlay} );
    $self->{_vp_fed_up_to} = -1;
    $self->{vp_mode}       = 'off';    # off | manual | auto
    if ($self->{indicator_manager}) {
        $self->{indicator_manager}->register('VolumeProfile', $self->{vp_indicator});
    }

    # Anchored VWAP (AVWAP) — manual + hasta 2 automáticos (pivot / fantasma)
    $self->{avwap_indicator} = Market::Indicators::AnchoredVWAP->new();
    $self->{avwap_overlay}   = Market::Overlays::AnchoredVWAP->new(
        indicator => $self->{avwap_indicator},
        theme     => $self->{theme},
        visible   => 0,
        show_handle => 1,
    );
    $self->{overlay_manager}->register( 'anchoredvwap', $self->{avwap_overlay} );
    $self->{_avwap_fed_up_to} = -1;
    if ($self->{indicator_manager}) {
        $self->{indicator_manager}->register('AnchoredVWAP', $self->{avwap_indicator});
    }

    # Auto-1: último pivot regular consolidado (high o low)
    $self->{avwap_auto1_indicator} = Market::Indicators::AnchoredVWAP->new();
    $self->{avwap_auto1_overlay}   = Market::Overlays::AnchoredVWAP->new(
        indicator   => $self->{avwap_auto1_indicator},
        theme       => { %{ $self->{theme} || {} }, vwap_line => '#26A69A' },
        tag         => 'ov_avwap_auto1',
        show_handle => 0,
        visible     => 0,
        color_vwap  => '#26A69A',
    );
    $self->{overlay_manager}->register( 'avwap_auto1', $self->{avwap_auto1_overlay} );
    $self->{_avwap_auto1_fed_up_to} = -1;

    # Auto-2: fantasma provisional (sigue x_last)
    $self->{avwap_auto2_indicator} = Market::Indicators::AnchoredVWAP->new();
    $self->{avwap_auto2_overlay}   = Market::Overlays::AnchoredVWAP->new(
        indicator   => $self->{avwap_auto2_indicator},
        theme       => { %{ $self->{theme} || {} }, vwap_line => '#9C27B0' },
        tag         => 'ov_avwap_auto2',
        show_handle => 0,
        visible     => 0,
        color_vwap  => '#9C27B0',
    );
    $self->{overlay_manager}->register( 'avwap_auto2', $self->{avwap_auto2_overlay} );
    $self->{_avwap_auto2_fed_up_to} = -1;

    # off | manual | auto | both
    $self->{avwap_mode} = 'off';

    # Pivot Points High Low & Missed (fantasmas) — LuxAlgo. Ancla del VWAP.
    $self->{pph_indicator} = Market::Indicators::PivotPointsHL->new();
    $self->{pph_overlay}   = Market::Overlays::PivotPointsHL->new(
        indicator => $self->{pph_indicator},
        theme     => $self->{theme},
        visible   => 0,
    );
    $self->{overlay_manager}->register( 'pivotpointshl', $self->{pph_overlay} );
    $self->{_pph_fed_up_to} = -1;
    if ($self->{indicator_manager}) {
        $self->{indicator_manager}->register('PivotPointsHL', $self->{pph_indicator});
    }

    # Trendline auto + Canal auto (ciclo de vida tipo OB; aparte de Drawing/ZZ)
    $self->{auto_tc_indicator} = Market::Indicators::AutoTrendChannel->new();
    $self->{auto_tc_overlay}   = Market::Overlays::AutoTrendChannel->new(
        indicator => $self->{auto_tc_indicator},
        theme     => $self->{theme},
        visible   => 0,
    );
    $self->{overlay_manager}->register( 'auto_tc', $self->{auto_tc_overlay} );
    $self->{_auto_tc_fed_up_to} = -1;
    if ( $self->{indicator_manager} ) {
        $self->{indicator_manager}->register( 'AutoTrendChannel', $self->{auto_tc_indicator} );
    }

    $self->bind_events();

    return $self;
}


# Devuelve el tope causal del frame. En Replay es replay_idx; fuera de Replay,
# el ultimo indice real. Ningun slice, indicador u overlay debe leer mas alla.
sub _causal_end {
    my ($self) = @_;
    my $last = ($self->{market_data}->size() || 0) - 1;
    return -1 if $last < 0;
    my $replay = $self->{replay_controller};
    return ($replay && $replay->is_active())
        ? $replay->effective_end($last)
        : $last;
}

sub _replay_blank_slots {
    my ($self, $visible) = @_;
    $visible ||= $self->{visible_bars} || MIN_VISIBLE_BARS;
    my $n = int($visible * REPLAY_RIGHT_GAP_FRAC + 0.5);
    $n = 1 if $visible > 1 && $n < 1;
    $n = $visible - 1 if $n >= $visible;
    return $n > 0 ? $n : 0;
}

# Ventana LOGICA del viewport. Puede incluir indices negativos a la izquierda o
# slots vacios posteriores al replay_idx. Los consumidores de datos usan
# _causal_slice(), de modo que esos slots nunca revelan velas futuras.
sub compute_window {
    my ($self) = @_;

    my $total_candles = $self->{market_data}->size();
    return (0, -1) if !$total_candles || $total_candles <= 0;

    my $visible = $self->{visible_bars} || 60;
    $visible = MIN_VISIBLE_BARS if $visible < MIN_VISIBLE_BARS;
    $visible = MAX_VISIBLE_BARS if $visible > MAX_VISIBLE_BARS;
    $visible = $total_candles if $visible > $total_candles;
    $visible = 1 if $visible < 1;
    $self->{visible_bars} = $visible;

    my $replay = $self->{replay_controller};
    if ($replay && $replay->is_active()) {
        return $self->_replay_window($visible);
    }

    $self->{offset} = $self->_clamp_offset($self->{offset}, $total_candles);
    my $end_idx = $total_candles - 1 - $self->{offset};
    return ($end_idx - $visible + 1, $end_idx);
}

# _replay_window($visible) — geometria del viewport durante Replay.
#
# MODELO ROBUSTO (unica fuente de verdad = replay_view_end, indice LOGICO
# absoluto del borde derecho del viewport). Reemplaza el antiguo trio en
# conflicto (follow_replay_head / offset / frozen) que provocaba que:
#   - tras pausar+interactuar+play todo el grafico se desplazara cada tick,
#   - un zoom-out dejara el estado inconsistente de forma permanente,
#   - al retroceder el head se alejara fuera de pantalla.
#
# Reglas (con replay_view_end definido, que es SIEMPRE en la app real porque
# frame_replay_view_at lo fija al encuadrar):
#   * AUTO-SCROLL POR DETECCION DE BORDE: la vista solo se desplaza cuando el
#     head estaba EXACTAMENTE en el borde derecho y avanzo (via
#     replay_prev_causal_end). Mientras haya hueco (view_end > causal_end) la
#     ventana queda FIJA y las velas nuevas rellenan el hueco SIN mover nada.
#     Tras panear/zoomear (view_end deja de coincidir con el borde), un nuevo
#     Play NO arrastra el grafico: las velas quedan estaticas. Esto elimina la
#     necesidad de flags de modo (no hay follow/frozen/offset en conflicto).
#   * Clamp min-visible SIEMPRE: al retroceder (step_backward) se conservan al
#     menos MIN_VISIBLE_BARS velas reales en pantalla; la vista se desplaza con
#     el head en lugar de dejarlo escapar del marco.
#   * Clamp izquierda: no se permite hueco en blanco a la izquierda (start >= 0).
#
# Ramas legacy (replay_view_end indefinido) solo para pruebas unitarias que
# construyen el ChartEngine a mano (t/38): reproducen el comportamiento previo.
sub _replay_window {
    my ($self, $visible) = @_;

    my $causal_end = $self->_causal_end();
    $causal_end = 0 if $causal_end < 0;

    if (defined $self->{replay_view_end}) {
        my $view_end = $self->{replay_view_end};

        # AUTO-SCROLL POR DETECCION DE BORDE (sin flags fragiles): la vista solo
        # se desplaza cuando el head estaba EXACTAMENTE en el borde derecho y
        # avanzo. Asi, tras panear (view_end deja de coincidir con el borde) o
        # tras pausar/interactuar, un nuevo Play NO arrastra todo el grafico:
        # las velas quedan estaticas y las nuevas rellenan el hueco. El head solo
        # "empuja" el borde cuando ya lo habia alcanzado (fase de scroll continuo).
        my $prev = $self->{replay_prev_causal_end};
        if (defined $prev && $causal_end > $prev && $view_end == $prev) {
            $view_end = $causal_end;
        }

        # CLAMP MIN-VISIBLE derecha (siempre): conservar >= MIN_VISIBLE_BARS velas
        # reales en pantalla. Al retroceder (step_backward) esto arrastra la vista
        # con el head en lugar de dejarlo escapar del marco; tambien acota el hueco
        # a la derecha para que no se pueda desplazar a puro blanco.
        my $min_real = MIN_VISIBLE_BARS;
        $min_real = $causal_end + 1 if $min_real > $causal_end + 1;
        my $max_blank = $visible - $min_real;
        $max_blank = 0 if $max_blank < 0;
        my $max_end = $causal_end + $max_blank;
        $view_end = $max_end if $view_end > $max_end;

        # CLAMP izquierda: no permitir hueco en blanco a la izquierda (start >= 0),
        # salvo que haya menos velas que el viewport (entonces se muestran todas).
        my $min_end = $visible - 1;
        $min_end = $causal_end if $causal_end < $min_end;
        $view_end = $min_end if $view_end < $min_end;

        $self->{replay_view_end} = $view_end;          # ancla absoluta persistente
        $self->{replay_prev_causal_end} = $causal_end; # para detectar el proximo avance
        return ($view_end - $visible + 1, $view_end);
    }

    # --- legacy (solo tests que construyen el ChartEngine a mano, p.ej. t/38) ---
    if ($self->{follow_replay_head}) {
        my $blank = $self->_replay_blank_slots($visible);
        my $view_end = $causal_end + $blank;
        return ($view_end - $visible + 1, $view_end);
    }

    my $effective_total = $causal_end + 1;
    $self->{offset} = $self->_clamp_offset($self->{offset}, $effective_total);
    my $view_end = $causal_end - $self->{offset};
    return ($view_end - $visible + 1, $view_end);
}

# Extrae solo datos causalmente permitidos y rellena el resto del viewport con
# undef. Evita que autoescala, ATR y render lean informacion futura indirecta.
sub _causal_slice {
    my ($self, $kind, $start, $end) = @_;
    return [] if !defined $start || !defined $end || $start > $end;

    my $causal_end = $self->_causal_end();
    my $read_end = $end < $causal_end ? $end : $causal_end;
    my $slice;
    if ($read_end >= $start) {
        $slice = $kind eq 'ATR'
            ? $self->{indicator_manager}->slice_array('ATR', $start, $read_end)
            : $self->{market_data}->get_slice($start, $read_end);
    }
    else {
        $slice = [];
    }
    $self->_pad_visible_slice($slice, $start, $end);
    return $slice;
}

# sync_overlay_indicators — task 0015 (producto oficial).
# Alimenta indicadores oficiales hasta el tope de Replay (sin futuro).
#   * Replay ACTIVO   → feed_to = replay_idx
#   * Replay INACTIVO → feed_to = size()-1
# Bajo demanda: solo capas visibles (smc_pro, smc_fvg, zigzag, …).
sub sync_overlay_indicators {
    my ($self) = @_;
    return unless $self->{overlay_manager};

    my $replay   = $self->{replay_controller};
    my $last_idx = $self->{market_data}->size() - 1;
    my $feed_to;
    if ($replay && $replay->is_active() && defined $replay->current_index()) {
        $feed_to = $replay->current_index();
        $feed_to = $last_idx if defined $last_idx && $feed_to > $last_idx;
    } else {
        $feed_to = $last_idx;
    }

    # Solo producto oficial.
    my $smc_wants_feed = $self->_any_named_overlay_wants(qw(smc_pro smc)) ? 1 : 0;
    my $smc_fvg_wants_feed = $self->_overlay_wants_feed('smc_fvg') ? 1 : 0;
    if ($smc_wants_feed) {
        my $done = $self->_feed_smc_chunk($feed_to, $self->{_smc_feed_chunk_size} // 1200);
        $self->_schedule_smc_background_feed($feed_to) unless $done;
    }
    if ($smc_fvg_wants_feed) {
        my $fvg_done = $self->_feed_indicator_chunk(
            $self->{smc_fvg_indicator}, '_smc_fvg_fed_up_to', $feed_to,
            $self->{_smc_feed_chunk_size} // 1200
        );
        $self->_schedule_smc_background_feed($feed_to) unless $fvg_done;
    }
    $self->_feed_indicator_to($self->{zigzag_indicator}, '_zigzag_fed_up_to', $feed_to)
        if $self->_overlay_wants_feed('zigzag');

    # Liquidity v2: pivotes limpios (ZZ externo y/o SMC) + feed on-demand
    if ( $self->_overlay_wants_feed('liq') && $self->{liq_indicator} ) {
        $self->_sync_liquidity_feed($feed_to);
    }

    # DIY Custom Strategy Builder (Supply/Demand Zones)
    if ( $self->_overlay_wants_feed('diy') && $self->{diy_indicator} ) {
        $self->_feed_indicator_to($self->{diy_indicator}, '_diy_fed_up_to', $feed_to);
    }

    # Anchored Volume Profile (AVP) — manual o auto (ZZ ext)
    my $vp_auto_on = ( ( $self->{vp_mode} // '' ) eq 'auto' ) ? 1 : 0;
    if ( $vp_auto_on ) {
        $self->_sync_vp_auto_anchor($feed_to);
    }
    elsif ( $self->_overlay_wants_feed('volumeprofile') && $self->{vp_indicator} ) {
        $self->_feed_indicator_to( $self->{vp_indicator}, '_vp_fed_up_to', $feed_to );
    }

    # Anchored VWAP (AVWAP)
    if ( $self->_overlay_wants_feed('anchoredvwap') && $self->{avwap_indicator} ) {
        $self->_feed_indicator_to($self->{avwap_indicator}, '_avwap_fed_up_to', $feed_to);
    }

    # Pivot Points High Low & Missed (fantasmas)
    my $avwap_auto_on = ( ( $self->{avwap_mode} // '' ) eq 'auto'
      || ( $self->{avwap_mode} // '' ) eq 'both' ) ? 1 : 0;
    if ( ( $self->_overlay_wants_feed('pivotpointshl') || $avwap_auto_on )
      && $self->{pph_indicator} )
    {
        $self->_feed_indicator_to($self->{pph_indicator}, '_pph_fed_up_to', $feed_to);
    }

    if ( $self->_overlay_wants_feed('auto_tc') && $self->{auto_tc_indicator} ) {
        # Chunked: el nacimiento combina pivotes + barridos O(span); no bloquear
        # el primer frame al prender Canal auto (mismo patrón que SMC).
        my $done = $self->_feed_indicator_chunk(
            $self->{auto_tc_indicator}, '_auto_tc_fed_up_to', $feed_to,
            $self->{_auto_tc_feed_chunk_size} // 250
        );
        $self->_schedule_auto_tc_background_feed($feed_to) unless $done;
    }

    if ($avwap_auto_on) {
        $self->_sync_avwap_auto_anchors($feed_to);
    }

    return $feed_to;
}

# _sync_liquidity_feed — pivotes ZZ/SMC absorbidos en historial (no se pierden al
# recortar ZZ a 15 segs). k-swing solo si aún no hay pivotes absorbidos.
sub _sync_liquidity_feed {
    my ( $self, $feed_to ) = @_;
    return unless $self->{liq_indicator} && defined $feed_to && $feed_to >= 0;

    my $fed = $self->{_liq_fed_up_to};
    $fed = -1 unless defined $fed;
    my $rewinding = ( $feed_to < $fed ) ? 1 : 0;

    # Un rewind invalida también el historial de pivotes: algunos pivotes con
    # index <= replay_idx pudieron confirmarse usando barras posteriores. Se
    # reconstruyen desde el ZZ/SMC causal, no se conservan con reset_soft.
    if ($rewinding) {
        if ( $self->{liq_indicator}->can('reset_full') ) {
            $self->{liq_indicator}->reset_full();
        }
        else {
            $self->{liq_indicator}->reset();
        }
        $self->{_liq_fed_up_to} = -1;
        $fed = -1;
    }

    # Si ZZ no está visible, igual alimentamos externo solo para pivotes de liquidez.
    if ( $self->{zigzag_indicator} ) {
        my $zz = $self->{zigzag_indicator};
        my $need_ext = 1;
        if ( $zz->can('wants_external') && $zz->wants_external ) {
            $need_ext = 0;
        }
        if ( $need_ext && $zz->can('set_compute_external') ) {
            $zz->set_compute_external(1);
            $self->_feed_indicator_to( $zz, '_zigzag_fed_up_to', $feed_to );
        }
        elsif ( $self->_overlay_wants_feed('zigzag') ) {
            # ya alimentado arriba
        }
        else {
            $self->_feed_indicator_to( $zz, '_zigzag_fed_up_to', $feed_to )
              if $zz->can('update_last');
        }
    }

    my $pivots = $self->_collect_liquidity_pivots($feed_to);
    my $added  = 0;
    if ( $pivots && @$pivots && $self->{liq_indicator}->can('absorb_pivots') ) {
        $added = $self->{liq_indicator}->absorb_pivots($pivots) || 0;
    }

    # Pivotes nuevos durante avance normal requieren re-simular niveles/eventos,
    # pero sí conservan el historial causal ya acumulado.
    if ( !$rewinding && $added > 0 && $fed >= 0 ) {
        if ( $self->{liq_indicator}->can('reset_soft') ) {
            $self->{liq_indicator}->reset_soft();
        }
        else {
            $self->{liq_indicator}->reset();
        }
        $self->{_liq_fed_up_to} = -1;
    }

    $self->_feed_indicator_to( $self->{liq_indicator}, '_liq_fed_up_to', $feed_to );
    return;
}

sub _liquidity_pivots_signature {
    my ( $self, $pivots ) = @_;
    return '' unless $pivots && @$pivots;
    my @parts =
      map { sprintf( '%d:%s:%.6g', $_->{index} // -1, $_->{side} // '', $_->{price} // 0 ) }
      sort { ( $a->{index} // 0 ) <=> ( $b->{index} // 0 ) } @$pivots;
    return join( '|', @parts );
}

# ZZ externo (siempre que haya segs) + SMC swing si está feedado. Ambos se
# absorben en el historial de Liquidity (no se pierden al trim de 15 segs ZZ).
sub _collect_liquidity_pivots {
    my ( $self, $feed_to ) = @_;
    my @out;
    my %seen;

    if ( $self->{zigzag_indicator} && $self->{zigzag_indicator}->can('get_values') ) {
        my $vals = $self->{zigzag_indicator}->get_values() || {};
        my $md   = $self->{market_data};
        # Preferir log completo (no recortado a 15 segs). Fallback a segs visibles.
        my $log = $vals->{external_pivot_log};
        if ( $log && @$log ) {
            for my $pv (@$log) {
                next if ( $pv->{open} // 0 );    # extremo aún en formación
                my $ix   = $pv->{index};
                my $side = $pv->{side};
                next unless defined $ix && $ix <= $feed_to && $side;
                my $c = $md ? $md->get_candle($ix) : undef;
                next unless $c;
                # Precio real OHLC (no low-of-bar ChartPrime)
                my $price = ( $side eq 'high' ) ? $c->[2] : $c->[3];
                next if $seen{"$ix:$side"}++;
                push @out, { index => $ix, price => $price, side => $side };
            }
        }
        else {
            my $segs = $vals->{external_segments} || [];
            my $nseg = scalar @$segs;
            for my $si ( 0 .. $nseg - 1 ) {
                my $s       = $segs->[$si];
                my $dir     = $s->{dir} // '';
                my $is_last = ( $si == $nseg - 1 ) ? 1 : 0;
                for my $e (
                    { i => $s->{from_index}, role => 'from' },
                    { i => $s->{to_index},   role => 'to' },
                  )
                {
                    next if $is_last && ( $e->{role} // '' ) eq 'to';
                    my $ix = $e->{i};
                    next unless defined $ix && $ix <= $feed_to;
                    my $c = $md ? $md->get_candle($ix) : undef;
                    next unless $c;
                    my ( $side, $price );
                    if ( $dir eq 'up' ) {
                        ( $side, $price ) =
                          $e->{role} eq 'from'
                          ? ( 'low', $c->[3] )
                          : ( 'high', $c->[2] );
                    }
                    else {
                        ( $side, $price ) =
                          $e->{role} eq 'from'
                          ? ( 'high', $c->[2] )
                          : ( 'low', $c->[3] );
                    }
                    next if $seen{"$ix:$side"}++;
                    push @out, { index => $ix, price => $price, side => $side };
                }
            }
        }
    }

    # SMC solo es fuente si su cursor corresponde a un prefijo causal no posterior
    # al feed solicitado. Si la capa está oculta y conserva estado del futuro, se
    # ignora hasta que sea recalculada.
    my $smc_fed = $self->{_smc_fed_up_to};
    $smc_fed = $self->{_smc_pro_fed_up_to} if !defined $smc_fed;
    if ( $self->{smc_pro_indicator}
        && defined $smc_fed && $smc_fed >= 0 && $smc_fed <= $feed_to
        && $self->{smc_pro_indicator}->can('get_pivots') ) {
        my $pivs = $self->{smc_pro_indicator}->get_pivots() || [];
        for my $p (@$pivs) {
            my $ix = $p->{index};
            next unless defined $ix && $ix <= $feed_to;
            my $scope = $p->{scope} // 'swing';
            next if $scope eq 'internal';
            my $type = uc( $p->{type} // '' );
            my $side;
            $side = 'high' if $type eq 'HH' || $type eq 'LH' || $type =~ /H$/;
            $side = 'low'  if $type eq 'LL' || $type eq 'HL' || ( $type =~ /L$/ && !$side );
            next unless $side;
            next if $seen{"$ix:$side"}++;
            push @out,
              {
                index => $ix,
                price => $p->{price},
                side  => $side,
              };
        }
    }

    return @out ? \@out : undef;
}

# compute_run_candle_map — task 0058: índices globales de velas RUN relevantes
# para recoloreo en PricePanel. Respeta toggle RUN del overlay y replay_idx.
# Público para tests headless (mismo patrón que sync_overlay_indicators).
sub _prepare_run_candle_map_for_frame {
    my ($self) = @_;
    # El mapa RUN es parte del render de velas, no solo del overlay. Debe salir
    # del mismo estado causal reconstruido para este frame.
    $self->sync_overlay_indicators() if $self->{overlay_manager};
    return $self->compute_run_candle_map();
}

sub compute_run_candle_map {
    my ($self) = @_;
    # Opcional: índices de velas con RUN resuelto (recolor futuro).
    return {} unless $self->{liq_indicator} && $self->{liq_overlay};
    return {} unless $self->{liq_overlay}->is_visible();
    return {} unless $self->{liq_overlay}->is_element_visible('RUN');

    my $events = $self->{liq_indicator}->get_events() || [];
    my %map;
    for my $ev (@$events) {
        next unless ( $ev->{resolution} // '' ) eq 'run';
        my $i = $ev->{resolve_index} // $ev->{sweep_index};
        $map{$i} = 1 if defined $i;
    }
    return \%map;
}

sub set_zigzag_internal_resolution {
    my ($self, $minutes) = @_;
    return unless $self->{zigzag_indicator};
    $self->{zigzag_indicator}->set_internal_resolution($minutes);
    $self->{_zigzag_fed_up_to} = -1;
    # Re-feed inmediato si la capa está visible (cambio 15/30/60 del profe).
    if ( $self->_overlay_wants_feed('zigzag') ) {
        $self->sync_overlay_indicators();
    }
    $self->request_render();
}

# set_zigzag_layer($elem, $on) — INTERNAL | EXTERNAL.
sub set_zigzag_layer {
    my ( $self, $elem, $on ) = @_;
    return unless $self->{zigzag_indicator} && $self->{zigzag_overlay};
    $elem = uc( $elem // '' );
    return unless $elem eq 'INTERNAL' || $elem eq 'EXTERNAL';
    $on = $on ? 1 : 0;

    my $ov  = $self->{zigzag_overlay};
    my $ind = $self->{zigzag_indicator};
    $ov->set_element_visible( $elem, $on );

    my $want_int = $ov->is_element_visible('INTERNAL') ? 1 : 0;
    my $want_ext = $ov->is_element_visible('EXTERNAL') ? 1 : 0;
    $ind->set_compute_internal($want_int);
    $ind->set_compute_external($want_ext);

    my $any =
         $ov->is_element_visible('INTERNAL')
      || $ov->is_element_visible('EXTERNAL')
      || $ov->is_element_visible('CHANNEL');
    $ov->set_visible( $any ? 1 : 0 );

    $ind->reset();
    $self->{_zigzag_fed_up_to} = -1;
    if ($any) {
        $self->sync_overlay_indicators();
    }
    $self->request_render();
    return $self;
}

# _overlay_wants_feed($name) — true si el indicador asociado debe alimentarse:
# cuando su overlay está visible, o cuando no hay overlay registrado (tests).
sub _overlay_wants_feed {
    my ($self, $name) = @_;
    my $mgr = $self->{overlay_manager};
    my $ov  = $mgr ? $mgr->get($name) : undef;
    return 1 unless $ov;                 # sin overlay (tests t/16) → alimentar
    return $ov->is_visible() ? 1 : 0;    # con overlay → solo si visible
}

# _any_named_overlay_wants(@names) — true si ALGUNO de los nombres registrados
# está visible. Si NINGUNO está registrado, true (tests sin capa). Si hay al
# menos uno registrado y todos OFF, false (arranque on-demand).
# Evita el bug: get('smc_pro') inexistente ⇒ "sin overlay" ⇒ alimentar siempre
# aunque exista 'smc' apagado.
sub _any_named_overlay_wants {
    my ($self, @names) = @_;
    my $mgr = $self->{overlay_manager};
    return 1 unless $mgr;
    my $found = 0;
    for my $name (@names) {
        my $ov = $mgr->get($name);
        next unless $ov;
        $found = 1;
        return 1 if $ov->is_visible();
    }
    return $found ? 0 : 1;
}


# _feed_indicator_to($indicator, $cursor_key, $feed_to)
# task 0015: lleva un indicador incremental exactamente al índice $feed_to,
# respetando el cursor $self->{$cursor_key} (último índice ya alimentado).
#   * Avance (feed_to > cursor): update_last de cursor+1 .. feed_to.
#   * Retroceso (feed_to < cursor): reset() + realimentar 0 .. feed_to.
# El indicador refleja el estado si el dataset terminara en feed_to (sin futuro en Replay).
sub _feed_indicator_to {
    my ($self, $indicator, $cursor_key, $feed_to) = @_;
    return unless $indicator && defined $feed_to;
    return if $feed_to < 0;

    my $fed_up_to = $self->{$cursor_key};
    $fed_up_to = -1 unless defined $fed_up_to;

    if ($feed_to > $fed_up_to) {
        for my $i ($fed_up_to + 1 .. $feed_to) {
            $indicator->update_last($self->{market_data}, $i);
        }
        $self->{$cursor_key} = $feed_to;
    } elsif ($feed_to < $fed_up_to) {
        $indicator->reset();
        for my $i (0 .. $feed_to) {
            $indicator->update_last($self->{market_data}, $i);
        }
        $self->{$cursor_key} = $feed_to;
    }
    return;
}

# --- SMC Pro / FVG: feed no bloqueante ---
sub _feed_indicator_chunk {
    my ($self, $indicator, $cursor_key, $feed_to, $chunk) = @_;
    return 1 unless $indicator && defined $feed_to && $feed_to >= 0;
    $chunk ||= 1200;
    my $fed = $self->{$cursor_key};
    $fed = -1 unless defined $fed;
    if ($feed_to < $fed) {
        # Retroceso (Replay): reset ANTES de comprobar si el cursor ya cubría
        # el objetivo. El estado previo puede contener estructuras del futuro.
        $indicator->reset() if $indicator->can('reset');
        $self->{$cursor_key} = -1;
        $fed = -1;
    }
    return 1 if $fed >= $feed_to;
    my $to = $fed + $chunk;
    $to = $feed_to if $to > $feed_to;
    $self->_feed_indicator_to($indicator, $cursor_key, $to);
    return (($self->{$cursor_key} // -1) >= $feed_to) ? 1 : 0;
}

sub _feed_smc_chunk {
    my ($self, $feed_to, $chunk) = @_;
    my $ind = $self->{smc_pro_indicator} // $self->{smc_indicator};
    my $done = $self->_feed_indicator_chunk($ind, '_smc_fed_up_to', $feed_to, $chunk);
    $self->{_smc_pro_fed_up_to} = $self->{_smc_fed_up_to};
    return $done;
}

sub _schedule_smc_background_feed {
    my ($self, $target) = @_;
    return if $self->{_smc_background_feed_pending};
    my $canvas = $self->{price_canvas} || $self->{atr_canvas};
    return unless $canvas;
    $self->{_smc_background_feed_pending} = 1;
    my $delay = $self->{_smc_feed_after_ms} // 16;
    $canvas->after($delay, sub {
        $self->{_smc_background_feed_pending} = 0;
        my $ok = eval {
            my $md = $self->{market_data};
            return 1 unless $md;
            my $last = $md->size() - 1;
            return 1 if $last < 0;
            my $replay = $self->{replay_controller};
            my $feed_to = $target;
            if ($replay && $replay->is_active() && defined $replay->current_index()) {
                $feed_to = $replay->current_index();
                $feed_to = $last if $feed_to > $last;
            } else {
                $feed_to = $last if !defined $feed_to || $feed_to > $last;
            }

            # Solo capas realmente registradas y visibles (mismo criterio on-demand).
            my $need_smc = $self->_any_named_overlay_wants(qw(smc_pro smc));
            my $need_fvg = $self->_overlay_wants_feed('smc_fvg');
            return 1 unless $need_smc || $need_fvg;

            my $chunk = $self->{_smc_feed_chunk_size} // 1200;
            my $done = 1;
            if ($need_smc) {
                $done = 0 unless $self->_feed_smc_chunk($feed_to, $chunk);
            }
            if ($need_fvg) {
                $done = 0 unless $self->_feed_indicator_chunk(
                    $self->{smc_fvg_indicator}, '_smc_fvg_fed_up_to', $feed_to, $chunk
                );
            }
            # Re-render para ir mostrando estructura (prefijo causal válido).
            $self->request_render();
            $self->_schedule_smc_background_feed($feed_to) unless $done;
            1;
        };
        if (!$ok) {
            warn "SMC background feed: $@";
            # Intentar pintar lo ya calculado y no dejar la capa muda.
            eval { $self->request_render() };
        }
    });
    return $self;
}

# Feed diferido AutoTrendChannel (mismo patrón que SMC; chunk más chico).
sub _schedule_auto_tc_background_feed {
    my ( $self, $target ) = @_;
    return if $self->{_auto_tc_background_feed_pending};
    my $canvas = $self->{price_canvas} || $self->{atr_canvas};
    return unless $canvas;
    $self->{_auto_tc_background_feed_pending} = 1;
    my $delay = $self->{_auto_tc_feed_after_ms} // 16;
    $canvas->after(
        $delay,
        sub {
            $self->{_auto_tc_background_feed_pending} = 0;
            my $ok = eval {
                return 1 unless $self->_overlay_wants_feed('auto_tc') && $self->{auto_tc_indicator};
                my $md = $self->{market_data};
                return 1 unless $md;
                my $last = $md->size() - 1;
                return 1 if $last < 0;
                my $replay  = $self->{replay_controller};
                my $feed_to = $target;
                if ( $replay && $replay->is_active() && defined $replay->current_index() ) {
                    $feed_to = $replay->current_index();
                    $feed_to = $last if $feed_to > $last;
                }
                else {
                    $feed_to = $last if !defined $feed_to || $feed_to > $last;
                }
                my $chunk = $self->{_auto_tc_feed_chunk_size} // 250;
                my $done  = $self->_feed_indicator_chunk(
                    $self->{auto_tc_indicator}, '_auto_tc_fed_up_to', $feed_to, $chunk
                );
                $self->request_render();
                $self->_schedule_auto_tc_background_feed($feed_to) unless $done;
                1;
            };
            if ( !$ok ) {
                warn "AutoTC background feed: $@";
                eval { $self->request_render() };
            }
        }
    );
    return $self;
}

sub round {
    my ($self, $value) = @_;

    return 0 if !defined $value;

    return int($value + ($value >= 0 ? 0.5 : -0.5));
}

sub _max_offset_for_visible {
    my ($self, $total_override) = @_;

    my $total = defined $total_override ? $total_override : ($self->{market_data}->size() || 0);
    return 0 if $total < MIN_VISIBLE_BARS;

    return ($total - MIN_VISIBLE_BARS) > 0 ? ($total - MIN_VISIBLE_BARS) : 0;
}

sub _min_offset_for_visible {
    my ($self, $total_override) = @_;

    my $total = defined $total_override ? $total_override : ($self->{market_data}->size() || 0);
    return 0 if $total < MIN_VISIBLE_BARS;


    my $visible = $self->{visible_bars} || MIN_VISIBLE_BARS;
    $visible = $total if $visible > $total;

    return -(($visible > MIN_VISIBLE_BARS) ? ($visible - MIN_VISIBLE_BARS) : 0);
}

sub _clamp_offset {
    my ($self, $offset, $total_override) = @_;

    $offset = 0 if !defined $offset;
    my $min_offset = $self->_min_offset_for_visible($total_override);
    my $max_offset = $self->_max_offset_for_visible($total_override);
    $offset = $min_offset if $offset < $min_offset;
    $offset = $max_offset if $offset > $max_offset;
    return $offset;
}

sub _visible_slice_has_candles {
    my ($self, $slice) = @_;

    return 0 unless $slice && @$slice;
    for my $c (@$slice) {
        next unless defined $c && ref $c eq 'ARRAY';
        return 1 if defined $c->[2] || defined $c->[3];
    }
    return 0;
}

sub _is_price_y_fallback {
    my ($self, $min, $max) = @_;
    return defined $min && defined $max && $min == 20000 && $max == 30000;
}

sub _pad_visible_slice {
    my ($self, $slice, $start, $end) = @_;

    return unless $slice;
    my $target = defined $start && defined $end && $end >= $start ? $end - $start + 1 : 0;
    push @$slice, (undef) x ($target - @$slice) if $target > @$slice;
}

# Ventana de dibujo con una barra de overscan para el paneo fraccional. En
# Replay la barra derecha adicional solo existe si ya pertenece al prefijo
# causal; nunca se consulta ni se pinta una vela posterior al replay head.
sub _compute_draw_window {
    my ($self, $start, $end) = @_;
    return ($start, $end) if !defined $start || !defined $end;

    my $total = $self->{market_data}->size();
    my $draw_start = $start > 0 ? $start - 1 : $start;
    my $draw_end   = ($end < $total - 1) ? $end + 1 : $end;

    my $replay = $self->{replay_controller};
    if ($replay && $replay->is_active()) {
        my $ridx = $replay->current_index();
        $draw_end = $ridx if defined $ridx && $draw_end > $ridx;
    }
    return ($draw_start, $draw_end);
}

sub _canvas_width {
    my ($self, $canvas) = @_;
    return 1 unless $canvas;

    my $w = 0;
    my $geom = eval { $canvas->geometry() };
    if (defined $geom && $geom =~ /^(\d+)x\d+/) {
        $w = $1;
    }
    $w ||= eval { $canvas->Width() } || eval { $canvas->width() } || 1;
    return $w > 1 ? $w : 1;
}

sub _canvas_size {
    my ($self, $canvas) = @_;
    return (1, 1) unless $canvas;
    my ($w, $h) = (0, 0);
    my $geom = eval { $canvas->geometry() };
    if (defined $geom && $geom =~ /^(\d+)x(\d+)/) {
        ($w, $h) = ($1, $2);
    }
    $w ||= eval { $canvas->Width() }  || eval { $canvas->width() }  || 1;
    $h ||= eval { $canvas->Height() } || eval { $canvas->height() } || 1;
    $w = 1 if $w < 1;
    $h = 1 if $h < 1;
    return ($w, $h);
}

sub _reset_canvas_view {
    my ($self, $canvas) = @_;
    return unless $canvas;

    my ($w, $h) = $self->_canvas_size($canvas);
    eval { $canvas->xviewMoveto(0) };
    eval { $canvas->yviewMoveto(0) };
    eval { $canvas->configure(-scrollregion => [0, 0, $w, $h]) };
}

sub request_render {
    my ($self) = @_;

    return if $self->{render_pending};
    $self->{render_pending} = 1;

    my $canvas = $self->{price_canvas} || $self->{atr_canvas};
    if ($canvas) {
        $canvas->after(20, sub {
            $self->{render_pending} = 0;
            $self->render();
        });
    } else {
        $self->{render_pending} = 0;
        $self->render();
    }
}

sub render {
    my ($self) = @_;

    # Barrera defensiva: si NO hay sesión de Replay viva (ni truncado, ni Select
    # Bar, ni pestaña Replay activa), purgar cualquier artefacto visual de Replay
    # que haya podido quedar colgado (marca de agua, velo/tijeras). Así, cambiar
    # de indicador o de pestaña tras salir de Replay nunca deja restos mezclados.
    my $replay_session_on = $self->_replay_session_active() ? 1 : 0;
    if (!$replay_session_on) {
        $self->_purge_replay_visuals();
    }
    if ( ref( $self->{replay_session_badge_sync} ) eq 'CODE' ) {
        $self->{replay_session_badge_sync}->($replay_session_on);
    }

    # 1. Obtener la porción temporal de la ventana visible
    my ($start, $end) = $self->compute_window();

    # 2. Extraer solo datos causalmente permitidos. Los slots logicos vacios
    # (incluido el hueco derecho de Replay) se rellenan con undef.
    my $visible_candles = $self->_causal_slice('OHLC', $start, $end);
    my $visible_atr     = $self->_causal_slice('ATR',  $start, $end);

    # spec 0000i: overscan de render horizontal. El slice de dibujo incluye
    # una vela extra a cada lado (start-1, end+1) para que las velas parcialmente
    # visibles durante paneo suave (ctrl_zoom_x_shift) se rendericen desde antes.
    # La escala X sigue usando x_bars de la ventana visible; draw_start_offset
    # permite al panel calcular el índice local correcto (incluyendo -1 y
    # visible_bars) para posicionar las velas overscan.
    my $replay = $self->{replay_controller};
    my ($draw_start, $draw_end) = $self->_compute_draw_window($start, $end);
    my $replay_head_candle;
    my $replay_head_atr;
    if ($replay && $replay->is_active()) {
        my $ridx = $replay->current_index();
        if (defined $ridx) {
            $replay_head_candle = $self->{market_data}->get_candle($ridx);
            my $atr_slice = $self->{indicator_manager}->slice_array('ATR', $ridx, $ridx);
            $replay_head_atr = $atr_slice->[0] if $atr_slice && @$atr_slice;
        }
    }
    my $draw_candles = $self->_causal_slice('OHLC', $draw_start, $draw_end);
    my $draw_atr     = $self->_causal_slice('ATR',  $draw_start, $draw_end);
    my $draw_start_offset = $draw_start - $start;
    my $visible_count = $end - $start + 1;

    # 3. Calcular rangos de precios e indicadores para construir escalas dinámicas
    my ($min_p, $max_p) = $self->{price_panel}->get_y_range($visible_candles);
    my ($min_a, $max_a) = $self->{atr_panel}->get_y_range($visible_atr);
    my $has_price_candles = $self->_visible_slice_has_candles($visible_candles);

    if (!$self->{is_auto_scale} && defined $self->{manual_min_y} && defined $self->{manual_max_y}) {
        ($min_p, $max_p) = ($self->{manual_min_y}, $self->{manual_max_y});
    } elsif (!$self->{is_auto_scale}
        && defined $self->{ctrl_zoom_y_lock_min}
        && defined $self->{ctrl_zoom_y_lock_max}) {
        ($min_p, $max_p) = ($self->{ctrl_zoom_y_lock_min}, $self->{ctrl_zoom_y_lock_max});
    } elsif ($self->{is_auto_scale} && $has_price_candles) {
        ($self->{manual_min_y}, $self->{manual_max_y}) = ($min_p, $max_p);
        ($self->{last_auto_min_y}, $self->{last_auto_max_y}) = ($min_p, $max_p);
    }

    if (!defined $min_p || !defined $max_p || $min_p == $max_p || !$has_price_candles) {
        if (defined $self->{last_auto_min_y} && defined $self->{last_auto_max_y}
            && !$self->_is_price_y_fallback($self->{last_auto_min_y}, $self->{last_auto_max_y})) {
            ($min_p, $max_p) = ($self->{last_auto_min_y}, $self->{last_auto_max_y});
        } elsif (!$self->{is_auto_scale}
            && defined $self->{manual_min_y} && defined $self->{manual_max_y}) {
            ($min_p, $max_p) = ($self->{manual_min_y}, $self->{manual_max_y});
        } else {
            $min_p = 20000;
            $max_p = 30000;
        }
    }
    if (!$self->{is_atr_auto_scale} && defined $self->{atr_manual_min_y} && defined $self->{atr_manual_max_y}) {
        ($min_a, $max_a) = ($self->{atr_manual_min_y}, $self->{atr_manual_max_y});
    } elsif ($self->{is_atr_auto_scale}) {
        ($self->{atr_manual_min_y}, $self->{atr_manual_max_y}) = ($min_a, $max_a);
        ($self->{last_auto_atr_min_y}, $self->{last_auto_atr_max_y}) = ($min_a, $max_a);
    }
    if (!defined $min_a || !defined $max_a || $min_a == $max_a) {
        $min_a = 0;
        $max_a = 100;
    }

    # 4. Instanciar los sistemas de coordenadas. La escala X usa un ancho compartido
    # para que PricePanel y ATRPanel queden sincronizados barra por barra.
    my ($price_w, $price_h) = $self->_canvas_size($self->{price_canvas});
    my ($atr_w, $atr_h)     = $self->_canvas_size($self->{atr_canvas});
    my $shared_w = $price_w;

    $self->_reset_canvas_view($self->{price_canvas});
    $self->_reset_canvas_view($self->{atr_canvas});
    $self->_reset_canvas_view($self->{price_axis_canvas});
    $self->_reset_canvas_view($self->{atr_axis_canvas});
    $self->_reset_canvas_view($self->{time_axis_canvas});

    if (!$self->{_printed_render_diag}) {
        print "[*] Render geometry: price=${price_w}x${price_h} atr=${atr_w}x${atr_h} window=$start-$end bars=" . scalar(@$visible_candles) . "\n";
        $self->{_printed_render_diag} = 1;
    }

    my $x_bars = $end - $start + 1;
    $x_bars = scalar(@$visible_candles) if $x_bars < 1;
    $x_bars = 1 if $x_bars < 1;

    # Replay ya reserva slots vacios a la derecha en compute_window(). Nunca
    # mutar x_shift desde render: queda reservado al pan fraccional.

    my $price_scale = Market::Panels::Scales->new(min_y => $min_p, max_y => $max_p, bars => $x_bars, right_margin => RIGHT_MARGIN);
    my $atr_scale   = Market::Panels::Scales->new(min_y => $min_a, max_y => $max_a, bars => $x_bars, right_margin => RIGHT_MARGIN);
    $price_scale->{width}  = $shared_w;
    $price_scale->{height} = $price_h;
    $price_scale->{draw_labels} = $self->{price_axis_canvas} ? 0 : 1;
    $price_scale->{draw_last_label} = $self->{price_axis_canvas} ? 0 : 1;
    $price_scale->{draw_crosshair_label} = $self->{price_axis_canvas} ? 0 : 1;
    $price_scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    $price_scale->{tick_size} = 0.25;
    $price_scale->{draw_start_offset} = $draw_start_offset;
    $price_scale->{visible_count} = $visible_count;
    $price_scale->{slice_base_index} = $draw_start;
    $price_scale->{draw_grid} = $self->{show_grid} ? 1 : 0;
    if (defined $replay_head_candle) {
        $price_scale->{replay_head_candle} = $replay_head_candle;
        $price_scale->{replay_max_index} = $replay->current_index();
    }
    $atr_scale->{width}    = $shared_w;
    $atr_scale->{height}   = $atr_h;
    $atr_scale->{draw_labels} = $self->{atr_axis_canvas} ? 0 : 1;
    $atr_scale->{draw_last_label} = $self->{atr_axis_canvas} ? 0 : 1;
    $atr_scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    $atr_scale->{draw_start_offset} = $draw_start_offset;
    $atr_scale->{visible_count} = $visible_count;
    $atr_scale->{slice_base_index} = $draw_start;
    $atr_scale->{draw_grid} = $self->{show_grid} ? 1 : 0;
    if (defined $replay_head_atr) {
        $atr_scale->{replay_head_value} = $replay_head_atr;
        $atr_scale->{replay_max_index}  = $replay->current_index();
    }

    # Los paneles también consumen estado semántico de indicadores (p. ej. color
    # de velas RUN). Prepararlo como sync → mapa evita que el primer frame tras
    # un rewind pinte etiquetas obtenidas con barras futuras.
    $self->{price_panel}->set_scale($price_scale);
    $self->{price_panel}->set_run_candles(
        $self->_prepare_run_candle_map_for_frame()
    );
    # Reutilizar en crosshair/snap (evita new Scales en cada Motion).
    $self->{_last_price_scale} = $price_scale;
    $self->{_last_atr_scale}   = $atr_scale;
    $self->{_last_window}      = [$start, $end];

    $self->{atr_panel}->set_scale($atr_scale);

    # 5. Ejecutar render en cada sub-canvas
    # spec 0000i: pasar draw_candles (con overscan) al panel para que las velas
    # parcialmente visibles durante paneo se rendericen desde antes.
    $self->{price_panel}->render($self->{price_canvas}, $draw_candles, $price_scale);
    $self->_draw_replay_watermark($self->{price_canvas});
    # ATR oculto (toggle UI): no pintar el panel ni su eje (canvas sin pack).
    my $atr_shown = !$self->{_atr_hidden};
    $self->{atr_panel}->render($self->{atr_canvas}, $draw_atr, $atr_scale) if $atr_shown;
    my $time_labels = $self->compute_intraday_labels();
    $self->{price_panel}->draw_time_axis($self->{price_canvas}, $time_labels, { draw_grid => ($self->{show_grid} ? 1 : 0), draw_labels => 0 });
    $self->_render_price_axis($price_scale, $visible_candles, $replay_head_candle);
    $self->_render_atr_axis($atr_scale, $visible_atr, $replay_head_atr) if $atr_shown;
    $self->_render_time_axis($price_scale, $time_labels);

    # spec 0003 / task 0015: overlays — compute + draw respetando replay_idx.
    # Los indicadores ya se sincronizaron antes de pintar los paneles para que
    # velas semánticas (RUN) y overlays compartan el mismo estado causal.
    if ($self->{overlay_manager}) {
        $self->_sync_fib_follow_zz_ext();
        # compute_all y el filtro del overlay (index <= end) actúan como segunda
        # barrera (defensa en profundidad); la corrección real es alimentar hasta
        # feed_to en sync_overlay_indicators.
        # Unico tope causal para todas las capas. En Replay nunca se deriva del
        # cursor SMC ni del final completo del dataset.
        my $feed_end = $self->_causal_end();
        for my $name (qw(smc_pro smc_fvg smc)) {
            my $ov = $self->{overlay_manager}->get($name);
            $ov->{_feed_end} = $feed_end if $ov;
        }
        if ( my $pov = $self->{overlay_manager}->get('pchan') ) {
            $pov->{_data_end} = $feed_end;
        }
        if ( my $fov = $self->{overlay_manager}->get('fib') ) {
            $fov->{_data_end} = $feed_end;
        }
        if ( my $hov = $self->{overlay_manager}->get('hld') ) {
            # Replay / feed: precio y fin de proyección = tope efectivo
            $hov->{_feed_end} = $feed_end;
        }
        if ( my $lov = $self->{overlay_manager}->get('liq') ) {
            $lov->{_feed_end} = $feed_end;
        }

        $self->{overlay_manager}->compute_all($self->{market_data}, $start, $feed_end);
        $self->{overlay_manager}->draw_all($self->{price_canvas}, $price_scale);
        # Velas por encima de líneas de indicadores (BOS/CHoCH/EQ/OB/HLD lines…).
        eval { $self->{price_canvas}->raise('candle'); 1 };
        eval { $self->{price_canvas}->raise('price_label'); 1 };
        # Etiquetas HLD siempre encima de las velas (chip + texto legible).
        eval { $self->{price_canvas}->raise('hld_lbl_bg'); 1 };
        eval { $self->{price_canvas}->raise('hld_lbl'); 1 };
    }

    if ($self->{_replay_select_mode}) {
        $self->_clear_chart_crosshair();
        if (defined $self->{last_mouse_x}) {
            $self->_draw_replay_select_hover(undef, $self->{last_mouse_x}, $self->{last_mouse_y});
        }
    }
    elsif ($self->{_vwap_select_mode}) {
        $self->_clear_chart_crosshair();
        # Banner siempre; línea de hover solo si hay cursor sobre el chart.
        $self->_draw_vwap_select_banner();
        if (defined $self->{last_mouse_x}) {
            $self->_draw_vwap_select_hover(undef, $self->{last_mouse_x}, $self->{last_mouse_y});
        }
    }
    elsif ($self->{_vp_select_mode}) {
        $self->_clear_chart_crosshair();
        $self->_draw_vp_select_banner();
        if (defined $self->{last_mouse_x}) {
            $self->_draw_vp_select_hover(undef, $self->{last_mouse_x}, $self->{last_mouse_y});
        }
    }
    elsif (defined $self->{last_mouse_x}) {
        $self->_draw_crosshair_all();
    }
    $self->_draw_replay_select_marker();
    $self->_redraw_pointer_symbol();
}

sub _render_price_axis {
    my ($self, $source_scale, $visible_candles, $replay_head_candle) = @_;

    my $canvas = $self->{price_axis_canvas};
    return unless $canvas && $source_scale;

    my ($w, $h) = $self->_canvas_size($canvas);
    $canvas->delete('y_scale');
    $canvas->delete('axis_last_price');

    my $axis_scale = Market::Panels::Scales->new(
        min_y        => $source_scale->{min_y},
        max_y        => $source_scale->{max_y},
        bars         => 1,
        right_margin => 0,
    );
    $axis_scale->{width}           = $w;
    $axis_scale->{height}          = $source_scale->{height} || $h;
    $axis_scale->{draw_grid}       = 0;
    $axis_scale->{draw_labels}     = 1;
    $axis_scale->{label_x}         = 4;
    $axis_scale->{label_anchor}    = 'w';
    $axis_scale->{grid_color}      = $self->{theme}{grid}      // '#e6e6e6';
    $axis_scale->{axis_text_color} = $self->{theme}{axis_text} // '#363a45';
    $axis_scale->{tick_size}       = $source_scale->{tick_size};
    $axis_scale->_draw_y_scale($canvas);

    my $last_candle = $replay_head_candle;
    if (!defined $last_candle && $visible_candles && @$visible_candles) {
        for my $candle (@$visible_candles) {
            $last_candle = $candle if defined $candle;
        }
    }
    return unless defined $last_candle;
    my ($open, $close) = @{$last_candle}[1, 4];
    return unless defined $close;

    my $y = $axis_scale->value_to_y($close);

    my $label = sprintf('%.2f', $close);
    my $bg = (defined $open && $close >= $open)
        ? ($self->{theme}{bull} // '#26a69a')
        : ($self->{theme}{bear} // '#ef5350');
    my $fg = $self->{theme}{last_price_fg} // '#ffffff';

    $canvas->createRectangle(0, $y - 8, $w, $y + 8, -fill => $bg, -outline => $bg, -tags => 'axis_last_price');
    $canvas->createText(4, $y, -text => $label, -anchor => 'w', -font => 'Helvetica 9 bold', -fill => $fg, -tags => 'axis_last_price');
}

sub _draw_price_axis_crosshair {
    my ($self, $y) = @_;

    my $canvas = $self->{price_axis_canvas};
    return unless $canvas;

    $canvas->delete('axis_crosshair');
    return unless defined $y;

    my $scale = $self->{price_panel} ? $self->{price_panel}->{scale} : undef;
    return unless $scale;

    my ($w, undef) = $self->_canvas_size($canvas);
    my $value = $scale->y_to_value($y);
    my $tick = $scale->{tick_size} || 0.25;
    $value = int($value / $tick + ($value >= 0 ? 0.5 : -0.5)) * $tick;
    my $label = sprintf('%.2f', $value);
    my $bg = $self->{theme}{label_bg} // '#363a45';
    my $fg = $self->{theme}{label_fg} // '#ffffff';

    $canvas->createRectangle(0, $y - 8, $w, $y + 8, -fill => $bg, -outline => $bg, -tags => 'axis_crosshair');
    $canvas->createText(4, $y, -text => $label, -anchor => 'w', -font => 'Helvetica 9 bold', -fill => $fg, -tags => 'axis_crosshair');
}

sub _draw_atr_axis_crosshair {
    my ($self, $y) = @_;

    my $canvas = $self->{atr_axis_canvas};
    return unless $canvas;

    $canvas->delete('atr_axis_crosshair');
    return unless defined $y;

    my $scale = $self->{atr_panel} ? $self->{atr_panel}->{scale} : undef;
    return unless $scale;

    my ($w, undef) = $self->_canvas_size($canvas);
    my $value = $scale->y_to_value($y);
    my $label = sprintf('%.4f', $value);
    my $bg = $self->{theme}{label_bg} // '#363a45';
    my $fg = $self->{theme}{label_fg} // '#ffffff';

    $canvas->createRectangle(0, $y - 8, $w, $y + 8, -fill => $bg, -outline => $bg, -tags => 'atr_axis_crosshair');
    $canvas->createText(4, $y, -text => $label, -anchor => 'w', -font => 'Helvetica 9 bold', -fill => $fg, -tags => 'atr_axis_crosshair');
}

sub _render_time_axis {
    my ($self, $source_scale, $labels) = @_;

    my $canvas = $self->{time_axis_canvas};
    return unless $canvas && $source_scale;

    my ($w, $h) = $self->_canvas_size($canvas);
    my $old_scale = $self->{price_panel}->{scale};
    my $axis_scale = Market::Panels::Scales->new(
        bars         => $source_scale->{bars},
        right_margin => RIGHT_MARGIN,
    );
    $axis_scale->{width}  = $source_scale->{width} || $w;
    $axis_scale->{height} = $h;
    $axis_scale->{x_shift} = $source_scale->{x_shift} || 0;

    $self->{price_panel}->{scale} = $axis_scale;
    $self->{price_panel}->draw_time_axis($canvas, $labels, { draw_grid => 0, draw_labels => 1 });
    $self->{price_panel}->{scale} = $old_scale;
}

sub _render_atr_axis {
    my ($self, $source_scale, $visible_atr, $replay_head_atr) = @_;

    my $canvas = $self->{atr_axis_canvas};
    return unless $canvas && $source_scale;

    my ($w, $h) = $self->_canvas_size($canvas);
    $canvas->delete('y_scale');
    $canvas->delete('atr_axis_last');

    my $axis_scale = Market::Panels::Scales->new(
        min_y        => $source_scale->{min_y},
        max_y        => $source_scale->{max_y},
        bars         => 1,
        right_margin => 0,
    );
    $axis_scale->{width}           = $w;
    $axis_scale->{height}          = $source_scale->{height} || $h;
    $axis_scale->{draw_grid}       = 0;
    $axis_scale->{draw_labels}     = 1;
    $axis_scale->{label_x}         = 4;
    $axis_scale->{label_anchor}    = 'w';
    $axis_scale->{grid_color}      = $self->{theme}{grid}      // '#e6e6e6';
    $axis_scale->{axis_text_color} = $self->{theme}{axis_text} // '#363a45';
    $axis_scale->_draw_y_scale($canvas);

    my $last = $replay_head_atr;
    if (!defined $last) {
        for my $v (@$visible_atr) {
            $last = $v if defined $v;
        }
    }
    return unless defined $last;

    my $y = $axis_scale->value_to_y($last);
    my $label = sprintf('%.4f', $last);
    my $fg = $self->{theme}{last_price_fg} // '#ffffff';
    my $line = $self->{theme}{atr_line} // '#2962ff';

    $canvas->createRectangle(0, $y - 8, $w, $y + 8, -fill => $line, -outline => $line, -tags => 'atr_axis_last');
    $canvas->createText(4, $y, -text => $label, -anchor => 'w', -font => 'Helvetica 9 bold', -fill => $fg, -tags => 'atr_axis_last');
}


sub _set_cursor {
    my ($self, $widget, $cursor) = @_;

    return unless defined $widget;
    return unless defined $cursor;
    # Tk acepta el arrayref ['@src', mask, fg, bg] tal cual (cursor XBM invisible).
    eval { $widget->configure(-cursor => $cursor) };
}

sub _draw_pointer_symbol {
    my ($self, $widget, $x, $y, $kind) = @_;

    return unless defined $widget;
    eval { $widget->delete('pointer_symbol') };
}

sub _clear_pointer_symbol {
    my ($self, $widget) = @_;

    eval { $widget->delete('pointer_symbol') } if defined $widget;
    $self->{pointer_widget} = undef;
}

sub _redraw_pointer_symbol {
    my ($self) = @_;

    return;
}

# ----------------------------------------------------------------------------
# Replay Select Bar (task 0030): elegir vela de inicio con click + Shift+flechas.
# ----------------------------------------------------------------------------

sub set_replay_select_mode {
    my ($self, $on) = @_;
    $on = $on ? 1 : 0;
    if (!$on && $self->{_replay_select_mode}) {
        $self->_clear_replay_select_hover();
    }
    $self->{_replay_select_mode} = $on;
    if ($on) {
        # TradingView: la línea azul solo aparece con el cursor dentro del chart.
        delete $self->{last_mouse_x};
        delete $self->{last_mouse_y};
        $self->_clear_replay_select_hover();
        $self->_clear_chart_crosshair();
        delete $self->{_select_blank_cursor};
    }
    else {
        delete $self->{_select_blank_cursor};
    }
    if (ref($self->{replay_select_mode_callback}) eq 'CODE') {
        $self->{replay_select_mode_callback}->($self->{_replay_select_mode});
    }
    $self->_apply_select_mode_cursor(1);
    return $self;
}

# _seed_replay_select_hover — legacy: ya no se invoca al entrar en select mode
# (TradingView: línea azul solo con cursor sobre price/atr/time canvas).
sub _seed_replay_select_hover {
    my ($self) = @_;
    return unless $self->{_replay_select_mode};
    return if defined $self->{last_mouse_x};

    my ($start, $end) = eval { $self->compute_window() };
    return unless defined $end && defined $start && $end >= $start;

    my $local = $end - $start;
    my $bars  = $end - $start + 1;
    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width}   = $self->_canvas_width($self->{price_canvas});
    $scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    my $x = $scale->index_to_center_x($local);
    return unless defined $x;

    $self->{last_mouse_x} = $self->round($x);
    my (undef, $h) = $self->_canvas_size($self->{price_canvas});
    $self->{last_mouse_y} = defined $h ? int($h / 2) : undef;
    return $self;
}

sub clear_replay_select_mode {
    my ($self) = @_;
    return $self->set_replay_select_mode(0);
}

sub clear_replay_select_state {
    my ($self) = @_;
    $self->{_selected_bar} = undef;
    return $self->clear_replay_select_mode();
}

# restore_after_replay_exit — vuelta a chart vivo: sin truncado ni shift de replay.
sub restore_after_replay_exit {
    my ($self) = @_;
    delete $self->{replay_view_anchor}; # compat con sesiones antiguas
    delete $self->{follow_replay_head};
    delete $self->{replay_view_end};    # ancla absoluta de Replay
    delete $self->{replay_prev_causal_end};
    $self->{ctrl_zoom_x_shift} = 0;
    $self->{offset} = 0;
    # Limpieza explícita e inmediata de artefactos de Replay (no esperar al render):
    # evita que la marca "Replay" o el velo de Select Bar queden colgados un frame.
    $self->_clear_replay_select_hover();
    $self->_purge_replay_visuals();
    return $self;
}

# task 0050/0051: atajos replay en canvas precio/ATR (guards por estado; sin binds dinamicos).
# Precedencia Shift+flechas: select_mode > replay activo > nada.

sub _replay_shift_down_key {
    my ($self) = @_;
    my $rc = $self->{replay_controller};
    return unless $rc && $rc->is_active();
    my $cb = $self->{replay_keyboard_callbacks}{toggle_play};
    $cb->() if ref($cb) eq 'CODE';
    return $self;
}

sub _replay_shift_right_key {
    my ($self) = @_;
    if ($self->{_replay_select_mode}) {
        $self->adjust_selected_bar(1);
        $self->request_render();
        return $self;
    }
    my $rc = $self->{replay_controller};
    return $self unless $rc && $rc->is_active();
    my $cb = $self->{replay_keyboard_callbacks}{step_fwd};
    $cb->() if ref($cb) eq 'CODE';
    return $self;
}

sub _replay_shift_left_key {
    my ($self) = @_;
    if ($self->{_replay_select_mode}) {
        $self->adjust_selected_bar(-1);
        $self->request_render();
        return $self;
    }
    my $rc = $self->{replay_controller};
    return $self unless $rc && $rc->is_active();
    my $cb = $self->{replay_keyboard_callbacks}{step_back};
    $cb->() if ref($cb) eq 'CODE';
    return $self;
}

# _replay_session_active — replay truncado, select bar o pestaña Replay activa.
sub _replay_session_active {
    my ($self) = @_;
    return 1 if $self->{_replay_select_mode};
    my $rc = $self->{replay_controller};
    return 1 if $rc && $rc->is_active();
    my $ref = $self->{replay_on_ref};
    return ($ref && ${ $ref }) ? 1 : 0;
}

sub _replay_escape_key {
    my ($self) = @_;
    # Precedencia: cancelar herramientas de dibujo antes que Replay.
    if ( $self->{fib_drawing} && $self->{fib_drawing}->is_tool_active() ) {
        $self->cancel_fib_retracement_tool();
        return $self;
    }
    if ( $self->{pchan_drawing} && $self->{pchan_drawing}->is_tool_active() ) {
        $self->cancel_parallel_channel_tool();
        return $self;
    }
    if ($self->{_vwap_select_mode}) {
        $self->cancel_vwap_select_mode();
        return $self;
    }
    if ($self->{_vp_select_mode}) {
        $self->cancel_vp_select_mode();
        return $self;
    }
    return $self unless $self->_replay_session_active();
    my $cb = $self->{replay_keyboard_callbacks}{exit};
    $cb->() if ref($cb) eq 'CODE';
    return $self;
}

sub _replay_key_m {
    my ($self, $panel) = @_;
    my $rc = $self->{replay_controller};
    if ($rc && $rc->is_active()) {
        my $cb = $self->{replay_keyboard_callbacks}{toggle_watermark};
        $cb->() if ref($cb) eq 'CODE';
        return $self;
    }
    if (($panel // 'price') eq 'atr') {
        $self->set_atr_scale_mode('manual');
    }
    else {
        $self->set_scale_mode('manual');
    }
    return $self;
}

# _replay_key_m_window — task 0052: M a nivel ventana solo toggle marca (no escala).
sub _replay_key_m_window {
    my ($self) = @_;
    my $rc = $self->{replay_controller};
    return $self unless $rc && $rc->is_active();
    my $cb = $self->{replay_keyboard_callbacks}{toggle_watermark};
    $cb->() if ref($cb) eq 'CODE';
    return $self;
}

# focus_price_canvas_for_replay — task 0052: foco teclado al chart tras arrancar replay.
sub focus_price_canvas_for_replay {
    my ($self) = @_;
    my $canvas = $self->{price_canvas};
    eval { $canvas->focus() } if $canvas;
    return $self;
}

# _blank_cursor_xbm_paths — (source, mask) de assets/. XBM 16x16 todo-ceros CON hotspot
# (_x_hot/_y_hot): sin hotspot X11/Tk da "bad hot spot in bitmap file". Verificado en WSLg.
sub _blank_cursor_xbm_paths {
    my ($self) = @_;
    return @{ $self->{_blank_cursor_xbm_paths} } if $self->{_blank_cursor_xbm_paths};

    my ($vol, $dirs, $file) = File::Spec->splitpath(__FILE__);
    my $base = File::Spec->catdir($dirs, File::Spec->updir(), 'assets');
    my $src  = File::Spec->rel2abs(File::Spec->catfile($base, 'blank_cursor.xbm'));
    my $mask = File::Spec->rel2abs(File::Spec->catfile($base, 'blank_cursor_mask.xbm'));
    if (-f $src && -f $mask) {
        $self->{_blank_cursor_xbm_paths} = [$src, $mask];
        return ($src, $mask);
    }
    return ();
}

# task 0053/UX: cursor plot invisible en Select Bar (solo tijera dibujada como puntero).
# Fedora35/WSLg (Tk 804.036): none/blank NO existen y '' deja cget=undef (WSLg muestra flecha
# fantasma). Lo que SÍ oculta el puntero: cursor XBM fuente+mascara todo-ceros con hotspot,
# spec arrayref ['@src', mask, fg, bg]. Verificado por captura (arquitecto, 0053).
sub _select_mode_blank_cursor {
    my ($self) = @_;
    return $self->{_select_blank_cursor} if exists $self->{_select_blank_cursor};

    my $canvas = $self->{price_canvas};
    my ($src, $mask) = $self->_blank_cursor_xbm_paths();
    if ($canvas && $src && $mask) {
        my $spec = ['@' . $src, $mask, 'black', 'black'];
        my $ok = eval { $canvas->configure(-cursor => $spec); 1 };
        if ($ok) {
            $self->{_select_blank_cursor} = $spec;
            $self->{_select_blank_cursor_kind} = 'xbm-hotspot';
            return $spec;
        }
    }

    $self->{_select_blank_cursor} = 'left_ptr';
    $self->{_select_blank_cursor_kind} = 'left_ptr-fallback';
    return 'left_ptr';
}

sub _chart_plot_cursor {
    my ($self) = @_;
    return $self->_select_mode_blank_cursor() if $self->{_replay_select_mode};
    return 'crosshair' if $self->{_vwap_select_mode} || $self->{_vp_select_mode};
    return 'crosshair';
}

sub _plot_cursor_targets {
    my ($self) = @_;
    my @out;
    my %seen;
    for my $w (
        $self->{price_canvas},
        $self->{atr_canvas},
        @{ $self->{plot_frames} // [] },
    ) {
        next unless $w;
        my $key = "$w";
        next if $seen{$key}++;
        push @out, $w;
    }
    return @out;
}

sub _apply_select_mode_cursor {
    my ($self, $force_probe) = @_;
    delete $self->{_select_blank_cursor} if $force_probe;

    if ($self->{_replay_select_mode}) {
        my $cursor = $self->_chart_plot_cursor();
        for my $w ($self->_plot_cursor_targets()) {
            $self->_set_cursor($w, $cursor);
        }
    }
    else {
        $self->_set_cursor($self->{price_canvas}, 'crosshair') if $self->{price_canvas};
        $self->_set_cursor($self->{atr_canvas}, 'crosshair') if $self->{atr_canvas};
    }
    return $self;
}

# init_plot_cursors — tras crear canvases sin -cursor crosshair (market.pl).
sub init_plot_cursors {
    my ($self) = @_;
    $self->_apply_select_mode_cursor(1);
    return $self;
}

# bind_replay_window_shortcuts($mw) — task 0052: atajos via bind all (foco en panel OK).
sub bind_replay_window_shortcuts {
    my ($self, $mw) = @_;
    return $self unless $mw;
    return $self if $self->{replay_window_shortcuts_bound};

    $self->{replay_shortcut_window} = $mw;
    $self->{replay_window_bind_sequences} = {};

    my %seq_method = (
        '<Shift-Down>'  => '_replay_shift_down_key',
        '<Shift-Right>' => '_replay_shift_right_key',
        '<Shift-Left>'  => '_replay_shift_left_key',
        '<Escape>'      => '_replay_escape_key',
    );
    for my $seq (keys %seq_method) {
        my $method = $seq_method{$seq};
        $mw->bind(all => $seq, sub {
            $self->$method();
            return;
        });
        $self->{replay_window_bind_sequences}{$seq} = 1;
    }
    $mw->bind(all => '<Key-m>', sub {
        $self->_replay_key_m_window();
        return;
    });
    $self->{replay_window_bind_sequences}{'<Key-m>'} = 1;

    $self->{replay_window_shortcuts_bound} = 1;
    return $self;
}

sub replay_window_shortcut_sequences {
    my ($self) = @_;
    my $h = $self->{replay_window_bind_sequences};
    return $h ? [ sort keys %$h ] : [];
}

# task 0040-B: encuadra la vista con $index como tope visible (offset=0 bajo Replay).
# $opts->{anchor} => 1 deja hueco ~20% a la derecha (ultima vela ~80% del plot).
sub frame_replay_view_at {
    my ($self, $index, $opts) = @_;
    $opts = {} if ref($opts) ne 'HASH';

    my $total = $self->{market_data} ? ($self->{market_data}->size() || 0) : 0;
    return $self unless $total > 0;

    $index = 0 if !defined $index || $index < 0;
    $index = $total - 1 if $index > $total - 1;

    my $vis = $self->{visible_bars} || 60;
    $vis = MIN_VISIBLE_BARS if $vis < MIN_VISIBLE_BARS;
    if ($total < MAX_VISIBLE_BARS) {
        $vis = $total if $vis > $total;
    } else {
        $vis = MAX_VISIBLE_BARS if $vis > MAX_VISIBLE_BARS;
    }
    $self->{visible_bars} = $vis;
    $self->{offset} = 0;
    delete $self->{replay_view_anchor}; # reemplazado por estado semantico
    delete $self->{follow_replay_head}; # legacy: reemplazado por replay_view_end
    $self->{ctrl_zoom_x_shift} = 0;

    # Ancla absoluta: borde derecho LOGICO del viewport. Con anchor => 1 (Select
    # Bar) se deja el hueco ~20% a la derecha (head al ~80%); sin anchor, el head
    # queda pegado al borde. A partir de aqui replay_view_end es la unica verdad.
    my $blank = $opts->{anchor} ? $self->_replay_blank_slots($vis) : 0;
    $self->{replay_view_end} = $index + $blank;
    delete $self->{replay_prev_causal_end}; # reinicia deteccion de borde
    return $self;
}

# mark_replay_play_start — al pulsar Play, garantiza que exista el ancla absoluta
# (replay_view_end). El relleno del hueco antes de desplazar, el auto-scroll por
# deteccion de borde y el clamp min-visible viven en _replay_window sobre
# replay_view_end (unica verdad), de modo que ninguna interaccion previa (pausa,
# zoom, step, paneo) deja el viewport en un estado que desplace todo el grafico
# al reanudar.
sub mark_replay_play_start {
    my ($self) = @_;
    my $rc = $self->{replay_controller};
    return $self unless $rc && $rc->is_active();
    # Si la vista no tiene ancla absoluta (arranque directo por Play sin pasar por
    # Select Bar), fijarla al borde derecho actual.
    if (!defined $self->{replay_view_end}) {
        my ($start, $end) = $self->compute_window();
        $self->{replay_view_end} = $end if defined $end;
    }
    $self->{ctrl_zoom_x_shift} = 0;
    return $self;
}

sub is_replay_select_mode {
    my ($self) = @_;
    return $self->{_replay_select_mode} ? 1 : 0;
}

sub selected_bar {
    my ($self) = @_;
    return $self->{_selected_bar};
}

# ---------------------------------------------------------------------------
# Anchored VWAP — modo "elige vela de anclaje" (como el tool nativo de TV)
# ---------------------------------------------------------------------------

# VWAP/VP placement = legacy (docs/LEGACY.md). Stubs (no dibujo / no estado).
sub is_vwap_select_mode {
    my ($self) = @_;
    return $self->{_vwap_select_mode} ? 1 : 0;
}

sub set_vwap_select_mode {
    my ($self, $on) = @_;
    $on = $on ? 1 : 0;
    if (!$on && $self->{_vwap_select_mode}) {
        $self->_clear_vwap_select_hover();
        $self->_clear_vwap_select_banner();
    }
    $self->{_vwap_select_mode} = $on;
    if ($on) {
        delete $self->{last_mouse_x};
        delete $self->{last_mouse_y};
        $self->_clear_vwap_select_hover();
        $self->_clear_chart_crosshair();
    }
    $self->_apply_select_mode_cursor();
    $self->request_render();
    return $self;
}

sub begin_vwap_placement {
    my ($self) = @_;
    if ($self->{avwap_overlay}) {
        $self->{avwap_overlay}->set_visible(1);
    }
    if ($self->{avwap_indicator} && !$self->{avwap_indicator}->has_anchor()) {
        $self->set_vwap_select_mode(1);
    }
    $self->request_render();
    return $self;
}

# Modo AVWAP: off | manual | auto | both
# Auto ≤2 (pivot consolidado + fantasma); manual adicional opcional.
# set_auto_tc_layers(trendline => 0|1, channel => 0|1)
# Checks UI "Trendline auto" / "Canal auto". Activa el overlay si alguno está ON;
# reset+refeed al cambiar (enable filtra nacimiento).
sub set_auto_tc_layers {
    my ( $self, %opts ) = @_;
    my $ind = $self->{auto_tc_indicator};
    my $ov  = $self->{auto_tc_overlay};
    return $self unless $ind && $ov;

    my $show_tl = exists $opts{trendline}
      ? ( $opts{trendline} ? 1 : 0 )
      : ( $ov->{show_trendline} ? 1 : 0 );
    my $show_ch = exists $opts{channel}
      ? ( $opts{channel} ? 1 : 0 )
      : ( $ov->{show_channel} ? 1 : 0 );

    $ind->set_enable_trendline($show_tl);
    $ind->set_enable_channel($show_ch);
    $ov->set_show_trendline($show_tl);
    $ov->set_show_channel($show_ch);

    my $any = ( $show_tl || $show_ch ) ? 1 : 0;
    $ov->set_visible($any);
    $ind->reset();
    if ( $self->{market_data} && defined $self->{market_data}{active_tf} ) {
        my %tfm = (
            '1m' => 1, '5m' => 5, '15m' => 15, '1h' => 60,
            '2h' => 120, '4h' => 240, 'D' => 1440, 'W' => 10080,
        );
        my $bm = $tfm{ $self->{market_data}{active_tf} } // 1;
        $ind->set_bar_minutes($bm) if $ind->can('set_bar_minutes');
    }
    $self->{_auto_tc_fed_up_to} = -1;
    $self->request_render();
    return $self;
}

sub set_avwap_mode {
    my ( $self, $mode ) = @_;
    $mode = $mode // 'off';
    $mode = 'off' unless $mode =~ /^(?:off|manual|auto|both)$/;
    $self->{avwap_mode} = $mode;

    my $want_manual = ( $mode eq 'manual' || $mode eq 'both' ) ? 1 : 0;
    my $want_auto   = ( $mode eq 'auto'   || $mode eq 'both' ) ? 1 : 0;

    if ( $self->{avwap_overlay} ) {
        $self->{avwap_overlay}->set_visible($want_manual);
    }
    if ( !$want_manual ) {
        $self->set_vwap_select_mode(0);
    }
    elsif ( $self->{avwap_indicator} && !$self->{avwap_indicator}->has_anchor() ) {
        $self->set_vwap_select_mode(1);
    }

    for my $ov ( $self->{avwap_auto1_overlay}, $self->{avwap_auto2_overlay} ) {
        $ov->set_visible($want_auto) if $ov;
    }
    if ( !$want_auto ) {
        for my $ind ( $self->{avwap_auto1_indicator}, $self->{avwap_auto2_indicator} ) {
            $ind->clear_anchor() if $ind && $ind->can('clear_anchor');
        }
    }
    else {
        my $feed = $self->_causal_end();
        $self->_sync_avwap_auto_anchors($feed) if defined $feed && $feed >= 0;
    }

    $self->request_render();
    return $self;
}

sub _sync_avwap_auto_anchors {
    my ( $self, $feed_to ) = @_;
    return $self unless $self->{pph_indicator};
    return $self unless defined $feed_to && $feed_to >= 0;

    # Asegurar PPH alimentado (Auto lee pivots/fantasma).
    $self->_feed_indicator_to( $self->{pph_indicator}, '_pph_fed_up_to', $feed_to );

    my $vals = $self->{pph_indicator}->get_values() || {};

    # Auto-1: último pivot REGULAR consolidado (high o low).
    my $reg = $vals->{last_regular};
    if ( $reg && defined $reg->{index} && $self->{avwap_auto1_indicator} ) {
        my $a1 = $self->{avwap_auto1_indicator};
        my $cur = $a1->anchor_index();
        if ( !defined $cur || $cur != $reg->{index} ) {
            $a1->set_anchor( $reg->{index} );
            $self->{_avwap_auto1_fed_up_to} = -1;
        }
        $self->_feed_indicator_to( $a1, '_avwap_auto1_fed_up_to', $feed_to );
        $self->{avwap_auto1_overlay}->set_visible(1) if $self->{avwap_auto1_overlay};
    }
    elsif ( $self->{avwap_auto1_indicator} ) {
        $self->{avwap_auto1_indicator}->clear_anchor();
        $self->{avwap_auto1_overlay}->set_visible(0) if $self->{avwap_auto1_overlay};
    }

    # Auto-2: punta actual del fantasma provisional (rebuild desde x_last).
    my $prov = $vals->{provisional};
    if ( $prov && defined $prov->{index} && $self->{avwap_auto2_indicator} ) {
        my $a2 = $self->{avwap_auto2_indicator};
        my $cur = $a2->anchor_index();
        if ( !defined $cur || $cur != $prov->{index} ) {
            $a2->set_anchor( $prov->{index} );
            $self->{_avwap_auto2_fed_up_to} = -1;
        }
        $self->_feed_indicator_to( $a2, '_avwap_auto2_fed_up_to', $feed_to );
        $self->{avwap_auto2_overlay}->set_visible(1) if $self->{avwap_auto2_overlay};
    }
    elsif ( $self->{avwap_auto2_indicator} ) {
        $self->{avwap_auto2_indicator}->clear_anchor();
        $self->{avwap_auto2_overlay}->set_visible(0) if $self->{avwap_auto2_overlay};
    }

    return $self;
}

# Toggle rastro "1" del fantasma (Josafa). Solo render; el cálculo se conserva.
sub set_pph_show_rastro {
    my ( $self, $on ) = @_;
    $self->{pph_overlay}->set_show_rastro($on) if $self->{pph_overlay};
    $self->request_render();
    return $self;
}

# Aplica toggles de bandas σ a manual + autos.
sub set_avwap_bands_all {
    my ( $self, %bands ) = @_;
    for my $ind (
        $self->{avwap_indicator},
        $self->{avwap_auto1_indicator},
        $self->{avwap_auto2_indicator},
      )
    {
        next unless $ind;
        for my $n ( 1, 2, 3 ) {
            next unless exists $bands{"band$n"};
            $ind->set_band( $n, on => $bands{"band$n"} ? 1 : 0 );
        }
    }
    for my $ov (
        $self->{avwap_overlay},
        $self->{avwap_auto1_overlay},
        $self->{avwap_auto2_overlay},
      )
    {
        next unless $ov;
        for my $n ( 1, 2, 3 ) {
            next unless exists $bands{"band$n"};
            $ov->set_element_visible( "BAND_$n", $bands{"band$n"} ? 1 : 0 );
        }
        if ( exists $bands{fill} ) {
            $ov->set_element_visible( 'BAND_FILL', $bands{fill} ? 1 : 0 );
        }
    }
    $self->request_render();
    return $self;
}

sub confirm_vwap_anchor {
    my ($self, $idx) = @_;
    return unless defined $idx;
    if ($self->{avwap_indicator}) {
        $self->{avwap_indicator}->set_anchor($idx);
    }
    if ($self->{avwap_overlay}) {
        $self->{avwap_overlay}->set_visible(1);
    }
    my $mode = $self->{avwap_mode} // 'off';
    if ( $mode eq 'off' ) {
        $self->{avwap_mode} = 'manual';
    }
    elsif ( $mode eq 'auto' ) {
        $self->{avwap_mode} = 'both';
    }
    $self->set_vwap_select_mode(0);
    $self->request_render();
    return $self;
}

sub reanchor_vwap {
    my ($self) = @_;
    $self->set_vwap_select_mode(1);
    return $self;
}

sub end_vwap_overlay {
    my ($self) = @_;
    $self->set_vwap_select_mode(0);
    if ($self->{avwap_overlay}) {
        $self->{avwap_overlay}->set_visible(0);
    }
    # Apagar solo el manual; Auto permanece si estaba en both.
    my $mode = $self->{avwap_mode} // 'off';
    if ( $mode eq 'manual' ) {
        $self->{avwap_mode} = 'off';
    }
    elsif ( $mode eq 'both' ) {
        $self->{avwap_mode} = 'auto';
    }
    $self->request_render();
    return $self;
}

# Eliminar por completo el AVWAP: oculta overlay, borra el ancla y sale del
# modo selección. Reactivar la capa vuelve a pedir una vela nueva.
sub remove_vwap_overlay {
    my ($self) = @_;
    $self->set_vwap_select_mode(0);
    $self->{_avwap_drag_active} = undef;
    if ($self->{avwap_indicator} && $self->{avwap_indicator}->can('clear_anchor')) {
        $self->{avwap_indicator}->clear_anchor();
    }
    if ($self->{avwap_overlay}) {
        $self->{avwap_overlay}->clear($self->{price_canvas}) if $self->{price_canvas};
        $self->{avwap_overlay}->set_visible(0);
    }
    # No apaga Auto aquí: solo limpia el manual. Usar set_avwap_mode('off'|'auto').
    my $mode = $self->{avwap_mode} // 'off';
    if ( $mode eq 'manual' ) {
        $self->{avwap_mode} = 'off';
    }
    elsif ( $mode eq 'both' ) {
        $self->{avwap_mode} = 'auto';
    }
    $self->request_render();
    return $self;
}

sub cancel_vwap_select_mode {
    my ($self) = @_;
    $self->set_vwap_select_mode(0);
}

sub _clear_vwap_select_hover {
    my ($self) = @_;
    for my $c ($self->{price_canvas}, $self->{atr_canvas}, $self->{time_canvas}, $self->{time_axis_canvas}) {
        next unless $c;
        $c->delete('vwap_select_hover');
        $c->delete('time_axis_crosshair');
    }
}

sub _clear_vwap_select_banner {
    my ($self) = @_;
    my $canvas = $self->{price_canvas};
    $canvas->delete('vwap_select_banner') if $canvas;
}

sub _draw_vwap_select_banner {
    my ($self) = @_;
    my $canvas = $self->{price_canvas};
    return unless $canvas;
    $canvas->delete('vwap_select_banner');
    my $w = $self->_canvas_width($canvas) || 400;
    eval {
        $canvas->createText(
            int($w / 2), 20,
            -text => 'Haz clic en una vela para anclar el Anchored VWAP (AVWAP)',
            -fill => '#2962FF',
            -font => 'Helvetica 11 bold',
            -tags => 'vwap_select_banner',
        );
        1;
    };
}

sub _draw_vwap_select_hover {
    my ($self, $widget, $x, $y) = @_;
    return unless $self->{_vwap_select_mode};
    $self->_clear_vwap_select_hover();
    return unless defined $x;

    # Usar el formateador oficial del crosshair de la app (formato fecha/hora TradingView)
    local $self->{last_mouse_x} = $x;
    my $ts_text = $self->_crosshair_time_label();

    my $color = '#2962FF';

    for my $canvas ($self->{price_canvas}, $self->{atr_canvas}) {
        next unless $canvas;
        my (undef, $h) = $self->_canvas_size($canvas);
        next unless defined $h && $h > 0;
        eval {
            $canvas->createLine(
                $x, 0, $x, $h,
                -fill  => $color,
                -width => 2,
                -dash  => '-',
                -tags  => 'vwap_select_hover',
            );
            1;
        };
    }

    if ($self->{price_panel} && $self->{time_axis_canvas} && length $ts_text) {
        eval {
            $self->{price_panel}->draw_time_crosshair_label($self->{time_axis_canvas}, $x, $ts_text);
            1;
        };
    }
}
sub is_vp_select_mode {
    my ($self) = @_;
    return $self->{_vp_select_mode} ? 1 : 0;
}

sub set_vp_select_mode {
    my ($self, $on) = @_;
    $on = $on ? 1 : 0;
    if (!$on && $self->{_vp_select_mode}) {
        $self->_clear_vp_select_hover();
        $self->_clear_vp_select_banner();
    }
    $self->{_vp_select_mode} = $on;
    if ($on) {
        delete $self->{last_mouse_x};
        delete $self->{last_mouse_y};
        $self->_clear_vp_select_hover();
        $self->_clear_chart_crosshair();
    }
    $self->_apply_select_mode_cursor();
    $self->request_render();
    return $self;
}

sub begin_vp_placement {
    my ($self) = @_;
    # Compat UI antigua / modo manual
    $self->{vp_mode} = 'manual' if ( $self->{vp_mode} // 'off' ) eq 'off';
    if ($self->{vp_overlay}) {
        $self->{vp_overlay}->set_visible(1);
        $self->{vp_overlay}{show_handle} = 1;
    }
    if ($self->{vp_indicator} && !$self->{vp_indicator}->has_anchor()) {
        $self->set_vp_select_mode(1);
    }
    $self->request_render();
    return $self;
}

sub confirm_vp_anchor {
    my ($self, $idx) = @_;
    return unless defined $idx;
    # En Auto el ancla la fija el ZZ; el clic manual no debe pisarla.
    return $self if ( $self->{vp_mode} // '' ) eq 'auto';
    if ($self->{vp_indicator}) {
        $self->{vp_indicator}->set_anchor($idx);
        $self->{_vp_fed_up_to} = -1;
    }
    $self->set_vp_select_mode(0);
    $self->request_render();
    return $self;
}

sub reanchor_vp {
    my ($self) = @_;
    return $self if ( $self->{vp_mode} // '' ) eq 'auto';
    $self->set_vp_select_mode(1);
    return $self;
}

sub end_vp_overlay {
    my ($self) = @_;
    $self->set_vp_select_mode(0);
    if ($self->{vp_overlay}) {
        $self->{vp_overlay}->set_visible(0);
    }
    # Si se apaga vía checkbox legacy, modo Off
    $self->{vp_mode} = 'off' if ( $self->{vp_mode} // '' ) ne 'auto';
    $self->request_render();
    return $self;
}

# Eliminar por completo el AVP: oculta overlay, borra el ancla y sale del
# modo selección. Reactivar la capa vuelve a pedir una vela nueva.
sub remove_vp_overlay {
    my ($self) = @_;
    $self->set_vp_select_mode(0);
    $self->{_vp_drag_active} = undef;
    delete $self->{_vp_zz_leg_sig};
    if ($self->{vp_indicator} && $self->{vp_indicator}->can('clear_anchor')) {
        $self->{vp_indicator}->clear_anchor();
    }
    if ($self->{vp_overlay}) {
        $self->{vp_overlay}->clear($self->{price_canvas}) if $self->{price_canvas};
        $self->{vp_overlay}->set_visible(0);
    }
    $self->{vp_mode} = 'off';
    $self->request_render();
    return $self;
}

# set_vp_mode(off|manual|auto) — espejo AVWAP.
# Auto: ancla al from_index del último swing ZZ externo consolidado.
sub set_vp_mode {
    my ( $self, $mode ) = @_;
    $mode = $mode // 'off';
    $mode = 'off' unless $mode =~ /^(?:off|manual|auto)$/;
    $self->{vp_mode} = $mode;

    if ( $mode eq 'off' ) {
        $self->set_vp_select_mode(0);
        $self->{_vp_drag_active} = undef;
        delete $self->{_vp_zz_leg_sig};
        if ( $self->{vp_indicator} && $self->{vp_indicator}->can('clear_anchor') ) {
            $self->{vp_indicator}->clear_anchor();
        }
        if ( $self->{vp_overlay} ) {
            $self->{vp_overlay}->clear( $self->{price_canvas} ) if $self->{price_canvas};
            $self->{vp_overlay}->set_visible(0);
            $self->{vp_overlay}{show_handle} = 1;
        }
        $self->{_vp_fed_up_to} = -1;
    }
    elsif ( $mode eq 'manual' ) {
        if ( $self->{vp_overlay} ) {
            $self->{vp_overlay}->set_visible(1);
            $self->{vp_overlay}{show_handle} = 1;
        }
        if ( $self->{vp_indicator} && !$self->{vp_indicator}->has_anchor() ) {
            $self->set_vp_select_mode(1);
        }
        else {
            $self->set_vp_select_mode(0);
        }
    }
    else {    # auto
        $self->set_vp_select_mode(0);
        $self->{_vp_drag_active} = undef;
        if ( $self->{vp_overlay} ) {
            $self->{vp_overlay}->set_visible(1);
            $self->{vp_overlay}{show_handle} = 0;    # no arrastrable en Auto
        }
        my $feed = $self->_causal_end();
        $self->_sync_vp_auto_anchor($feed) if defined $feed && $feed >= 0;
    }

    $self->request_render();
    return $self;
}

# Ancla AVP al inicio (from_index) del último swing ZZ ext consolidado.
sub _sync_vp_auto_anchor {
    my ( $self, $feed_to ) = @_;
    return $self unless ( $self->{vp_mode} // '' ) eq 'auto';
    return $self unless $self->{vp_indicator} && $self->{zigzag_indicator};
    return $self unless defined $feed_to && $feed_to >= 0;

    my $zz = $self->{zigzag_indicator};
    $zz->set_compute_external(1) if $zz->can('set_compute_external');
    $self->_feed_indicator_to( $zz, '_zigzag_fed_up_to', $feed_to );

    my $vals = $zz->get_values() || {};
    my $leg  = Market::Drawing::FibRetracement->last_consolidated_zz_segment(
        $vals->{external_segments} || []
    );

    if ( !$leg || !defined $leg->{from_index} ) {
        # Sin pierna consolidada: no inventar ancla
        if ( $self->{vp_indicator}->can('clear_anchor') ) {
            $self->{vp_indicator}->clear_anchor();
        }
        delete $self->{_vp_zz_leg_sig};
        $self->{_vp_fed_up_to} = -1;
        return $self;
    }

    my $sig = Market::Drawing::FibRetracement->zz_leg_signature($leg);
    my $idx = 0 + $leg->{from_index};
    my $cur = $self->{vp_indicator}->can('anchor_index')
      ? $self->{vp_indicator}->anchor_index()
      : undef;

    if ( !defined $self->{_vp_zz_leg_sig}
        || $self->{_vp_zz_leg_sig} ne $sig
        || !defined $cur
        || $cur != $idx )
    {
        $self->{vp_indicator}->set_anchor($idx);
        $self->{_vp_zz_leg_sig} = $sig;
        $self->{_vp_fed_up_to}  = -1;
    }

    $self->_feed_indicator_to( $self->{vp_indicator}, '_vp_fed_up_to', $feed_to );
    return $self;
}

sub cancel_vp_select_mode {
    my ($self) = @_;
    return $self->set_vp_select_mode(0);
}

sub _clear_vp_select_hover {
    my ($self) = @_;
    for my $c ($self->{price_canvas}, $self->{atr_canvas}, $self->{time_canvas}, $self->{time_axis_canvas}) {
        next unless $c;
        $c->delete('vp_select_hover');
        $c->delete('time_axis_crosshair');
    }
}

sub _clear_vp_select_banner {
    my ($self) = @_;
    my $canvas = $self->{price_canvas};
    $canvas->delete('vp_select_banner') if $canvas;
}

sub _draw_vp_select_banner {
    my ($self) = @_;
    my $canvas = $self->{price_canvas};
    return unless $canvas;
    $canvas->delete('vp_select_banner');
    my $w = $self->_canvas_width($canvas) || 400;
    eval {
        $canvas->createText(
            int($w / 2), 20,
            -text => 'Haz clic en una vela para anclar el Perfil de Volumen (AVP)',
            -fill => '#29B6F6',
            -font => 'Helvetica 11 bold',
            -tags => 'vp_select_banner',
        );
        1;
    };
}

sub _draw_vp_select_hover {
    my ($self, $widget, $x, $y) = @_;
    return unless $self->{_vp_select_mode};
    $self->_clear_vp_select_hover();
    return unless defined $x;

    local $self->{last_mouse_x} = $x;
    my $ts_text = $self->_crosshair_time_label();

    my $color = '#29B6F6';

    # 1) Línea vertical entrecortada en price y atr canvas
    for my $canvas ($self->{price_canvas}, $self->{atr_canvas}) {
        next unless $canvas;
        my (undef, $h) = $self->_canvas_size($canvas);
        next unless defined $h && $h > 0;
        eval {
            $canvas->createLine(
                $x, 0, $x, $h,
                -fill  => $color,
                -width => 2,
                -dash  => '-',
                -tags  => 'vp_select_hover',
            );
            1;
        };
    }

    # 2) Etiqueta negra oficial de fecha/hora en el eje temporal (misma del crosshair libre)
    if ($self->{price_panel} && $self->{time_axis_canvas} && length $ts_text) {
        eval {
            $self->{price_panel}->draw_time_crosshair_label($self->{time_axis_canvas}, $x, $ts_text);
            1;
        };
    }
}

sub set_selected_bar {
    my ($self, $idx) = @_;
    return $self unless defined $idx;
    my $md = $self->{market_data};
    my $last = (defined $md && $md->can('size')) ? ($md->size() - 1) : 0;
    $idx = 0 if $idx < 0;
    $idx = $last if $idx > $last;
    $self->_clear_replay_select_hover();
    $self->{_selected_bar} = $idx;
    # task 0040-C: tras elegir vela, volver a paneo normal (modo OFF, conservar selección).
    $self->clear_replay_select_mode();
    return $self;
}

sub adjust_selected_bar {
    my ($self, $delta) = @_;
    return $self unless $self->{_replay_select_mode};
    my $idx;
    if (!defined $self->{_selected_bar}) {
        $idx = $self->_global_index_from_x($self->{last_mouse_x});
        $idx = 0 unless defined $idx;
    }
    else {
        $idx = $self->{_selected_bar} + $delta;
    }
    return $self->set_selected_bar($idx);
}

# index_for_timestamp($ts_str) — índice de vela con timestamp más cercano (task 0044).
sub index_for_timestamp {
    my ($self, $ts_str) = @_;
    return undef unless defined $ts_str && length $ts_str;

    my $md = $self->{market_data};
    return undef unless $md && $md->can('size') && $md->can('get_timestamp');

    my $size = $md->size() || 0;
    return undef unless $size > 0;

    my $target = eval { Time::Moment->from_string($ts_str) };
    if (!$target && $ts_str =~ /^(\d{4}-\d{2}-\d{2})$/) {
        $target = eval { Time::Moment->from_string("$1T00:00:00-05:00") };
        $target //= eval { Time::Moment->from_string("$1T00:00:00") };
    }
    return undef unless $target;

    my $target_epoch = $target->epoch;
    my $best_idx = 0;
    my $best_dist;
    for my $i (0 .. $size - 1) {
        my $ts = $md->get_timestamp($i);
        next unless defined $ts;
        my $tm = eval { Time::Moment->from_string($ts) };
        next unless $tm;
        my $dist = abs($tm->epoch - $target_epoch);
        if (!defined $best_dist || $dist < $best_dist) {
            $best_dist = $dist;
            $best_idx  = $i;
        }
    }
    return $best_idx;
}

# replay_random_start_index — índice aleatorio válido para Go-to Random (task 0044).
sub replay_random_start_index {
    my ($self) = @_;
    my $md = $self->{market_data};
    my $last = (defined $md && $md->can('size')) ? ($md->size() - 1) : 0;
    return 0 if $last < MIN_VISIBLE_BARS;
    my $lo = MIN_VISIBLE_BARS;
    my $hi = $last - 1;
    return $lo if $hi <= $lo;
    return $lo + int(rand($hi - $lo + 1));
}

# replay_start_index — índice para ReplayController->start: selected-1 o auto.
sub replay_start_index {
    my ($self) = @_;
    if (defined $self->{_selected_bar}) {
        my $idx = $self->{_selected_bar} - 1;
        $idx = 0 if $idx < 0;
        my $md = $self->{market_data};
        my $last = (defined $md && $md->can('size')) ? ($md->size() - 1) : 0;
        $idx = $last if $idx > $last;
        return $idx;
    }
    my $md = $self->{market_data};
    my $last = (defined $md && $md->can('size')) ? ($md->size() - 1) : 0;
    my $vis = $self->{visible_bars} || 60;
    my $start_idx = $last - $vis;
    return $start_idx < 0 ? 0 : $start_idx;
}

# _global_index_from_x($x) — índice GLOBAL bajo la coordenada X del canvas.
sub _global_index_from_x {
    my ($self, $x) = @_;
    return undef unless defined $x;

    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    return undef if $bars < 1;

    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});
    $scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    my $local = $scale->x_to_index($x);
    my $global = $start + $local;
    my $causal_end = $self->_causal_end();
    return undef if $global < 0 || $global > $causal_end;
    return $global;
}

# _replay_watermark_visible — task 0046: marca "Replay" solo si activo Y flag ON.
sub _replay_watermark_visible {
    my ($self) = @_;
    my $replay = $self->{replay_controller};
    return 0 unless $replay && $replay->is_active();
    my $ref = $self->{replay_watermark_on_ref};
    return 1 unless $ref;
    return ${ $ref } ? 1 : 0;
}

# _purge_replay_visuals — borra TODOS los artefactos visuales de una sesión Replay
# (marca de agua, velo/línea/tijeras de Select Bar, marcador y etiqueta Re:). Es
# idempotente y no depende del estado: se llama al salir de Replay y como barrera
# defensiva en cada render cuando NO hay sesión activa, para que nunca queden
# elementos "colgados" (marca Replay gris, velo azul, cursor tijeras) al mezclarse
# con cambios de indicador/pestaña. No toca velas ni overlays.
sub _purge_replay_visuals {
    my ($self) = @_;
    my @tags = qw(
        replay_watermark
        replay_select_hover replay_select_veil replay_select_scissors
        replay_select_marker
    );
    for my $canvas ($self->{price_canvas}, $self->{atr_canvas}) {
        next unless $canvas;
        for my $tag (@tags) {
            eval { $canvas->delete($tag) };
        }
    }
    if ($self->{time_axis_canvas}) {
        eval { $self->{time_axis_canvas}->delete('replay_select_re_label') };
    }
    return $self;
}

# _draw_replay_watermark — texto gris centrado, detrás de velas (tag replay_watermark).
sub _draw_replay_watermark {
    my ($self, $canvas) = @_;
    return unless $canvas;
    eval { $canvas->delete('replay_watermark') };
    return unless $self->_replay_watermark_visible();

    my ($w, $h) = $self->_canvas_size($canvas);
    return unless defined $w && $w > 0 && defined $h && $h > 0;
    eval {
        $canvas->createText(
            $w / 2, $h / 2,
            -text   => 'Replay',
            -fill   => '#d0d0d0',
            -font   => 'Helvetica 48 bold',
            -tags   => 'replay_watermark',
        );
        $canvas->lower('replay_watermark', 'candle');
    };
    return;
}

# TradingView no muestra línea fija en la vela ya elegida; solo el hover azul en select mode.
sub _draw_replay_select_marker {
    my ($self) = @_;
    my $tag = 'replay_select_marker';
    for my $canvas ($self->{price_canvas}, $self->{atr_canvas}) {
        eval { $canvas->delete($tag) } if $canvas;
    }
    return;
}

# task 0042: hover visual estilo TradingView (línea azul, velo, Re:, tijeras).
sub _clear_replay_select_hover {
    my ($self) = @_;
    my @tags = qw(replay_select_hover replay_select_veil replay_select_scissors);
    for my $canvas ($self->{price_canvas}, $self->{atr_canvas}) {
        next unless $canvas;
        for my $tag (@tags) {
            eval { $canvas->delete($tag) };
        }
    }
    if ($self->{time_axis_canvas}) {
        eval { $self->{time_axis_canvas}->delete('replay_select_re_label') };
    }
    return $self;
}

# _replay_select_hover_layout($raw_x) — geometría de la línea/velo para tests y dibujo.
sub _replay_select_hover_layout {
    my ($self, $raw_x) = @_;
    return undef unless $self->{_replay_select_mode};
    return undef unless defined $raw_x;

    my $line_x = $self->_snap_crosshair_x($raw_x);
    return undef unless defined $line_x;

    my $global = $self->_global_index_from_x($line_x);
    return undef unless defined $global;

    my $canvas = $self->{price_canvas};
    my $w = $self->_canvas_width($canvas);

    my $saved_x = $self->{last_mouse_x};
    $self->{last_mouse_x} = $line_x;
    my $time_text = $self->_crosshair_time_label();
    $self->{last_mouse_x} = $saved_x;

    my $re_text = defined $time_text ? "Re: $time_text" : undef;

    return {
        line_x       => $line_x,
        global_index => $global,
        veil_x0      => $line_x,
        veil_x1      => $w,
        re_text      => $re_text,
    };
}

sub _draw_replay_select_re_label {
    my ($self, $line_x, $re_text) = @_;
    my $canvas = $self->{time_axis_canvas};
    return unless $canvas && defined $line_x && defined $re_text && length $re_text;

    eval { $canvas->delete('replay_select_re_label') };

    my ($w, $h) = $self->_canvas_size($canvas);
    my $color = '#2962ff';
    my $char_w = 7;
    my $pad_x  = 6;
    my $half_w = (length($re_text) * $char_w) / 2 + $pad_x;

    my $cx = $line_x;
    $cx = $half_w      if $cx - $half_w < 0;
    $cx = $w - $half_w if $cx + $half_w > $w;

    eval {
        $canvas->createRectangle(
            $cx - $half_w, 0, $cx + $half_w, $h,
            -fill => $color, -outline => $color, -tags => 'replay_select_re_label',
        );
        $canvas->createText(
            $cx, $h / 2,
            -text => $re_text, -anchor => 'center',
            -font => 'Helvetica 9 bold', -fill => '#ffffff',
            -tags => 'replay_select_re_label',
        );
    };
}

sub _draw_replay_select_hover {
    my ($self, $widget, $line_x, $y) = @_;
    return unless $self->{_replay_select_mode};

    $self->_clear_replay_select_hover();
    return unless defined $line_x;

    my $layout = $self->_replay_select_hover_layout($line_x);
    return unless $layout;

    my $x = $layout->{line_x};
    my $veil_x0 = $layout->{veil_x0};
    my $veil_x1 = $layout->{veil_x1};
    my $color = '#2962ff';

    for my $canvas ($self->{price_canvas}, $self->{atr_canvas}) {
        next unless $canvas;
        my (undef, $h) = $self->_canvas_size($canvas);
        next unless defined $h && $h > 0;
        eval {
            if ($veil_x1 > $veil_x0) {
                $canvas->createRectangle(
                    $veil_x0, 0, $veil_x1, $h,
                    -fill => 'white', -stipple => 'gray25', -outline => '',
                    -tags => 'replay_select_veil',
                );
            }
            $canvas->createLine(
                $x, 0, $x, $h,
                -fill => $color, -width => 2, -tags => 'replay_select_hover',
            );
        };
    }

    if ($self->{price_canvas}) {
        my (undef, $h) = $self->_canvas_size($self->{price_canvas});
        my $scissor_y = defined $y ? $y : ($h / 2);
        eval {
            $self->{price_canvas}->createText(
                $x, $scissor_y,
                -text => "\x{2702}", -anchor => 'center',
                -font => REPLAY_SELECT_SCISSOR_FONT,
                -fill => REPLAY_SELECT_SCISSOR_FILL,
                -tags => 'replay_select_scissors',
            );
        };
    }

    $self->_draw_replay_select_re_label($x, $layout->{re_text});
    return $self;
}

sub _bind_all_canvas {
    my ($self) = @_;

    # Aseguramos capturar las referencias exactas de los objetos de Tk
    my $p_canvas = $self->{price_canvas};
    my $a_canvas = $self->{atr_canvas};
    my $axis_canvas = $self->{price_axis_canvas};
    my $atr_axis_canvas = $self->{atr_axis_canvas};
    my $time_canvas = $self->{time_axis_canvas};

    # 1. Binding nativo para el panel de Precios usando la sintaxis clásica 'bind'
    if (defined $p_canvas) {
        $p_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_mouse_move($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $p_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_start_horizontal_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $p_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_horizontal_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $p_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_drag(); });
        $p_canvas->Tk::bind('<MouseWheel>', [sub {
            my ($widget, $delta, $x, $y, $state) = @_;
            my $step = $delta > 0 ? -ZOOM_STEP : ZOOM_STEP;
            $self->_wheel_zoom($widget, $step, $x, $y, $state);
            return 'break';
        }, Tk::Ev('D'), Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $p_canvas->Tk::bind('<Button-4>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, -ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $p_canvas->Tk::bind('<Button-5>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $p_canvas->Tk::bind('<Double-Button-1>', sub { $self->reset_view(); });
        $p_canvas->Tk::bind('<Configure>', sub { $self->_on_resize($p_canvas); });
        $p_canvas->Tk::bind('<Key-a>', sub { $self->set_scale_mode('auto'); });
        $p_canvas->Tk::bind('<Key-m>', sub {
            my $rc = $self->{replay_controller};
            return if $rc && $rc->is_active();
            $self->set_scale_mode('manual');
        });
        $p_canvas->Tk::bind('<Key-plus>', sub { $self->set_scale_mode('manual'); $self->_vertical_zoom(0.9); });
        $p_canvas->Tk::bind('<Key-minus>', sub { $self->set_scale_mode('manual'); $self->_vertical_zoom(1.1); });
        $p_canvas->Tk::bind('<Up>', sub { $self->set_scale_mode('manual'); $self->_vertical_drag(-10); });
        $p_canvas->Tk::bind('<Down>', sub { $self->set_scale_mode('manual'); $self->_vertical_drag(10); });
        $p_canvas->Tk::bind('<Enter>', sub {
            $self->_set_cursor($p_canvas, $self->_chart_plot_cursor());
            $p_canvas->focus;
        });
        $p_canvas->Tk::bind('<Leave>', sub {
            $self->_set_cursor($p_canvas, $self->_chart_plot_cursor());
            $self->{last_mouse_x} = undef;
            $self->{last_mouse_y} = undef;
            $self->{active_canvas} = undef;
            $self->_draw_crosshair_all();
            $self->_clear_replay_select_hover();
            $self->_clear_vwap_select_hover();
            $self->_clear_vp_select_hover() if $self->can('_clear_vp_select_hover');
            $self->_clear_pointer_symbol($p_canvas);
        });
    }

    # 2. Binding nativo idéntico para el panel del ATR
    if (defined $a_canvas) {
        $a_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_mouse_move($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $a_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_start_horizontal_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $a_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_horizontal_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $a_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_drag(); });
        $a_canvas->Tk::bind('<MouseWheel>', [sub {
            my ($widget, $delta, $x, $y, $state) = @_;
            my $step = $delta > 0 ? -ZOOM_STEP : ZOOM_STEP;
            $self->_wheel_zoom($widget, $step, $x, $y, $state);
            return 'break';
        }, Tk::Ev('D'), Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $a_canvas->Tk::bind('<Button-4>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, -ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $a_canvas->Tk::bind('<Button-5>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $a_canvas->Tk::bind('<Configure>', sub { $self->_on_resize($a_canvas); });
        $a_canvas->Tk::bind('<Key-a>', sub { $self->set_atr_scale_mode('auto'); });
        $a_canvas->Tk::bind('<Key-m>', sub {
            my $rc = $self->{replay_controller};
            return if $rc && $rc->is_active();
            $self->set_atr_scale_mode('manual');
        });
        $a_canvas->Tk::bind('<Key-plus>', sub { $self->set_atr_scale_mode('manual'); $self->_atr_vertical_zoom(0.9); });
        $a_canvas->Tk::bind('<Key-minus>', sub { $self->set_atr_scale_mode('manual'); $self->_atr_vertical_zoom(1.1); });
        $a_canvas->Tk::bind('<Up>', sub { $self->set_atr_scale_mode('manual'); $self->_atr_vertical_drag(-10); });
        $a_canvas->Tk::bind('<Down>', sub { $self->set_atr_scale_mode('manual'); $self->_atr_vertical_drag(10); });
        $a_canvas->Tk::bind('<Enter>', sub {
            $self->_set_cursor($a_canvas, $self->_chart_plot_cursor());
            $a_canvas->focus;
        });
        $a_canvas->Tk::bind('<Leave>', sub {
            $self->_set_cursor($a_canvas, $self->_chart_plot_cursor());
            $self->{last_mouse_x} = undef;
            $self->{last_mouse_y} = undef;
            $self->{active_canvas} = undef;
            $self->_draw_crosshair_all();
            $self->_clear_replay_select_hover();
            $self->_clear_pointer_symbol($a_canvas);
        });
    }

    if (defined $axis_canvas) {
        $axis_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_draw_pointer_symbol($widget, $x, $y, 'v');
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $axis_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $y) = @_;
            $self->_start_price_axis_drag($widget, $y);
        }, Tk::Ev('y')]);
        $axis_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $y) = @_;
            $self->_on_price_axis_drag($widget, $y);
        }, Tk::Ev('y')]);
        $axis_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_price_axis_drag(); });
        $axis_canvas->Tk::bind('<Double-Button-1>', sub { $self->set_scale_mode('auto'); });
        $axis_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($axis_canvas, 'sb_v_double_arrow') });
        $axis_canvas->Tk::bind('<Leave>', sub { $self->_set_cursor($axis_canvas, 'sb_v_double_arrow'); $self->_clear_pointer_symbol($axis_canvas); });
    }

    if (defined $atr_axis_canvas) {
        $atr_axis_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_draw_pointer_symbol($widget, $x, $y, 'v');
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $atr_axis_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $y) = @_;
            $self->_start_atr_axis_drag($widget, $y);
        }, Tk::Ev('y')]);
        $atr_axis_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $y) = @_;
            $self->_on_atr_axis_drag($widget, $y);
        }, Tk::Ev('y')]);
        $atr_axis_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_atr_axis_drag(); });
        $atr_axis_canvas->Tk::bind('<Double-Button-1>', sub { $self->_reset_atr_scale(); });
        $atr_axis_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($atr_axis_canvas, 'sb_v_double_arrow') });
        $atr_axis_canvas->Tk::bind('<Leave>', sub { $self->_set_cursor($atr_axis_canvas, 'sb_v_double_arrow'); $self->_clear_pointer_symbol($atr_axis_canvas); });
    }

    if (defined $time_canvas) {
        $time_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_time_axis_motion($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $time_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_start_time_axis_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $time_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_time_axis_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $time_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_time_axis_drag(); });
        $time_canvas->Tk::bind('<MouseWheel>', [sub {
            my ($widget, $delta, $x, $y, $state) = @_;
            my $step = $delta > 0 ? -ZOOM_STEP : ZOOM_STEP;
            $self->_wheel_zoom($widget, $step, $x, $y, $state);
            return 'break';
        }, Tk::Ev('D'), Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $time_canvas->Tk::bind('<Button-4>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, -ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $time_canvas->Tk::bind('<Button-5>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $time_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($time_canvas, 'sb_h_double_arrow') });
        $time_canvas->Tk::bind('<Leave>', sub {
            $self->_set_cursor($time_canvas, 'sb_h_double_arrow');
            $self->{last_mouse_x} = undef;
            $self->{last_mouse_y} = undef;
            $self->{active_canvas} = undef;
            $self->_draw_crosshair_all();
            $self->_clear_replay_select_hover();
            $self->_clear_pointer_symbol($time_canvas);
        });
    }
}

sub bind_events {
    my ($self) = @_;
    $self->_bind_all_canvas();
}

# _anchor_index_and_x($anchor_x) — calcula el punto de anclaje del zoom (Req. 9.1, 9.2,
# 9.4) ANTES de cambiar el nivel de zoom.
#
# Dado un X de pantalla (o undef), devuelve la pareja:
#       ($anchor_index, $anchor_screen_x)
# donde $anchor_index es el índice GLOBAL del dato que debe quedar fijo y
# $anchor_screen_x es la coordenada X de pantalla en la que debe permanecer.
#
# Toda conversión X<->índice vive EXCLUSIVAMENTE en Scales (regla de oro de
# coordenadas): se instancia un Market::Panels::Scales con los mismos parámetros que
# usa render() —bars = nº de velas visibles (end - start + 1 de compute_window),
# right_margin => RIGHT_MARGIN y el ancho real del canvas de precios—.
#
#   * $anchor_x DEFINIDO (cursor sobre una barra del área de ploteo):
#       local  = Scales->x_to_index($anchor_x)   # índice LOCAL acotado a [0, bars-1]
#       global = start + local                    # índice GLOBAL del dato
#       => devuelve (global, $anchor_x)
#
#   * $anchor_x UNDEF (sin cursor): el ancla es la última vela visible, cuyo índice
#     GLOBAL es 'end' (de compute_window). Su X de pantalla es el centro de su barra:
#       local_de_end = end - start
#       screen_x     = Scales->index_to_center_x(local_de_end)
#       => devuelve (end, screen_x)
sub _anchor_index_and_x {
    my ($self, $anchor_x) = @_;

    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    $bars = 1 if $bars < 1;

    # Escala SOLO para convertir X <-> índice; mismos parámetros que render().
    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});
    $scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;

    if (defined $anchor_x) {
        # Cursor sobre una barra: índice LOCAL -> GLOBAL; la X se conserva tal cual.
        my $local  = $scale->x_to_index($anchor_x);
        my $global = $start + $local;
        my $last_real = $self->_causal_end();
        $global = 0 if $global < 0;
        $global = $last_real if $global > $last_real;
        return ($global, $anchor_x);
    }

    # Sin cursor: ancla = última vela causal visible, no el final futuro del CSV.
    my $last_real = $self->_causal_end();
    my $anchor_index = $end > $last_real ? $last_real : $end;
    $anchor_index = 0 if $anchor_index < 0;
    my $local_of_anchor = $anchor_index - $start;

    my $screen_x = $scale->index_to_center_x($local_of_anchor);
    return ($anchor_index, $screen_x);
}

# _zoom_anchor_x — decide el X de anclaje para los eventos de rueda/Button-4/5.
#
# Devuelve $self->{last_mouse_x} (ya actualizado por <Motion>) SOLO si el cursor está
# sobre una barra del área de ploteo, es decir, dentro de [0, plot_width]. En cualquier
# otro caso (sin cursor, o el cursor cae sobre el margen derecho de precios) devuelve
# undef, de modo que el ancla pase a ser la última vela visible (Req. 9.1).
#
# plot_width vive en Scales (regla de oro): se obtiene de una instancia con el ancho
# real del canvas y RIGHT_MARGIN, sin calcular el margen por nuestra cuenta.
sub _zoom_anchor_x {
    my ($self) = @_;

    my $x = $self->{last_mouse_x};
    return undef unless defined $x;                  # sin cursor => última vela

    my $canvas = $self->{price_canvas};
    return undef unless $canvas;
    my $w = $self->_canvas_width($canvas);
    return undef unless defined $w && $w > 0;

    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    $bars = 1 if $bars < 1;

    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $w;
    my $plot_w = $scale->plot_width();

    return ($x >= 0 && $x <= $plot_w) ? $x : undef;
}

sub _clear_ctrl_zoom_state {
    my ($self) = @_;

    # x_shift es exclusivamente residuo subvela; nunca representa el hueco Replay.
    $self->{ctrl_zoom_x_shift} = 0;
    $self->{ctrl_zoom_y_lock_min} = undef;
    $self->{ctrl_zoom_y_lock_max} = undef;
}

sub _wheel_zoom_delta {
    my ($self, $step) = @_;

    my $total = $self->{market_data}->size() || 0;
    return 0 unless $total > 0;

    my $old_visible = $self->{visible_bars} || MIN_VISIBLE_BARS;
    my $max_visible = $total < MAX_VISIBLE_BARS ? $total : MAX_VISIBLE_BARS;
    $max_visible = MIN_VISIBLE_BARS if $max_visible < MIN_VISIBLE_BARS;

    my $zoom_scale = -$step / ZOOM_STEP;
    my $factor = 1 + ($zoom_scale / 10);
    $factor = 0.1 if $factor < 0.1;

    my $new_visible = $self->round($old_visible / $factor);
    $new_visible = MIN_VISIBLE_BARS if $new_visible < MIN_VISIBLE_BARS;
    $new_visible = $max_visible if $new_visible > $max_visible;

    if ($new_visible == $old_visible) {
        if ($zoom_scale < 0 && $old_visible < $max_visible) {
            $new_visible = $old_visible + 1;
        } elsif ($zoom_scale > 0 && $old_visible > MIN_VISIBLE_BARS) {
            $new_visible = $old_visible - 1;
        }
    }

    return $new_visible - $old_visible;
}

sub _wheel_zoom {
    my ($self, $widget, $step, $x, $y, $state) = @_;

    if (defined $x) {
        $self->{last_mouse_x} = $self->_snap_crosshair_x($x);
        $self->{last_mouse_y} = $self->round($y) if defined $y;
        $self->{active_canvas} = $widget if defined $widget;
    }

    my $delta = $self->_wheel_zoom_delta($step);
    return if $delta == 0;

    my $ctrl_pressed = defined $state && ($state & CTRL_MASK);
    if ($ctrl_pressed) {
        my $anchor_x = $self->_zoom_anchor_x();
        if (defined $anchor_x) {
            $self->_ctrl_horizontal_zoom($delta, $anchor_x);
            return;
        }
    }

    $self->_clear_ctrl_zoom_state();
    $self->_horizontal_zoom($delta, undef);
}

sub _ctrl_horizontal_zoom {
    my ($self, $delta, $anchor_x) = @_;

    my $total = $self->{market_data}->size();
    return if !$total;

    my ($start, $end) = $self->compute_window();
    my $old_visible = $self->{visible_bars} || ($end - $start + 1) || 1;
    my $max_visible = $total < MAX_VISIBLE_BARS ? $total : MAX_VISIBLE_BARS;
    $max_visible = MIN_VISIBLE_BARS if $max_visible < MIN_VISIBLE_BARS;
    my $new_visible = $old_visible + $delta;
    $new_visible = MIN_VISIBLE_BARS if $new_visible < MIN_VISIBLE_BARS;
    $new_visible = $max_visible     if $new_visible > $max_visible;
    return if $new_visible == $old_visible;

    my $canvas_w = $self->_canvas_width($self->{price_canvas});
    return if !$canvas_w || $canvas_w <= 0;

    my $rc = $self->{replay_controller};

    my $old_scale = Market::Panels::Scales->new(bars => $old_visible, right_margin => RIGHT_MARGIN);
    $old_scale->{width} = $canvas_w;
    $old_scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    my $anchor_global = $start + $old_scale->x_to_index_float($anchor_x) - 0.5;
    # El cursor puede caer en slots vacios de Replay. El ancla de datos nunca
    # puede superar el tope causal ni ser anterior al primer índice real.
    my $anchor_limit = $self->_causal_end();
    $anchor_global = 0 if $anchor_global < 0;
    $anchor_global = $anchor_limit if $anchor_global > $anchor_limit;

    my $new_scale = Market::Panels::Scales->new(bars => $new_visible, right_margin => RIGHT_MARGIN);
    $new_scale->{width} = $canvas_w;
    my $new_bar_w = $new_scale->plot_width() / $new_visible;
    return if $new_bar_w <= 0;

    my $target_start = $anchor_global - (($anchor_x - ($new_bar_w / 2)) / $new_bar_w);
    my $new_start = $self->round($target_start);
    my $new_end = $new_start + $new_visible - 1;

    $self->{visible_bars} = $new_visible;
    if ($rc && $rc->is_active() && defined $self->{replay_view_end}) {
        # En Replay el viewport se gobierna por replay_view_end (borde derecho
        # LOGICO). El zoom preserva el ancla ajustando ese borde; _replay_window
        # aplica los clamps (min-visible, no-blanco-izquierda). No se toca offset.
        $self->{replay_view_end} = $new_end;
    }
    else {
        my $base_end = ($rc && $rc->is_active()) ? $self->_causal_end() : ($total - 1);
        my $base_total = $base_end + 1;
        my $new_offset = $base_end - $new_end;
        $self->{offset} = $self->_clamp_offset($new_offset, $base_total);
    }
    ($new_start, $new_end) = $self->compute_window();

    my $new_shift = $anchor_x - (($anchor_global - $new_start + 0.5) * $new_bar_w);
    # En los límites del historial no siempre es posible conservar exactamente
    # el ancla. Nunca convertir esa diferencia en un desplazamiento de muchas
    # barras: x_shift sigue siendo exclusivamente residuo subvela.
    while ($new_shift >= $new_bar_w) { $new_shift -= $new_bar_w; }
    while ($new_shift <= -$new_bar_w) { $new_shift += $new_bar_w; }
    $self->{ctrl_zoom_x_shift} = $new_shift;
    $self->{last_mouse_x} = $self->round($anchor_x);

    if ($self->{is_auto_scale}) {
        $self->{ctrl_zoom_y_lock_min} = undef;
        $self->{ctrl_zoom_y_lock_max} = undef;
    } elsif (!defined $self->{ctrl_zoom_y_lock_min} || !defined $self->{ctrl_zoom_y_lock_max}) {
        if (defined $self->{manual_min_y} && defined $self->{manual_max_y}) {
            $self->{ctrl_zoom_y_lock_min} = $self->{manual_min_y};
            $self->{ctrl_zoom_y_lock_max} = $self->{manual_max_y};
        }
    }

    $self->request_render();
}

# _horizontal_zoom($delta, $anchor_x) — zoom horizontal con ANCLAJE (Req. 8.1, 8.2,
# 9.1, 9.2, 9.3, 9.4).
#
# $delta      cambio en visible_bars (negativo = zoom-in, positivo = zoom-out).
# $anchor_x   X de pantalla del ancla, o undef. Si se llama con un solo argumento
#             ($anchor_x undef), el ancla es la última vela visible (compatibilidad
#             con los llamadores antiguos de un argumento).
#
# Algoritmo (design.md, "Algoritmo de zoom con anclaje"):
#   1. (anchor_index, anchor_screen_x) = _anchor_index_and_x($anchor_x)  [ANTES del zoom]
#   2. new_visible = clamp(visible_bars + delta, MIN_VISIBLE_BARS, total)
#   3. visible_bars = new_visible
#   4. bar_w' = plot_width / new_visible  (derivado dentro de Scales)
#   5. reposicionar el ancla en anchor_screen_x:
#        local'   = anchor_screen_x / bar_w' - 0.5   (vía Scales->x_to_index_float)
#        end_idx' = anchor_index + (new_visible - 1 - local')
#        offset   = (total - 1) - end_idx'
#   6. offset entero y acotado para conservar como mínimo dos velas reales en cada extremo.

#   7. request_render()
#
# Toda conversión X<->índice se hace SOLO con Scales (Req. 9.4). El ancla se conserva
# dentro de la tolerancia de una barra (Req. 9.3) porque offset es entero (el redondeo
# introduce a lo sumo ±0.5 barra de desviación).
sub _horizontal_zoom {
    my ($self, $delta, $anchor_x) = @_;

    my $total = $self->{market_data}->size();
    return unless $total && $total > 0;
    my $old_offset = $self->{offset};
    my $use_cursor_anchor = defined $anchor_x;

    # 1. Punto de anclaje (índice GLOBAL + X de pantalla) ANTES de cambiar el zoom.
    #    Solo Ctrl+rueda usa ancla de cursor; rueda normal conserva el borde derecho.
    my ($anchor_index, $anchor_screen_x) = $use_cursor_anchor ? $self->_anchor_index_and_x($anchor_x) : $self->_anchor_index_and_x(undef);

    # 2. Nuevo nº de velas visibles, acotado a [MIN_VISIBLE_BARS, total].
    #    (Esto sustituye el antiguo mínimo de 10 por MIN_VISIBLE_BARS = 2.)
    my $new_visible = $self->{visible_bars} + $delta;

    my $max_visible = $total < MAX_VISIBLE_BARS ? $total : MAX_VISIBLE_BARS;
    $new_visible = MIN_VISIBLE_BARS if $new_visible < MIN_VISIBLE_BARS;
    $new_visible = $max_visible     if $new_visible > $max_visible;

    # 3. Aplicar el nuevo zoom.
    $self->{visible_bars} = $new_visible;
    my $rc = $self->{replay_controller};
    my $in_replay_abs = ($rc && $rc->is_active() && defined $self->{replay_view_end}) ? 1 : 0;

    if (!$use_cursor_anchor && !$in_replay_abs) {
        if ($old_offset <= 0) {
            $self->{offset} = $self->_clamp_offset($old_offset);
            $self->request_render();
            return;
        }
    }

    # 4. Nueva escala con el nuevo nº de barras. bar_w' = plot_width / new_visible se
    #    deriva dentro de Scales; la inversión X->índice continuo vive en x_to_index_float.
    my $scale = Market::Panels::Scales->new(
        bars         => $new_visible,

        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});

    # 5. Reposicionar el ancla en su X de pantalla previa.
    #    index_to_center_x(local) = (local + 0.5) * bar_w  =>  local = X/bar_w - 0.5.
    #    X/bar_w lo da Scales->x_to_index_float (la división vive en Scales).
    my $local_target = $scale->x_to_index_float($anchor_screen_x) - 0.5;
    my $end_idx      = $anchor_index + ($new_visible - 1 - $local_target);
    $end_idx = $self->round($end_idx);

    if ($in_replay_abs) {
        # En Replay el viewport se gobierna por replay_view_end (borde derecho
        # LOGICO absoluto). El zoom preserva el ancla ajustando ese borde;
        # _replay_window aplica los clamps. No se toca offset (ignorado en Replay).
        $self->{replay_view_end} = $end_idx;
    }
    else {
        my $base_end = $total - 1;
        my $base_total = $base_end + 1;
        my $offset = $base_end - $end_idx;
        # 6. Offset entero y acotado. compute_window define:
        #      end = total - 1 - offset ; start = end - visible_bars + 1.
        $self->{offset} = $self->_clamp_offset($offset, $base_total);
    }

    if ($use_cursor_anchor) {
        my ($new_start, undef) = $self->compute_window();
        my $new_local = $anchor_index - $new_start;
        $new_local = 0 if $new_local < 0;
        $new_local = $new_visible - 1 if $new_local >= $new_visible;
        $scale->{x_shift} = 0;
        $self->{last_mouse_x} = $self->round($scale->index_to_center_x($new_local));
    }

    # 7. Render diferido (coalescing).
    $self->request_render();
}

sub _start_horizontal_drag {
    my ($self, $widget, $x, $y) = @_;

    # Fib Retracement: 2 clics o drag de handles
    if ( $self->{fib_drawing} && $self->{fib_drawing}->is_tool_active() ) {
        $self->_fib_click( $x, $y );
        return;
    }
    if ( $self->{fib_drawing} && $self->{fib_drawing}->get_fib() ) {
        my $hit = $self->_fib_hit_test( $x, $y );
        if ($hit) {
            $self->{_fib_drag} = { handle => $hit };
            return;
        }
    }

    # Parallel Channel: 3 clics (no inicia paneo)
    if ( $self->{pchan_drawing} && $self->{pchan_drawing}->is_tool_active() ) {
        $self->_pchan_click( $x, $y );
        return;
    }

    # TrendLine: 2 clics por línea (modo tool), o drag de un extremo existente.
    if ( $self->{trend_drawing} && $self->{trend_drawing}->is_tool_active() ) {
        $self->_trend_click( $x, $y );
        return;
    }
    if ( $self->{trend_drawing} && $self->{trend_drawing}->line_count() ) {
        my $hit = $self->_trend_hit_test( $x, $y );
        if ( defined $hit ) {
            $self->{_trend_drag} = { handle => $hit };
            # Para arrastre del cuerpo ('body'), sembrar el anclaje delta con la
            # posición actual del cursor (evita salto en el primer movimiento).
            if ( $hit =~ /:body$/ ) {
                my $idx = $self->_global_index_from_x($x);
                my $scale = $self->{_last_price_scale}
                  // ( $self->{price_panel} ? $self->{price_panel}{scale} : undef );
                my $price = ( $scale && $scale->can('y_to_value') ) ? $scale->y_to_value($y) : undef;
                $self->{_trend_drag}{last} = { index => $idx, price => $price }
                  if defined $idx && defined $price;
            }
            return;
        }
    }

    # Parallel Channel: drag de un ancla / punto medio / cuerpo — no paneo
    if ( $self->{pchan_drawing} && $self->{pchan_drawing}->get_channel() ) {
        my $hit = $self->_pchan_hit_test( $x, $y );
        if ( defined $hit ) {
            $self->{_pchan_drag} = { handle => $hit };
            # Arrastre del cuerpo: sembrar anclaje delta con la posición actual.
            if ( $hit eq 'body' ) {
                my $idx = $self->_global_index_from_x($x);
                my $scale = $self->{_last_price_scale}
                  // ( $self->{price_panel} ? $self->{price_panel}{scale} : undef );
                my $price = ( $scale && $scale->can('y_to_value') ) ? $scale->y_to_value($y) : undef;
                $self->{_pchan_drag}{last} = { index => $idx, price => $price }
                  if defined $idx && defined $price;
            }
            return;
        }
    }

    if ($self->{_replay_select_mode}) {
        my $idx = $self->_global_index_from_x($x);
        # Robustez: si el clic cae en zona sin vela (borde/hueco), en vez de dejar
        # al usuario "atrapado" en modo tijeras, resolvemos a la vela válida más
        # cercana (última vela de la ventana visible). Así un clic siempre confirma.
        if (!defined $idx) {
            my $last_valid = $self->_causal_end();
            $idx = $last_valid if defined $last_valid && $last_valid >= 0;
        }
        if (defined $idx) {
            $self->set_selected_bar($idx);
            if (ref($self->{replay_bar_selected_callback}) eq 'CODE') {
                $self->{replay_bar_selected_callback}->($idx);
            }
            $self->request_render();
        }
        return;
    }

    # Anchored VWAP (TradingView): clic fija la vela de anclaje.
    if ($self->{_vwap_select_mode}) {
        my $idx = $self->_global_index_from_x($x);
        if (!defined $idx) {
            my $last_valid = $self->_causal_end();
            $idx = $last_valid if defined $last_valid && $last_valid >= 0;
        }
        if (defined $idx) {
            $self->confirm_vwap_anchor($idx);
        }
        return;
    }

    # Anchored Volume Profile: clic fija ancla.
    if ($self->{_vp_select_mode}) {
        my $idx = $self->_global_index_from_x($x);
        if (!defined $idx) {
            my $last_valid = $self->_causal_end();
            $idx = $last_valid if defined $last_valid && $last_valid >= 0;
        }
        if (defined $idx) {
            $self->confirm_vp_anchor($idx);
        }
        return;
    }

    # Drag del ancla del Perfil de Volumen (AVP)
    if ($self->{vp_overlay} && $self->{vp_overlay}->is_visible() && $self->{vp_indicator} && $self->{vp_indicator}->has_anchor()) {
        my $anchor_idx = $self->{vp_indicator}->anchor_index();
        my ($view_start, $view_end) = eval { $self->compute_window() };
        if (defined $view_start && defined $anchor_idx && $anchor_idx >= $view_start && $anchor_idx <= $view_end) {
            my $local = $anchor_idx - $view_start;
            my $bars  = $view_end - $view_start + 1;
            my $scale = Market::Panels::Scales->new(bars => $bars, right_margin => RIGHT_MARGIN);
            $scale->{width} = $self->_canvas_width($self->{price_canvas});
            my $x_anchor = $scale->index_to_center_x($local);
            if (defined $x_anchor && abs($x - $x_anchor) <= 25) {
                $self->{_vp_drag_active} = 1;
                return;
            }
        }
    }

    # Drag del ancla del Anchored VWAP (AVWAP)
    if ($self->{avwap_overlay} && $self->{avwap_overlay}->is_visible() && $self->{avwap_indicator} && $self->{avwap_indicator}->has_anchor()) {
        my $anchor_idx = $self->{avwap_indicator}->anchor_index();
        my ($view_start, $view_end) = eval { $self->compute_window() };
        if (defined $view_start && defined $anchor_idx && $anchor_idx >= $view_start && $anchor_idx <= $view_end) {
            my $local = $anchor_idx - $view_start;
            my $bars  = $view_end - $view_start + 1;
            my $scale = Market::Panels::Scales->new(bars => $bars, right_margin => RIGHT_MARGIN);
            $scale->{width} = $self->_canvas_width($self->{price_canvas});
            my $x_anchor = $scale->index_to_center_x($local);
            if (defined $x_anchor && abs($x - $x_anchor) <= 25) {
                $self->{_avwap_drag_active} = 1;
                return;
            }
        }
    }

    # spec 0000c: preservar x_shift para paneo fraccional suave. NO limpiar
    # ctrl_zoom_state aquí; reset_view/set_timeframe sí lo resetean cuando corresponde.
    my $root_x = eval { $widget->pointerx() };
    my $root_y = eval { $widget->pointery() };
    $self->{drag_start_x} = defined $root_x ? $root_x : $x;
    $self->{drag_start_y} = defined $root_y ? $root_y : $y;
    $self->{drag_start_panel} = defined $widget && defined $self->{atr_canvas} && $widget == $self->{atr_canvas} ? 'atr' : 'price';
    my $rc = $self->{replay_controller};
    if ($rc && $rc->is_active()) {
        # En Replay el viewport se gobierna por replay_view_end (borde derecho
        # LOGICO absoluto), no por offset. Se captura el borde actual para que el
        # paneo parta sin salto.
        my (undef, $view_end) = $self->compute_window();
        $self->{drag_start_view_end} = $view_end;
    }
    else {
        $self->{drag_start_offset} = $self->{offset};
    }
    $self->{drag_start_x_shift} = $self->{ctrl_zoom_x_shift} || 0;

    if (defined $widget) {
        $self->_set_cursor($widget, 'fleur');
        $self->{drag_cursor_canvas} = $widget;
    }

    my $price_scale = $self->{price_panel} ? $self->{price_panel}->{scale} : undef;
    $self->{drag_start_min_y} = defined $self->{manual_min_y} ? $self->{manual_min_y} : (defined $price_scale ? $price_scale->{min_y} : undef);
    $self->{drag_start_max_y} = defined $self->{manual_max_y} ? $self->{manual_max_y} : (defined $price_scale ? $price_scale->{max_y} : undef);

    my $atr_scale = $self->{atr_panel} ? $self->{atr_panel}->{scale} : undef;
    $self->{atr_drag_start_min_y} = defined $self->{atr_manual_min_y} ? $self->{atr_manual_min_y} : (defined $atr_scale ? $atr_scale->{min_y} : undef);
    $self->{atr_drag_start_max_y} = defined $self->{atr_manual_max_y} ? $self->{atr_manual_max_y} : (defined $atr_scale ? $atr_scale->{max_y} : undef);
}

sub _on_horizontal_drag {
    my ($self, $widget, $x, $y) = @_;

    $self->_on_mouse_move($widget, $x, $y);

    # Drag de ancla del Perfil de Volumen (AVP) — solo Manual
    if ( $self->{_vp_drag_active} ) {
        if ( ( $self->{vp_mode} // '' ) eq 'auto' ) {
            $self->{_vp_drag_active} = undef;
            return;
        }
        my $idx = $self->_global_index_from_x($x);
        if (defined $idx) {
            $self->{vp_indicator}->set_anchor($idx);
            $self->{_vp_fed_up_to} = -1;
            $self->request_render();
        }
        return;
    }

    # Drag de ancla del Anchored VWAP (AVWAP)
    if ($self->{_avwap_drag_active}) {
        my $idx = $self->_global_index_from_x($x);
        if (defined $idx) {
            $self->{avwap_indicator}->set_anchor($idx);
            $self->request_render();
        }
        return;
    }

    # Drag de handles Fib (p1/p2/bordes) — no paneo
    if ( $self->{_fib_drag} && $self->{fib_drawing} && $self->{fib_drawing}->get_fib() ) {
        $self->_fib_drag_to( $x, $y );
        return;
    }

    # Drag de un extremo de TrendLine — no paneo
    if ( $self->{_trend_drag} && $self->{trend_drawing} ) {
        $self->_trend_drag_to( $x, $y );
        return;
    }

    # Drag de un ancla del Parallel Channel — no paneo
    if ( $self->{_pchan_drag} && $self->{pchan_drawing} && $self->{pchan_drawing}->get_channel() ) {
        $self->_pchan_drag_to( $x, $y );
        return;
    }

    return unless defined $self->{drag_start_x};
    my $canvas = $self->{price_canvas};
    return unless $canvas;

    my $root_x = eval { $widget->pointerx() };
    my $root_y = eval { $widget->pointery() };
    my $current_x = defined $root_x ? $root_x : $x;
    my $current_y = defined $root_y ? $root_y : $y;
    my $width = $self->_canvas_width($canvas);
    my $scale = Market::Panels::Scales->new(
        bars         => $self->{visible_bars} || 1,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $width;
    my $bar_w = $scale->plot_width() / ($self->{visible_bars} || 1);
    return if $bar_w <= 0;

    # spec 0000c: paneo horizontal suave/fraccional. Se separa el desplazamiento
    # en píxeles en parte entera (offset) y resto fraccional (x_shift), de modo
    # que arrastres menores a una vela desplacen visualmente sin saltar offset.
    my $dx = $current_x - $self->{drag_start_x};
    my $delta_float = $dx / $bar_w;
    my $delta_whole = int($delta_float);
    my $remainder_px = $dx - ($delta_whole * $bar_w);

    my $new_shift  = ($self->{drag_start_x_shift} || 0) + $remainder_px;
    my $rc = $self->{replay_controller};

    if ($rc && $rc->is_active() && defined $self->{drag_start_view_end}) {
        # PANEO EN REPLAY: gobernado por replay_view_end (borde derecho LOGICO
        # absoluto), no por offset. Arrastrar a la derecha (dx>0) mueve la vista
        # hacia el pasado (view_end disminuye). El clamp min-visible / izquierda
        # vive en _replay_window, unica autoridad de geometria.
        my $new_view_end = $self->{drag_start_view_end} - $delta_whole;
        while ($new_shift >= $bar_w) { $new_shift -= $bar_w; $new_view_end -= 1; }
        while ($new_shift <= -$bar_w) { $new_shift += $bar_w; $new_view_end += 1; }
        $self->{replay_view_end} = $new_view_end;
        my ($vs, $ve) = $self->compute_window();     # aplica clamps
        # Si el clamp corrigio el borde, no permitir residuo subvela (sin temblor).
        $new_shift = 0 if defined $ve && $ve != $new_view_end;
        $self->{ctrl_zoom_x_shift} = $new_shift;
    }
    else {
        my $new_offset = $self->{drag_start_offset} + $delta_whole;

        # Normalizar: mantener x_shift en [-bar_w, bar_w] ajustando offset.
        while ($new_shift >= $bar_w) {
            $new_shift -= $bar_w;
            $new_offset += 1;
        }
        while ($new_shift <= -$bar_w) {
            $new_shift += $bar_w;
            $new_offset -= 1;
        }

        $self->{offset} = $self->_clamp_offset($new_offset, undef);
        # spec 0018c: si el offset tocó su límite (2 velas en el borde), NO permitir
        # desplazamiento sub-vela adicional: x_shift se anula para que las velas no
        # tiemblen ni se asomen más allá del límite al seguir arrastrando.
        if ($self->{offset} != $new_offset) {
            $new_shift = 0;
        }
        $self->{ctrl_zoom_x_shift} = $new_shift;
    }

    if (($self->{drag_start_panel} || 'price') eq 'atr') {
        $self->_apply_atr_vertical_drag_from_start($current_y);
    } else {
        $self->_apply_vertical_drag_from_start($current_y);
    }
    $self->request_render();
}

sub _on_time_axis_motion {
    my ($self, $widget, $x, $y) = @_;

    return unless defined $x;
    $self->{last_mouse_x} = $self->_snap_crosshair_x($x);
    $self->{last_mouse_y} = undef;
    $self->{active_canvas} = $widget if defined $widget;
    if ($self->{_replay_select_mode}) {
        $self->_apply_select_mode_cursor();
        $self->_clear_chart_crosshair();
        $self->_draw_replay_select_hover($widget, $self->{last_mouse_x}, $y);
        return $self;
    }
    $self->_draw_crosshair_all();
    $self->_draw_pointer_symbol($widget, $x, $y, 'h') if defined $widget && defined $y;
    return $self;
}

sub _start_time_axis_drag {
    my ($self, $widget, $x, $y) = @_;

    $self->_clear_ctrl_zoom_state();
    $self->_set_cursor($widget, 'sb_h_double_arrow');
    my $root_x = eval { $widget->pointerx() };
    $self->{time_axis_drag_start_x} = defined $root_x ? $root_x : $x;
    $self->{time_axis_drag_visible} = $self->{visible_bars};
}

sub _on_time_axis_drag {
    my ($self, $widget, $x, $y) = @_;

    $self->_on_time_axis_motion($widget, $x, $y);
    return unless defined $self->{time_axis_drag_start_x};

    my $root_x = eval { $widget->pointerx() };
    my $current_x = defined $root_x ? $root_x : $x;
    return unless defined $current_x;

    my $total = $self->{market_data}->size();
    return unless $total && $total > 0;

    my $max_visible = $total < MAX_VISIBLE_BARS ? $total : MAX_VISIBLE_BARS;
    my $delta = int(($current_x - $self->{time_axis_drag_start_x}) / TIME_AXIS_DRAG_PX_PER_BAR);
    my $new_visible = ($self->{time_axis_drag_visible} || $self->{visible_bars}) + $delta;
    $new_visible = MIN_VISIBLE_BARS if $new_visible < MIN_VISIBLE_BARS;
    $new_visible = $max_visible     if $new_visible > $max_visible;
    return if $new_visible == $self->{visible_bars};

    $self->_horizontal_zoom($new_visible - $self->{visible_bars}, undef);
}

sub _end_time_axis_drag {
    my ($self) = @_;
    $self->_set_cursor($self->{time_axis_canvas}, 'sb_h_double_arrow');
    $self->{time_axis_drag_start_x} = undef;
    $self->{time_axis_drag_visible} = undef;
}

sub _apply_vertical_drag_from_start {
    my ($self, $current_y) = @_;

    return if $self->{is_auto_scale};
    return unless defined $current_y;
    return unless defined $self->{drag_start_y};
    return unless defined $self->{drag_start_min_y} && defined $self->{drag_start_max_y};

    my $range = $self->{drag_start_max_y} - $self->{drag_start_min_y};
    return if $range <= 0;

    my (undef, $height) = $self->_canvas_size($self->{price_canvas});
    return if $height <= 0;

    my $dy = $current_y - $self->{drag_start_y};
    return if $dy == 0;

    my $delta_value = $dy * ($range / $height);
    $self->{manual_min_y} = $self->{drag_start_min_y} + $delta_value;
    $self->{manual_max_y} = $self->{drag_start_max_y} + $delta_value;
    $self->{ctrl_zoom_y_lock_min} = undef;
    $self->{ctrl_zoom_y_lock_max} = undef;
}

sub _apply_atr_vertical_drag_from_start {
    my ($self, $current_y) = @_;

    return if $self->{is_atr_auto_scale};
    return unless defined $current_y;
    return unless defined $self->{drag_start_y};
    return unless defined $self->{atr_drag_start_min_y} && defined $self->{atr_drag_start_max_y};

    my $range = $self->{atr_drag_start_max_y} - $self->{atr_drag_start_min_y};
    return if $range <= 0;

    my (undef, $height) = $self->_canvas_size($self->{atr_canvas});
    return if $height <= 0;

    my $dy = $current_y - $self->{drag_start_y};
    return if $dy == 0;

    my $delta_value = $dy * ($range / $height);
    $self->{atr_manual_min_y} = $self->{atr_drag_start_min_y} + $delta_value;
    $self->{atr_manual_max_y} = $self->{atr_drag_start_max_y} + $delta_value;
}

sub _start_price_axis_drag {
    my ($self, $widget, $y) = @_;

    $self->_clear_ctrl_zoom_state();
    $self->_set_cursor($widget, 'sb_v_double_arrow');
    my $root_y = eval { $widget->pointery() };
    $self->{axis_drag_start_y} = defined $root_y ? $root_y : $y;

    my $scale = $self->{price_panel} ? $self->{price_panel}->{scale} : undef;
    my $min = defined $self->{manual_min_y} ? $self->{manual_min_y} : (defined $scale ? $scale->{min_y} : undef);
    my $max = defined $self->{manual_max_y} ? $self->{manual_max_y} : (defined $scale ? $scale->{max_y} : undef);
    return unless defined $min && defined $max && $max > $min;

    $self->{axis_drag_min_y} = $min;
    $self->{axis_drag_max_y} = $max;
}

sub _on_price_axis_drag {
    my ($self, $widget, $y) = @_;

    return unless defined $self->{axis_drag_start_y};
    return unless defined $self->{axis_drag_min_y} && defined $self->{axis_drag_max_y};

    my $root_y = eval { $widget->pointery() };
    my $current_y = defined $root_y ? $root_y : $y;
    return unless defined $current_y;

    my $dy = $current_y - $self->{axis_drag_start_y};
    my $min = $self->{axis_drag_min_y};
    my $max = $self->{axis_drag_max_y};
    my $center = ($min + $max) / 2;
    my $half = ($max - $min) / 2;

    my $factor = exp($dy / 220);
    $factor = 0.000001 if $factor < 0.000001;
    $half *= $factor;

    $self->{manual_min_y} = $center - $half;
    $self->{manual_max_y} = $center + $half;
    if ($self->{is_auto_scale}) {
        $self->set_scale_mode('manual');
    } else {
        $self->request_render();
    }
}

sub _end_price_axis_drag {
    my ($self) = @_;

    $self->_set_cursor($self->{price_axis_canvas}, 'sb_v_double_arrow');
    $self->{axis_drag_start_y} = undef;
    $self->{axis_drag_min_y} = undef;
    $self->{axis_drag_max_y} = undef;
}

sub _start_atr_axis_drag {
    my ($self, $widget, $y) = @_;

    $self->_clear_ctrl_zoom_state();
    $self->_set_cursor($widget, 'sb_v_double_arrow');
    my $root_y = eval { $widget->pointery() };
    $self->{atr_axis_drag_start_y} = defined $root_y ? $root_y : $y;

    my $scale = $self->{atr_panel} ? $self->{atr_panel}->{scale} : undef;
    my $min = defined $self->{atr_manual_min_y} ? $self->{atr_manual_min_y} : (defined $scale ? $scale->{min_y} : undef);
    my $max = defined $self->{atr_manual_max_y} ? $self->{atr_manual_max_y} : (defined $scale ? $scale->{max_y} : undef);
    return unless defined $min && defined $max && $max > $min;

    $self->{atr_axis_drag_min_y} = $min;
    $self->{atr_axis_drag_max_y} = $max;
}

sub _on_atr_axis_drag {
    my ($self, $widget, $y) = @_;

    return unless defined $self->{atr_axis_drag_start_y};
    return unless defined $self->{atr_axis_drag_min_y} && defined $self->{atr_axis_drag_max_y};

    my $root_y = eval { $widget->pointery() };
    my $current_y = defined $root_y ? $root_y : $y;
    return unless defined $current_y;

    my $dy = $current_y - $self->{atr_axis_drag_start_y};
    my $min = $self->{atr_axis_drag_min_y};
    my $max = $self->{atr_axis_drag_max_y};
    my $center = ($min + $max) / 2;
    my $half = ($max - $min) / 2;

    my $factor = exp($dy / 220);
    $factor = 0.000001 if $factor < 0.000001;
    $half *= $factor;

    $self->{atr_manual_min_y} = $center - $half;
    $self->{atr_manual_max_y} = $center + $half;
    if ($self->{is_atr_auto_scale}) {
        $self->set_atr_scale_mode('manual');
    } else {
        $self->request_render();
    }
}

sub _end_atr_axis_drag {
    my ($self) = @_;

    $self->_set_cursor($self->{atr_axis_canvas}, 'sb_v_double_arrow');
    $self->{atr_axis_drag_start_y} = undef;
    $self->{atr_axis_drag_min_y} = undef;
    $self->{atr_axis_drag_max_y} = undef;
}

sub _reset_atr_scale {
    my ($self) = @_;

    $self->set_atr_scale_mode('auto');
}

sub _compute_visible_price_y_range {
    my ($self) = @_;

    return (undef, undef) unless $self->{market_data} && $self->{price_panel};
    my ($start, $end) = $self->compute_window();
    my $visible = $self->_causal_slice('OHLC', $start, $end);
    return $self->{price_panel}->get_y_range($visible);
}

sub _compute_visible_atr_y_range {
    my ($self) = @_;

    return (undef, undef) unless $self->{market_data} && $self->{atr_panel} && $self->{indicator_manager};
    my ($start, $end) = $self->compute_window();
    my $visible = $self->_causal_slice('ATR', $start, $end);
    return $self->{atr_panel}->get_y_range($visible);
}

sub _capture_price_y_range {
    my ($self) = @_;

    # Los caches pueden pertenecer al chart live anterior. En Replay se captura
    # siempre el viewport causal actual, incluso antes de su primer render.
    my $replay = $self->{replay_controller};
    return $self->_compute_visible_price_y_range()
        if $replay && $replay->is_active();

    if (defined $self->{last_auto_min_y} && defined $self->{last_auto_max_y}
        && !$self->_is_price_y_fallback($self->{last_auto_min_y}, $self->{last_auto_max_y})) {
        return ($self->{last_auto_min_y}, $self->{last_auto_max_y});
    }
    if (defined $self->{manual_min_y} && defined $self->{manual_max_y}
        && !$self->_is_price_y_fallback($self->{manual_min_y}, $self->{manual_max_y})) {
        return ($self->{manual_min_y}, $self->{manual_max_y});
    }
    my $scale = $self->{price_panel} ? $self->{price_panel}->{scale} : undef;
    if (defined $scale && defined $scale->{min_y} && defined $scale->{max_y}) {
        return ($scale->{min_y}, $scale->{max_y});
    }
    return $self->_compute_visible_price_y_range();
}

sub _capture_atr_y_range {
    my ($self) = @_;

    # Igual que precio: nunca heredar un rango live al entrar en Replay.
    my $replay = $self->{replay_controller};
    return $self->_compute_visible_atr_y_range()
        if $replay && $replay->is_active();

    if (defined $self->{last_auto_atr_min_y} && defined $self->{last_auto_atr_max_y}) {
        return ($self->{last_auto_atr_min_y}, $self->{last_auto_atr_max_y});
    }
    if (defined $self->{atr_manual_min_y} && defined $self->{atr_manual_max_y}) {
        return ($self->{atr_manual_min_y}, $self->{atr_manual_max_y});
    }
    my $scale = $self->{atr_panel} ? $self->{atr_panel}->{scale} : undef;
    if (defined $scale && defined $scale->{min_y} && defined $scale->{max_y}) {
        return ($scale->{min_y}, $scale->{max_y});
    }
    return $self->_compute_visible_atr_y_range();
}

sub set_atr_scale_mode {
    my ($self, $mode) = @_;

    return unless defined $mode && ($mode eq 'auto' || $mode eq 'manual');
    if ($mode eq 'auto') {
        $self->{is_atr_auto_scale} = 1;
        $self->{atr_manual_min_y} = undef;
        $self->{atr_manual_max_y} = undef;
    } else {
        $self->{is_atr_auto_scale} = 0;
        my ($min, $max) = $self->_capture_atr_y_range();
        if (defined $min && defined $max) {
            $self->{atr_manual_min_y} = $min;
            $self->{atr_manual_max_y} = $max;
        }
    }

    if (ref($self->{atr_scale_mode_callback}) eq 'CODE') {
        $self->{atr_scale_mode_callback}->($mode);
    }

    $self->request_render();
}

# set_show_grid($bool) — muestra/oculta el grid de fondo (líneas horizontales de
# precio/ATR y verticales del eje temporal). No afecta velas ni overlays; solo
# la cuadrícula, para ver mejor los indicadores cuando se requiera.
sub set_show_grid {
    my ($self, $bool) = @_;
    $self->{show_grid} = $bool ? 1 : 0;
    $self->request_render();
    return $self->{show_grid};
}

sub show_grid {
    my ($self) = @_;
    return $self->{show_grid} ? 1 : 0;
}

sub toggle_grid {
    my ($self) = @_;
    return $self->set_show_grid(!$self->{show_grid});
}

# Línea horizontal entrecortada al precio actual (última vela causal).
sub set_show_last_price_line {
    my ($self, $bool) = @_;
    $self->{show_last_price_line} = $bool ? 1 : 0;
    if ( $self->{price_panel} ) {
        $self->{price_panel}{show_last_price_line} = $self->{show_last_price_line};
    }
    $self->request_render();
    return $self->{show_last_price_line};
}

sub show_last_price_line {
    my ($self) = @_;
    return $self->{show_last_price_line} ? 1 : 0;
}

sub toggle_last_price_line {
    my ($self) = @_;
    return $self->set_show_last_price_line( !$self->{show_last_price_line} );
}

# --- Panel ATR ocultable/desplegable (deja más espacio al gráfico) ---
# El panel inferior de ATR se puede ocultar con packForget del $atr_frame.
# Como el price_frame tiene expand=1, al ocultarlo el gráfico crece solo.
# _atr_hidden guarda el estado; el render omite pintar el ATR cuando está oculto.
sub atr_panel_visible {
    my ($self) = @_;
    return $self->{_atr_hidden} ? 0 : 1;
}

sub set_atr_panel_visible {
    my ($self, $on) = @_;
    $on = $on ? 1 : 0;
    my $frame = $self->{atr_frame};
    return $self unless $frame;
    if ($on) {
        $self->{_atr_hidden} = 0;
        # Re-empaquetar debajo del eje de tiempo (top, fill x), como al arrancar.
        eval { $frame->pack(-side => 'top', -fill => 'x'); 1 };
    }
    else {
        $self->{_atr_hidden} = 1;
        eval { $frame->packForget; 1 };
    }
    # Reencuadrar: el price_frame (expand=1) toma/cede el alto liberado.
    $self->request_render();
    return $self;
}

sub toggle_atr_panel {
    my ($self) = @_;
    $self->set_atr_panel_visible( $self->{_atr_hidden} ? 1 : 0 );
    return $self->atr_panel_visible();
}

sub set_scale_mode {
    my ($self, $mode) = @_;

    return unless defined $mode && ($mode eq 'auto' || $mode eq 'manual');

    if ($mode eq 'auto') {
        $self->{is_auto_scale} = 1;
        $self->{manual_min_y} = undef;
        $self->{manual_max_y} = undef;
        $self->{ctrl_zoom_y_lock_min} = undef;
        $self->{ctrl_zoom_y_lock_max} = undef;
    } else {
        $self->{is_auto_scale} = 0;
        $self->{ctrl_zoom_y_lock_min} = undef;
        $self->{ctrl_zoom_y_lock_max} = undef;
        my ($min, $max) = $self->_capture_price_y_range();
        if (defined $min && defined $max) {
            $self->{manual_min_y} = $min;
            $self->{manual_max_y} = $max;
        }
    }

    if (ref($self->{scale_mode_callback}) eq 'CODE') {
        $self->{scale_mode_callback}->($mode);
    }

    $self->request_render();
}

sub _on_resize {
    my ($self, $widget) = @_;

    return if $self->{_resize_pending};
    $self->{_resize_pending} = 1;
    my $canvas = $self->{price_canvas} || $widget;
    if ($canvas) {
        $canvas->after(60, sub {
            $self->{_resize_pending} = 0;
            $self->request_render();
        });
        return;
    }
    $self->{_resize_pending} = 0;
    $self->request_render();
}

sub _end_drag {
    my ($self) = @_;

    if (defined $self->{drag_cursor_canvas}) {
        $self->_set_cursor($self->{drag_cursor_canvas}, $self->_chart_plot_cursor());
    }
    $self->{drag_start_x} = undef;
    $self->{drag_start_y} = undef;
    $self->{drag_start_panel} = undef;
    $self->{drag_start_min_y} = undef;
    $self->{drag_start_max_y} = undef;
    $self->{atr_drag_start_min_y} = undef;
    $self->{atr_drag_start_max_y} = undef;
    $self->{drag_start_offset} = undef;
    $self->{drag_start_x_shift} = undef;
    $self->{drag_cursor_canvas} = undef;
    $self->{_fib_drag} = undef;
    $self->{_vp_drag_active} = undef;
    $self->{_avwap_drag_active} = undef;
    $self->{_trend_drag} = undef;
    $self->{_pchan_drag} = undef;
}

sub _vertical_drag {
    my ($self, $dy) = @_;

    return if $self->{is_auto_scale};
    return if !$dy || $dy == 0;

    my $price_scale = $self->{price_panel}->{scale};
    return if !defined $price_scale;

    my $val_at_zero = $price_scale->y_to_value(0);
    my $val_at_one  = $price_scale->y_to_value(1);
    my $units_per_pixel = $val_at_zero - $val_at_one;

    my $value_delta = $dy * $units_per_pixel;

    $self->{manual_min_y} += $value_delta;
    $self->{manual_max_y} += $value_delta;
    $self->{ctrl_zoom_y_lock_min} = undef;
    $self->{ctrl_zoom_y_lock_max} = undef;

    $self->request_render();
}

sub _vertical_zoom {
    my ($self, $factor) = @_;

    return if $self->{is_auto_scale};
    return if !$factor || $factor <= 0;

    my $min = $self->{manual_min_y};
    my $max = $self->{manual_max_y};
    return if !defined $min || !defined $max;

    my $center = ($min + $max) / 2;
    my $half_range = ($max - $min) / 2;

    $half_range *= $factor;

    $self->{manual_min_y} = $center - $half_range;
    $self->{manual_max_y} = $center + $half_range;
    $self->{ctrl_zoom_y_lock_min} = undef;
    $self->{ctrl_zoom_y_lock_max} = undef;

    $self->request_render();
}

sub _atr_vertical_drag {
    my ($self, $dy) = @_;

    return if $self->{is_atr_auto_scale};
    return if !$dy || $dy == 0;

    my $atr_scale = $self->{atr_panel}->{scale};
    return if !defined $atr_scale;

    my $val_at_zero = $atr_scale->y_to_value(0);
    my $val_at_one  = $atr_scale->y_to_value(1);
    my $units_per_pixel = $val_at_zero - $val_at_one;

    my $value_delta = $dy * $units_per_pixel;

    $self->{atr_manual_min_y} += $value_delta;
    $self->{atr_manual_max_y} += $value_delta;

    $self->request_render();
}

sub _atr_vertical_zoom {
    my ($self, $factor) = @_;

    return if $self->{is_atr_auto_scale};
    return if !$factor || $factor <= 0;

    my $min = $self->{atr_manual_min_y};
    my $max = $self->{atr_manual_max_y};
    return if !defined $min || !defined $max;

    my $center = ($min + $max) / 2;
    my $half_range = ($max - $min) / 2;

    $half_range *= $factor;

    $self->{atr_manual_min_y} = $center - $half_range;
    $self->{atr_manual_max_y} = $center + $half_range;

    $self->request_render();
}

sub _snap_crosshair_x {
    my ($self, $raw_x) = @_;

    return undef unless defined $raw_x;
    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    return $self->round($raw_x) if $bars < 1;

    # Preferir la escala del último render (misma geometría X que las velas).
    my $scale = $self->{_last_price_scale};
    if (!$scale || ($scale->{bars} || 0) != $bars) {
        $scale = Market::Panels::Scales->new(
            bars         => $bars,
            right_margin => RIGHT_MARGIN,
        );
        $scale->{width} = $self->_canvas_width($self->{price_canvas});
        $scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    }
    my $local = $scale->x_to_index($raw_x);
    return $self->round($scale->index_to_center_x($local));
}

sub _on_mouse_move {
    my ($self, $widget, $raw_x, $raw_y) = @_;

    return if !defined $raw_x || !defined $raw_y;

    my $pixel_x = $self->_snap_crosshair_x($raw_x);
    my $pixel_y = $self->round($raw_y);

    # Skip si el crosshair no se mueve de pixel (ahorra delete/create Tk).
    if (defined $self->{last_mouse_x} && defined $self->{last_mouse_y}
        && $self->{last_mouse_x} == $pixel_x
        && $self->{last_mouse_y} == $pixel_y
        && defined $self->{active_canvas} && $self->{active_canvas} == $widget)
    {
        return;
    }

    $self->{last_mouse_x} = $pixel_x;
    $self->{last_mouse_y} = $pixel_y;
    $self->{active_canvas} = $widget;

    if ($self->{_replay_select_mode}) {
        $self->_apply_select_mode_cursor();
        $self->_clear_chart_crosshair();
        $self->_draw_replay_select_hover($widget, $pixel_x, $pixel_y);
    }
    elsif ($self->{_vwap_select_mode}) {
        $self->_set_cursor($widget, 'crosshair') if $widget;
        $self->_clear_chart_crosshair();
        $self->_draw_vwap_select_hover($widget, $pixel_x, $pixel_y);
    }
    elsif ($self->{_vp_select_mode}) {
        $self->_set_cursor($widget, 'crosshair') if $widget;
        $self->_clear_chart_crosshair();
        $self->_draw_vp_select_hover($widget, $pixel_x, $pixel_y);
    }
    else {
        $self->_draw_crosshair_all();
        $self->_draw_pointer_symbol($widget, $pixel_x, $pixel_y, 'cross');
    }

    # Preview en vivo del Parallel Channel: con 2 puntos fijos, el 3.º (altura del
    # canal) sigue el cursor hasta el 3.er clic (estilo TradingView).
    if ( $self->{pchan_drawing} && $self->{pchan_drawing}->is_tool_active()
        && $self->{pchan_drawing}->draft_count() == 2 && $self->{pchan_overlay} ) {
        my $idx = $self->_global_index_from_x($pixel_x);
        my $scale = $self->{_last_price_scale}
          // ( $self->{price_panel} ? $self->{price_panel}{scale} : undef );
        my $price = ( $scale && $scale->can('y_to_value') ) ? $scale->y_to_value($pixel_y) : undef;
        if ( defined $idx && defined $price ) {
            $self->{pchan_overlay}{_preview_cursor} = { index => $idx, price => $price };
            $self->request_render();
        }
    }
    elsif ( $self->{pchan_overlay} && $self->{pchan_overlay}{_preview_cursor} ) {
        delete $self->{pchan_overlay}{_preview_cursor};
    }
}

# _crosshair_time_label — etiqueta de fecha estilo TradingView (Dow DD Mon 'YY) de la vela bajo el cursor (Req. 7.4, spec 0000).
#
# Calcula el índice de dato bajo el cursor a partir de la posición horizontal
# almacenada en $self->{last_mouse_x}. Toda conversión X->índice vive en Scales
# (regla de oro de coordenadas): se instancia un Market::Panels::Scales con los
# mismos parámetros que usan render()/compute_intraday_labels —bars = nº de velas
# visibles (end - start + 1 de compute_window), right_margin => RIGHT_MARGIN y el
# ancho real del canvas de precios— y se usa x_to_index para obtener el índice
# LOCAL dentro de la ventana visible.
#
# El índice LOCAL se convierte a GLOBAL sumando 'start' (inicio de la ventana):
#   global = start + local
# Con ese índice global se obtiene el timestamp de MarketData (get_timestamp), se
# parsea con Time::Moment y se formatea como fecha+hora TradingView
# 'Dow DD Mon 'YY HH:MM' (p.ej. "Thu 23 Apr '26 09:31") reutilizando el helper
# _crosshair_date_label($tm) como prefijo de fecha y añadiendo HH:MM (spec 0000c).
#
# Devuelve la cadena 'Dow DD Mon 'YY HH:MM', o undef si:
#   * no hay cursor (last_mouse_x indefinido),
#   * la ventana visible no tiene barras,
#   * el índice global queda fuera del rango real de datos, o
#   * el timestamp no existe / no es parseable por Time::Moment.
sub _crosshair_time_label {
    my ($self) = @_;

    my $last_x = $self->{last_mouse_x};
    return undef unless defined $last_x;          # sin cursor => sin etiqueta

    # Ventana visible en índices GLOBALES; 'start' mapea local -> global.
    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    return undef if $bars < 1;                    # ventana vacía => sin etiqueta

    # Escala SOLO para convertir X -> índice (regla de oro: conversión en Scales).
    # Mismos parámetros que render()/compute_intraday_labels: right_margin reservado
    # y el ancho real del canvas de precios (bar_w = plot_width / bars).
    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});
    $scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;

    # X -> índice LOCAL (acotado por Scales a [0, bars-1]) -> índice GLOBAL.
    my $local  = $scale->x_to_index($last_x);
    my $global = $start + $local;

    # En el hueco derecho de Replay no existe vela ni timestamp interactivo.
    my $causal_end = $self->_causal_end();
    return undef if $global < 0 || $global > $causal_end;

    # Timestamp de MarketData -> Time::Moment -> 'Dow DD Mon 'YY HH:MM' (spec 0000c).
    my $ts = $self->{market_data}->get_timestamp($global);
    return undef unless defined $ts;
    my $tm = eval { Time::Moment->from_string($ts) };
    return undef unless $tm;

    my $date = $self->_crosshair_date_label($tm);
    return undef unless defined $date;
    return sprintf("%s %02d:%02d", $date, $tm->hour, $tm->minute);
}

# _clear_chart_crosshair — borra lineas/etiquetas crosshair (precio, ATR, ejes).
sub _clear_chart_crosshair {
    my ($self) = @_;
    $self->{price_panel}->draw_crosshair(undef, undef, undef) if $self->{price_panel};
    $self->{atr_panel}->draw_crosshair(undef, undef) if $self->{atr_panel};
    for my $canvas ($self->{price_canvas}, $self->{atr_canvas}) {
        next unless $canvas;
        eval { $canvas->delete($_) } for qw(price_crosshair atr_crosshair);
    }
    $self->_draw_price_axis_crosshair(undef);
    $self->_draw_atr_axis_crosshair(undef);
    if (defined $self->{time_axis_canvas}) {
        eval { $self->{time_axis_canvas}->delete('time_axis_crosshair') };
    }
    return $self;
}

sub _draw_crosshair_all {
    my ($self) = @_;

    if ($self->{_replay_select_mode}) {
        $self->_clear_chart_crosshair();
        return;
    }

    my $last_x = $self->{last_mouse_x};
    my $last_y = $self->{last_mouse_y};

    if (!defined $last_x) {
        # Cursor fuera: limpiar el crosshair y la etiqueta de tiempo en ambos
        # paneles. Contrato acordado con la tarea 6.2 para PricePanel:
        # draw_crosshair($x, $y, $time_text) -> con todo undef se borra también la
        # etiqueta de tiempo. El ATRPanel conserva su firma de 2 argumentos.
        $self->{price_panel}->draw_crosshair(undef, undef, undef);
        $self->{atr_panel}->draw_crosshair(undef, undef);
        $self->_draw_price_axis_crosshair(undef);
        $self->_draw_atr_axis_crosshair(undef);
        # spec 0000d: limpiar la etiqueta del crosshair temporal del canvas del eje.
        if (defined $self->{time_axis_canvas}) {
            $self->{time_axis_canvas}->delete('time_axis_crosshair');
        }
        return;
    }

    my $price_y = undef;
    my $atr_y = undef;

    if (defined $self->{active_canvas} && defined $self->{time_axis_canvas} && $self->{active_canvas} == $self->{time_axis_canvas}) {
        $price_y = undef;
        $atr_y = undef;
    } elsif (defined $self->{active_canvas} && $self->{active_canvas} == $self->{atr_canvas}) {
        $atr_y = $last_y;
    } else {
        $price_y = $last_y;
    }

    # Etiqueta de tiempo (HH:MM) de la vela bajo el cursor; undef si no aplica.
    my $time_text = $self->_crosshair_time_label();

    # PricePanel recibe la etiqueta de tiempo como TERCER argumento (Req. 7.4):
    # draw_crosshair($x, $y, $time_text). El ATRPanel mantiene su firma de 2
    # argumentos (NO recibe etiqueta de tiempo); la X sigue sincronizada entre
    # ambos paneles porque comparten $last_x.
    # spec 0000d: si existe time_axis_canvas, la caja de tiempo se dibuja ahí
    # (draw_time_crosshair_label), no en el price_canvas.
    if (defined $self->{time_axis_canvas}) {
        $self->{price_panel}->draw_crosshair($last_x, $price_y, undef);
        $self->{price_panel}->draw_time_crosshair_label($self->{time_axis_canvas}, $last_x, $time_text);
    } else {
        $self->{price_panel}->draw_crosshair($last_x, $price_y, $time_text);
    }
    $self->{atr_panel}->draw_crosshair($last_x, $atr_y);
    $self->_draw_price_axis_crosshair($price_y);
    $self->_draw_atr_axis_crosshair($atr_y);
}

sub set_timeframe {
    my ($self, $tf) = @_;

    # spec 0001: 8 temporalidades soportadas.
    my %valid_tf = map { $_ => 1 } qw(1m 5m 15m 1h 2h 4h D W);
    if (!$valid_tf{$tf}) {
            warn "Temporalidad '$tf' no soportada por el sistema.";
            return;
    }

    # task 0040-D: cambio de TF normaliza replay/selección (Play se detiene en Callbacks).
    if ($self->{replay_controller}) {
        $self->{replay_controller}->exit();
    }
    $self->clear_replay_select_state();

    # Lazy: construir el TF solo al elegirlo (cacheado en MarketData).
    # Con base_tf=15m, ensure no construye 1m/5m (más finos que la base).
    my $base_tf = '1m';
    if ($self->{market_data}->can('base_timeframe')) {
        $base_tf = $self->{market_data}->base_timeframe() // '1m';
    }
    if ($tf ne $base_tf && $self->{market_data}->can('ensure_timeframe')) {
        $self->{market_data}->ensure_timeframe($tf);
    }
    elsif ($tf ne $base_tf) {
        $self->{market_data}->build_tf_candles($tf);
    }
    $self->{market_data}->set_timeframe($tf);
    $self->_sync_fibonacci_levels_for_timeframe($tf);
    $self->{indicator_manager}->reset_all();
    my $n_bars = $self->{market_data}->size() || 0;
    for (my $i = 0; $i < $n_bars; $i++) {
        $self->{indicator_manager}->update_last($self->{market_data}, $i);
    }
    # spec 0013: reset SMC Pro + Structures/FVG al cambiar timeframe.
    if ($self->{smc_pro_indicator} || $self->{smc_indicator}) {
        my $ind = $self->{smc_pro_indicator} // $self->{smc_indicator};
        $ind->reset() if $ind;
        $self->{_smc_fed_up_to} = -1;
        $self->{_smc_pro_fed_up_to} = -1;
    }
    if ($self->{smc_fvg_indicator}) {
        $self->{smc_fvg_indicator}->reset();
        $self->{_smc_fvg_fed_up_to} = -1;
    }
    if ($self->{zigzag_indicator}) {
        $self->{zigzag_indicator}->reset();
        $self->{_zigzag_fed_up_to} = -1;
    }
    if ( $self->{liq_indicator} ) {
        if ( $self->{liq_indicator}->can('reset_full') ) {
            $self->{liq_indicator}->reset_full();
        }
        else {
            $self->{liq_indicator}->reset();
        }
        $self->{_liq_fed_up_to}  = -1;
        $self->{_liq_pivot_sig} = undef;
    }
    if ( $self->{auto_tc_indicator} ) {
        $self->{auto_tc_indicator}->reset();
        my %tfm = (
            '1m' => 1, '5m' => 5, '15m' => 15, '1h' => 60,
            '2h' => 120, '4h' => 240, 'D' => 1440, 'W' => 10080,
        );
        my $bm = $tfm{$tf} // 1;
        $self->{auto_tc_indicator}->set_bar_minutes($bm)
          if $self->{auto_tc_indicator}->can('set_bar_minutes');
        $self->{_auto_tc_fed_up_to} = -1;
    }
    $self->{is_auto_scale} = 1;
    $self->{manual_min_y} = undef;
    $self->{manual_max_y} = undef;
    $self->{is_atr_auto_scale} = 1;
    $self->{atr_manual_min_y} = undef;
    $self->{atr_manual_max_y} = undef;
    if (ref($self->{atr_scale_mode_callback}) eq 'CODE') {
        $self->{atr_scale_mode_callback}->('auto');
    }
    $self->_clear_ctrl_zoom_state();
    $self->reset_view();
}

sub reset_view {
    my ($self) = @_;

    $self->{visible_bars} = 60;
    $self->{offset} = 0;
    $self->{is_auto_scale} = 1;
    $self->{manual_min_y} = undef;
    $self->{manual_max_y} = undef;
    $self->{is_atr_auto_scale} = 1;
    $self->{atr_manual_min_y} = undef;
    $self->{atr_manual_max_y} = undef;
    if (ref($self->{atr_scale_mode_callback}) eq 'CODE') {
        $self->{atr_scale_mode_callback}->('auto');
    }
    $self->_clear_ctrl_zoom_state();
    $self->request_render();
}

# compute_intraday_labels — etiquetas del eje de tiempo inferior (Req. 5.2, 5.6, 5.7,
# 5.8, 6.1, 6.2, 6.4).
#
# Produce un arrayref de etiquetas enriquecidas con la forma:
#       { index => <índice LOCAL en la ventana visible>,
#         text  => <'HH:MM' o 'DD Mon'>,
#         is_date => 0|1,
#         grid => 0|1,
#         label => 0|1 }
#
# Convención de índice (CRÍTICA): el `index` de salida es LOCAL (0-based dentro de la
# ventana visible), porque las velas se dibujan con índices locales 0..N-1 y
# PricePanel::draw_time_axis centra cada etiqueta vía Scales->index_to_center_x(index).
# El índice local se obtiene como `global - start`, robusto frente a timestamps
# omitidos (no es la posición del bucle).
#
# Espaciado temporal (Req. 5.6, spec 0000b): el eje inferior prioriza fronteras
# REALES de reloj/calendario tipo TradingView, no equidistancia por stride. Se
# escanea cada timestamp visible; un tick se selecciona si cae en una frontera
# real del intervalo elegido (HH:MM con (hour*60+minute) % interval == 0). Los
# gaps de sesión/noche/fin de semana no crean huecos visuales (las velas siguen
# por índice), pero tampoco fuerzan marcas equidistantes que pierdan coherencia
# de reloj.
#
# Cambios de día (Req. 6.1, 6.4): la fecha ("DD Mon", is_date => 1) aparece SOLO
# cuando hay cambio real de día respecto al timestamp global anterior, o cuando la
# vela cae en medianoche real (00:00) sin vela anterior. La primera vela visible a
# mitad de día NO se convierte en fecha: muestra "HH:MM".
#
# Casos límite:
#   * Ventana sin barras => lista vacía sin error (Req. 5.7).
#   * Timestamp no parseable => esa etiqueta se omite y continúan las demás (Req. 5.8;
#     get_all_timestamps ya descarta los no parseables).
sub compute_intraday_labels {
    my ($self) = @_;

    my @labels;

    # Elementos visibles: arrayref de { index => <GLOBAL>, ts => <Time::Moment> }.
    # get_all_timestamps ya descarta los timestamps no parseables (Req. 5.8).
    my $visible_elements = $self->get_all_timestamps();
    my $total = scalar(@$visible_elements);
    return \@labels if $total == 0;   # Req. 5.7: ventana sin barras => sin etiquetas.

    # Ventana visible en índices GLOBALES. 'start' permite convertir los índices
    # globales (velas y anclas de tiempo) a LOCALES (los que consume draw_time_axis).
    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    $bars = 1 if $bars < 1;

    # Escala temporal SOLO para medir la separación en píxeles entre etiquetas.
    # Regla de oro: la conversión de coordenadas vive en Scales, así que se
    # instancia Market::Panels::Scales con el mismo right_margin que usa render()
    # y se le inyecta el ancho real del canvas de precios (bar_w = plot_width/bars).
    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});
    $scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;

    # Mapa índice LOCAL => Time::Moment de cada vela visible con timestamp parseable.
    my %tm_by_local;
    for my $el (@$visible_elements) {
        $tm_by_local{ $el->{index} - $start } = $el->{ts};
    }

    my $bar_w = $bars > 0 ? $scale->plot_width() / $bars : 1;
    $bar_w = 1 if $bar_w <= 0;
    my $tf_minutes = $self->_timeframe_minutes();
    my $interval_minutes = $self->_time_axis_interval_minutes($tf_minutes, $bar_w);

    # spec 0000g: plan global de cadencia uniforme tipo TradingView.
    # Se elige UNA cadencia dominante para toda la ventana visible, no se
    # aceptan candidatos localmente por peso. Los días son anchors obligatorios
    # y las horas siguen una única cadencia. Esto evita secuencias irregulares
    # tipo DAY|HOUR|DAY|DAY|HOUR.
    # Modo A = días + horas uniformes. El modo diario es fallback incompleto.

    # Peek al timestamp pre-ventana para detectar cambio de día en el primer visible.
    my $prev_tm;
    if ($start > 0 && ($start - 1) <= $self->_causal_end()) {
        my $pre_ts = $self->{market_data}->get_timestamp($start - 1);
        $prev_tm = eval { Time::Moment->from_string($pre_ts) } if defined $pre_ts;
    }

    # Construir candidatos desde velas reales (spec 0000e/0000f: índices enteros).
    my @candidates;
    for my $el (@$visible_elements) {
        my $global = $el->{index};
        my $tm     = $el->{ts};
        next unless defined $tm;

        my $local  = $global - $start;
        my $weight = $self->_time_axis_weight_for_point($tm, $prev_tm);
        next if $weight < 21;  # skip MIN1: TradingView closest cadence is 5m
        my $text   = $self->_time_axis_label_for_weight($tm, $weight);
        next unless defined $text;

        push @candidates, {
            index         => $local,
            text          => $text,
            weight        => $weight,
            is_date       => ($weight >= 50) ? 1 : 0,
            intraday_mins => $tm->hour * 60 + $tm->minute,
            year          => $tm->year,
            month         => $tm->month,
            day           => $tm->day_of_month,
            date_ordinal  => $tm->year * 366 + $tm->day_of_year,
            grid          => 1,
            label         => 0,
            x             => $scale->index_to_center_x($local),
        };
        $prev_tm = $tm;
    }

    # Elegir el mejor plan global de cadencia (spec 0000g).
    my $plan = $self->_choose_time_axis_plan(\@candidates, $bar_w, $tf_minutes);

    # Marcar aceptados del plan con label=1; el resto queda con label=0 pero
    # grid=1 para compatibilidad con tests que inspeccionan candidatos por grid.
    # El plan puede sobrescribir texto/tipo (p.ej. día 1 -> Apr en zoom calendario).
    my %accepted = map { $_->{index} => $_ } @$plan;
    for my $cand (@candidates) {
        my $planned = $accepted{ $cand->{index} };
        if ($planned) {
            $cand->{label} = 1;
            $cand->{text} = $planned->{text} if defined $planned->{text};
            $cand->{is_date} = $planned->{is_date} if exists $planned->{is_date};
        }
        else {
            $cand->{label} = 0;
        }
    }

    for my $item (sort { $a->{index} <=> $b->{index} } @candidates) {
        push @labels, {
            index   => $item->{index},
            text    => $item->{text},
            is_date => $item->{is_date},
            grid    => $item->{grid},
            label   => $item->{label},
        };
    }

    return \@labels;
}

# _choose_time_axis_plan($candidates, $bar_w, $tf_minutes) — spec 0000g
# Elije un plan global de cadencia uniforme. Prueba cadencias de densa a
# dispersa; la primera que produce min_gap_px >= 65 y consistencia entre
# segmentos día-a-día es el plan Modo A aceptado.
# Si ninguna cadencia intradía funciona, retorna solo días (fallback incompleto).
sub _choose_time_axis_plan {
    my ($self, $candidates, $bar_w, $tf_minutes) = @_;

    # Zoom calendario: cuando el ancho por barra es mínimo y la ventana cubre
    # muchas fechas, TradingView deja de mostrar horas y usa mes + días.
    # No activar en rangos cortos 1m/5m: aunque bar_w sea bajo, allí 0000g debe
    # seguir mostrando Modo A (días + horas) si caben horas.
    my @date_candidates = grep { $_->{is_date} } @$candidates;
    if ($bar_w <= 1.15 && @date_candidates >= 20) {
        my @calendar = $self->_build_calendar_time_axis_plan($candidates, $bar_w);
        return \@calendar if @calendar >= 2;
    }

    my @cadences = (5, 15, 30, 60, 90, 180, 360, 720, 1440);
    @cadences = grep { $_ >= $tf_minutes } @cadences;

    # Similar a LWC: separar por ancho de label. 65px evita saturar 1m/5m
    # y permite 90m en NQ1!/15m cuando el canvas visible tiene ancho comparable
    # al de la app/screenshot de TradingView.
    my $min_label_px = 65;
    my $min_indices  = int(($min_label_px / $bar_w) + 0.999);
    $min_indices = 1 if $min_indices < 1;

    for my $cad (@cadences) {
        # spec 0000g: solo probar cadencias cuyo espaciado natural en píxeles
        # es >= min_label_px. Thinning de una cadencia densa crea cadencias
        # efectivas sucias (e.g. thinning 1h a cada 8h produce 08:00, no limpio).
        my $cadence_px = ($cad / $tf_minutes) * $bar_w;
        next if $cadence_px < $min_label_px;

        my @plan = $self->_build_time_axis_plan($candidates, $cad, $min_indices);
        @plan = $self->_adjust_sparse_time_axis_plan($candidates, \@plan, $cad, $tf_minutes, $min_indices);
        @plan = $self->_densify_sparse_gaps_in_time_axis_plan($candidates, \@plan, $cad, $tf_minutes, $min_indices);
        next unless @plan >= 2;

        my $min_gap = $self->_plan_min_gap_px(\@plan, $cad, $tf_minutes);
        next if !defined($min_gap) || $min_gap < $min_label_px;

        if ($self->_plan_is_consistent(\@plan, $cad, $tf_minutes)) {
            return \@plan;
        }
    }

    # Fallback: solo días (incompleto, no aceptación final de spec 0000g).
    my @daily = $self->_build_time_axis_plan($candidates, 1440, $min_indices);
    return \@daily;
}

# _build_calendar_time_axis_plan($candidates, $bar_w) — zoom calendario.
# Usa solo anchors de fecha reales: mes + días seleccionados. No muestra horas.
# Generalista: separación por ancho estimado de label (box-based), no umbral fijo.
# Los anchors de mes (Apr, May) siempre ganan frente a días cercanos.
# spec 0000i: densidad tipo TradingView — permite días consecutivos si caben.
# spec 0000j: filtra días de sesión parcial nocturna (primera vela >= 17:00)
# que TradingView no muestra como labels principales en modo calendario mensual.
sub _build_calendar_time_axis_plan {
    my ($self, $candidates, $bar_w) = @_;

    my @dates = grep { $_->{is_date} } @$candidates;
    return () unless @dates;

    my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    # spec 0000j: umbral de sesión parcial nocturna. Un día cuya primera vela
    # sea >= 17:00 (1020 min) y no tenga velas antes del mediodía es un anchor
    # débil: TradingView no lo usa como label principal en calendario mensual.
    my $NOCTURNAL_THRESHOLD_MINS = 1020;

    # Ancho estimado de cada tipo de label en píxeles.
    my $day_label_px = 20;
    my $month_label_px = 40;
    my $min_gap_px = 6;

    # spec 0000j: separación mínima entre días basada en calendario, no solo
    # en ancho de texto. Cuando se omiten días parciales (domingos nocturnos),
    # los días vecinos pueden quedar comprimidos por el gap de sesión. Exigir
    # que la separación x entre días sea >= 80% de un día calendario normal.
    # Esto evita que aparezcan días como 6 pegados a 3 tras omitir el domingo 5.
    my $normal_day_indices = 96; # ~96 barras de 15m por día con sesión completa
    my $min_day_gap_px = int($normal_day_indices * $bar_w * 0.80 + 0.5);
    $min_day_gap_px = $min_gap_px if $min_day_gap_px < $min_gap_px;

    my @calendar;
    for my $d (@dates) {
        my %cand = %$d;
        if (($cand{day} || 0) == 1 || ($cand{weight} || 0) >= 60) {
            $cand{text} = $months[($cand{month} || 1) - 1] || $cand{text};
            $cand{calendar_month_anchor} = 1;
            $cand{label_half_width} = $month_label_px / 2;
            $cand{weak_partial_session} = 0;
        }
        else {
            $cand{label_half_width} = $day_label_px / 2;
            # spec 0000j: detectar sesión parcial nocturna.
            my $first_mins = $cand{intraday_mins} // 0;
            $cand{weak_partial_session} = ($first_mins >= $NOCTURNAL_THRESHOLD_MINS) ? 1 : 0;
        }
        push @calendar, \%cand;
    }

    my @accepted;
    for my $cand (@calendar) {
        if ($cand->{calendar_month_anchor}) {
            # Mes siempre entra. Si colisiona con último día aceptado, el día se elimina.
            if (@accepted && !$accepted[-1]{calendar_month_anchor}) {
                my $half_sum = $accepted[-1]{label_half_width} + $cand->{label_half_width} + $min_gap_px;
                if ($cand->{x} - $accepted[-1]{x} < $half_sum) {
                    pop @accepted;
                }
            }
            push @accepted, $cand;
            next;
        }

        # spec 0000j: omitir días de sesión parcial nocturna en modo calendario.
        next if $cand->{weak_partial_session};

        # Día normal: aceptar si no colisiona con el último aceptado.
        if (@accepted) {
            my $last = $accepted[-1];
            if (!$last->{calendar_month_anchor}) {
                # Día-día: exigir separación calendario mínima.
                next if $cand->{x} - $last->{x} < $min_day_gap_px;
            }
            else {
                # Mes-día: separación por ancho de label.
                my $half_sum = $last->{label_half_width} + $cand->{label_half_width} + $min_gap_px;
                next if $cand->{x} - $last->{x} < $half_sum;
            }
        }
        push @accepted, $cand;
    }

    return @accepted;
}

# _build_time_axis_plan($candidates, $cadence, $min_indices) — spec 0000g
# Construye un plan con una sola cadencia: todos los anchors de día/mes/año
# + horas que satisfagan minutes % cadence == 0.
#
# Importante: dentro de UNA cadencia, las horas se aceptan cronológicamente.
# No se ordenan por peso porque eso degrada 90m a una cadencia visual de 3h
# (18:00/21:00 desplazan 19:30/22:30), distinto a TradingView en NQ1! 15m.
# Los anchors de día/mes/año siguen reemplazando el timestamp de su propia vela.
sub _build_time_axis_plan {
    my ($self, $candidates, $cadence, $min_indices) = @_;

    my @filtered;
    for my $cand (@$candidates) {
        if ($cand->{weight} >= 50) {
            push @filtered, { %$cand };
        }
        elsif ($cadence < 1440 && defined $cand->{intraday_mins}
               && $cand->{intraday_mins} % $cadence == 0) {
            push @filtered, { %$cand };
        }
    }

    my @accepted;
    for my $cand (sort { $a->{index} <=> $b->{index} } @filtered) {
        if (@accepted && $cand->{index} - $accepted[-1]{index} < $min_indices) {
            # Si el candidato actual representa una frontera temporal más importante
            # (p.ej. 01:00 sobre 00:15, o DAY/MONTH sobre hora cercana), reemplaza
            # la marca previa. Esto mantiene fronteras reales de reloj/calendario sin
            # volver al thinning global por peso que destruía la cadencia 90m.
            if (($cand->{weight} || 0) > ($accepted[-1]{weight} || 0)) {
                pop @accepted;
            }
            else {
                next;
            }
        }
        $cand->{label} = 1;
        push @accepted, $cand;
    }

    return @accepted;
}

# _adjust_sparse_time_axis_plan() — ajustes tipo TradingView en zooms lejanos.
# Generalista: parte del plan de cadencia global y, solo para cadencias intradía
# lejanas (>=12h, <1D), enriquece huecos amplios con candidatos reales de alta
# jerarquía (HOUR12/HOUR6/HOUR3) si respetan separación. No hardcodea fechas ni
# horas específicas: la hora elegida sale de pesos temporales + espacio disponible.
sub _adjust_sparse_time_axis_plan {
    my ($self, $candidates, $plan, $cadence, $tf_minutes, $min_indices) = @_;
    return @$plan if !defined($cadence) || $cadence < 720 || $cadence >= 1440 || !$plan || !@$plan;

    my @out = map { { %$_ } } @$plan;
    my $natural_indices = (defined $tf_minutes && $tf_minutes > 0)
        ? int(($cadence / $tf_minutes) + 0.999)
        : 0;
    my $compressed_gap_limit = $natural_indices + int($natural_indices / 2 + 0.999);

    # Si hay DAY|DAY comprimido por sesión/weekend, el segundo DAY puede ocultarse
    # para dejar que el intervalo respire con horas intradía reales. Esto replica la
    # compresión lógica de TradingView sin inventar puntos.
    my %drop_index;
    my @dropped_dates;
    for (my $i = 1; $i < @out; $i++) {
        my $left  = $out[$i - 1];
        my $right = $out[$i];
        next unless $left->{is_date} && $right->{is_date};
        next unless $natural_indices > 0 && ($right->{index} - $left->{index}) <= $compressed_gap_limit;

        my $next = $out[$i + 1];
        next unless $next;
        my @inside = grep {
            !$_->{is_date}
            && ($_->{weight} || 0) >= 31
            && $_->{index} > $right->{index}
            && $_->{index} < $next->{index}
            && $_->{index} - $left->{index} >= $min_indices
            && $next->{index} - $_->{index} >= $min_indices
        } @$candidates;
        if (@inside) {
            $drop_index{ $right->{index} } = 1;
            push @dropped_dates, { %$right };
        }
    }
    @out = grep { !$drop_index{ $_->{index} } } @out;

    my %selected = map { $_->{index} => 1 } @out;
    my @extra;

    my $try_add_between = sub {
        my ($left, $right) = @_;
        my $left_idx  = defined $left  ? $left->{index}  : -1;
        my $right_idx = defined $right ? $right->{index} : undef;
        return unless defined $right_idx;

        my @pool = grep {
            !$_->{is_date}
            && !$selected{ $_->{index} }
            && ($_->{weight} || 0) >= 31
            && $_->{index} > $left_idx
            && $_->{index} < $right_idx
        } @$candidates;

        # Igual que LWC: pesos mayores primero; luego orden cronológico. La separación
        # final evita saturar y determina si queda HOUR12, HOUR6 o HOUR3.
        for my $cand (sort { ($b->{weight} || 0) <=> ($a->{weight} || 0) || $a->{index} <=> $b->{index} } @pool) {
            my $ok = 1;
            for my $s (@out, @extra) {
                if (abs($cand->{index} - $s->{index}) < $min_indices) {
                    $ok = 0;
                    last;
                }
            }
            next unless $ok;
            push @extra, { %$cand };
            $selected{ $cand->{index} } = 1;
        }
    };

    # Borde izquierdo. Esto añade labels como 03:00 solo cuando realmente caben
    # antes del primer hito fuerte.
    $try_add_between->(undef, $out[0]) if @out;

    # Huecos internos: solo rellenar el intervalo que contiene un DAY comprimido
    # ocultado. No llenar cualquier DAY|DAY, porque TradingView mantiene huecos
    # como 24|26 sin insertar una hora artificial.
    for my $dropped (@dropped_dates) {
        my ($left, $right);
        for my $item (@out) {
            $left = $item if $item->{index} < $dropped->{index};
            if ($item->{index} > $dropped->{index}) {
                $right = $item;
                last;
            }
        }
        $try_add_between->($left, $right) if $left && $right;
    }

    return sort { $a->{index} <=> $b->{index} } (@out, @extra);
}

# _densify_sparse_gaps_in_time_axis_plan() — spec 0000h.
# Después de construir un plan intradía válido, mide los huecos visuales entre
# labels consecutivos. Si un hueco es demasiado grande (> 1.5x la cadencia
# natural), intenta insertar un candidato real existente que reduzca el hueco
# sin colisionar. El caso 14:30 entre 12:00 y 18:00 sale de esta regla general,
# no de hardcodear la fecha/hora.
sub _densify_sparse_gaps_in_time_axis_plan {
    my ($self, $candidates, $plan, $cadence, $tf_minutes, $min_indices) = @_;
    return @$plan if !defined($cadence) || $cadence >= 1440 || !$plan || @$plan < 2;

    my @out = map { { %$_ } } @$plan;
    my $natural_indices = int(($cadence / $tf_minutes) + 0.999);
    my $gap_threshold = int($natural_indices * 1.5 + 0.999);

    my %selected = map { $_->{index} => 1 } @out;
    my @extra;

    for (my $i = 0; $i < $#out; $i++) {
        my $left  = $out[$i];
        my $right = $out[$i + 1];
        my $gap = $right->{index} - $left->{index};
        next if $gap <= $gap_threshold;

        # No densificar gaps entre dos anchors de día (session/weekend gaps).
        next if $left->{is_date} && $right->{is_date};

        my @pool = grep {
            !$selected{$_->{index}}
            && !$_->{is_date}
            && ($_->{weight} || 0) >= 22
            && $_->{index} > $left->{index}
            && $_->{index} < $right->{index}
            && $_->{index} - $left->{index} >= $min_indices
            && $right->{index} - $_->{index} >= $min_indices
        } @$candidates;

        next unless @pool;

        my $midpoint = ($left->{index} + $right->{index}) / 2;
        my $best;
        my $best_score;
        for my $cand (@pool) {
            my $dist_from_mid = abs($cand->{index} - $midpoint);
            my $score = -$dist_from_mid * 10 + ($cand->{weight} || 0);
            if (!defined $best_score || $score > $best_score) {
                $best = { %$cand };
                $best_score = $score;
            }
        }

        if ($best) {
            $best->{label} = 1;
            $selected{$best->{index}} = 1;
            push @extra, $best;
        }
    }

    return sort { $a->{index} <=> $b->{index} } (@out, @extra);
}

# _plan_min_gap_px($plan) — spec 0000g
# Retorna el menor gap en píxeles entre labels consecutivos del plan.
sub _plan_min_gap_px {
    my ($self, $plan, $cadence, $tf_minutes) = @_;
    return undef if @$plan < 2;
    my $min;
    my $natural_indices = (defined $cadence && defined $tf_minutes && $tf_minutes > 0)
        ? int(($cadence / $tf_minutes) + 0.999)
        : 0;
    for my $i (1 .. $#$plan) {
        my $left  = $plan->[$i - 1];
        my $right = $plan->[$i];
        # Igual que TradingView, no invalidar el plan por anchors de día pegados
        # cuando el gap de mercado está comprimido por índice lógico (ej. 26|27).
        my $compressed_gap_limit = $natural_indices + int($natural_indices / 2 + 0.999);
        next if $natural_indices > 0
             && $left->{is_date} && $right->{is_date}
             && ($right->{index} - $left->{index}) <= $compressed_gap_limit;
        my $gap = $right->{x} - $left->{x};
        $min = $gap if !defined($min) || $gap < $min;
    }
    return $min;
}

# _plan_is_consistent($plan) — spec 0000g
# Verifica que no haya patrón DAY|HOUR|DAY|DAY|HOUR en segmentos internos.
# Los gaps de sesión (días consecutivos sin horas entre ellos) son excepciones
# aceptables solo en bordes. La inconsistencia se detecta cuando un segmento
# interno tiene 0 horas mientras otros tienen >0.
# También rechaza planes con 1 sola hora perdida entre muchos días (no es Modo A).
sub _plan_is_consistent {
    my ($self, $plan, $cadence, $tf_minutes) = @_;

    my @day_pos;
    for my $i (0 .. $#$plan) {
        push @day_pos, $i if $plan->[$i]{is_date};
    }

    return 1 if @day_pos < 2;

    my @hour_counts;
    for my $i (1 .. $#day_pos) {
        push @hour_counts, $day_pos[$i] - $day_pos[$i - 1] - 1;
    }

    my $has_hours = grep { $_ > 0 } @hour_counts;
    my $has_zero  = grep { $_ == 0 } @hour_counts;

    # spec 0000g: si hay horas pero son muy pocas frente a muchos días, no es Modo A.
    # En zooms más alejados TradingView sí acepta ~1 hora por día (p.ej. 12:00),
    # así que solo rechazamos planes realmente pobres: menos de media hora visible
    # por anchor de día.
    my $total_hours = grep { !$_->{is_date} } @$plan;
    if (@day_pos >= 3 && $total_hours > 0 && $total_hours < int(@day_pos / 2)) {
        return 0;
    }

    return 1 if !$has_hours || !$has_zero;

    # Hay mezcla: algunos segmentos con horas, otros sin.
    # Segmentos internos (no borde) con 0 horas son inconsistentes salvo
    # que los días estén tan cerca que no quepa ninguna hora (gap de sesión).
    for my $i (0 .. $#hour_counts) {
        next if $i == 0 && $hour_counts[0] == 0;  # borde izquierdo
        next if $i == $#hour_counts && $hour_counts[-1] == 0;  # borde derecho
        if ($hour_counts[$i] == 0 && $has_hours) {
            my $left  = $plan->[ $day_pos[$i] ];
            my $right = $plan->[ $day_pos[$i + 1] ];
            my $natural_indices = (defined $cadence && defined $tf_minutes && $tf_minutes > 0)
                ? int(($cadence / $tf_minutes) + 0.999)
                : 0;
            # TradingView comprime gaps de sesión/weekend por índice lógico: dos días
            # pueden quedar muy juntos (p.ej. 26|27) y no por eso debe caerse a
            # modo diario. Si entre ambos anchors no cabría ni una marca de la
            # cadencia elegida, se permite como gap comprimido interno.
            my $compressed_gap_limit = $natural_indices + int($natural_indices / 2 + 0.999);
            next if $natural_indices > 0 && ($right->{index} - $left->{index}) <= $compressed_gap_limit;
            return 0;
        }
    }

    return 1;
}

# debug_time_axis_snapshot() — wrapper mínimo hacia módulo removible de debug.
# La lógica profesional vive en Market/Debug/TimeAxisSnapshot.pm para poder
# eliminar/omitir el sistema de diagnóstico sin mezclarlo con el motor principal.
sub debug_time_axis_snapshot {
    my ($self, %opts) = @_;
    require Market::Debug::TimeAxisSnapshot;
    if (exists $opts{timeframe} || exists $opts{start_ts} || exists $opts{end_ts}
        || exists $opts{start_index} || exists $opts{end_index} || exists $opts{visible_bars}) {
        return Market::Debug::TimeAxisSnapshot->capture_range($self, %opts);
    }
    return Market::Debug::TimeAxisSnapshot->capture($self, %opts);
}

# _time_axis_weight_for_point($tm, $prev_tm) — spec 0000f
# Asigna un peso temporal comparando el timestamp actual con el anterior real.
# Inspirado en lightweight-charts/time-scale-point-weight-generator.ts.
# Pesos: YEAR=70, MONTH=60, DAY=50, HOUR12=33, HOUR6=32, HOUR3=31,
# HOUR1=30, MIN90=29, MIN30=22, MIN15=21.5, MIN5=21, MIN1=20.
sub _time_axis_weight_for_point {
    my ($self, $tm, $prev_tm) = @_;

    if (defined $prev_tm) {
        return 70 if $tm->year != $prev_tm->year;
        return 60 if $tm->month != $prev_tm->month;
        return 50 if $tm->day_of_month != $prev_tm->day_of_month;
    }
    elsif ($tm->hour == 0 && $tm->minute == 0) {
        return 50;
    }

    my $m = $tm->hour * 60 + $tm->minute;
    return 33   if $m % 720 == 0;
    return 32   if $m % 360 == 0;
    return 31   if $m % 180 == 0;
    return 30   if $m % 60  == 0;
    return 29   if $m % 90  == 0;
    return 22   if $m % 30  == 0;
    return 21.5 if $m % 15  == 0;
    return 21   if $m % 5   == 0;
    return 20;
}

# _time_axis_label_for_weight($tm, $weight) — spec 0000f
# Formatea el texto del label del eje inferior según el peso temporal.
# YEAR => "2026", MONTH => "Apr", DAY => "15", intradía => "HH:MM".
sub _time_axis_label_for_weight {
    my ($self, $tm, $weight) = @_;

    return undef unless defined $tm && ref($tm) eq 'Time::Moment';

    if ($weight >= 70) {
        return sprintf("%04d", $tm->year);
    }
    elsif ($weight >= 60) {
        my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
        return $months[$tm->month - 1];
    }
    elsif ($weight >= 50) {
        return sprintf("%d", $tm->day_of_month);
    }
    return sprintf("%02d:%02d", $tm->hour, $tm->minute);
}

# _time_label_for_index($tm, $is_date) — formatea el texto de UNA etiqueta del eje
# de tiempo (Req. 5.2, 5.8, 6.4).
#
# Firma elegida: recibe el objeto Time::Moment YA PARSEADO ($tm) y el flag $is_date.
# Se opta por el objeto (en vez del string ISO o el índice) porque
# compute_intraday_labels ya dispone de los Time::Moment construidos por
# get_all_timestamps; así se evita re-parsear y se centraliza la validación.
#
# Formato de salida:
#   * $is_date verdadero => fecha corta "DD Mon": día con dos dígitos (cero a la
#     izquierda) y abreviatura de mes en inglés de 3 letras, p.ej. "18 May".
#   * $is_date falso     => hora "HH:MM" en 24h con cero a la izquierda, rango
#     "00:00".."23:59", p.ej. "09:05".
#
# Devuelve undef si $tm no es un Time::Moment utilizable (timestamp no parseable),
# para que el llamador omita esa etiqueta y continúe con las demás (Req. 5.8).
sub _is_time_axis_boundary {
    my ($self, $tm, $interval_minutes) = @_;

    return 0 unless defined $tm && ref($tm) eq 'Time::Moment';
    return 0 unless defined $interval_minutes && $interval_minutes > 0;

    if ($interval_minutes < 1440) {
        my $minutes = $tm->hour * 60 + $tm->minute;
        return ($minutes % $interval_minutes) == 0 ? 1 : 0;
    }

    return $tm->hour == 0 && $tm->minute == 0 ? 1 : 0;
}

sub _time_axis_interval_minutes {
    my ($self, $tf_minutes, $bar_w) = @_;

    # Escaleras por fronteras reales tipo TradingView (spec 0000b). Cada candidato
    # es >= tf_minutes y divisible por tf_minutes (salvo 90m que es multiple de
    # 1/5/15). 5m omite 720/12h: el usuario observó que de 6h pasa a dias. 15m
    # añade 2880/4320 (2D/3D) en zoom muy lejano. Las ramas 1h/2h/4h/D/W quedan
    # preparadas para Fase 2 (no se invocan hoy porque _timeframe_minutes solo
    # devuelve 1/5/15).
    my @ladder;
    if    ($tf_minutes == 1)     { @ladder = (1, 5, 15, 30, 60, 90, 180, 360, 720, 1440, 10080, 43200, 525600); }
    elsif ($tf_minutes == 5)     { @ladder = (5, 15, 30, 60, 90, 180, 360, 1440, 10080, 43200, 525600); }
    elsif ($tf_minutes == 15)    { @ladder = (15, 30, 60, 90, 180, 360, 1440, 2880, 4320, 10080, 43200, 525600); }
    elsif ($tf_minutes == 60)    { @ladder = (60, 180, 360, 720, 1440, 10080, 43200, 525600); }
    elsif ($tf_minutes == 120)   { @ladder = (120, 240, 360, 720, 1440, 10080, 43200, 525600); }
    elsif ($tf_minutes == 240)   { @ladder = (240, 720, 1440, 10080, 43200, 525600); }
    elsif ($tf_minutes == 1440)  { @ladder = (1440, 10080, 43200, 129600, 259200, 525600); }
    elsif ($tf_minutes == 10080) { @ladder = (10080, 43200, 129600, 259200, 525600); }
    else                         { @ladder = (1, 5, 15, 30, 60, 90, 180, 360, 720, 1440, 10080, 43200, 525600); }

    my $target_px = 100;
    for my $interval (@ladder) {
        next if $interval < $tf_minutes;
        my $px = ($interval / $tf_minutes) * $bar_w;
        return $interval if $px >= $target_px;
    }
    return $ladder[-1];
}

sub _time_label_for_index {
    my ($self, $tm, $is_date) = @_;

    return undef unless defined $tm && ref($tm) eq 'Time::Moment';

    if ($is_date) {
        my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
        my $mon = $months[ $tm->month - 1 ];
        return undef unless defined $mon;          # mes fuera de rango (defensivo)
        return sprintf("%02d %s", $tm->day_of_month, $mon);
    }

    return sprintf("%02d:%02d", $tm->hour, $tm->minute);
}

# _local_abs_minutes($tm) — minutos absolutos en zona horaria local del timestamp.
# Usado por compute_intraday_labels para detectar fronteras de reloj entre dos
# timestamps cuando hay un gap de datos (spec 0000c). Es monótono en tiempo local
# y alineado a medianoche local: como 1440 es divisible por todos los intervalos
# intradía usados, los múltiplos de interval_minutes caen en fronteras de reloj.
sub _local_abs_minutes {
    my ($self, $tm) = @_;
    return (($tm->year * 366 + $tm->day_of_year) * 1440 + $tm->hour * 60 + $tm->minute);
}

# _crosshair_date_label($tm) — etiqueta inferior del crosshair estilo TradingView
# (spec 0000): 'Dow DD Mon 'YY', p.ej. "Thu 23 Apr '26".
# Time::Moment->day_of_week es ISO 8601 (1=Lun .. 7=Dom), verificado con prueba
# mínima sobre 2026-04-23 (dow=4 => Thu).
sub _crosshair_date_label {
    my ($self, $tm) = @_;

    return undef unless defined $tm && ref($tm) eq 'Time::Moment';

    my @dow = qw(Mon Tue Wed Thu Fri Sat Sun);
    my @mon = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my $dow = $dow[ $tm->day_of_week - 1 ];
    my $mon = $mon[ $tm->month - 1 ];
    return undef unless defined $dow && defined $mon;

    return sprintf("%s %02d %s '%02d", $dow, $tm->day_of_month, $mon, $tm->year % 100);
}

sub get_all_timestamps {
    my ($self) = @_;

    my ($start, $end) = $self->compute_window();
    my @timestamps;
    my $causal_end = $self->_causal_end();
    my $last_index = eval { $self->{market_data}->last_index() };
    $last_index = ($self->{market_data}->size() || 0) - 1 if !defined $last_index;
    $last_index = $causal_end if $causal_end < $last_index;

    my $md = $self->{market_data};
    my $can_cache = $md && $md->can('_parse_tm_cached');
    my $read_end = $end < $last_index ? $end : $last_index;
    for (my $i = $start; $i <= $read_end; $i++) {
        next if $i < 0;
        my $ts = $md->get_timestamp($i);
        next unless defined $ts;
        my $parsed = $can_cache
            ? $md->_parse_tm_cached($ts)
            : eval { Time::Moment->from_string($ts) };
        push @timestamps, { index => $i, ts => $parsed } if $parsed;
    }

    # El espacio derecho conserva el calendario/grid como TradingView, pero se
    # deriva unicamente del timestamp causal y del TF: nunca consulta velas futuras.
    if ($end > $last_index && $last_index >= 0) {
        my $base_ts = $md->get_timestamp($last_index);
        my $base_tm = defined $base_ts
            ? ($can_cache ? $md->_parse_tm_cached($base_ts)
                          : eval { Time::Moment->from_string($base_ts) })
            : undef;
        my $tf_minutes = $self->_timeframe_minutes();
        if ($base_tm) {
            for my $i (($last_index + 1) .. $end) {
                my $future = eval { $base_tm->plus_minutes(($i - $last_index) * $tf_minutes) };
                push @timestamps, { index => $i, ts => $future, synthetic => 1 } if $future;
            }
        }
    }

    return \@timestamps;

}

# Stub: Fib de producto es Drawing::FibRetracement (no ratios en SMC/ZZ).
sub _sync_fibonacci_levels_for_timeframe {
    my ( $self, $tf ) = @_;
    return $self;
}

sub _timeframe_minutes {
    my ($self) = @_;

    my $tf = eval { $self->{market_data}->{active_tf} } || '1m';
    return 5    if $tf eq '5m';
    return 15   if $tf eq '15m';
    return 60   if $tf eq '1h';
    return 120  if $tf eq '2h';
    return 240  if $tf eq '4h';
    return 1440 if $tf eq 'D';
    return 10080 if $tf eq 'W';
    return 1;
}

# ---------------------------------------------------------------------------
# Parallel Channel (drawing tool TV) — Fase actual
# ---------------------------------------------------------------------------
sub start_parallel_channel_tool {
    my ($self) = @_;
    return $self unless $self->{pchan_drawing};
    $self->{pchan_drawing}->start_tool();
    if ( ref( $self->{pchan_mode_callback} ) eq 'CODE' ) {
        $self->{pchan_mode_callback}->( 1, 0 );
    }
    $self->request_render();
    return $self;
}

sub cancel_parallel_channel_tool {
    my ($self) = @_;
    return $self unless $self->{pchan_drawing};
    $self->{pchan_drawing}->cancel_tool();
    if ( ref( $self->{pchan_mode_callback} ) eq 'CODE' ) {
        $self->{pchan_mode_callback}->( 0, $self->{pchan_drawing}->draft_count() );
    }
    $self->request_render();
    return $self;
}

sub clear_parallel_channel {
    my ($self) = @_;
    return $self unless $self->{pchan_drawing};
    $self->{pchan_drawing}->clear_channel();
    $self->{pchan_drawing}->cancel_tool();
    if ( ref( $self->{pchan_mode_callback} ) eq 'CODE' ) {
        $self->{pchan_mode_callback}->( 0, 0 );
    }
    $self->request_render();
    return $self;
}

sub _pchan_hit_test {
    my ( $self, $x, $y ) = @_;
    my $ov = $self->{pchan_overlay};
    return undef unless $ov && $ov->can('hit_test');
    my $scale = $self->{_last_price_scale}
      // ( $self->{price_panel} ? $self->{price_panel}{scale} : undef );
    return undef unless $scale;
    my ( $ws, $we ) = eval { $self->compute_window() };
    return $ov->hit_test( $x, $y, $scale, $ws // 0 );
}

sub _pchan_drag_to {
    my ( $self, $x, $y ) = @_;
    my $handle = $self->{_pchan_drag}{handle} or return;
    my $draw   = $self->{pchan_drawing} or return;
    return unless $draw->get_channel();

    my $idx = $self->_global_index_from_x($x);
    if ( !defined $idx ) {
        my $last_valid = $self->_causal_end();
        $idx = $last_valid if defined $last_valid && $last_valid >= 0;
    }
    my $scale = $self->{_last_price_scale}
      // ( $self->{price_panel} ? $self->{price_panel}{scale} : undef );
    return unless $scale && $scale->can('y_to_value');
    my $price = $scale->y_to_value($y);
    return unless defined $idx && defined $price;

    if ( $handle eq 'p1' || $handle eq 'p2' ) {
        # Esquinas de la base: reposicionan el ancla completo (índice + precio).
        $draw->set_point( $handle, { index => $idx, price => $price } );
    }
    elsif ( $handle eq 'p3' ) {
        # Altura del lado paralela: p3 solo cambia el precio; se mantiene centrado
        # en el índice medio de la base (lo re-centra base_mid_index).
        my $mid = $draw->base_mid_index();
        $draw->set_point( 'p3', { index => $mid, price => $price } );
    }
    elsif ( $handle eq 'mid_base' ) {
        # Altura del lado base: desplaza la línea p1-p2 en vertical (conserva pendiente).
        $draw->move_base_to_price($price);
    }
    elsif ( $handle eq 'body' ) {
        # Arrastrar todo el canal por el delta desde la posición previa del cursor.
        my $last = $self->{_pchan_drag}{last};
        if ($last) {
            $draw->move_channel( $idx - $last->{index}, $price - $last->{price} );
        }
        $self->{_pchan_drag}{last} = { index => $idx, price => $price };
    }
    $self->request_render();
}

sub _pchan_click {
    my ( $self, $x, $y ) = @_;
    my $draw = $self->{pchan_drawing};
    return unless $draw && $draw->is_tool_active();

    my $idx = $self->_global_index_from_x($x);
    if ( !defined $idx ) {
        my $last_valid = $self->_causal_end();
        $idx = $last_valid if defined $last_valid && $last_valid >= 0;
    }
    return unless defined $idx;

    my $scale = $self->{_last_price_scale}
      // ( $self->{price_panel} ? $self->{price_panel}{scale} : undef );
    return unless $scale && $scale->can('y_to_value');
    my $price = $scale->y_to_value($y);
    return unless defined $price;

    my $status = $draw->add_point( { index => $idx, price => $price } );
    if ( ref( $self->{pchan_mode_callback} ) eq 'CODE' ) {
        my $active = $draw->is_tool_active() ? 1 : 0;
        my $n      = $active ? $draw->draft_count() : 3;
        $self->{pchan_mode_callback}->( $active, $n );
    }
    $self->request_render();
    return $status;
}

# ---------------------------------------------------------------------------
# Fib Retracement (drawing tool TV) — 2 clics, pick ZZ, bandas, handles
# ---------------------------------------------------------------------------
sub start_fib_retracement_tool {
    my ($self) = @_;
    return $self unless $self->{fib_drawing};
    $self->_clear_fib_follow_zz_ext();
    $self->cancel_parallel_channel_tool()
      if $self->{pchan_drawing} && $self->{pchan_drawing}->is_tool_active();
    $self->{fib_drawing}->start_tool();
    if ( ref( $self->{fib_mode_callback} ) eq 'CODE' ) {
        $self->{fib_mode_callback}->( 1, 0 );    # modo 2 clics
    }
    $self->request_render();
    return $self;
}

sub cancel_fib_retracement_tool {
    my ($self) = @_;
    return $self unless $self->{fib_drawing};
    $self->{fib_drawing}->cancel_tool();
    $self->{_fib_drag} = undef;
    if ( ref( $self->{fib_mode_callback} ) eq 'CODE' ) {
        $self->{fib_mode_callback}->( 0, 0 );
    }
    $self->request_render();
    return $self;
}

# ---------------------------------------------------------------------------
# TrendLine (drawing tool TV) — varias líneas de 2 puntos, extremos arrastrables
# ---------------------------------------------------------------------------
sub start_trendline_tool {
    my ($self) = @_;
    return $self unless $self->{trend_drawing};
    # No mezclar con otras herramientas de clic activas.
    $self->cancel_parallel_channel_tool()
      if $self->{pchan_drawing} && $self->{pchan_drawing}->is_tool_active();
    $self->cancel_fib_retracement_tool()
      if $self->{fib_drawing} && $self->{fib_drawing}->is_tool_active();
    $self->{trend_drawing}->start_tool();
    if ( ref( $self->{trend_mode_callback} ) eq 'CODE' ) {
        $self->{trend_mode_callback}->( 1, 0 );
    }
    $self->request_render();
    return $self;
}

sub cancel_trendline_tool {
    my ($self) = @_;
    return $self unless $self->{trend_drawing};
    $self->{trend_drawing}->cancel_tool();
    $self->{_trend_drag} = undef;
    if ( ref( $self->{trend_mode_callback} ) eq 'CODE' ) {
        $self->{trend_mode_callback}->( 0, 0 );
    }
    $self->request_render();
    return $self;
}

# Borra la última línea colocada (deshacer).
sub clear_last_trendline {
    my ($self) = @_;
    return $self unless $self->{trend_drawing};
    $self->{trend_drawing}->clear_last();
    $self->request_render();
    return $self;
}

# Borra todas las líneas y sale del modo tool.
sub clear_trendlines {
    my ($self) = @_;
    return $self unless $self->{trend_drawing};
    $self->{trend_drawing}->clear_all();
    $self->{trend_drawing}->cancel_tool();
    $self->{_trend_drag} = undef;
    if ( ref( $self->{trend_mode_callback} ) eq 'CODE' ) {
        $self->{trend_mode_callback}->( 0, 0 );
    }
    $self->request_render();
    return $self;
}

sub _trend_click {
    my ( $self, $x, $y ) = @_;
    my $draw = $self->{trend_drawing};
    return unless $draw && $draw->is_tool_active();

    my $idx = $self->_global_index_from_x($x);
    if ( !defined $idx ) {
        my $last_valid = $self->_causal_end();
        $idx = $last_valid if defined $last_valid && $last_valid >= 0;
    }
    return unless defined $idx;

    my $scale = $self->{_last_price_scale}
      // ( $self->{price_panel} ? $self->{price_panel}{scale} : undef );
    return unless $scale && $scale->can('y_to_value');
    my $price = $scale->y_to_value($y);
    return unless defined $price;

    my $status = $draw->add_point( { index => $idx, price => $price } );
    if ( ref( $self->{trend_mode_callback} ) eq 'CODE' ) {
        my $n = $draw->draft_count();
        $self->{trend_mode_callback}->( 1, $n );
    }
    $self->request_render();
    return $status;
}

sub _trend_hit_test {
    my ( $self, $x, $y ) = @_;
    my $ov = $self->{trend_overlay};
    return undef unless $ov && $ov->can('hit_test');
    my $scale = $self->{_last_price_scale}
      // ( $self->{price_panel} ? $self->{price_panel}{scale} : undef );
    return undef unless $scale;
    my ( $ws, $we ) = eval { $self->compute_window() };
    return $ov->hit_test( $x, $y, $scale, $ws // 0 );
}

sub _trend_drag_to {
    my ( $self, $x, $y ) = @_;
    my $handle = $self->{_trend_drag}{handle};
    return unless defined $handle;
    my $draw = $self->{trend_drawing} or return;
    my ( $li, $which ) = split /:/, $handle;
    return unless defined $li && defined $which;

    my $idx = $self->_global_index_from_x($x);
    if ( !defined $idx ) {
        my $last_valid = $self->_causal_end();
        $idx = $last_valid if defined $last_valid && $last_valid >= 0;
    }
    my $scale = $self->{_last_price_scale}
      // ( $self->{price_panel} ? $self->{price_panel}{scale} : undef );
    return unless $scale && $scale->can('y_to_value');
    my $price = $scale->y_to_value($y);
    return unless defined $idx && defined $price;

    if ( $which eq 'body' ) {
        # Arrastrar la línea entera: mover ambos extremos por el delta respecto
        # a la posición previa del cursor (index/price). Anclaje en _trend_drag.
        my $last = $self->{_trend_drag}{last};
        if ($last) {
            $draw->move_line( $li, $idx - $last->{index}, $price - $last->{price} );
        }
        $self->{_trend_drag}{last} = { index => $idx, price => $price };
    }
    else {
        $draw->set_point( $li, $which, { index => $idx, price => $price } );
    }
    $self->request_render();
}

sub clear_fib_retracement {
    my ($self) = @_;
    return $self unless $self->{fib_drawing};
    $self->_clear_fib_follow_zz_ext();
    $self->{fib_drawing}->clear_fib();
    $self->{fib_drawing}->cancel_tool();
    $self->{_fib_drag} = undef;
    if ( ref( $self->{fib_mode_callback} ) eq 'CODE' ) {
        $self->{fib_mode_callback}->( 0, 0 );
    }
    $self->request_render();
    return $self;
}

# Fib ZZ ext: re-ancla al último impulso consolidado mientras fib_follow_zz_ext=1
sub _clear_fib_follow_zz_ext {
    my ($self) = @_;
    delete $self->{fib_follow_zz_ext};
    delete $self->{_fib_zz_leg_sig};
    return $self;
}

sub _sync_fib_follow_zz_ext {
    my ($self) = @_;
    return $self unless $self->{fib_follow_zz_ext};
    return $self unless $self->{fib_drawing} && $self->{zigzag_indicator};

    my $zz = $self->{zigzag_indicator};
    $zz->set_compute_external(1) if $zz->can('set_compute_external');

    my $feed_to = $self->_causal_end();
    return $self unless defined $feed_to && $feed_to >= 0;
    $self->_feed_indicator_to( $zz, '_zigzag_fed_up_to', $feed_to );

    my $vals = $zz->get_values() || {};
    my $leg  = Market::Drawing::FibRetracement->last_impulse_zz_segment_for_fib(
        $vals->{external_segments} || []
    );
    return $self unless $leg;

    my $sig = Market::Drawing::FibRetracement->zz_leg_signature($leg);
    return $self if defined $self->{_fib_zz_leg_sig} && $self->{_fib_zz_leg_sig} eq $sig;

    $self->{fib_drawing}->set_from_zz_leg($leg);
    $self->{_fib_zz_leg_sig} = $sig;
    return $self;
}

# Fib desde el último impulso consolidado del ZZ externo (1 clic en botón UI)
sub apply_fib_last_zz_impulse {
    my ($self) = @_;
    return $self unless $self->{fib_drawing};
    $self->cancel_parallel_channel_tool()
      if $self->{pchan_drawing} && $self->{pchan_drawing}->is_tool_active();
    $self->cancel_fib_retracement_tool()
      if $self->{fib_drawing}->is_tool_active();

    if ( $self->{zigzag_indicator} && $self->{zigzag_indicator}->can('set_compute_external') ) {
        $self->set_zigzag_layer( 'EXTERNAL', 1 );
    }
    if ( ref( $self->{zz_external_ui_sync} ) eq 'CODE' ) {
        $self->{zz_external_ui_sync}->(1);
    }

    $self->set_fib_extend_to_last(1);
    $self->{fib_follow_zz_ext} = 1;
    delete $self->{_fib_zz_leg_sig};
    $self->_sync_fib_follow_zz_ext();

    if ( !$self->{fib_drawing}->get_fib() ) {
        $self->_clear_fib_follow_zz_ext();
        if ( ref( $self->{fib_mode_callback} ) eq 'CODE' ) {
            $self->{fib_mode_callback}->( 3, -1 );
        }
        $self->request_render();
        return $self;
    }

    if ( ref( $self->{fib_mode_callback} ) eq 'CODE' ) {
        $self->{fib_mode_callback}->( 0, 0 );
    }
    $self->request_render();
    return $self;
}

# Proyectar caja del fib hasta la última vela (no más allá)
sub set_fib_extend_to_last {
    my ( $self, $on ) = @_;
    return $self unless $self->{fib_drawing};
    $self->{fib_drawing}->set_extend_to_last($on);
    $self->request_render();
    return $self;
}

sub _fib_click {
    my ( $self, $x, $y ) = @_;
    my $draw = $self->{fib_drawing};
    return unless $draw && $draw->is_tool_active();

    my $idx = $self->_global_index_from_x($x);
    if ( !defined $idx ) {
        my $last_valid = $self->_causal_end();
        $idx = $last_valid if defined $last_valid && $last_valid >= 0;
    }
    return unless defined $idx;

    my $scale = $self->{_last_price_scale}
      // ( $self->{price_panel} ? $self->{price_panel}{scale} : undef );
    return unless $scale && $scale->can('y_to_value');
    my $price = $scale->y_to_value($y);
    return unless defined $price;

    my $status = $draw->add_point( { index => $idx, price => $price } );
    if ( ref( $self->{fib_mode_callback} ) eq 'CODE' ) {
        my $active = $draw->is_tool_active() ? 1 : 0;
        my $n      = $active ? $draw->draft_count() : 2;
        $self->{fib_mode_callback}->( $active, $n );
    }
    $self->request_render();
    return $status;
}

sub _fib_hit_test {
    my ( $self, $x, $y ) = @_;
    my $ov = $self->{fib_overlay};
    return undef unless $ov && $ov->can('hit_test');
    my $scale = $self->{_last_price_scale}
      // ( $self->{price_panel} ? $self->{price_panel}{scale} : undef );
    return undef unless $scale;
    my ( $ws, $we ) = eval { $self->compute_window() };
    return $ov->hit_test( $x, $y, $scale, $ws // 0 );
}

sub _fib_drag_to {
    my ( $self, $x, $y ) = @_;
    my $handle = $self->{_fib_drag}{handle} or return;
    my $draw   = $self->{fib_drawing} or return;
    my $fib    = $draw->get_fib() or return;

    $self->_clear_fib_follow_zz_ext();

    my $idx = $self->_global_index_from_x($x);
    if ( !defined $idx ) {
        my $last_valid = $self->_causal_end();
        $idx = $last_valid if defined $last_valid && $last_valid >= 0;
    }
    my $scale = $self->{_last_price_scale}
      // ( $self->{price_panel} ? $self->{price_panel}{scale} : undef );
    return unless $scale && $scale->can('y_to_value');
    my $price = $scale->y_to_value($y);

    # Solo anclas p1/p2: al moverlas, geometry_for recalcula el ancho de la caja
    if ( $handle eq 'p1' && defined $idx && defined $price ) {
        $draw->set_p1( { index => $idx, price => $price } );
    }
    elsif ( $handle eq 'p2' && defined $idx && defined $price ) {
        $draw->set_p2( { index => $idx, price => $price } );
    }
    $self->request_render();
}

# Legacy no-op (market.pl puede llamar al arranque)
sub enable_liquidity_background_feed { return $_[0]; }

1;
