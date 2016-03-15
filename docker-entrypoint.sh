#!/bin/bash

set -e

BACKUP_FILE="/tmp/openmaint/database/openmaint-demo.backup"

wait_for_pg_restore_to_finish () {
	COUNT_PG_RESTORE_RUNNING_PROCESSES_QUERY="SELECT count(*) FROM pg_stat_activity WHERE application_name='pg_restore';"
	result=$(psql_command "${COUNT_PG_RESTORE_RUNNING_PROCESSES_QUERY}")
	echo "ISTO: $result"
	while [[ "$result" == "1" ]];
	do
		sleep 2
		result=$(psql_command "${COUNT_PG_RESTORE_RUNNING_PROCESSES_QUERY}")
		
	done
}

psql_command () {
	psql -U ${DB_USER} -h ${DB_HOST} -p ${DB_PORT} -t -c "$1" ${DB_NAME} | xargs
}

restore_backup () {
	pg_restore -d $DB_NAME -U ${DB_USER} -h ${DB_HOST} ${BACKUP_FILE}
}

create_database () {	
	createdb -U $DB_USER -O $DB_USER -h $DB_HOST -p $DB_PORT -w -e $DB_NAME > /dev/null	
}

create_shark_database_role () {
	psql -U ${DB_USER} -h ${DB_HOST} -c "create user shark WITH PASSWORD 'shark';"	
}

set_db_pass_for_psql () {
	echo "*:*:*:*:${DB_PASS}" > ~/.pgpass
	chmod 0600 ~/.pgpass
}

wait_for_host_and_port_to_open () {
	RETRIES=0
	MAX_RETRIES=5
	while ! nc -z $1 $2 </dev/null; 
	do 
		echo "Waiting for host $1 to become available on port $2 ($RETRIES)";
		sleep 15;
		RETRIES=$((RETRIES+1))
		if [ "$RETRIES" -gt "$MAX_RETRIES" ]; then
			exit 4;
		fi
	done
}

set_database_search_path () {
	psql_command "ALTER DATABASE ${DB_NAME} SET search_path=shark,public,gis;"
}

setup_database () {
	wait_for_host_and_port_to_open ${DB_HOST} ${DB_PORT}
	set_db_pass_for_psql ${DB_PASS}		
	if ! psql -U ${DB_USER} -h ${DB_HOST} -p ${DB_PORT} ${DB_NAME} -c '\q' 2>&1; then		
		create_database		
		create_shark_database_role		
		set_database_search_path		
		restore_backup
	fi
}

unzip_wars () {	
	unzip /tmp/openmaint/openmaint*.war -d $CATALINA_HOME/webapps/openmaint
	unzip /tmp/openmaint/cmdbuild-shark-server*.war -d $CATALINA_HOME/webapps/shark
}

setup_conf_file () {
	envsubst < "/tmp/openmaint/configuration/$1.conf" > "/usr/local/tomcat/webapps/openmaint/WEB-INF/conf/$1.conf"
}

setup_conf_file_bim () {	
	BIM_URL=$(echo $BIM_URL | sed 's|:|\\:|g')
	setup_conf_file "bim"
}

setup_conf_file_gis () {	
	GEOSERVER_URL=$(echo $GEOSERVER_URL | sed 's|:|\\:|g')
	setup_conf_file "gis"
}

configure_application () {
	sed -i 's@localhost/${cmdbuild}@'"${DB_HOST}:${DB_PORT}/${DB_NAME}"'@' $CATALINA_HOME/webapps/shark/META-INF/context.xml 
	sed -i 's@org.cmdbuild.ws.url=http://localhost:8080/cmdbuild/@org.cmdbuild.ws.url=http://localhost:8080/openmaint/@' webapps/shark/conf/Shark.conf
	setup_conf_file "database"
	setup_conf_file "cmdbuild"	
	setup_conf_file "workflow"	
	setup_conf_file_bim
	setup_conf_file_gis
}

setup_application () {		
	if ! [ -d $CATALINA_HOME/webapps/shark ]; then		
		echo "$CATALINA_HOME/webapps/shark does not exist, setting up application"
		cp /tmp/openmaint/scheduler/* $CATALINA_HOME/lib/
		cp /tmp/openmaint/extras/tomcat-libs/6.0/* $CATALINA_HOME/lib/
		unzip_wars		
		configure_application		
	fi
}

cleanup () {
	rm -rf /tmp/openmaint
}

#END OF PRIVATE FUNCS

if [ "$1" = 'openmaint' ]; then	
	setup_application
	setup_database
	cleanup
	exec catalina.sh run
fi

exec "$@"