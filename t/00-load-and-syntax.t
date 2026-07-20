use strict;
use warnings;
use Test::More;

use lib '.';

# Producto oficial únicamente (docs/PRODUCTO_OFICIAL.md).
# Legacy está FUERA del repo (docs/LEGACY.md).

use_ok('Market::MarketData');
use_ok('Market::IndicatorManager');
use_ok('Market::Indicators::ATR');
use_ok('Market::Indicators::SMC_Pro');
use_ok('Market::Indicators::SMC_Structures_FVG');
use_ok('Market::Indicators::HLD');
use_ok('Market::Indicators::ZigZag');
use_ok('Market::Indicators::Liquidity');
use_ok('Market::Overlays::Liquidity');
use_ok('Market::Drawing::ParallelChannel');
use_ok('Market::Drawing::FibRetracement');
use_ok('Market::Panels::Scales');
use_ok('Market::ChartEngine');
use_ok('Market::Panels::PricePanel');
use_ok('Market::Panels::ATRPanel');
use_ok('Market::UI::Callbacks');

my @syntax_files = qw(
    market.pl
    Market/MarketData.pm
    Market/IndicatorManager.pm
    Market/Indicators/ATR.pm
    Market/Indicators/SMC_Pro.pm
    Market/Indicators/SMC_Structures_FVG.pm
    Market/Indicators/HLD.pm
    Market/Indicators/ZigZag.pm
    Market/Indicators/Liquidity.pm
    Market/Overlays/SMC_Pro.pm
    Market/Overlays/SMC_Structures_FVG.pm
    Market/Overlays/HLD.pm
    Market/Overlays/ZigZag.pm
    Market/Overlays/Liquidity.pm
    Market/Overlays/ParallelChannel.pm
    Market/Overlays/FibRetracement.pm
    Market/Drawing/ParallelChannel.pm
    Market/Drawing/FibRetracement.pm
    Market/Panels/Scales.pm
    Market/ChartEngine.pm
    Market/Panels/PricePanel.pm
    Market/Panels/ATRPanel.pm
    Market/UI/Callbacks.pm
);

for my $file (@syntax_files) {
    my $output = `$^X -I. -c $file 2>&1`;
    is($? >> 8, 0, "$file compila");
    like($output, qr/syntax OK/, "$file reporta syntax OK");
}

# Liquidity v2 es oficial; el resto del legacy sigue fuera del árbol.
ok( -f 'Market/Indicators/Liquidity.pm', 'Liquidity v2 indicator presente' );
ok( -f 'Market/Overlays/Liquidity.pm',   'Liquidity v2 overlay presente' );
ok( -f 'docs/LIQUIDITY_V2.md',           'spec LIQUIDITY_V2.md' );

for my $f (qw(
    Market/Indicators/Mxwll_Suite.pm
    Market/Indicators/Strategy_Builder.pm
    Market/Indicators/VolumeProfile.pm
    Market/Indicators/AnchoredVWAP.pm
    Market/Indicators/SMC_Structures.pm
    Market/Overlays/Mxwll_Suite.pm
    Market/Overlays/Strategy_Builder.pm
    Market/Overlays/VolumeProfile.pm
    Market/Overlays/AnchoredVWAP.pm
    Market/Overlays/SMC_Structures.pm
)) {
    ok( !-f $f, "ausente en producto: $f" );
}

ok( !-d 'legacy', 'carpeta legacy/ no está en el repo' );
ok( !-d 't/legacy', 'carpeta t/legacy/ no está en el repo' );
ok( -f 'docs/PRODUCTO_OFICIAL.md', 'existe PRODUCTO_OFICIAL.md' );
ok( -f 'docs/LEGACY.md', 'existe LEGACY.md (apunta fuera del repo)' );

done_testing;
