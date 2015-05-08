package main

import (
	"flag"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"path"
	"strings"
)

var (
	VERSION             = "v0.3.17"
	ROOT_KEYS           = "/root/.ssh/authorized_keys"
	SERVICE_FILE        = "/etc/init/dokku-installer.conf"
	NGINX_CONF          = "/etc/nginx/conf.d/dokku-installer.conf"
	NGINX_SITES_ENABLED = "/etc/nginx/sites-enabled"
)

func getAdminKey() (string, error) {
	keys, err := ioutil.ReadFile(ROOT_KEYS)
	if err != nil {
		return "", err
	}

	return strings.SplitN(string(keys), "\n", 1)[0], nil
}

func getDokkuRoot() string {

	if root := os.Getenv("DOKKU_ROOT"); root != "" {
		return root
	} else {
		return "/home/dokku"
	}
}

func getExternalIP() (string, error) {
	resp, err := http.Get("http://icanhazip.com")
	defer resp.Body.Close()

	if err != nil {
		return "", err
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	return strings.TrimSpace(string(body)), nil
}

func testHostname(hostname string) error {
	return exec.Command("dig", "+short", hostname).Run()
}

func getHostname() (string, error) {
	hostname, err := os.Hostname()
	if err != nil || hostname == "" {
		return getExternalIP()
	}

	if err := testHostname(hostname); err != nil {
		return getExternalIP()
	}

	return hostname, nil
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	adminKey, err := getAdminKey()
	if err != nil {
		fmt.Println(err)
		adminKey = ""
	}

	hostname, err := getHostname()
	if err != nil {
		fmt.Println(err)
		hostname = ""
	}

	fmt.Fprintf(w, TEMPLATE, VERSION, adminKey, hostname)
}

func handleSetup(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", 405)
		return
	}

	vhostFile := path.Join(getDokkuRoot(), "VHOST")
	hostnameFile := path.Join(getDokkuRoot(), "HOSTNAME")

	vhost := r.FormValue("vhost") == "true"
	hostname := strings.TrimSpace(r.FormValue("hostname"))
	sshKey := strings.TrimSpace(r.FormValue("key"))

	// DOKKU_ROOT/HOSTNAME
	if err := ioutil.WriteFile(hostnameFile, []byte(hostname), 0644); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	// DOKKU_ROOT/VHOST
	if vhost {
		if err := ioutil.WriteFile(vhostFile, []byte(hostname), 0644); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
	} else {
		if err := os.Remove(vhostFile); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
	}

	// Add SSH key
	cmd := exec.Command("sshcommand", "acl-add", "dokku", "admin")
	stdin, err := cmd.StdinPipe()
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	if err := cmd.Start(); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	if _, err := stdin.Write([]byte(sshKey)); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	if err := stdin.Close(); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	if err := cmd.Wait(); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	if flag.Arg(0) == "selfdestruct" {
		if err := os.Remove(NGINX_CONF); err != nil {
			fmt.Println(err)
		}
		if err := exec.Command("restart nginx").Run(); err != nil {
			fmt.Println(err)
		}

		if err := os.Remove(SERVICE_FILE); err != nil {
			fmt.Println(err)
		}
		if err := exec.Command("stop dokku-installer").Run(); err != nil {
			fmt.Println(err)
		}
	}
}

