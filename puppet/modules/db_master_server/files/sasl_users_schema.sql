CREATE TABLE users (
     username VARCHAR(128) NOT NULL,
     password VARCHAR(64) NOT NULL,
	 customer_id INTEGER NOT NULL,
     active CHAR(1) DEFAULT 'Y' NOT NULL
);