use inc::Module::Install;

name 'skypelog2html.pl';
all_from 'skypelog2html.pl';

requires 'Class::Accessor::Lite';
requires 'Data::Section::Simple';
requires 'DBIx::Simple';
requires 'Pod::Usage';
requires 'Time::Piece';

install_script 'skypelog2html.pl';

auto_install;
WriteAll;
