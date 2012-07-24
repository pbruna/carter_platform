class db_master_server {
	$sasl_db_user = "dovecot"
	$sasl_db_password = "dovecot"

	package {"mysql-server":}
	package {"mysql":}
	
	file {"my.cnf":
		path => "/etc/my.cnf",
		owner => "root",
		group => "root",
		source => "puppet:///modules/db_master_server/my.cnf",
		notify => Service["mysqld"]
	}
	
	service {"mysqld":
		ensure => running,
		enable => true,
		require => [Package["mysql-server"], File["my.cnf"]]
	}
	
	exec {"create-sasl-users-db":
		unless => "/usr/bin/mysql sasl_users",
		command => "/usr/bin/mysql -e \"create database sasl_users; grant all on sasl_users.* to ${sasl_db_user}@'%' identified by '${sasl_db_password}';\"",
		require => Service["mysqld"]
	}
	
	exec {"local-sasl-users-permision":
		unless => "/usr/bin/mysql -u dovecot -h localhost -pdovecot sasl_users",
		command => "/usr/bin/mysql -e \"grant all on sasl_users.* to ${sasl_db_user}@localhost identified by '${sasl_db_password}';\"",
		require => [Service["mysqld"], Exec["create-sasl-users-db"]]
	}
	
	file {"sasl_users_schema":
		path => "/tmp/sasl_users_schema.sql",
		source => "puppet:///modules/db_master_server/sasl_users_schema.sql"
	}
	
	exec {"load-sasl-users-schema":
		unless => "/usr/bin/mysql sasl_users -e \"select count(password) from users\"",
		command => "/usr/bin/mysql sasl_users < /tmp/sasl_users_schema.sql",
		require => [File["sasl_users_schema"], Exec["create-sasl-users-db"]]
	}
			
}