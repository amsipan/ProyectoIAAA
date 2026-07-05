package Market::UI::ReplayDropdown;
use strict;
use warnings;
use utf8;

# Market::UI::ReplayDropdown — base place/toggle/click-outside (tasks 0044/0045/0049).

sub new {
    my ($class, %args) = @_;
    my $parent = $args{parent} or die "ReplayDropdown: requiere parent";
    my $root   = $args{root} || $parent;

    my $frame = $parent->Frame(
        -background => '#ffffff',
        -relief     => 'solid',
        -bd         => 1,
    );

    return bless {
        frame   => $frame,
        parent  => $parent,
        root    => $root,
        anchor  => undef,
        visible => 0,
    }, $class;
}

sub frame { shift->{frame} }

sub set_anchor {
    my ($self, $widget) = @_;
    $self->{anchor} = $widget if defined $widget;
    return $self;
}

sub toggle {
    my ($self, $anchor) = @_;
    $self->set_anchor($anchor) if defined $anchor;
    return $self->hide() if $self->{visible};
    return $self->show();
}

sub show {
    my ($self) = @_;
    my $anchor = $self->{anchor};
    return $self unless $anchor && eval { $anchor->exists };

    $self->{frame}->idletasks();
    my $menu_h = $self->{frame}->reqheight() || 120;
    my $ax = $anchor->rootx() - $self->{parent}->rootx();
    my $ay = $anchor->rooty() - $self->{parent}->rooty();
    $self->{frame}->place(
        -x      => $ax,
        -y      => $ay - $menu_h - 2,
        -anchor => 'sw',
    );
    $self->{visible} = 1;
    $self->_install_outside_bind();
    return $self;
}

sub hide {
    my ($self) = @_;
    $self->{frame}->placeForget();
    $self->{visible} = 0;
    $self->_remove_outside_bind();
    return $self;
}

sub is_visible {
    my ($self) = @_;
    return $self->{visible} ? 1 : 0;
}

sub _install_outside_bind {
    my ($self) = @_;
    return if $self->{_outside_bound};
    my $root = $self->{root};
    return unless $root && eval { $root->exists };

    my $menu   = $self->{frame};
    my $anchor = $self->{anchor};
    $self->{_outside_cb} = sub {
        return unless $self->{visible};
        my $w = eval { $root->containing($root->pointerx, $root->pointery) };
        while (defined $w) {
            return if defined $menu && $w == $menu;
            return if defined $anchor && $w == $anchor;
            my $parent = eval { $w->Parent };
            last if !defined $parent || $w eq $parent;
            $w = $parent;
        }
        $self->hide();
    };
    $root->Tk::bind('<Button-1>', $self->{_outside_cb});
    $self->{_outside_bound} = 1;
    return;
}

sub _remove_outside_bind {
    my ($self) = @_;
    return unless $self->{_outside_bound};
    my $root = $self->{root};
    if ($root && $self->{_outside_cb}) {
        eval { $root->Tk::bind('<Button-1>', '') };
    }
    delete $self->{_outside_cb};
    $self->{_outside_bound} = 0;
    return;
}

1;