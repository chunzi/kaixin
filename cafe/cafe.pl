#!/usr/bin/perl
use strict;
use WWW::Mechanize;
my $v = '';
my $mech = WWW::Mechanize->new;
$mech->get('http://wap.kaixin001.com/cafe/index.php?verify='.$v);
map {
    my $url = sprintf "http://wap.kaixin001.com%s\n", $_->url;
    print STDERR "found $url .... ";
    $mech->get($url);
    $mech->follow_link( url_regex => qr/cook/ );
    print STDERR "OK\n";
} grep { $_->url =~ /dish/ } $mech->links;


map { 
    my $url = sprintf "http://wap.kaixin001.com%s\n", $_->url;
    print STDERR "new $url .... ";
    $mech->get($url);
    my ( $qurl ) = grep { $_->url =~ /dishid=5/ } $mech->links;
#    $qurl =~ s/dishid=5/dishid=46/; # jiaozi
#    print STDERR "qurl $qurl .... ";
    $mech->get($qurl);
    print STDERR "OK\n";
} grep { $_->url =~ /menu/ } $mech->links;
