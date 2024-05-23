variable "VAULT_VERSION" { default = "latest" }
target "docker-metadata-action" {}
target "github-metadata-action" {}

target "default" {
    inherits = [ "hashicorp-vault" ]
    platforms = [
        "linux/amd64",
        "linux/arm64"
    ]
}

target "local" {
    inherits = [ "hashicorp-vault" ]
    tags = [ "swarmlibs/hashicorp-vault:local" ]
}

target "hashicorp-vault" {
    context = "."
    dockerfile = "Dockerfile"
    inherits = [
        "docker-metadata-action",
        "github-metadata-action",
    ]
    args = {
        VAULT_VERSION = "${VAULT_VERSION}"
    }
}
