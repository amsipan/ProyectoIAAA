use strict;
use warnings;
use Test::More;

use lib '.';

# Producto oficial únicamente (docs/PRODUCTO_OFICIAL.md).
# Legacy en legacy/ y t/legacy/ no se carga aquí.

use_ok('Market::MarketData');
use_ok('Market::IndicatorManager');
use_ok('Market::Indicators::ATR');
use_ok('Market::Indicators::SMC_Pro');
use_ok('Market::Indicators::SMC_Structures_FVG');
use_ok('Market::Indicators::HLD');
use_ok('Market::Indicators::ZigZag');
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
    Market/Overlays/SMC_Pro.pm
    Market/Overlays/SMC_Structures_FVG.pm
    Market/Overlays/HLD.pm
    Market/Overlays/ZigZag.pm
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

# Asegurar que no se cargan módulos legacy en el árbol principal
ok( !-f 'Market/Indicators/Liquidity.pm', 'Liquidity no está en Indicators/ (cuarentena legacy/)' );
ok( !-f 'Market/Indicators/Mxwll_Suite.pm', 'Mxwll no está en Indicators/' );
ok( -f 'legacy/Market/Indicators/Liquidity.pm', 'Liquidity cuarentenado en legacy/' );
ok( -f 'docs/PRODUCTO_OFICIAL.md', 'existe PRODUCTO_OFICIAL.md' );
ok( -f 'docs/LEGACY.md', 'existe LEGACY.md' );

done_testing;
