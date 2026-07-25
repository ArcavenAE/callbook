# callbook — content + shell + Helm

default:
    @just --list

# shellcheck the kit + lint and render the chart
check:
    shellcheck kit/*.sh
    helm lint deploy/helm/dolt
    helm template test deploy/helm/dolt --set existingSecret=dummy >/dev/null
    @echo "check: OK"

# render the chart with default values (existingSecret stubbed)
template:
    helm template test deploy/helm/dolt --set existingSecret=dummy
