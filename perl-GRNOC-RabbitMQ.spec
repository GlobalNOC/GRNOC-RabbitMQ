%global debug_package %{nil} # Don't generate debug info
%global _binaries_in_noarch_packages_terminate_build   0
AutoReqProv: no # Keep rpmbuild from trying to figure out Perl on its own

Summary: GRNOC RabbitMQ Perl Libraries
Name: perl-GRNOC-RabbitMQ
Version: 1.2.2
Release: 1%{?dist}
License: APL 2.0
Group: Network
URL: http://globalnoc.iu.edu
Source0: %{name}-%{version}.tar.gz
BuildRoot: %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
BuildArch:noarch

BuildRequires: perl
Requires: perl-GRNOC-Log
Requires: perl-GRNOC-WebService

%description
The GRNOC::RabbitMQ collection is a set of perl modules which are used to
provide and interact with GRNOC RabbitMQ services.

%prep
%setup -q -n perl-GRNOC-RabbitMQ-%{version}

%build

%install
rm -rf %{buildroot}

%{__install} -d -p %{buildroot}/%{perl_vendorlib}/GRNOC/RabbitMQ/
%{__install} -d -p %{buildroot}/opt/grnoc/venv/%{name}/lib/perl5

%{__install} lib/GRNOC/RabbitMQ.pm %{buildroot}/%{perl_vendorlib}/GRNOC
%{__install} lib/GRNOC/RabbitMQ/Client.pm %{buildroot}/%{perl_vendorlib}/GRNOC/RabbitMQ
%{__install} lib/GRNOC/RabbitMQ/Dispatcher.pm %{buildroot}/%{perl_vendorlib}/GRNOC/RabbitMQ
%{__install} lib/GRNOC/RabbitMQ/Method.pm %{buildroot}/%{perl_vendorlib}/GRNOC/RabbitMQ

# add virtual environment files
cp -r venv/lib/perl5/* -t %{buildroot}/opt/grnoc/venv/%{name}/lib/perl5

# clean up buildroot
find %{buildroot} -name .packlist -exec %{__rm} {} \;

%{_fixperms} $RPM_BUILD_ROOT/*

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(644, root, root, -)
%{perl_vendorlib}/GRNOC/RabbitMQ.pm
%{perl_vendorlib}/GRNOC/RabbitMQ/Dispatcher.pm
%{perl_vendorlib}/GRNOC/RabbitMQ/Method.pm
%{perl_vendorlib}/GRNOC/RabbitMQ/Client.pm

%defattr(644, root, root, 755)
/opt/grnoc/venv/%{name}/lib/perl5/*
