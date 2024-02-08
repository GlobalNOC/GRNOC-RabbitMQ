NAME=perl-GRNOC-RabbitMQ
VERSION=1.2.2

.PHONY: all

test: venv
	/usr/bin/perl -I ./lib -I ./venv/lib/perl5 t/TEST $(TEST_VERBOSE)

rpm: dist
	cd dist; tar -czvf $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)
	rpmbuild -ta  dist/$(NAME)-$(VERSION).tar.gz

clean:
	rm -rf dist/$(NAME)-$(VERSION)/
	rm -rf dist

dist: clean venv
	mkdir -p dist/$(NAME)-$(VERSION)/
	cp -rv lib venv $(NAME).spec dist/$(NAME)-$(VERSION)/
	cd dist; tar -czvf $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)/

venv:
	carton install --path=venv