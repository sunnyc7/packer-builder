#!/bin/bash

COMMAND=$1
NAME=$2
FACILITY=ams1
OSTYPE=ubuntu_14_04
PLAN=baremetal_0
PROJECT=packer

if [ -z "${COMMAND}" ]; then
  echo "Usage:"
  echo "  $0 create name      create a new machine"
  echo "  $0 delete name      delete a machine"
  echo "  $0 ip name          get IP address of a machine"
  echo "  $0 list             list all machines"
  echo "  $0 photo name       take a photo from packer build"
  echo "  $0 provision name   provision the machine"
  echo "  $0 ssh name         ssh into a machine"
  echo "  $0 start name       start a machine"
  echo "  $0 stop name        stop a machine"
  exit 1
fi

TOKEN=$(pass packet_token)

function create {
  NAME=$1
  PROJECTID=$2

  if [ -z "${NAME}" ]; then
    echo "Usage: $0 name"
    exit 1
  fi

  # create project if it does not exist
  if [ -z "${PROJECTID}" ]; then
    PROJECTID=$(packet -k "${TOKEN}" \
      project create --name "${PROJECT}" | jq -r .id)
  fi

  # create vm
  packet -k "${TOKEN}" device create \
    --facility "${FACILITY}" \
    --os-type "${OSTYPE}" \
    --plan "${PLAN}" \
    --project-id "${PROJECTID}" \
    --hostname "${NAME}"

  # addstorage "${NAME}" "${PROJECTID}"
  provision "${NAME}" "${PROJECTID}"
}

function cmd {
  NAME=$1
  PROJECTID=$2
  CMD=$3

  if [ -z "${NAME}" ] || [ -z "${PROJECTID}" ] || [ -z "${CMD}" ]; then
    echo "Usage: $0 name id command"
    exit 1
  fi

  DEVICEID=$(packet -k "${TOKEN}" \
    device listall --project-id "${PROJECTID}" | jq -r ".[] | select(.hostname == \"${NAME}\") .id")

  packet -k "${TOKEN}" \
    device "${CMD}" --device-id "${DEVICEID}"
}

function start {
  echo "Starting $1"
  cmd "$1" "$2" power-on
}

function stop {
  echo "Stopping $1"
  cmd "$1" "$2" power-off
}

function delete {
  echo "Deleting $1"
  cmd "$1" "$2" delete
  # deletestorage "$1" "$2"
}

function list {
  packet -k "${TOKEN}" device listall --project-id "${PROJECTID}" | \
    jq -r '.[] | .hostname + "	" + .state'
}

function ip {
  packet -k "${TOKEN}" device listall --project-id "${PROJECTID}" | \
    jq -r ".[] | select(.hostname == \"${NAME}\") | .ip_addresses[] | select(.public == true) | select(.address_family == 4).address"
}

function provision {
  echo "Provisioning $1"
  IP=$(ip)
  ssh-keygen -R "${IP}"
  cat scripts/provision-vmware-builder.sh | /usr/bin/ssh "root@${IP}"
}

function addstorage {
  NAME=$1
  PROJECTID=$2

  set -x
  STORAGEID=$(packet -k "${TOKEN}" storage create \
    --facility "${FACILITY}" \
    --desc "${NAME}" \
    --plan storage_2 \
    --size 160 \
    --project-id "${PROJECTID}" | jq -r .id)

  DEVICEID=$(packet -k "${TOKEN}" \
    device listall --project-id "${PROJECTID}" | jq -r ".[] | select(.hostname == \"${NAME}\") .id")

  packet -k "${TOKEN}" storage attach \
    --device-id "${DEVICEID}" \
    --storage-id "${STORAGEID}"
}

function deletestorage {
  STORAGEID=$(packet -k "${TOKEN}" \
    storage listall --project-id "${PROJECTID}" | jq -r ".[] | select(.description == \"${NAME}\") .id")

  if [ ! -z "${STORAGEID}" ]; then
    packet -k "${TOKEN}" storage delete --storage-id "${STORAGEID}"
  fi
}

function ssh {
  /usr/bin/ssh "root@$(ip)"
}

function photo {
  IP=$(ip)
  /usr/bin/ssh "root@${IP}" photo snapshot.jpg
  scp "root@${IP}:snapshot.jpg" snapshot.jpg
  open snapshot.jpg
}

PROJECTID=$(packet -k "${TOKEN}" \
  project listall | jq -r ".[] | select(.name == \"${PROJECT}\") .id")

"${COMMAND}" "${NAME}" "${PROJECTID}"
