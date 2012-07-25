include base_packages
include smtp_server
include db_master_server
include stats_server

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