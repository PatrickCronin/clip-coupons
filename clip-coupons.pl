#!/usr/bin/perl

use Modern::Perl;

package CouponClipper;

use Moo;

use Config::INI::Reader ();
use Const::Fast 'const';
use Mojo::DOM ();
use Ref::Util 'is_plain_arrayref';
use WWW::Mechanize ();

const my $CRED_USERNAME_VAR => 'CC_USERNAME';
const my $CRED_PASSWORD_VAR => 'CC_PASSWORD';
const my $CRED_FILE => '/etc/clip-coupons.ini';

has _creds => (
    is => 'ro',
    isa => sub {
        die '_creds must be a ref to an array of two values'
            if ! is_plain_arrayref($_[0])
            && @{ $_[0] } != 2;
    },
    builder => '_build__creds',
);

has _mech => (
    is => 'ro',
    isa => sub {
        die '_mech must be a WWW::Mechanize instance'
            if ! ref $_[0] eq 'WWW::Mechanize';
    },
    default => sub {
        my $mech = WWW::Mechanize->new(autocheck => 1);
        $mech->agent_alias('Mac Safari');
        return $mech;
    },
);

sub _build__creds {
    my $self = shift;
    
    my ($username, $password) = @ENV{ $CRED_USERNAME_VAR, $CRED_PASSWORD_VAR };
    return [$username, $password] if defined $username && defined $password;
    
    my $c = Config::INI::Reader->read_file($CRED_FILE);
    if (exists $c->{_}{$CRED_USERNAME_VAR} && exists $c->{_}{$CRED_PASSWORD_VAR}) {
        return [ @{ $c->{_} }{ $CRED_USERNAME_VAR, $CRED_PASSWORD_VAR } ];
    }
    
    die "Unable to find viable credentials\n";
}

sub run {
    my $self = shift;
    
    $self->login;
    $self->maybe_activate_rewards;
    $self->clip_unclipped_coupons;
    $self->logout;
}

sub login {
    my $self = shift;
    
    $self->_mech->get('https://www.hannaford.com/login');
    $self->_mech->submit_form(
        with_fields => {
            userName => $self->_creds->[0],
            password => $self->_creds->[1],
        },
    );
    $self->_mech->submit;
}

sub maybe_activate_rewards {
    my $self = shift;

    $self->_mech->get('/includes/myaccount_include_rewards.jsp?location=my%20account%20layer');
    my $link = $self->_mech->find_link( id => 'activateRewards' );

    if ($link) {
        print "Activating rewards.\n";
        $self->_mech->get( $link->url() );
    }
    else {
        print "No rewards to activate.\n";
    }
}

sub clip_unclipped_coupons {
    my $self = shift;
    
    $self->_mech->get('/coupons');
    $self->clip_coupons_on_page();
}

sub clip_coupons_on_page {
    my $self = shift;
    
    printf "Clipping coupons on %s\n", $self->_mech->uri;

    my $dom = Mojo::DOM->new( $self->_mech->content );

    my @coupons;
    $dom->find( 'div.couponTile[data-clipped="false"]' )
        ->each( sub {
            push @coupons, {
                id      => $_[0]->attr('data-tileid'),
                offer   => $_[0]->at('p.summary')->text,
                product => $_[0]->at('p.brand')->text,
            };
        } );

    foreach my $coupon (@coupons) {
        printf "%s on %s\n", $coupon->{offer}, $coupon->{product};
        $self->_mech->get( sprintf('/user/clip_coupon.cmd?offerId=%s', $coupon->{id}) );
        sleep 1 + int rand 10;
    }
}

sub logout {
    my $self = shift;
    
    $self->_mech->get('/user/logout.cmd');
}

1;

package main;

use CouponClipper;

binmode(STDOUT, ':utf8');
CouponClipper->new->run;
