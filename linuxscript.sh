#!/bin/bash
#
# Nice DNS: the script builds up an authoritative DNS server using DNSmasq,
# and offers options to populate and ask questions to the local DNS server run by the daemon.
#
# Author: Naoufal Bouazzaoui email:naoufalb2003@gmail.com

# Stop het script bij een onbestaande variabele

set -o nounset # abort on unbound variable

### Algemene variabelen worden eerst gedefinieerd
NAMES_LIST=''
DNS_DIR=/var/dns
DOMAIN=linux.prep
RANGE=10.22.33.0/24
DNS_IP=127.0.0.1
### --- functions ---

# installeer de DNS server, ook al zou de service al geïnstalleerd zijn. 
# Gebruik idempotente commando's waar mogelijk.
function install_dnsserver {
  if ! rpm -q dnsmasq > /dev/null 2>&1; then
    # Install dnsmasq
    sudo dnf -y install dnsmasq > /dev/null 2>&1
    sudo systemctl restart dnsmasq > /dev/null 2>&1
  fi
  sudo chown vagrant /etc/
  sudo setenforce 0

  # Pas de configuratie van de DNS server aan
  # Change the conf-dir option in dnsmasq.conf to /var/dns/
  sudo sed -i 's/conf-dir=\/etc\/dnsmasq.d/conf-dir=\/var\/dns/' /etc/dnsmasq.conf
  sudo sed -i 's/conf-dir=\/var\/dns,.rpmnew,.rpmsave,.rpmorig/conf-dir=\/var\/dns/' /etc/dnsmasq.conf
  # Check if the /var/dns directory exists
  if ! -d "/var/dns" > /dev/null 2>&1; then
    # Create the /var/dns directory
    sudo mkdir -p /var/dns
  fi
  # Restart the dnsmasq service
  #sudo systemctl restart dnsmasq

  # maak server actief op intnet en localhost maar niet NAT(=eth0) 
  if ! grep -q "interface=eth1" /etc/dnsmasq.conf ; then
    sed -i '$a\interface=eth1' /etc/dnsmasq.conf
    sed -i '/interface=eth0/d' /etc/dnsmasq.conf
  fi
  # enable en start dnsmasq
  sudo systemctl enable dnsmasq > /dev/null 2>&1 
  sudo systemctl start dnsmasq > /dev/null 2>&1
  #poort accesible via alle IP-adressen
  sudo firewall-cmd --permanent --add-port=53/tcp > /dev/null 2>&1
  sudo echo -e "interface=eth1\nbogus-priv\nexpand-hosts\nno-resolv\nlocal=/linux.prep/\ndomain=linux.prep" >> /etc/dnsmasq.conf > /dev/null 2>&1
  sudo firewall-cmd --reload > /dev/null 2>&1
  sudo systemctl restart dnsmasq > /dev/null 2>&1
}

# Initialiseer een nieuwe database voor het opgegeven domain;
# voeg drie eerste gebruikers toe.
# Bemerk: de range wordt hier hardcoded gebruikt - dit kan in se beter!
function init_dns_db {
  sudo chown vagrant /var/dns
  local Domain=${1}
  
  if ! [ -f "${DNS_DIR}"/db."${Domain}" ] ; then
	# Generate an empty file, let everybody write to it
    cat << EOF > "${DNS_DIR}"/db."${Domain}"
# SOA config
# ----------------------------------------------------------------------------
auth-soa=2016021014,hostmaster.${Domain},1200,120,604800
auth-server=${DOMAIN},${DNS_IP}
auth-zone=${DOMAIN},${RANGE}

# A records
# ----------------------------------------------------------------------------
host-record=andy.linux.prep,10.22.33.1
host-record=bert.linux.prep,10.22.33.2
host-record=thomas.linux.prep,10.22.33.3
EOF
  fi 
}

# De functie neemt een naam en een domain als input, en voegt een RR
# (resource record) toe in de database file in de juiste map (globale variabelen)
function create_resource_record {
  local Nameee=$1
  Nameee=$(echo "$Nameee" | tr '[:upper:]' '[:lower:]')
  local Domain=$2
  local j
  # Find the next available IP address in the 10.22.33.0/24 range
  for ((j=1; j<=254; j++)); do
    next_ip="10.22.33.$j"
    if ! grep -q "$next_ip" "${DNS_DIR}/db.${Domain}"; then
      # Add the new RR to the database file 
      echo "host-record=${Nameee}.${Domain},${next_ip}" >> "${DNS_DIR}/db.${Domain}"
      sudo systemctl restart dnsmasq > /dev/null 2>&1
      break
    fi
  done
  if [ $j -eq 255 ]; then
    echo "Error: No more available IP addresses in the range 10.22.33.0/24"
  fi

}

