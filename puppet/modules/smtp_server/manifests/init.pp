class smtp_server {
	include postfix
	
	class postfix {
		package {"postfix":
			ensure => present
		}
	
		file {"postfix_main":
			ensure => present,
			owner => "root",
			group => "root",
			path => "/etc/postfix/main.cf",
			require => Package["postfix"],
			notify => Service["postfix"],
			source => "puppet:///modules/smtp_server/main.cf"
		}
	
		service {"postfix":
			ensure => running,
			enable => true,
			hasstatus => true,
			hasrestart => true,
			require => [Package["postfix"], File["postfix_main"]]
		}
	}
	
}