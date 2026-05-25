package Market::Panels::Scales;
use strict;
use warnings;

# Inicializa el sistema de coordenadas para un panel.
# Argumentos que llegan desde ChartEngine::render():
#   min_y  => valor mínimo del eje Y (precio o indicador)
#   max_y  => valor máximo del eje Y
#   bars   => cantidad de barras visibles en la ventana
# Los atributos width y height son inyectados por los paneles en render()
# al llamar: $scale->{width} = $canvas->width(); $scale->{height} = $canvas->height();
sub new {
    my ($class, %args) = @_;
    my $self = {
        %args,
    };
    bless $self, $class;
    return $self;
}

# Convierte un índice de barra (0-based) al borde izquierdo de esa barra en píxeles X.
sub index_to_x {
    my ($self, $index) = @_;
    my $bars  = $self->{bars} || 1;
    my $bar_w = $self->{width} / $bars;
    return $index * $bar_w;
}PM 

# Convierte una coordenada X en píxeles al índice de barra más cercano (entero).
sub x_to_index {
    my ($self, $x) = @_;
    my $bars  = $self->{bars} || 1;
    my $bar_w = $self->{width} / $bars;
    return 0 if $bar_w <= 0;
    my $idx = int($x / $bar_w);
    $idx = 0         if $idx < 0;
    $idx = $bars - 1 if $idx >= $bars;
    return $idx;
}

# Convierte X a índice en punto flotante (mayor precisión para el crosshair).
sub x_to_index_float {
    my ($self, $x) = @_;
    my $bars  = $self->{bars} || 1;
    my $bar_w = $self->{width} / $bars;
    return 0 if $bar_w <= 0;
    return $x / $bar_w;
}

# Devuelve la coordenada X del centro horizontal de una barra.
# Usado para dibujar mechas de velas y puntos de la línea ATR.
sub index_to_center_x {
    my ($self, $index) = @_;
    my $bars  = $self->{bars} || 1;
    my $bar_w = $self->{width} / $bars;
    return $index * $bar_w + $bar_w / 2;
}

# Mapea un valor financiero (precio/indicador) a coordenada Y en píxeles.
# max_y queda en Y=0 (arriba del canvas) y min_y en Y=height (abajo).
sub value_to_y {
    my ($self, $value) = @_;
    my $range = $self->{max_y} - $self->{min_y};
    return 0 if $range == 0;
    return (($self->{max_y} - $value) / $range) * $self->{height};
}

# Operación inversa: convierte una coordenada Y en píxeles al valor financiero.
# Usado por draw_crosshair para mostrar el precio o ATR bajo el cursor.
sub y_to_value {
    my ($self, $y) = @_;
    my $range = $self->{max_y} - $self->{min_y};
    return $self->{min_y} unless $self->{height};
    return $self->{max_y} - ($y / $self->{height}) * $range;
}

# Dibuja el eje Y: líneas de cuadrícula horizontales y etiquetas de valor
# en el margen derecho del canvas.
sub _draw_y_scale {
    my ($self, $canvas) = @_;
    return unless defined $canvas;

    $canvas->delete('y_scale');

    my $width  = $self->{width};
    my $height = $self->{height};
    my $min    = $self->{min_y};
    my $max    = $self->{max_y};
    my $range  = $max - $min;
    return if $range == 0;

    # Calcular paso "limpio" para que las etiquetas no se solapen
    my $raw_step   = $range / 5;
    my $exp        = int(log($raw_step + 1e-10) / log(10));
    my $magnitude  = 10 ** $exp;
    my $nice_step  = $magnitude * int($raw_step / $magnitude + 0.5);
    $nice_step     = $magnitude if $nice_step <= 0;

    # Primer valor por encima de min_y que sea múltiplo del paso
    my $start_val = $nice_step * int($min / $nice_step + 1e-10);
    $start_val += $nice_step if $start_val < $min - 1e-10;

    my $val = $start_val;
    while ($val <= $max + 1e-10) {
        my $y = $self->value_to_y($val);

        # Línea de cuadrícula horizontal
        $canvas->createLine(
            0, $y, $width, $y,
            -fill => '#2a2a2a',
            -tags => 'y_scale',
        );

        # Etiqueta numérica en el margen derecho
        my $label = ($val >= 100) ? sprintf("%.2f", $val) : sprintf("%.4f", $val);
        $canvas->createText(
            $width - 2, $y,
            -text   => $label,
            -anchor => 'e',
            -font   => 'Helvetica 8',
            -fill   => '#888888',
            -tags   => 'y_scale',
        );

        $val += $nice_step;
    }
}

1;
