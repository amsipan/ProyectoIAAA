#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use lib '.';

BEGIN {
    package Tk;
    sub bind {
        my $w = shift;
        my ($seq, $cb) = @_;
        if (ref($w) eq 'MockDropdownRoot') {
            $w->{binds}{$seq} = $cb;
        }
        return;
    }
}

use Market::UI::ReplayDropdown;

# task 0045: race click-fuera en dropdowns Replay (Fedora35 Tk).

{
    package MockWidgetTree;
    sub new { bless { parent => $_[1] }, shift }
    sub Parent { shift->{parent} }

    package main;

    my $root = MockWidgetTree->new(undef);
    my $mid  = MockWidgetTree->new($root);
    my $leaf = MockWidgetTree->new($mid);

    ok(Market::UI::ReplayDropdown::_widget_contains($leaf, $leaf), 'widget_contains: self');
    ok(Market::UI::ReplayDropdown::_widget_contains($leaf, $mid), 'widget_contains: child of mid');
    ok(Market::UI::ReplayDropdown::_widget_contains($leaf, $root), 'widget_contains: grandchild');
    ok(!Market::UI::ReplayDropdown::_widget_contains($mid, $leaf), 'widget_contains: parent not in child');
    ok(!Market::UI::ReplayDropdown::_widget_contains(undef, $root), 'widget_contains: undef leaf');
}

{
    package MockDropdownRoot;
    sub new { bless { binds => {}, after_q => [] }, shift }
    sub exists { return 1 }
    sub rootx { return 0 }
    sub rooty { return 0 }
    sub pointerx { return 0 }
    sub pointery { return 0 }
    sub containing { return undef }
    sub after {
        my ($self, $ms, $cb) = @_;
        push @{ $self->{after_q} }, $cb if $cb;
        return scalar @{ $self->{after_q} };
    }
    sub afterCancel { return }

    package MockDropdownParent;
    sub new { bless {}, shift }
    sub exists { return 1 }
    sub rootx { return 0 }
    sub rooty { return 0 }
    sub Frame {
        my ($p, %o) = @_;
        return bless { parent => $p, opts => \%o, placed => 0 }, 'MockDropdownFrame';
    }

    package MockDropdownFrame;
    sub idletasks { return }
    sub reqheight { return 80 }
    sub rootx { return 10 }
    sub rooty { return 20 }
    sub exists { return 1 }
    sub place { my ($s, %o) = @_; $s->{placed} = 1; $s->{place_opts} = \%o; return $s }
    sub placeForget { my ($s) = @_; $s->{placed} = 0; return $s }

    package MockDropdownAnchor;
    sub new { bless {}, shift }
    sub exists { return 1 }
    sub rootx { return 50 }
    sub rooty { return 40 }

    package main;

    my $root   = MockDropdownRoot->new();
    my $parent = MockDropdownParent->new();
    my $menu   = Market::UI::ReplayDropdown->new(parent => $parent, root => $root);
    my $anchor = MockDropdownAnchor->new();
    $menu->set_anchor($anchor);

    ok(!$menu->is_visible(), 'dropdown: oculto al crear');
    $menu->show();
    ok($menu->is_visible(), 'dropdown: show marca visible');
    ok($menu->{frame}{placed}, 'dropdown: frame colocado');
    ok(!exists $root->{binds}{'<Button-1>'}, 'dropdown: bind NO sincrono tras show (diferido)');

    my $cb = shift @{ $root->{after_q} };
    ok(ref($cb) eq 'CODE', 'dropdown: after(1) programado');
    $cb->();
    ok(exists $root->{binds}{'<Button-1>'}, 'dropdown: bind instalado tras after(1)');

    $menu->hide();
    ok(!$menu->is_visible(), 'dropdown: hide marca oculto');
    ok(!$menu->{frame}{placed}, 'dropdown: frame des-colocado');
}

done_testing();