func doOnboot() error {
	execPath, err := os.Readlink("/proc/self/exe")
	if err != nil {
		return err
	}

	// Write init script
	initContent := []byte(strings.TrimSpace(fmt.Sprintf(`
		start on runlevel [2345]
		exec %s selfdestruct
	`, execPath)))

	if err := ioutil.WriteFile(SERVICE_FILE, initContent, 0644); err != nil {
		return err
	}

	// Write NGINX config
	nginxConfig := []byte(`
		upstream dokku-installer { server 127.0.0.1:2000; }
		server {
			listen 80;
			location / {
				proxy_pass http://dokku-installer;
			}
		}
	`)

	if err := ioutil.WriteFile(NGINX_CONF, nginxConfig, 0644); err != nil {
		return err
	}

	// Remove all enabled sites
	enabledSites, err := ioutil.ReadDir(NGINX_SITES_ENABLED)
	if err != nil {
		return err
	}

	for _, f := range enabledSites {
		if err := os.Remove(path.Join(NGINX_SITES_ENABLED, f.Name())); err != nil {
			fmt.Println(NGINX_SITES_ENABLED, f.Name(), err)
		}
	}

	fmt.Println("Installed Upstart service and default Nginx virtualhost for installer to run on boot.")
	return nil
}

func main() {
	flag.Parse()

	if flag.Arg(0) == "onboot" {
		if err := doOnboot(); err != nil {
			fmt.Println(err)
			os.Exit(1)
		} else {
			os.Exit(0)
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/setup", handleSetup)

	if err := http.ListenAndServe(":2000", mux); err != nil {
		fmt.Println(err)
	}
}

var TEMPLATE = `
<html>
<head>
  <title>Dokku Setup</title>
  <link rel="stylesheet" href="//netdna.bootstrapcdn.com/bootstrap/3.0.0/css/bootstrap.min.css" />
  <script src="//ajax.googleapis.com/ajax/libs/jquery/1.10.2/jquery.min.js"></script>
</head>
<body>
  <div class="container" style="width: 640px;">
  <form id="form" role="form">
    <h1>Dokku Setup <small>%s</small></h1>
    <div class="form-group">
      <h3><small style="text-transform: uppercase;">Admin Access</small></h3>
      <label for="key">Public Key</label><br />
      <textarea class="form-control" name="key" rows="7" id="key">%s</textarea>
    </div>
    <div class="form-group">
      <h3><small style="text-transform: uppercase;">Hostname Configuration</small></h3>
      <div class="form-group">
        <label for="hostname">Hostname</label>
        <input class="form-control" type="text" id="hostname" name="hostname" value="%s" />
      </div>
      <div class="checkbox">
        <label><input id="vhost" name="vhost" type="checkbox" value="true"> Use <abbr title="Nginx will be run on port 80 and backend to your apps based on hostname">virtualhost naming</abbr> for apps</label>
      </div>
      <p>Your app URLs will look like:</p>
      <pre id="example">http://hostname:port</pre>
    </div>
    <button type="button" onclick="setup()" class="btn btn-primary">Finish Setup</button> <span style="padding-left: 20px;" id="result"></span>
  </form>
  </div>
  <div id="error-output"></div>
  <script>
    function setup() {
      if ($.trim($("#key").val()) == "") {
        alert("Your admin public key cannot be blank.")
        return
      }
      if ($.trim($("#hostname").val()) == "") {
        alert("Your hostname cannot be blank.")
        return
      }
      data = $("#form").serialize()
      $("input,textarea,button").prop("disabled", true);
      $.post('/setup', data)
        .done(function() {
          $("#result").html("Success!")
          window.location.href = "http://progrium.viewdocs.io/dokku/application-deployment";
        })
        .fail(function(data) {
          $("#result").html("Something went wrong...")
          $("#error-output").html(data.responseText)
        });
    }
    function update() {
      if ($("#vhost").is(":checked") && $("#hostname").val().match(/^(\d{1,3}\.){3}\d{1,3}$/)) {
        alert("In order to use virtualhost naming, the hostname must not be an IP but a valid domain name.")
        $("#vhost").prop('checked', false);
      }
      if ($("#vhost").is(':checked')) {
        $("#example").html("http://&lt;app-name&gt;."+$("#hostname").val())
      } else {
        $("#example").html("http://"+$("#hostname").val()+":&lt;app-port&gt;")
      }
    }
    $("#vhost").change(update);
    $("#hostname").change(update);
    update();
  </script>
</body>
</html>
`
