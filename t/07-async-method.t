#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 7;
use Cwd;
use Proc::Daemon;
use AnyEvent;

use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Client;

my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new(
    queue => "Test",
    exchange => "Test",
    topic => "Test.Data",
    user => "guest",
    pass => "guest",
    port => "5672"
    );

my $method = GRNOC::RabbitMQ::Method->new(
    name => "get",
    description => "get data from queue",
    async => 1,
    callback => sub { my $method_ref = shift; my $p_ref = shift; $method_ref->{'success_callback'}({success => 1}) },
    );
$dispatcher->register_method($method);

$method = GRNOC::RabbitMQ::Method->new(
    name => "plus",
    description => "adds two numbers",
    async => 1,
    callback => sub { my $mref = shift; my $pref = shift; $mref->{'success_callback'}( $pref->{'a'}{'value'} + $pref->{'b'}{'value'}); });
$method->add_input_parameter(
    name => 'a',
    description => "first addend",
    pattern => '^(-?[0-9]+)$' );
$method->add_input_parameter(
    name => 'b',
    description => "second addend",
    pattern => '^(-?[0-9]+)$' );
$dispatcher->register_method($method);

my $client = GRNOC::RabbitMQ::Client->new(
    topic => "Test.Data",
    exchange => "Test",
    user => "guest",
    pass => "guest"
    );

my $res;
$client->get(async_callback => sub {
    $res = shift;
    $dispatcher->stop_consuming();
	     });

$dispatcher->start_consuming();

ok(defined($res), "Res was defined");
ok(defined($res->{'results'}), "Results was defined");
ok(($res->{'results'}->{'success'}), "client can talk to dispatcher");

$client->help( async_callback => sub {
    $res = shift;
    $dispatcher->stop_consuming();
               });

$dispatcher->start_consuming();

ok((scalar @{$res->{'results'}} == 3), "confirm three registered methods");
ok((grep {$_ eq "Test.Data.help"} @{$res->{'results'}}), "help is a method");
ok((grep {$_ eq "Test.Data.get"} @{$res->{'results'}}), "get is a method");
ok((grep {$_ eq "Test.Data.plus"} @{$res->{'results'}}), "plus is a method");
