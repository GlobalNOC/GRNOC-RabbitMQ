#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Test::More tests => 14;

use GRNOC::Log;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Client;

GRNOC::Log->new( level => 'DEBUG');

sub tester {
    return {success => 1};
}

######################
### Dispatcher Creation
######################
my $bad_dispatcher;
eval{
$bad_dispatcher = GRNOC::RabbitMQ::Dispatcher->new(
    queue_name => "Test",
    exchange => "Test",
    user => "foobar",
    pass => "foobar",
    port => "5671"
    );
};

ok(!defined($bad_dispatcher), "Failure to create was ok");

my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new(
    queue_name => "Test",
    exchange => "Test",
    topic => "Test.Data",
    user => "guest",
    pass => "guest",
    port => "5672"
    );

ok(defined($dispatcher), "got a dispatcher");
ok($dispatcher->connected, "is connected");


#######################
### Client Creation
#######################

my $bad_client;
eval {
    $bad_client = GRNOC::RabbitMQ::Client->new();
};

ok(!defined($bad_client), "Was not able to create a bad client");

my $client = GRNOC::RabbitMQ::Client->new(
    timeout => 1,
    topic => "Test.Data",
    exchange => "Test",
    user => "guest",
    pass => "guest"
    );

ok($client, "Client exists");
ok($client->connected, "Client is connected");
######################
### Method Creation
######################
eval {
    my $bad_method = GRNOC::RabbitMQ::Method->new(
	name => "tester",
	callback => \&tester,
    );

};
ok($@, "fatal error for no method description");

eval {
    my $bad_method = GRNOC::RabbitMQ::Method->new(
	name => "tester",
	description => "Tester Method"
    );

};
ok($@, "fatal error for no method callback");

eval {
    my $bad_method = GRNOC::RabbitMQ::Method->new(
	callback => \&tester,
	description => "Tester Method"
    );
};
ok($@, "fatal error for no method name");

my $method = GRNOC::RabbitMQ::Method->new(
    name => "tester",
    callback => \&tester,
    description => "Tester Method"
    );

ok(defined($method), "got a method");

#####################
### Method Registration
#####################
eval {
    $dispatcher->register_method("bad method");
};
ok($@, "fatal error registering  invalid method");

my $register = $dispatcher->register_method($method);
ok($register, "method registered");

####################
### Client Calling Methods
####################
my $res;
$res = $client->bad_method();
ok($res->{'error'}, "bad method call fails");


$client->tester( async_callback => sub { $res = shift; $dispatcher->stop_consuming(); });
$dispatcher->start_consuming();

warn Dumper($res);
ok($res->{'results'});

