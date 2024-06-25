docker-stack-name := vault

it:
	@echo "make [deploy|remove|clean|reset] docker-stack-name=$(docker-stack-name)"

deploy:
	docker network create --scope=swarm --driver=overlay --attachable dockerswarm_ingress || true
	docker network create --scope=swarm --driver=overlay --attachable dockerswarm_metrics || true
	docker stack deploy -c docker-stack.yml --detach=false $(docker-stack-name)

remove:
	docker stack rm --detach=false $(docker-stack-name)

clean:
	docker volume ls -q | grep $(docker-stack-name) | xargs docker volume rm

reset: remove wait clean deploy

wait:
	@echo "Waiting for previous recipe to finish..."
	@sleep 10
