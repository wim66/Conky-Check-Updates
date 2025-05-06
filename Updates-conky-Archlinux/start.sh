#!/bin/bash
killall conky
sleep 1
# Bepaal het pad naar de Conky-map
CONKY_DIR=$(dirname "$(readlink -f "$0")")



# Start Conky met de juiste configuratie en log fouten
cd $CONKY_DIR
conky -c conky_checkupdates.conf
exit 0
