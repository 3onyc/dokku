# Install Dokku using Vagrant

- Download and install [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
- Download and install [Vagrant](http://www.vagrantup.com/downloads.html)
- Clone Dokku

    ```
    git clone https://github.com/progrium/dokku.git
    ```

- Setup SSH hosts in your `/etc/hosts`

    ```
    10.0.0.2 dokku.me
    ```

- Create VM
    ```
    # Optional ENV arguments:
    # - `BOX_NAME`
    # - `BOX_URI`
    # - `BOX_MEMORY`
    # - `DOKKU_DOMAIN`
    # - `DOKKU_IP`
    # - `FORWARDED_PORT`.
    cd path/to/dokku
    vagrant up
    ```
- Setup SSH Config in `~/.ssh/config`. The port listed here is usually correct, though you may want to verify that it is the same as the one listed in the output of `vagrant ssh-config dokku`

    ```
    Host dokku.me
        Port 2222
    ```

- Add your public key

  `$ cat ~/.ssh/id_rsa.pub | make vagrant-acl-add`

You are now ready to deploy an app or install plugins.

For a different, complete, example see https://github.com/RyanBalfanz/dokku-vagrant-example.
