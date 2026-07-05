package Market::UI::ReplayGotoMenu;
use strict;
use warnings;
use utf8;

use Market::UI::Callbacks;

# Market::UI::ReplayGotoMenu — dropdown "SELECT STARTING POINT" (task 0044).
# Frame con place sobre el boton "v"; sin Optionmenu. Etiquetas ASCII (0048).

sub expected_menu_labels {
    return (
        'SELECT STARTING POINT',
        '|< Bar',
        'Date...',
        'First available date',
        'Random bar',
    );
}

sub new {
    my ($class, %args) = @_;
    my $parent = $args{parent} or die "ReplayGotoMenu: requiere parent";
    my $chart  = $args{chart}  or die "ReplayGotoMenu: requiere chart";
    my $vars   = $args{ui_vars} || {};
    my $mw     = $args{mw};
    my $root   = $args{root} || $mw || $parent;

    my $frame = $parent->Frame(
        -background => '#ffffff',
        -relief     => 'solid',
        -bd         => 1,
    );
    $frame->Label(
        -text       => 'SELECT STARTING POINT',
        -font       => 'Helvetica 8',
        -foreground => '#888888',
        -background => '#ffffff',
    )->pack(-fill => 'x', -padx => 6, -pady => [4, 2]);

    my $self = bless {
        frame   => $frame,
        parent  => $parent,
        root    => $root,
        chart   => $chart,
        mw      => $mw,
        ui_vars => $vars,
        anchor  => undef,
        visible => 0,
    }, $class;

    my $row_opts = sub {
        my ($label, $cb) = @_;
        return $frame->Button(
            -text             => $label,
            -command          => sub { $cb->(); $self->hide() },
            -relief           => 'flat',
            -anchor           => 'w',
            -padx             => 8,
            -pady             => 2,
            -background       => '#ffffff',
            -activebackground => '#e8e8e8',
            -width            => 22,
        );
    };

    $row_opts->('|< Bar', Market::UI::Callbacks->make_replay_goto_bar($chart, $vars))
        ->pack(-fill => 'x');
    $row_opts->('Date...', Market::UI::Callbacks->make_replay_goto_date($chart, $mw, $vars))
        ->pack(-fill => 'x');
    $row_opts->('First available date', Market::UI::Callbacks->make_replay_goto_first($chart, $vars))
        ->pack(-fill => 'x');
    $row_opts->('Random bar', Market::UI::Callbacks->make_replay_goto_random($chart, $vars))
        ->pack(-fill => 'x');

    $frame->placeForget();
    return $self;
}

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

    my $menu = $self->{frame};
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