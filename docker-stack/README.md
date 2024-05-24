# About

This is the **Docker Stack** file for deploying **HashiCorp Vault** inside **Docker Swarm** environment.

## Features

- Automatically join the Vault cluster within the same stack using the **Integrated Raft Storage** backend and perform peer discovery using the **Docker** service discovery mechanism.
- Configure part of the Vault instance using **Environment Variables**.
- Exported metrics for monitoring using **Prometheus**.

## Entrypoints

There are two entrypoints for the **Vault** container:
- `default`: [`/docker-entrypoint-shim.sh`](../rootfs/docker-entrypoint-shim.sh)
    
    The `default` entrypoint is used for the **Vault** container to start in **standalone** mode with the **Integrated Raft Storage** backend. It also provides the ability to configure the **Vault** instance using **Environment Variables**.
- `dockerswarm`: [`/dockerswarm-entrypoint.sh`](../rootfs/dockerswarm-entrypoint.sh)
    
    The `dockerswarm` entrypoint is used for starting **Vault** in a **Docker Swarm** environment. It will automatically join the **Vault** cluster within the same stack using the **Integrated Raft Storage** backend and perform peer discovery using the **Docker** service discovery mechanism.

    > The `dockerswarm` entrypoint will redirect the execution context to the `default` entrypoint for starting the **Vault** instance.
