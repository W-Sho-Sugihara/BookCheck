DATABASE=$1

dropdb $DATABASE
createdb $DATABASE

psql -d $DATABASE < init_setup/schema.sql

ruby init_setup/init_library.rb
