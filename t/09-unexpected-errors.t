#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 5;
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
    callback => sub { return {success => 1}; },
    );
$dispatcher->register_method($method);

$method = GRNOC::RabbitMQ::Method->new(
    name => "plus",
    description => "adds two numbers",
    callback => sub { my $mref = shift; my $pref = shift; return $pref->{'a'}{'value'} + $pref->{'b'}{'value'}});
$method->add_input_parameter(
    name => 'a',
    description => "first addend",
    pattern => '^(-?[0-9]+)$' );
$method->add_input_parameter(
    name => 'b',
    description => "second addend",
    pattern => '^(-?[0-9]+)$' );
$dispatcher->register_method($method);

$dispatcher->methods->{'Test.Data.plus'} = undef;
delete $dispatcher->methods->{'Test.Data.plus'};

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

$client->plus( a => 1,
               b => 2,
               async_callback => sub {
                   $res = shift;
                   $dispatcher->stop_consuming();
               });

$dispatcher->start_consuming();

warn Data::Dumper::Dumper($res);

ok($res->{'error'}, "Error was returned");
ok($res->{'error_text'} eq 'unknown method: Test.Data.plus', "proper error message was returned");
