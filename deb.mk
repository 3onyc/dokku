BUILDSTEP_DESCRIPTION = 'Buildstep uses Docker and Buildpacks to build applications like Heroku'
BUILDSTEP_REPO_NAME ?= progrium/buildstep
BUILDSTEP_VERSION ?= 0.0.1
BUILDSTEP_ARCHITECTURE = amd64
BUILDSTEP_PACKAGE_NAME = buildstep_$(BUILDSTEP_VERSION)_$(BUILDSTEP_ARCHITECTURE).deb

DOKKU_DESCRIPTION = 'Docker powered mini-Heroku in around 100 lines of Bash'
DOKKU_REPO_NAME ?= progrium/dokku
DOKKU_ARCHITECTURE = amd64

PLUGINHOOK_DESCRIPTION = 'Simple dispatcher and protocol for shell-based plugins, an improvement to hook scripts'
PLUGINHOOK_REPO_NAME ?= progrium/pluginhook
PLUGINHOOK_VERSION ?= 0.0.1
PLUGINHOOK_ARCHITECTURE = amd64
PLUGINHOOK_PACKAGE_NAME = pluginhook_$(PLUGINHOOK_VERSION)_$(PLUGINHOOK_ARCHITECTURE).deb

SSHCOMMAND_DESCRIPTION = 'Turn SSH into a thin client specifically for your app'
SSHCOMMAND_REPO_NAME ?= progrium/sshcommand
SSHCOMMAND_VERSION ?= 0.0.1
SSHCOMMAND_ARCHITECTURE = amd64
SSHCOMMAND_PACKAGE_NAME = sshcommand_$(SSHCOMMAND_VERSION)_$(SSHCOMMAND_ARCHITECTURE).deb

GEM_ARCHITECTURE = amd64

GOROOT = /usr/lib/go
GOBIN = /usr/bin/go
GOPATH = /home/vagrant/gocode

.PHONY: install-from-deb deb-all deb-buildstep deb-dokku deb-gems deb-pluginhook deb-setup deb-sshcommand

install-from-deb:
	echo "--> Initial apt-get update"
	sudo apt-get update -qqy
	sudo apt-get install -qqy apt-transport-https curl

	echo "--> Installing docker gpg key"
	curl --silent https://get.docker.com/gpg 2> /dev/null | apt-key add - 2>&1 >/dev/null

	echo "--> Installing dokku gpg key"
	curl --silent https://packagecloud.io/gpg.key 2> /dev/null | apt-key add - 2>&1 >/dev/null

	echo "--> Setting up apt repositories"
	echo "deb http://get.docker.io/ubuntu docker main" > /etc/apt/sources.list.d/docker.list
	echo "deb https://packagecloud.io/dokku/dokku/ubuntu/ trusty main" > /etc/apt/sources.list.d/dokku.list

	echo "--> Running apt-get update"
	sudo apt-get update > /dev/null

	echo "--> Installing pre-requisites"
	sudo apt-get install -y linux-image-extra-`uname -r`

	echo "--> Installing dokku"
	sudo apt-get install -y dokku

	echo "--> Done!"

deb-all: deb-buildstep deb-dokku deb-gems deb-pluginhook deb-sshcommand
	echo "Done"

deb-setup:
	echo "-> Updating deb repository and installing build requirements"
	[ -n "$(SKIP_APT_UPDATE)" ] || sudo apt-get update > /dev/null

	[ -f /usr/include/ruby-1.9.1/ruby.h ] || sudo apt-get install -qqy ruby1.9.1-dev
	which git 2>&1 >/dev/null || sudo apt-get install -qqy git
	which gcc 2>&1 >/dev/null || sudo apt-get install -qqy gcc
	which fpm 2>&1 >/dev/null || sudo gem install fpm --no-ri --no-rdoc

	## Disabled for now, not sure what original goal was
	# ssh -o StrictHostKeyChecking=no git@github.com || true

	mkdir -p /vagrant/pkg /tmp/gems /tmp/src

