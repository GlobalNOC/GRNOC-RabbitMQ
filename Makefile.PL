use strict;
use warnings;
use ExtUtils::MakeMaker;

sub MY::postamble { << 'END';}
rpm:    dist
	rpmbuild -ta perl-GRNOC-RabbitMQ-$(VERSION).tar.gz
END

WriteMakefile(
    NAME                => 'perl-GRNOC-RabbitMQ',
    AUTHOR              => 'GRNOC Systems Engineering <syseng@grnoc.iu.edu>',
    VERSION_FROM        => 'lib/GRNOC/RabbitMQ.pm',
    PL_FILES            => {},
    PREREQ_PM => {
	'AnyEvent::RabbitMQ' => 0,
	'GRNOC::Log' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'perl-GRNOC-RabbitMQ-*' },
    );

sub MY::test
{
    q(
TEST_VERBOSE=1
test : pure_all
	$(FULLPERL) t/TEST $(TEST_VERBOSE)

test_jenkins : pure_all
	$(FULLPERL) t/TEST $(TEST_VERBOSE) --formatter=TAP::Formatter::Console

    );
}


