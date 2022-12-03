#!/bin/bash
#set -x
export MOSQUITTO_PORT=54322


export TMP_MOSQUITTO=/tmp/mosquitto_tmp
export MOSQUITTO_CONF=/etc/mosquitto/mosquitto.conf

function main() {
	
	cleanup
	check_installation 
	check_conf_file
	set_listener_port "$MOSQUITTO_PORT"
	allow_anonymous
	run_mosquitto
	test_pubsub
	refresh_server

	exit 0
}

function cleanup() {

	if [[ -d $TMP_MOSQUITTO ]]
	then
		rm -rf $TMP_MOSQUITTO
	fi

	mkdir $TMP_MOSQUITTO
	echo "" > $TMP_MOSQUITTO/mosquitto.log

}

function check_installation() {

	apt list --installed | grep "mosquitto/" &>/dev/null
	if [[ $? -ne 0 ]]
	then
		echo "mosquitto not found"
		echo "mosquitto is installing"
		sudo apt install mosquitto
	fi

	apt list --installed | grep "mosquitto-clients/" &>/dev/null
	if [[ $? -ne 0 ]]
	then
		echo "mosquitto-clients not found"
		echo "mosquitto-clients is installing"
		sudo apt install mosquitto-clients
	fi
	echo;
	echo;

}


function check_conf_file() {

	if [[ ! -f $MOSQUITTO_CONF ]]
	then
		echo "Config file does not exist"
	fi
}


function allow_anonymous() {

	grep "allow_anonymous true" $MOSQUITTO_CONF > /dev/null
	result_anonymous=$?

	if [[ $result_anonymous -eq 0 ]] 
	then
		echo "Mosquitto allows the anonym clients"
	else
		echo "Mosquitto doesnt allow the anonym clients"
		echo "Configuring the config file $MOSQUITTO_CONF"
		echo "allow_anonymous true" >> $MOSQUITTO_CONF
		echo "Mosquitto allows the anonym clients"
	fi
}

# Params: Port $1, 
function set_listener_port() {

	grep "listener $MOSQUITTO_PORT" $MOSQUITTO_CONF
	result_port=$?
	
	if [[ $result_port -eq 0 ]]
	then
		echo "Mosquitto port already setted to $(grep listener $MOSQUITTO_CONF)"
	else
		echo "Mosquitto port does not defined in config file ( $MOSQUITTO_CONF )"
		sed -i "/listener/d" $MOSQUITTO_CONF
		echo "Setting the mosquitto port as $MOSQUITTO_PORT"
		echo "listener $MOSQUITTO_PORT" >> $MOSQUITTO_CONF
		echo "Mosquitto port is setted as $MOSQUITTO_PORT"
	fi 


}

function kill_mosquitto() {

	pid_curr_mosq=$(ps -ef | grep mosquitto | grep -v grep | grep -v $0 | gawk '{print $2}')
	if [[ ! -z $pid_curr_mosq ]]
	then
		kill $pid_curr_mosq
	fi

}

function run_mosquitto() { 
	
	ps -ef | grep mosquitto | grep -v grep > /dev/null
	mosq_state=$?

	if [[ mosq_state -eq 0 ]]
	then
		kill_mosquitto
	fi
	echo "Mosquitto is starting"
	timeout 10 mosquitto -v -c /etc/mosquitto/mosquitto.conf >> $TMP_MOSQUITTO/mosquitto.log 2>&1 &
	pid_sv=$!
	while :
	do
		grep "running" $TMP_MOSQUITTO/mosquitto.log
		if [[ $? -eq 0 ]]
		then
			break
		fi
		echo "Waiting for mosquitto running..."
		sleep 1
	done

}

function command_call() {
	
	echo "In order to test mosquitto, you can use listed command"
	echo "1 -> \"sub topic\", subscribes the topic"
	echo "2 -> \"pub topic message\", publishes the message to the topic"
	echo "3 -> \"quit\", command returns tolinux terminal"

	while :
	do
		printf "COMMAND > "
		read command 
		echo $command > $TMP_MOSQUITTO/command

		grep "sub " $TMP_MOSQUITTO/command
		result_command=$?

		if [[ $result_command -eq 0 ]]
		then
			count_of_word=$(cat $TMP_MOSQUITTO/command | wc -w)
			if [[ $count_of_word -ne 2 ]] 
			then
				echo "Please enter a command with given type"
				continue;
			fi

			topic=$(cat $TMP_MOSQUITTO/command | gawk '{print $2}')

			mosquitto_sub -t $topic -h localhost -p $MOSQUITTO_PORT &
		fi

		grep "pub " $TMP_MOSQUITTO/command
		result_command=$?

		if [[ $result_command -eq 0 ]]
		then
			count_of_word=$(cat $TMP_MOSQUITTO/command | wc -w)
			if [[ $count_of_word -ne 3 ]] 
			then
				echo "Please enter a command with given type"
				continue;
			fi

			topic=$(cat $TMP_MOSQUITTO/command | gawk '{print $2}')
			message=$(cat $TMP_MOSQUITTO/command | gawk '{print $3}')
			mosquitto_pub -t $topic -m $message -h localhost -p $MOSQUITTO_PORT > /dev/null

		fi


		grep -E "[exit|quit]" $TMP_MOSQUITTO/command
		result_command=$?
		if [[ $result_command -eq 0 ]]
		then
			exit 0;
		fi

	done



}

function refresh_server() {

	kill $pid_sv
	sleep 1
	
	mosquitto -c /etc/mosquitto/mosquitto.conf > /dev/null &
	sleep 1
	
	command_call

	wait $!

}

function test_pubsub() {
	
	echo "Subscribing to test_topic..."
	timeout 5 mosquitto_sub -t "test_topic" -p $MOSQUITTO_PORT >> $TMP_MOSQUITTO/test_topic &
	pid_sub=$!
	echo "Publishing message to test_topic..."
	
	while :
	do
		grep "SUBSCRIBE" $TMP_MOSQUITTO/mosquitto.log
		if [[ $? -eq 0 ]]
		then
			break
		fi
		echo "Waiting for subscription..."
		sleep 1
	done


	mosquitto_pub -t "test_topic" -m "test_message" -p $MOSQUITTO_PORT -h localhost
	wait $pid_sub >> $TMP_MOSQUITTO/test_topic

	grep "test_message" $TMP_MOSQUITTO/test_topic > /dev/null
	result_test=$?

	if [[ $result_test -eq 0 ]]
	then
		echo "Publish and subscribe test is OK"
	else	
		echo "Publish and subscribe test is NOK"
	fi



}


main
