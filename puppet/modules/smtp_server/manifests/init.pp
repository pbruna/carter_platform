class smtp_server {
	include mta_server
	include auth_sasl_server
	
	class mta_server {
		package {"postfix":
			ensure => present
		}
	
		file {"postfix_main":
			ensure => file,
			owner => "root",
			group => "root",
			path => "/etc/postfix/main.cf",
			require => Package["postfix"],
			notify => Service["postfix"],
			content => template("smtp_server/main.cf.erb")
		}
		
		file {"postfix_master":
			ensure => present,
			owner => "root",
			group => "root",
			path => "/etc/postfix/master.cf",
			require => Package["postfix"],
			notify => Service["postfix"],
			source => "puppet:///modules/smtp_server/master.cf"
		}
	
		service {"postfix":
			ensure => running,
			enable => true,
			hasstatus => true,
			hasrestart => true,
			require => [Package["postfix"], File["postfix_main"]]
		}
	}
	
	class auth_sasl_server {
		$mysql_auth_servers = ["localhost"]
		
		package {"dovecot":
			ensure => present
		}
		
		package {"dovecot-mysql":
			ensure => present
		}
		
		file {"dovecot_conf": 
			ensure => present,
			owner => "root",
			group => "root",
			mode => "644",
			path => "/etc/dovecot/dovecot.conf",
			source => "puppet:///modules/smtp_server/dovecot.conf",
			require => Package["dovecot"],
			notify => Service["dovecot"]
		}
		
		file {"dovecot_logrotate":
			ensure => file,
			owner => "root",
			group => "root",
			mode => "644",
			path => "/etc/logrotate.d/dovecot",
			source => "puppet:///modules/smtp_server/dovecot_logrotate",
			require => Package["dovecot"],
		}
		
		file {"dovecot_sql":
			ensure => present,
			owner => "root",
			group => "root",
			mode => "644",
			path => "/etc/dovecot/dovecot-sql.conf",
			content => template("smtp_server/dovecot-sql.conf.erb"),
			require => [Package["dovecot"], File["dovecot_conf"]],
			notify => Service["dovecot"]
		}
		
		service {"dovecot":
			ensure => running,
			enable => true,
			hasrestart => true,
			hasstatus => true,
			require => [Package["dovecot"], File["dovecot_conf", "dovecot_sql"]]
		}
		
	}
	
}