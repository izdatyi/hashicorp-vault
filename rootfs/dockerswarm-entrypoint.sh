#!/bin/bash
# https://github.com/swarmlibs/dockerswarm-entrypoint.sh/blob/main/dockerswarm-entrypoint.sh

# Get the IP addresses of the tasks of the service using DNS resolution
function dockerswarm_sd() {
	local service_name=$1
	if [ -z "$service_name" ]; then
		echo "[dockerswarm_sd]: command line is not complete, service name is required"
		return 1
	fi
	dig +short "tasks.${service_name}" | sort
}

# Docker Swarm Auto Join for Hashicorp Vault
function dockerswarm_auto_join() {
	local auto_join_scheme=${DOCKERSWARM_AUTO_JOIN_SCHEME:-"http"}
	local auto_join_port=${DOCKERSWARM_AUTO_JOIN_PORT:-"8200"}

	# Loop to check the tasks of the service
	local current_cluster_ips=""
	while true; do
		# Get the cluster IPs of the service
		local auto_join_config=""
		local cluster_ips=$(dockerswarm_sd "${1}")
		# Skip if the cluster_ips is empty
		if [[ -z "${cluster_ips}" ]]; then
			current_cluster_ips="" # reset the current_cluster_ips
			sleep 15 # Grace period before checking the tasks again
			continue
		fi
		# if VAULT_STORAGE_BOOTSTRAP_EXPECT is equal to 1, then it's a single node cluster
		if [[ ${VAULT_STORAGE_BOOTSTRAP_EXPECT} -eq 1 ]]; then
			# Write the configuration to the file
			echo "disable_mlock = \"true\"  storage \"raft\" { /* single node cluster */ }" > "$VAULT_STORAGE_CONFIG_FILE"
			break
		fi
		# if cluster_ips is less than VAULT_STORAGE_BOOTSTRAP_EXPECT, then wait for more tasks to join
		if [[ $(echo "${cluster_ips}" | wc -l) -lt ${VAULT_STORAGE_BOOTSTRAP_EXPECT} ]]; then
			sleep 15 # Grace period before checking the tasks again
			continue
		fi
		# Check if the current_cluster_ips is different from the cluster_ips
		if [[ "${current_cluster_ips}" != "${cluster_ips}" ]]; then
			# Update the current_cluster_ips
			current_cluster_ips=$cluster_ips
			# Loop to add the tasks to the auto_join_config
			for task in ${cluster_ips}; do
				# Skip if the task is the current node
				if [[ "$(hostname -i)" == *"${task}"* ]]; then
					sleep 15 # Grace period before checking the tasks again
					continue
				fi
				# Add the task to the auto_join_config
				if [[ -n "${auto_join_config}" ]]; then
					auto_join_config="${auto_join_config} "
				fi
				auto_join_config="${auto_join_config}retry_join { leader_api_addr = \"${auto_join_scheme}://${task}:${auto_join_port}\" }"
			done
			# Write the configuration to the file
			echo "disable_mlock = \"true\"  storage \"raft\" { ${auto_join_config} }" > "$VAULT_STORAGE_CONFIG_FILE"
			# Send a SIGHUP signal to reload the configuration
			if [ -f "$VAULT_PID_FILE" ]; then
				echo "==> [Docker Swarm Entrypoint] detected a change in the cluster, reloading the configuration..."
				kill -s SIGHUP $(cat $VAULT_PID_FILE)
			fi
		fi
		# All done, break the loop
		break
	done
}

# VAULT_DATA_DIR is exposed as a volume for possible persistent storage. The
# VAULT_CONFIG_DIR isn't exposed as a volume but you can compose additional
# config files in there if you use this image as a base, or use
# VAULT_LOCAL_CONFIG below.
VAULT_DATA_DIR=/vault/file
VAULT_CONFIG_DIR=/vault/config
VAULT_PID_FILE=/vault/config/vault.pid
VAULT_STORAGE_BOOTSTRAP_EXPECT=${VAULT_STORAGE_BOOTSTRAP_EXPECT:-1}
VAULT_STORAGE_CONFIG_FILE=${VAULT_STORAGE_CONFIG_FILE:-"$VAULT_CONFIG_DIR/raft-storage.hcl"}

# Docker Swarm Entrypoint
export DOCKERSWARM_ENTRYPOINT=true
export DOCKERSWARM_STARTUP_DELAY=${DOCKERSWARM_STARTUP_DELAY:-15}
echo "Enable Docker Swarm Entrypoint..."

