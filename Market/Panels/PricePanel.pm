package Market::Panels::PricePanel;
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
sub _init_crosshair_objects {
my ($self) = @_;
# TODO
}
sub round {
my ($self, $value) = @_;
# TODO
}
sub render {
my ($self, $canvas, $data, $scale) = @_;
# TODO
}
sub render_last_visible_price {
my ($self, $canvas) = @_;
# TODO
}
sub get_y_range {
my ($self, $data) = @_;
# TODO
}
sub set_scale {
my ($self, $scale) = @_;
# TODO
}
sub draw_crosshair {
my ($self, $x, $y) = @_;
# TODO
}
sub draw_time_axis {
my ($self, $canvas, $timestamps) = @_;
# TODO
}
1;