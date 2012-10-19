class mongo_master {
	
	file {"mongo_yum_repo":
		ensure => present,
		owner => "root",
		mode => "0644",
		path => "/etc/yum.repos.d/mongo.repo",
		source => "puppet:///modules/mongo_master/mongo.repo"
	}
	
	Package {require => File["mongo_yum_repo"]}
	
	package {"mongo-10gen":; "mongo-10gen-server":;}
	
	service {"mongod":
		ensure => running,
		hasstatus => true,
		hasrestart => true,
		enable => true,
		require => Package["mongo-10gen-server"]
	}
	
}