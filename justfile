# callbook: content + shell + Helm

default:
    @just --list

# shellcheck the kit + lint and render the chart + style/leak gates
check:
    shellcheck kit/*.sh
    helm lint deploy/helm/dolt
    helm template test deploy/helm/dolt --set existingSecret=dummy --set tls.issuerRef.name=example >/dev/null
    ! grep -rn "$(printf '\342\200\224')" --exclude-dir=.git . || { echo "em dash found"; exit 1; }
    ! grep -rniE "18{1}98|e98[dsp]|ms{1}sci" --exclude-dir=.git . || { echo "org token found"; exit 1; }
    @echo "check: OK"

# render the chart with default values (existingSecret stubbed)
template:
    helm template test deploy/helm/dolt --set existingSecret=dummy