deb-buildstep: deb-setup
	rm -rf /tmp/tmp /tmp/build && mkdir -p /tmp/tmp /tmp/build

	echo "-> Creating deb files"
	echo "#!/usr/bin/env bash" >> /tmp/tmp/post-install
	echo "sleep 5" >> /tmp/tmp/post-install
	echo "count=\`sudo docker images | grep progrium/buildstep | wc -l\`" >> /tmp/tmp/post-install
	echo 'if [ "$$count" -ne 0 ]; then' >> /tmp/tmp/post-install
	echo "  echo 'Removing old buildstep image'" >> /tmp/tmp/post-install
	echo "  sudo docker rmi progrium/buildstep" >> /tmp/tmp/post-install
	echo "fi" >> /tmp/tmp/post-install
	echo "echo 'Importing buildstep into docker (around 5 minutes)'" >> /tmp/tmp/post-install
	echo "sudo docker build -t progrium/buildstep /var/lib/buildstep 1> /dev/null" >> /tmp/tmp/post-install

	echo "-> Cloning repository"
	[ -d /tmp/src/buildstep ] || git clone -q "https://github.com/$(BUILDSTEP_REPO_NAME).git" /tmp/src/buildstep > /dev/null
	rm -rf /tmp/src/buildstep/.git /tmp/src/buildstep/.gitignore

	echo "-> Copying files into place"
	mkdir -p "/tmp/build/var/lib"
	cp -rf /tmp/src/buildstep /tmp/build/var/lib/buildstep

	echo "-> Creating $(BUILDSTEP_PACKAGE_NAME)"
	fpm --force -t deb -s dir -C /tmp/build -n buildstep -v $(BUILDSTEP_VERSION) -a $(BUILDSTEP_ARCHITECTURE) -p /vagrant/pkg/$(BUILDSTEP_PACKAGE_NAME) --deb-pre-depends 'lxc-docker >= 1.4.0' --after-install /tmp/tmp/post-install --url "https://github.com/$(BUILDSTEP_REPO_NAME)" --description $(BUILDSTEP_DESCRIPTION) --license 'MIT License' .

deb-dokku: deb-setup
	rm -rf /tmp/tmp /tmp/build && mkdir -p /tmp/tmp /tmp/build

	cp -r debian /tmp/build/DEBIAN
	mkdir -p /tmp/build/usr/local/bin
	mkdir -p /tmp/build/var/lib/dokku
	mkdir -p /tmp/build/usr/local/share/man/man1
	mkdir -p /tmp/build/usr/local/share/dokku/contrib

	cp dokku /tmp/build/usr/local/bin
	cp -r plugins /tmp/build/var/lib/dokku
	find plugins/ -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | while read plugin; do touch /tmp/build/var/lib/dokku/plugins/$$plugin/.core; done
	$(MAKE) help2man
	$(MAKE) HELP2MAN_OUTPUT=/tmp/build/usr/local/share/man/man1/dokku.1 addman
	cp contrib/dokku-installer.rb /tmp/build/usr/local/share/dokku/contrib
	git describe --tags > /tmp/build/var/lib/dokku/VERSION
	cat /tmp/build/var/lib/dokku/VERSION | cut -d '-' -f 1 | cut -d 'v' -f 2 > /tmp/build/var/lib/dokku/STABLE_VERSION
	git rev-parse HEAD > /tmp/build/var/lib/dokku/GIT_REV
	sed -i "s/^Version: .*/Version: `cat /tmp/build/var/lib/dokku/STABLE_VERSION`/g" /tmp/build/DEBIAN/control
	dpkg-deb --build /tmp/build "/vagrant/pkg/dokku_`cat /tmp/build/var/lib/dokku/STABLE_VERSION`_$(DOKKU_ARCHITECTURE).deb"

