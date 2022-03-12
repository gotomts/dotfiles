# anyenv
export PATH=${HOME}/.anyenv/bin:${PATH}
eval "$(anyenv init -)"

# golang
export GOPATH=${HOME}/go
export PATH=${GOPATH}/bin:${PATH}

export PATH=${PATH}:${GOPATH}/gqlgen
export PATH=${PATH}:${GOPATH}/ent