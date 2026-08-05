package Market::Overlays::Base;
use strict;
use warnings;

# Contrato base de overlays (visible / compute / draw).

sub validate {
    my ($class, $overlay) = @_;
    die "overlay does not implement set_visible"   unless $overlay->can('set_visible');
    die "overlay does not implement is_visible"    unless $overlay->can('is_visible');
    die "overlay does not implement compute_visible" unless $overlay->can('compute_visible');
    die "overlay does not implement draw"          unless $overlay->can('draw');
    die "overlay does not implement clear"         unless $overlay->can('clear');
    die "overlay does not implement tag"           unless $overlay->can('tag');
    return 1;
}

1;
