package Market::Panels::ATRPanel;
use strict;
use warnings;

sub new {
my ($class, %args) = @_;
my $self = {
%args,
};
bless $self, $class;
return $self;
}
sub _init_crosshair {
my ($self) = @_;
# TODO
}
sub get_y_range {
my ($self, $values) = @_;
# TODO
}
sub set_scale {
my ($self, $scale) = @_;
# TODO
}
sub render {
my ($self, $canvas, $values, $scale) = @_;
# TODO
}
sub render_last_visible_value {
my ($self, $canvas) = @_;
# TODO
}
sub draw_crosshair {
my ($self, $x, $y) = @_;
# TODO
}
1;