#!/bin/zsh

# download dotfiles
if [[ ! -e ${HOME}/.dotfiles ]]; then
    git clone https://github.com/gotomts/dotfiles.git ${HOME}/.dotfiles
else
    if git -C "${HOME}/.dotfiles" diff --quiet 2>/dev/null && \
       git -C "${HOME}/.dotfiles" diff --cached --quiet 2>/dev/null; then
        git -C "${HOME}/.dotfiles" pull
    else
        echo "\e[33mWarning: dotfiles repo has uncommitted changes, skipping pull\e[m"
    fi
fi

cd ${HOME}/.dotfiles

# config, docs, aliase are managed separately or referenced directly
skip_names=(setup README.md ssh claude config docs aliase)

for name in *; do
    if [[ ${name} != 'setup' ]] && [[ ${name} != 'README.md' ]] && [[ ${name} != 'ssh' ]] && [[ ${name} != 'claude' ]] && [[ ${name} != 'CLAUDE.md' ]] && [[ ${name} != 'config' ]] && [[ ${name} != 'docs' ]]; then
        if [[ -L ${HOME}/.${name} ]]; then
            unlink ${HOME}/.${name}
        fi
        ln -sfv ${PWD}/${name}  ${HOME}/.${name}
    fi
done

if [[ ! -d ${HOME}/.claude ]]; then
    mkdir ${HOME}/.claude
fi
cd claude
for name in *; do
    if [[ -d ${name} ]]; then
        if [[ ! -d ${HOME}/.claude/${name} ]]; then
            mkdir ${HOME}/.claude/${name}
        elif [[ -L ${HOME}/.claude/${name} ]]; then
            unlink ${HOME}/.claude/${name}
            mkdir ${HOME}/.claude/${name}
        fi
        for sub in ${name}/**/*(N.); do
            sub_dir=${HOME}/.claude/${sub:h}
            [[ -d ${sub_dir} ]] || mkdir -p ${sub_dir}
            if [[ -L ${HOME}/.claude/${sub} ]]; then
                unlink ${HOME}/.claude/${sub}
            fi
            ln -sfv ${PWD}/${sub} ${HOME}/.claude/${sub}
        done
    else
        if [[ -L ${HOME}/.claude/${name} ]]; then
            unlink ${HOME}/.claude/${name}
        fi
        ln -sfv ${PWD}/${name} ${HOME}/.claude/${name}
    fi
done
cd ..

if [[ ! -d ${HOME}/.config ]]; then
    mkdir ${HOME}/.config
fi
cd config
for dir in */; do
    dir=${dir%/}
    if [[ ! -d ${HOME}/.config/${dir} ]]; then
        mkdir ${HOME}/.config/${dir}
    fi
    for name in ${dir}/*(N); do
        [[ -f ${name} ]] || continue
        target=${HOME}/.config/${name}
        if [[ -L ${target} ]]; then
            unlink ${target}
        fi
        ln -sfv ${PWD}/${name} ${target}
    done
done
cd ..

if [[ ! -d ${HOME}/.ssh ]]; then
    mkdir ${HOME}/.ssh
fi
cd ssh
for name in *; do
    if [[ -L ${HOME}/.ssh/$name ]]; then
        unlink ${HOME}/.ssh/$name
    fi
    ln -sfv ${PWD}/${name} ${HOME}/.ssh/${name}
done
cd ..

# install
FORCE=1
. ${HOME}/.dotfiles/setup/install.zsh