# Gebruik de bovenstaande functie om N aantal records toe te voegen aan het 
# opgegeven domain. De lijst met namen is opnieuw een globale variabele.
# Bemerk: werken met een tempfile is slechts één mogelijkheid.
# Een oplossing met een array van namen is een andere.
function generate_RRs {  
  local aantal=$1
  # Convert the variable into an array
  name_array=($NAMES_LIST)

  # Get the number of names in the array
  num_names=${#name_array[@]}

  # Use a for loop to select 5 random names
  for ((i=1; i<="$aantal"; i++)); do
    random_index=$((RANDOM % num_names))
    create_resource_record "${name_array[random_index]}" "$DOMAIN"
    echo "Added ${name_array[random_index]}.$DOMAIN"
  done
}

# de short lookup geeft enkel het IP-adres weer in grote letters.
# Hint: figlet
function short_lookup {
  local URL=$1
  Serv=${DNS_IP}
  output=$(nslookup -query=A "$URL".linux.prep "$Serv" | grep 'Address: ' | awk '{print $2}')
  figlet "$output"
}

# de fancy lookup geeft eerst een newline, de datum, 
# en dan het resultaat van een lookup in een tekstballon van een koe
# Hint: cowsay
function fancy_lookup {
  par=$1
  namee=$(nslookup "$par".$DOMAIN ${DNS_IP})
  today=$(date +%Y-%m-%d)
  echo -e "\nVandaag is het $today.\n"
  echo "$namee" | cowsay
}

# Deze functie neemt als input een (hoofd)letter en een domain.
# De namenlijst is opnieuw een globale variabele.
# Alle namen beginnend met de letter worden (short) opge
function display_names {
    local NAMES_LISTT=$1
    local START_LETTER=$2

    name_array=($NAMES_LISTT)

    for name in "${name_array[@]}"; do
        if [[ "$name" == $START_LETTER* ]]; then
        echo "looking up $name"
        output=$(nslookup -query=A "$name".linux.prep "$DNS_IP" | grep 'Address: ' | awk '{print $2}' | tail -n 1)
        figlet "$output"
        fi
    done
}

### --- main script ---
### Voer de opeenvolgende taken uit

# installeer DNS server, ook al is het reeds geïnstalleerd. 
sudo setenforce 0
sudo chmod 777 /etc/rc.d/rc.local
install_dnsserver
# initialiseer de local DNS database, indien nodig
init_dns_db "${DOMAIN}"
sudo chmod 777 /etc/rc.d/rc.local

# Ga na of er argumenten zijn of niet; zoniet onderbreek je het script
if [ "${#}" -eq '0' ]; then
  echo "At least one argument expected, exiting..."
  exit 1
fi

if ! rpm -qa | grep -qw epel-release; then
  sudo dnf -y update > /dev/null 2>&1 
  sudo dnf -y install epel-release > /dev/null 2>&1
fi
if ! rpm -qa | grep -qw cowsay; then
  sudo dnf -y install cowsay > /dev/null 2>&1
fi
if ! rpm -qa | grep -qw figlet; then
  sudo dnf -y install figlet > /dev/null 2>&1
fi

if ! [ -e /vagrant/provisioning/voornamen.list ]; then
  wget http://157.193.215.171/voornamen.list > /dev/null 2>&1
  NAMES_LIST=$(cat voornamen.list)
else 
  NAMES_LIST=$(cat voornamen.list)
fi

# With a case statement, check if the positional parameters, as a single
# string, matches one of the text the script understands.
OPTION=${1}


#Check the value of OPTION and perform the appropriate action
if [ "$OPTION" == "-s" ] || [ "$OPTION" == "--short" ]; then
  short_lookup ${2}
elif [ "$OPTION" == "-a" ] || [ "$OPTION" == "--add" ]; then
  create_resource_record ${2} "$DOMAIN"
elif [ "$OPTION" == "-g" ] || [ "$OPTION" == "--gen" ]; then
  generate_RRs ${2}
elif [ "$OPTION" == "-r" ] || [ "$OPTION" == "--range" ]; then
  display_names "$NAMES_LIST" "${2}"
else
  fancy_lookup ${1}

fi
# Einde script