deb-gems: deb-setup
	rm -rf /tmp/tmp /tmp/build && mkdir -p /tmp/tmp /tmp/build

	[ -f /tmp/gems/rack-1.5.2.gem ] || (cd /tmp/gems && gem fetch rack -v 1.5.2)
	[ -f /tmp/gems/rack-protection-1.5.3.gem ] || (cd /tmp/gems && gem fetch rack-protection -v 1.5.3)
	[ -f /tmp/gems/sinatra-1.4.5.gem ] || (cd /tmp/gems && gem fetch sinatra -v 1.4.5)
	[ -f /tmp/gems/tilt-1.4.1.gem ] || (cd /tmp/gems && gem fetch tilt -v 1.4.1)

	find /tmp/gems -name '*.gem' | xargs -rn1 fpm --force -d ruby -d ruby --package /vagrant/pkg --prefix /var/lib/gems/1.9.1 -s gem -t deb -a $(GEM_ARCHITECTURE)

deb-pluginhook: deb-setup
	rm -rf /tmp/tmp /tmp/build && mkdir -p /tmp/tmp /tmp/build

	echo "-> Cloning repository"
	[ -d /tmp/src/pluginhook ] || git clone -q "https://github.com/$(PLUGINHOOK_REPO_NAME).git" /tmp/src/pluginhook > /dev/null
	rm -rf /tmp/src/pluginhook/.git /tmp/src/pluginhook/.gitignore

	echo "-> Copying files into place"
	mkdir -p /tmp/build/usr/local/bin $(GOPATH)
	which git 2>&1 >/dev/null || sudo apt-get install -qqy git
	which hg 2>&1 >/dev/null || sudo apt-get install -qqy mercurial
	which go 2>&1 >/dev/null || sudo apt-get install -qqy golang
	export PATH=$(PATH):$(GOROOT)/bin:$(GOPATH)/bin && export GOROOT=$(GOROOT) && export GOPATH=$(GOPATH) && go get "code.google.com/p/go.crypto/ssh/terminal"
	export PATH=$(PATH):$(GOROOT)/bin:$(GOPATH)/bin && export GOROOT=$(GOROOT) && export GOPATH=$(GOPATH) && cd /tmp/src/pluginhook && go build -o pluginhook
	mv /tmp/src/pluginhook/pluginhook /tmp/build/usr/local/bin/pluginhook

	echo "-> Creating $(PLUGINHOOK_PACKAGE_NAME)"
	fpm --force -t deb -s dir -C /tmp/build -n pluginhook -v $(PLUGINHOOK_VERSION) -a $(PLUGINHOOK_ARCHITECTURE) -p /vagrant/pkg/$(PLUGINHOOK_PACKAGE_NAME) --url "https://github.com/$(PLUGINHOOK_REPO_NAME)" --description $(PLUGINHOOK_DESCRIPTION) --license 'MIT License' .

deb-sshcommand: deb-setup
	rm -rf /tmp/tmp /tmp/build && mkdir -p /tmp/tmp /tmp/build

	echo "-> Cloning repository"
	[ -d /tmp/src/sshcommand ] || git clone -q "https://github.com/$(SSHCOMMAND_REPO_NAME).git" /tmp/src/sshcommand > /dev/null
	rm -rf /tmp/src/sshcommand/.git /tmp/src/sshcommand/.gitignore

	echo "-> Copying files into place"
	mkdir -p "/tmp/build/usr/local/bin"
	cp /tmp/src/sshcommand/sshcommand /tmp/build/usr/local/bin/sshcommand
	chmod +x /tmp/build/usr/local/bin/sshcommand

	echo "-> Creating $(SSHCOMMAND_PACKAGE_NAME)"
	fpm --force -t deb -s dir -C /tmp/build -n sshcommand -v $(SSHCOMMAND_VERSION) -a $(SSHCOMMAND_ARCHITECTURE) -p /vagrant/pkg/$(SSHCOMMAND_PACKAGE_NAME) --url "https://github.com/$(SSHCOMMAND_REPO_NAME)" --description $(SSHCOMMAND_DESCRIPTION) --license 'MIT License' .