# Docker Swarm service template variables
#  - DOCKERSWARM_SERVICE_ID={{.Service.ID}}
#  - DOCKERSWARM_SERVICE_NAME={{.Service.Name}}
#  - DOCKERSWARM_NODE_ID={{.Node.ID}}
#  - DOCKERSWARM_NODE_HOSTNAME={{.Node.Hostname}}
#  - DOCKERSWARM_TASK_ID={{.Task.ID}}
#  - DOCKERSWARM_TASK_NAME={{.Task.Name}}
#  - DOCKERSWARM_TASK_SLOT={{.Task.Slot}}
#  - DOCKERSWARM_STACK_NAMESPACE={{ index .Service.Labels "com.docker.stack.namespace"}}
export DOCKERSWARM_SERVICE_ID=${DOCKERSWARM_SERVICE_ID}
export DOCKERSWARM_SERVICE_NAME=${DOCKERSWARM_SERVICE_NAME}
export DOCKERSWARM_NODE_ID=${DOCKERSWARM_NODE_ID}
export DOCKERSWARM_NODE_HOSTNAME=${DOCKERSWARM_NODE_HOSTNAME}
export DOCKERSWARM_TASK_ID=${DOCKERSWARM_TASK_ID}
export DOCKERSWARM_TASK_NAME=${DOCKERSWARM_TASK_NAME}
export DOCKERSWARM_TASK_SLOT=${DOCKERSWARM_TASK_SLOT}
export DOCKERSWARM_STACK_NAMESPACE=${DOCKERSWARM_STACK_NAMESPACE}

echo "==> [Docker Swarm Entrypoint] waiting for Docker Swarm to configure the network and DNS resolution... (${DOCKERSWARM_STARTUP_DELAY}s)"
sleep ${DOCKERSWARM_STARTUP_DELAY}

# Generate a random node ID which will be persisted in the data directory
if [ ! -f "${VAULT_DATA_DIR}/node-id" ]; then
	echo "==> [Docker Swarm Entrypoint] generate a random node ID which will be persisted in the data directory..."
	uuidgen > "${VAULT_DATA_DIR}/node-id"
fi
# Set the VAULT_RAFT_NODE_ID to the content of the node-id file
export VAULT_RAFT_NODE_ID=$(cat "${VAULT_DATA_DIR}/node-id")

# Set the VAULT_CLUSTER_NAME using DOCKERSWARM_STACK_NAMESPACE
if [ -n "$DOCKERSWARM_STACK_NAMESPACE" ]; then
	export VAULT_CLUSTER_NAME=${DOCKERSWARM_STACK_NAMESPACE}
	echo "==> [Docker Swarm Entrypoint] using \"$DOCKERSWARM_STACK_NAMESPACE\" stack for VAULT_CLUSTER_NAME: $VAULT_CLUSTER_NAME"
fi

# Auto-join the Docker Swarm service
export DOCKERSWARM_AUTO_JOIN_ENABLED=${DOCKERSWARM_AUTO_JOIN_ENABLED:-true}
if [[ "${DOCKERSWARM_AUTO_JOIN_ENABLED}" == "true" ]]; then
	if [[ -n "${DOCKERSWARM_SERVICE_NAME}" ]]; then
		echo "==> [Docker Swarm Entrypoint] configure auto-join for \"${DOCKERSWARM_SERVICE_NAME}\" stack..."
		dockerswarm_auto_join $DOCKERSWARM_SERVICE_NAME
	else
		echo "==> [Docker Swarm Entrypoint] failed to configure auto-join: DOCKERSWARM_SERVICE_NAME is not set"
		exit 1
	fi
else
	echo "==> [Docker Swarm Entrypoint] auto-join is disabled"
fi

# If DOCKERSWARM_ENTRYPOINT is set, wait for the storage configuration file to be created
if [[ -n "${DOCKERSWARM_ENTRYPOINT}" ]]; then
	echo "==> [Docker Swarm Entrypoint] waiting for auto-join config \"$VAULT_STORAGE_CONFIG_FILE\" to be created..."
	while [ ! -f "$VAULT_STORAGE_CONFIG_FILE" ]; do
		sleep 1
	done
fi

# Redirect the execution context to the original entrypoint, if needed
# Uncomment the following line to enable the original entrypoint
exec /docker-entrypoint-shim.sh "${@}"
