#!/usr/bin/env bats

PROJECT_NAME=openmainttest
DOCKER_COMPOSE_FILE="docker-compose-bats.yml"

@test "SETUP (start up docker-compose)" { 
	run docker_compose up -d	
	result="$(docker ps -q -f "name=$PROJECT_NAME_" | wc -l)"
	[ "$status" -eq 0 ]  
	[ "$result" -eq 2 ]  
}

@test "Postgres is available" {
	wait_seconds_for_log 120 "FATAL:  database \"openmaint\" does not exist"	
	check_host_and_port postgres 5432	
}

@test "Extra Tomcat required libraries in place" {	
	check_for_file "/usr/local/tomcat/lib/postgresql-9.1-901.jdbc4.jar"
	check_for_file "/usr/local/tomcat/lib/scheduler-utils-0.1.jar"
}

@test "Webapps in place and exploded" {	
	wait_seconds_for_log 60 "creating: /usr/local/tomcat/webapps/shark/META-INF/"
	check_for_file "/usr/local/tomcat/webapps/openmaint"
	check_for_file "/usr/local/tomcat/webapps/shark"
}

@test "Configuration files in place and contain correct configuration" {
	check_string_present_in_config_file "test" "database"
	check_string_present_in_config_file "ru" "cmdbuild"
	check_string_present_in_config_file "teststring" "bim"
	check_string_present_in_config_file "teststring" "gis"	
	check_string_present_in_config_file "true" "workflow"	
}

@test "context.xml and Shark.xml contain correct configuration" {
	check_string_present_in_file "openmaint" "/usr/local/tomcat/webapps/shark/META-INF/context.xml"
	check_string_present_in_file "openmaint" "/usr/local/tomcat/webapps/shark/conf/Shark.conf"
}

@test "Tomcat is up" {
	wait_seconds_for_log 120 "INFO: Server startup in"
	check_host_and_port localhost 8080	
}

@test "Application is up" {
	check_url "http://localhost:8888/openmaint"
	check_url "http://localhost:8888/shark"
}

@test "TEARDOWN" {  
	docker_compose stop
	run docker_compose rm -f -v
	result="$(docker ps -a -q -f "name=$PROJECT_NAME_" | wc -l)"
	[ "$status" -eq 0 ]  
	[ "$result" -eq 0 ]  
}

docker_exec () {
	docker exec ${PROJECT_NAME}_openmaint_1 "$@"
}

check_host_and_port () {
	run docker_exec nc -z $1 $2
	[ "$status" -eq 0 ]
}

check_for_file () {
	run docker_exec ls $1	
	echo "$output"
	[ "$status" -eq 0 ] 
}

docker_psql_command () {
	docker_exec psql -U ${DB_USER} -h postgres -t -c "$1" ${DB_NAME} | xargs
}

docker_compose () {
	docker-compose --file $DOCKER_COMPOSE_FILE  --project-name $PROJECT_NAME "$@"
}

wait_seconds_for_log () {	
	# timeout launches its own shell so we have to pass it the whole command
	(timeout "$1s" stdbuf -o0 docker-compose --file $DOCKER_COMPOSE_FILE --project-name $PROJECT_NAME logs &) | grep -q "$2" 
}

check_string_present_in_file () {
	run docker_exec grep -q "$1" "$2"
	echo "$output"
	echo "$status"
	[ "$status" -eq 0 ] 
}

check_string_present_in_config_file () {
	run check_string_present_in_file "$1" "/usr/local/tomcat/webapps/openmaint/WEB-INF/conf/$2.conf"
	echo "$output"
	echo "$status"
	[ "$status" -eq 0 ] 
}

check_url () {
	run curl --max-time 10 -sSf $1
	echo "$output"
	echo "$status"
	[ "$status" -eq 0 ] 
}
