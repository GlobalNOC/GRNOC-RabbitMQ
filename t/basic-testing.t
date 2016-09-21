#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Test::More tests => 12;

use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Client;

sub tester {
    return {success => 1};
}

######################
### Dispatcher Creation
######################
eval {
    my $bad_dispatcher = GRNOC::RabbitMQ::Dispatcher->new(
	queue => "Test",
	exchange => "Test",
	topic => "Test.Data",
	user => "guest",
	pass => "guest",
	port => "5671"
	);
};
ok($@, "fatal error for failed Rabbit connect");

my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new(
    queue => "Test",
    exchange => "Test",
    topic => "Test.Data",
    user => "guest",
    pass => "guest",
    port => "5672"
    );
ok(defined($dispatcher), "got a dispatcher");

#######################
### Client Creation
#######################
eval {
    my $bad_client = GRNOC::RabbitMQ::Client->new();
};
ok($@, "fatal error for invalid client");

my $client = GRNOC::RabbitMQ::Client->new(
    topic => "Test.Data",
    exchange => "Test",
    user => "guest",
    pass => "guest"
    );
ok($client, "Client exists");

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
my $res = $client->bad_method();
ok($res->{'error'}, "bad method call fails");

$res = $client->tester();
ok($res->{'results'}, "good method call works");

