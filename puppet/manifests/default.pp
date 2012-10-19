include base_packages
include catcher
include mongo_master
include carter_app

class base_packages {
	package {
		"file":;
		"vim-enhanced":;
		"tcpdump":;
		"telnet":;
	}
	
	file {"/etc/selinux/config":
		owner => "root",
		group => "root",
		mode => "644",
		content => "SELINUX=permissive\nSELINUXTYPE=targeted\n"
	}
}