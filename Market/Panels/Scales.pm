package Market::Panels::Scales;
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
sub index_to_x {
my ($self, $index) = @_;
# TODO
}
sub x_to_index {
my ($self, $x) = @_;
# TODO
}
sub x_to_index_float {
my ($self, $x) = @_;
# TODO
}
sub index_to_center_x {
my ($self, $index) = @_;
# TODO
}
sub value_to_y {
my ($self, $value) = @_;
# TODO
}
sub y_to_value {
my ($self, $y) = @_;
# TODO
}
sub _draw_y_scale {
my ($self, $canvas) = @_;
# TODO
}
1;